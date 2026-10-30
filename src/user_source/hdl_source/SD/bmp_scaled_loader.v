`timescale 1ns/1ps
// Load-time BMP scaler. Complete top-down canvas; contiguous source files.
module bmp_scaled_loader #(
    parameter integer DST_WIDTH=640, DST_HEIGHT=480,
    parameter integer MAX_SRC_WIDTH=1280, MAX_SRC_HEIGHT=1024,
    parameter integer BILINEAR=1, FAST_IDENTITY=1, IO_TIMEOUT_CYCLES=100000000
)(
    input wire clk,input wire rst,output wire ready,
    input wire scan_start,input wire [31:0] scan_start_sector,
    input wire [31:0] scan_max_sector,input wire [2:0] scan_target_count,
    output reg scan_done,output reg scan_found_valid,
    output reg [31:0] scan_found_sector,output reg [2:0] scan_found_total,
    input wire load_start,input wire [31:0] load_sector,
    input wire sd_init_done,output reg [3:0] state_code,
    input wire [15:0] bmp_width,input wire [15:0] bmp_height,
    output reg write_req,input wire write_req_ack,input wire write_ready,
    output reg load_error,
    output wire sd_sec_read,output wire [31:0] sd_sec_read_addr,
    input wire [7:0] sd_sec_read_data,input wire sd_sec_read_data_valid,
    input wire sd_sec_read_end,
    output wire bmp_data_wr_en,output reg [23:0] bmp_data
);
localparam IDLE=0,HDR_RESET=1,HDR_REQ=2,HDR_WAIT=3,HDR_CHECK=4,
    FIT_START=5,FIT_WAIT=6,STEP_X_START=7,STEP_X_WAIT=8,
    STEP_Y_START=9,STEP_Y_WAIT=10,WRITE_WAIT=11,NEW_ROW=12,
    CHECK_TOP=13,CHECK_BOTTOM=14,ROW_SETUP=15,ROW_OFFSET=16,
    ROW_REQ=17,ROW_WAIT=18,PIXEL_PREP=19,LEFT_WAIT=20,LEFT_CAPTURE=21,
    RIGHT_WAIT=22,RIGHT_CAPTURE=23,H_MUL=24,H_ADD=25,V_MUL=26,
    V_ADD=27,OUT_PIXEL=28,FAIL=29,HEADER_MATH1=30,HEADER_MATH2=31,
    HEADER_MATH3=32,HEADER_MATH4=33,FIT_PREP=34,MAP_X=35,MAP_Y=36;
(* fsm_encoding="one_hot" *) reg [5:0] state;
reg return_to_bottom;
reg is_scan;
reg [31:0] base_sector,scan_sector,byte_offset;
reg [5:0] header_pos;
reg [15:0] signature,planes,bit_count;
reg [31:0] file_len,pixel_offset,dib_size,width_raw,height_raw,compression;
wire [31:0] height_abs=height_raw[31] ? (~height_raw+32'd1) : height_raw;
wire [15:0] stride_calc=(width_raw[15:0]*16'd3+16'd3)&16'hfffc;
reg [31:0] height_abs_reg,pixel_bytes_reg,file_sectors,next_scan;
reg [15:0] stride_reg;
reg [32:0] min_file_len;
reg header_basic_ok,header_ok;
reg [31:0] fit_product_w,fit_product_h;
reg byte_req;
wire byte_valid,byte_error;
wire [7:0] byte_value;
sd_byte_cache #(.TIMEOUT_CYCLES(IO_TIMEOUT_CYCLES)) u_byte_cache (
    .clk(clk),.rst(rst),.req(byte_req),
    .sector(base_sector+(byte_offset>>9)),.byte_index(byte_offset[8:0]),
    .valid(byte_valid),.data(byte_value),.error(byte_error),
    .sd_read(sd_sec_read),.sd_addr(sd_sec_read_addr),
    .sd_data(sd_sec_read_data),.sd_valid(sd_sec_read_data_valid),.sd_end(sd_sec_read_end)
);
reg [15:0] src_w,src_h,row_stride,draw_w,draw_h,offset_x,offset_y;
reg [15:0] src_last_x,src_last_y;
reg [31:0] mapped_x,mapped_y;
reg bottom_up,fit_width;
reg div_start;
reg [31:0] div_num,div_den;
wire [31:0] div_q;
wire div_done,div_busy;
scale_divider u_divider(clk,rst,div_start,div_num,div_den,div_q,div_done,div_busy);
reg [31:0] step_x,step_y;
reg signed [31:0] start_x,src_x_q,src_y_q;
wire [31:0] max_x_q={src_last_x,16'd0};
wire [31:0] max_y_q={src_last_y,16'd0};
wire signed [31:0] rounded_x=src_x_q+((BILINEAR==0)?32'sd32768:32'sd0);
wire signed [31:0] rounded_y=src_y_q+((BILINEAR==0)?32'sd32768:32'sd0);
wire [31:0] sample_x=(rounded_x<0)?32'd0:
    (($unsigned(rounded_x)>max_x_q)?max_x_q:$unsigned(rounded_x));
wire [31:0] sample_y=(rounded_y<0)?32'd0:
    (($unsigned(rounded_y)>max_y_q)?max_y_q:$unsigned(rounded_y));
reg [15:0] canvas_x,canvas_y,wanted_y0,wanted_y1;
reg active_row;
wire identity_fast=FAST_IDENTITY&&src_w==DST_WIDTH&&src_h==DST_HEIGHT;
wire active_column=(canvas_x>=offset_x && canvas_x<offset_x+draw_w);
reg [8:0] frac_x,frac_y;
reg [15:0] x_right;
// Sequential scheduling pauses SD fetching while two source rows are sampled.
localparam LINE_AW=(MAX_SRC_WIDTH<=1)?1:$clog2(MAX_SRC_WIDTH);
wire [23:0] row0_q,row1_q;
reg valid0,valid1;
reg [15:0] tag0,tag1;
reg top_bank,bottom_bank,fill_bank;
reg [15:0] fill_row,fill_x,read_x;
reg [1:0] byte_phase;
reg [15:0] bgr_partial;
reg [31:0] row_product;
wire [15:0] file_row=bottom_up ? (src_last_y-fill_row) : fill_row;
wire line_we=(state==ROW_WAIT && byte_valid && !byte_error && byte_phase==2);
scale_line_ram #(.ADDR_WIDTH(LINE_AW)) u_row0 (
    .clk(clk),.we(line_we && !fill_bank),.wa(fill_x[LINE_AW-1:0]),
    .di({byte_value,bgr_partial}),.ra(read_x[LINE_AW-1:0]),.dout(row0_q));
scale_line_ram #(.ADDR_WIDTH(LINE_AW)) u_row1 (
    .clk(clk),.we(line_we && fill_bank),.wa(fill_x[LINE_AW-1:0]),
    .di({byte_value,bgr_partial}),.ra(read_x[LINE_AW-1:0]),.dout(row1_q));
reg [23:0] p00,p10,p01,p11;
reg [1:0] channel;
function [7:0] component;
    input [23:0] p;input [1:0] c;
    begin
        case(c) 0:component=p[23:16];1:component=p[15:8];default:component=p[7:0];endcase
    end
endfunction
reg [16:0] hp00,hp10,hp01,hp11;
reg [15:0] h_top,h_bottom;
reg [24:0] vp_top,vp_bottom;
wire [24:0] rounded_component=vp_top+vp_bottom+25'd32768;
assign ready=(state==IDLE);
assign bmp_data_wr_en=(state==OUT_PIXEL && write_ready);
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=IDLE;return_to_bottom<=1'b0;is_scan<=0;
        base_sector<=0;scan_sector<=0;byte_offset<=0;header_pos<=0;
        height_abs_reg<=0;pixel_bytes_reg<=0;file_sectors<=0;next_scan<=0;stride_reg<=0;
        min_file_len<=0;header_basic_ok<=0;header_ok<=0;fit_product_w<=0;fit_product_h<=0;
        signature<=0;planes<=0;bit_count<=0;file_len<=0;pixel_offset<=0;
        dib_size<=0;width_raw<=0;height_raw<=0;compression<=0;
        scan_done<=0;scan_found_valid<=0;scan_found_sector<=0;scan_found_total<=0;
        write_req<=0;load_error<=0;state_code<=0;byte_req<=0;
        src_w<=0;src_h<=0;row_stride<=0;draw_w<=0;draw_h<=0;
        src_last_x<=0;src_last_y<=0;mapped_x<=0;mapped_y<=0;
        offset_x<=0;offset_y<=0;bottom_up<=0;fit_width<=0;
        div_start<=0;div_num<=0;div_den<=1;step_x<=0;step_y<=0;
        start_x<=0;src_x_q<=0;src_y_q<=0;
        canvas_x<=0;canvas_y<=0;wanted_y0<=0;wanted_y1<=0;
        active_row<=0;frac_x<=0;frac_y<=0;x_right<=0;
        valid0<=0;valid1<=0;tag0<=0;tag1<=0;top_bank<=0;bottom_bank<=0;
        fill_bank<=0;fill_row<=0;fill_x<=0;read_x<=0;byte_phase<=0;bgr_partial<=0;row_product<=0;
        p00<=0;p10<=0;p01<=0;p11<=0;channel<=0;
        hp00<=0;hp10<=0;hp01<=0;hp11<=0;h_top<=0;h_bottom<=0;
        vp_top<=0;vp_bottom<=0;bmp_data<=0;
    end else begin
        scan_found_valid<=0;div_start<=0;load_error<=0;
        case(state)
            IDLE: begin
                byte_req<=0;write_req<=0;
                if(sd_init_done && scan_start) begin
                    is_scan<=1;scan_done<=0;scan_found_total<=0;
                    scan_sector<=scan_start_sector;base_sector<=scan_start_sector;
                    state_code<=2;state<=HDR_RESET;
                end else if(sd_init_done && load_start) begin
                    is_scan<=0;base_sector<=load_sector;valid0<=0;valid1<=0;
                    state_code<=2;state<=HDR_RESET;
                end
            end
            HDR_RESET: begin
                header_pos<=0;byte_offset<=0;signature<=0;planes<=0;bit_count<=0;
                file_len<=0;pixel_offset<=0;dib_size<=0;width_raw<=0;height_raw<=0;compression<=0;
                state<=HDR_REQ;
            end
            HDR_REQ: begin byte_req<=1;state<=HDR_WAIT;end
            HDR_WAIT: if(byte_valid) begin
                byte_req<=0;
                if(byte_error) state<=FAIL;
                else begin
                    case(header_pos)
                        0:signature[7:0]<=byte_value;1:signature[15:8]<=byte_value;
                        2:file_len[7:0]<=byte_value;3:file_len[15:8]<=byte_value;
                        4:file_len[23:16]<=byte_value;5:file_len[31:24]<=byte_value;
                        10:pixel_offset[7:0]<=byte_value;11:pixel_offset[15:8]<=byte_value;
                        12:pixel_offset[23:16]<=byte_value;13:pixel_offset[31:24]<=byte_value;
                        14:dib_size[7:0]<=byte_value;15:dib_size[15:8]<=byte_value;
                        16:dib_size[23:16]<=byte_value;17:dib_size[31:24]<=byte_value;
                        18:width_raw[7:0]<=byte_value;19:width_raw[15:8]<=byte_value;
                        20:width_raw[23:16]<=byte_value;21:width_raw[31:24]<=byte_value;
                        22:height_raw[7:0]<=byte_value;23:height_raw[15:8]<=byte_value;
                        24:height_raw[23:16]<=byte_value;25:height_raw[31:24]<=byte_value;
                        26:planes[7:0]<=byte_value;27:planes[15:8]<=byte_value;
                        28:bit_count[7:0]<=byte_value;29:bit_count[15:8]<=byte_value;
                        30:compression[7:0]<=byte_value;31:compression[15:8]<=byte_value;
                        32:compression[23:16]<=byte_value;33:compression[31:24]<=byte_value;
                        default:begin end
                    endcase
                    if(header_pos==53) state<=HEADER_MATH1;
                    else begin header_pos<=header_pos+1'b1;byte_offset<=byte_offset+1'b1;state<=HDR_REQ;end
                end
            end
            HEADER_MATH1: begin
                height_abs_reg<=height_abs;stride_reg<=stride_calc;state<=HEADER_MATH2;
            end
            HEADER_MATH2: begin
                pixel_bytes_reg<=stride_reg*height_abs_reg[15:0];
                header_basic_ok<=(signature==16'h4d42) && (planes==1) &&
                    (bit_count==24) && (compression==0) &&
                    (width_raw>=1 && width_raw<=MAX_SRC_WIDTH) &&
                    (height_abs_reg>=1 && height_abs_reg<=MAX_SRC_HEIGHT) &&
                    ((dib_size==40 && pixel_offset>=54) ||
                     (dib_size==108 && pixel_offset>=122) ||
                     (dib_size==124 && pixel_offset>=138)) && pixel_offset<=65536;
                state<=HEADER_MATH3;
            end
            HEADER_MATH3: begin
                min_file_len<={1'b0,pixel_offset}+{1'b0,pixel_bytes_reg};
                file_sectors<=(file_len+32'd511)>>9;state<=HEADER_MATH4;
            end
            HEADER_MATH4: begin
                header_ok<=header_basic_ok && !min_file_len[32] &&
                    file_len>=min_file_len[31:0] && file_len<=16777216;
                next_scan<=scan_sector+file_sectors;state<=HDR_CHECK;
            end
            HDR_CHECK: begin
                if(is_scan) begin
                    if(header_ok) begin
                        scan_found_valid<=1;scan_found_sector<=scan_sector;
                        scan_found_total<=scan_found_total+1'b1;
                        if(scan_found_total+1>=scan_target_count || next_scan>scan_max_sector) begin
                            scan_done<=1;state_code<=1;state<=IDLE;
                        end else begin scan_sector<=next_scan;base_sector<=next_scan;state<=HDR_RESET;end
                    end else if(scan_sector>=scan_max_sector) begin scan_done<=1;state_code<=1;state<=IDLE;end
                    else begin scan_sector<=scan_sector+1'b1;base_sector<=scan_sector+1'b1;state<=HDR_RESET;end
                end else if(header_ok && bmp_width==DST_WIDTH && bmp_height==DST_HEIGHT) begin
                    src_w<=width_raw[15:0];src_h<=height_abs[15:0];row_stride<=stride_calc;
                    bottom_up<=!height_raw[31];state_code<=3;state<=FIT_PREP;
                end else state<=FAIL;
            end
            FIT_PREP: begin
                fit_product_w<=src_w*DST_HEIGHT;fit_product_h<=src_h*DST_WIDTH;
                src_last_x<=src_w-1'b1;src_last_y<=src_h-1'b1;
                state<=FIT_START;
            end
            FIT_START: begin
                if(fit_product_w >= fit_product_h) begin
                    draw_w<=DST_WIDTH;fit_width<=1;
                    div_num<=fit_product_h;div_den<={16'd0,src_w};
                end else begin
                    draw_h<=DST_HEIGHT;fit_width<=0;
                    div_num<=fit_product_w;div_den<={16'd0,src_h};
                end
                div_start<=1;state<=FIT_WAIT;
            end
            FIT_WAIT: if(div_done) begin
                if(fit_width) draw_h<=(div_q==0)?16'd1:div_q[15:0];
                else draw_w<=(div_q==0)?16'd1:div_q[15:0];
                state<=STEP_X_START;
            end
            STEP_X_START: begin
                offset_x<=(DST_WIDTH-draw_w)>>1;offset_y<=(DST_HEIGHT-draw_h)>>1;
                div_num<={src_w,16'd0};div_den<={16'd0,draw_w};div_start<=1;state<=STEP_X_WAIT;
            end
            STEP_X_WAIT: if(div_done) begin
                step_x<=div_q;start_x<=$signed(div_q>>1)-32'sd32768;state<=STEP_Y_START;
            end
            STEP_Y_START: begin
                div_num<={src_h,16'd0};div_den<={16'd0,draw_h};div_start<=1;state<=STEP_Y_WAIT;
            end
            STEP_Y_WAIT: if(div_done) begin
                step_y<=div_q;src_y_q<=$signed(div_q>>1)-32'sd32768;
                src_x_q<=start_x;canvas_x<=0;canvas_y<=0;write_req<=1;state<=WRITE_WAIT;
            end
            WRITE_WAIT: if(write_req_ack) begin write_req<=0;state_code<=4;state<=NEW_ROW;end
            NEW_ROW: begin
                if(canvas_y<offset_y || canvas_y>=offset_y+draw_h) begin
                    active_row<=0;state<=PIXEL_PREP;
                end else begin
                    active_row<=1;mapped_y<=sample_y;state<=MAP_Y;
                end
            end
            MAP_Y: begin
                wanted_y0<=mapped_y[31:16];
                wanted_y1<=(identity_fast || BILINEAR==0 || mapped_y[31:16]>=src_last_y)?mapped_y[31:16]:mapped_y[31:16]+1'b1;
                frac_y<=(BILINEAR==0)?9'd0:{1'b0,mapped_y[15:8]};state<=CHECK_TOP;
            end
            CHECK_TOP: begin
                if(valid0 && tag0==wanted_y0) begin top_bank<=0;state<=CHECK_BOTTOM;end
                else if(valid1 && tag1==wanted_y0) begin top_bank<=1;state<=CHECK_BOTTOM;end
                else begin
                    fill_bank<=(valid0 && tag0==wanted_y1);fill_row<=wanted_y0;
                    return_to_bottom<=1'b0;state<=ROW_SETUP;
                end
            end
            CHECK_BOTTOM: begin
                if(wanted_y1==wanted_y0) begin bottom_bank<=top_bank;state<=PIXEL_PREP;end
                else if(valid0 && tag0==wanted_y1) begin bottom_bank<=0;state<=PIXEL_PREP;end
                else if(valid1 && tag1==wanted_y1) begin bottom_bank<=1;state<=PIXEL_PREP;end
                else begin fill_bank<=!top_bank;fill_row<=wanted_y1;return_to_bottom<=1'b1;state<=ROW_SETUP;end
            end
            ROW_SETUP: begin row_product<=file_row*row_stride;state<=ROW_OFFSET;end
            ROW_OFFSET: begin
                byte_offset<=pixel_offset+row_product;fill_x<=0;byte_phase<=0;state<=ROW_REQ;
            end
            ROW_REQ: begin byte_req<=1;state<=ROW_WAIT;end
            ROW_WAIT: if(byte_valid) begin
                byte_req<=0;
                if(byte_error) state<=FAIL;
                else begin
                    byte_offset<=byte_offset+1'b1;
                    if(byte_phase==0) begin bgr_partial[7:0]<=byte_value;byte_phase<=1;state<=ROW_REQ;end
                    else if(byte_phase==1) begin bgr_partial[15:8]<=byte_value;byte_phase<=2;state<=ROW_REQ;end
                    else begin
                        byte_phase<=0;
                        if(fill_x==src_last_x) begin
                            if(fill_bank) begin valid1<=1;tag1<=fill_row;end
                            else begin valid0<=1;tag0<=fill_row;end
                            state<=return_to_bottom?CHECK_BOTTOM:CHECK_TOP;
                        end else begin fill_x<=fill_x+1'b1;state<=ROW_REQ;end
                    end
                end
            end
            PIXEL_PREP: begin
                if(!active_row || !active_column) begin bmp_data<=0;state<=OUT_PIXEL;end
                else if(identity_fast)begin read_x<=canvas_x;state<=LEFT_WAIT;end
                else begin mapped_x<=sample_x;state<=MAP_X;end
            end
            MAP_X: begin
                read_x<=mapped_x[31:16];
                x_right<=(BILINEAR==0 || mapped_x[31:16]>=src_last_x)?mapped_x[31:16]:mapped_x[31:16]+1'b1;
                frac_x<=(BILINEAR==0)?9'd0:{1'b0,mapped_x[15:8]};state<=LEFT_WAIT;
            end
            LEFT_WAIT: state<=LEFT_CAPTURE;
            LEFT_CAPTURE: begin
                if(identity_fast)begin bmp_data<=top_bank?row1_q:row0_q;state<=OUT_PIXEL;end
                else begin
                    p00<=top_bank?row1_q:row0_q;p01<=bottom_bank?row1_q:row0_q;
                    read_x<=x_right;state<=RIGHT_WAIT;
                end
            end
            RIGHT_WAIT: state<=RIGHT_CAPTURE;
            RIGHT_CAPTURE: begin
                p10<=top_bank?row1_q:row0_q;p11<=bottom_bank?row1_q:row0_q;
                channel<=0;state<=H_MUL;
            end
            H_MUL: begin
                hp00<=component(p00,channel)*(9'd256-frac_x);hp10<=component(p10,channel)*frac_x;
                hp01<=component(p01,channel)*(9'd256-frac_x);hp11<=component(p11,channel)*frac_x;
                state<=H_ADD;
            end
            H_ADD: begin h_top<=hp00+hp10;h_bottom<=hp01+hp11;state<=V_MUL;end
            V_MUL: begin vp_top<=h_top*(9'd256-frac_y);vp_bottom<=h_bottom*frac_y;state<=V_ADD;end
            V_ADD: begin
                case(channel)
                    0:bmp_data[23:16]<=rounded_component[23:16];
                    1:bmp_data[15:8]<=rounded_component[23:16];
                    2:bmp_data[7:0]<=rounded_component[23:16];
                    default:begin end
                endcase
                if(channel==2) state<=OUT_PIXEL;
                else begin channel<=channel+1'b1;state<=H_MUL;end
            end
            OUT_PIXEL: if(write_ready) begin
                if(active_row && active_column) src_x_q<=src_x_q+$signed(step_x);
                if(canvas_x==DST_WIDTH-1) begin
                    canvas_x<=0;src_x_q<=start_x;
                    if(active_row) src_y_q<=src_y_q+$signed(step_y);
                    if(canvas_y==DST_HEIGHT-1) begin state_code<=1;state<=IDLE;end
                    else begin canvas_y<=canvas_y+1'b1;state<=NEW_ROW;end
                end else begin canvas_x<=canvas_x+1'b1;state<=PIXEL_PREP;end
            end
            FAIL: begin
                byte_req<=0;write_req<=0;state_code<=4'he;
                if(is_scan) scan_done<=1;else load_error<=1;
                state<=IDLE;
            end
            default: state<=FAIL;
        endcase
    end
end
endmodule

// Power-of-two depth, registered read and explicit Anlogic BRAM inference.
module scale_line_ram #(parameter ADDR_WIDTH=11)(
 input wire clk,input wire we,input wire [ADDR_WIDTH-1:0] wa,
 input wire [23:0] di,input wire [ADDR_WIDTH-1:0] ra,output reg [23:0] dout
);
reg [23:0] mem [0:(1<<ADDR_WIDTH)-1] /* synthesis ram_style=bram_32k */;
always @(posedge clk) if(we) mem[wa]<=di;
always @(posedge clk) dout<=mem[ra];
endmodule
