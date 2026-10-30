`timescale 1ns/1ps
// Actual H11 digital drive, sampled at 25 MHz / 781 = 32.010 kHz.
// 256 samples cover 7.998 ms. This is a waveform, not an FFT or microphone.
// Capture and display use opposite RAM banks; banks change only at VS falling.
// RGB, VS and DE all have exactly two registered stages.
module audio_wave_overlay #(
    parameter integer SAMPLE_DIV=781
)(
    input wire clk, input wire rst,
    input wire buzzer_n, input wire audio_active,
    input wire enable,
    input wire [23:0] rgb_in, input wire vs_in, input wire de_in,
    output reg [23:0] rgb_out, output reg vs_out, output reg de_out
);
function integer bits_for;
    input integer value;
    integer t;
    begin
        bits_for=0;
        for(t=value-1;t>0;t=t>>1)bits_for=bits_for+1;
        if(bits_for<1)bits_for=1;
    end
endfunction
localparam integer DIV_W=bits_for(SAMPLE_DIV);
reg [2:0] buz_sync,active_sync;
reg vs_d,de_d,show_frame;
reg [11:0] next_x,line_y;
wire frame_tick=vs_d && !vs_in;
wire [11:0] pixel_x=de_d ? next_x : 12'd0;
// 00 = rest (zero); 01 = positive; 10 = negative.
wire [1:0] live_sample=!active_sync[2] ? 2'b00 :
                       (!buz_sync[2] ? 2'b01 : 2'b10);
reg [3:0] sample_mem [0:511]; // {previous sample,current sample}
reg display_bank,capture_bank,display_valid;
reg capturing,capture_ready,capture_active,display_active;
reg [7:0] capture_index;
reg [DIV_W-1:0] sample_count;
reg [1:0] last_sample;
always @(posedge clk or posedge rst) begin
    if(rst)begin
        buz_sync<=3'b111;active_sync<=0;vs_d<=0;de_d<=0;
        show_frame<=0;next_x<=0;line_y<=0;
        display_bank<=0;capture_bank<=1;display_valid<=0;
        capturing<=0;capture_ready<=0;capture_active<=0;display_active<=0;
        capture_index<=0;sample_count<=0;last_sample<=0;
    end else begin
        buz_sync<={buz_sync[1:0],buzzer_n};
        active_sync<={active_sync[1:0],audio_active};
        vs_d<=vs_in;de_d<=de_in;
        if(frame_tick)begin
            next_x<=0;line_y<=0;show_frame<=enable;
            // A late acquisition is allowed to finish. Never publish partial RAM.
            if(capture_ready || !capturing)begin
                if(capture_ready)begin
                    display_bank<=capture_bank;display_valid<=1;
                    display_active<=capture_active;capture_bank<=~capture_bank;
                end
                capture_ready<=0;capturing<=1;capture_index<=0;
                sample_count<=0;capture_active<=0;last_sample<=0;
            end
        end else begin
            if(de_in)next_x<=pixel_x+1'b1;else next_x<=0;
            if(de_d && !de_in)line_y<=line_y+1'b1;
        end
        if(capturing && !frame_tick)begin
            if(sample_count==SAMPLE_DIV-1)begin
                sample_count<=0;last_sample<=live_sample;
                capture_active<=capture_active || active_sync[2];
                if(capture_index==255)begin capturing<=0;capture_ready<=1;end
                else capture_index<=capture_index+1'b1;
            end else sample_count<=sample_count+1'b1;
        end
    end
end
// No reset of the RAM array: display_valid masks uninitialized storage.
always @(posedge clk)begin
    if(!rst && capturing && !frame_tick && sample_count==SAMPLE_DIV-1)
        sample_mem[{capture_bank,capture_index}]<=
            {capture_index==0 ? live_sample : last_sample,live_sample};
end

wire [11:0] chart_x=pixel_x-12'd64;
wire [11:0] header_x=pixel_x-12'd64;
wire [11:0] header_y=line_y-12'd324;
wire panel_hit=show_frame && de_in && pixel_x>=48 && pixel_x<592 && line_y>=320 && line_y<416;
wire chart_hit=panel_hit && pixel_x>=64 && pixel_x<576 && line_y>=344 && line_y<408;
wire header_hit=panel_hit && pixel_x>=64 && pixel_x<576 && line_y>=324 && line_y<340;
reg [7:0] character;
always @* begin
    character=" ";
    case(header_x[8:3])
        0:character="B";1:character="U";2:character="Z";3:character="Z";
        4:character="E";5:character="R";7:character="W";8:character="A";
        9:character="V";10:character="E";
        19:character="8";20:character="M";21:character="S";
        55:character=display_valid ? (display_active ? "P" : "R") : "W";
        56:character=display_valid ? (display_active ? "L" : "E") : "A";
        57:character=display_valid ? (display_active ? "A" : "S") : "I";
        58:character=display_valid ? (display_active ? "Y" : "T") : "T";
        default:character=" ";
    endcase
end
reg [3:0] samples_s1;
always @(posedge clk) samples_s1<=sample_mem[{display_bank,chart_x[8:1]}];
reg [23:0] rgb_s1;
reg vs_s1,de_s1,hit_s1,chart_s1,header_s1,valid_s1,border_s1;
reg [11:0] x_s1,y_s1;
reg [7:0] char_s1;
reg [2:0] col_s1;
reg [3:0] row_s1;
wire font_pixel;
hx4s20_osd_font u_font(.character(char_s1),.column(col_s1),.row(row_s1),.pixel(font_pixel));
function [11:0] sample_y;
    input [1:0] sample;
    begin
        case(sample)
            2'b01:sample_y=356;
            2'b10:sample_y=396;
            default:sample_y=376;
        endcase
    end
endfunction
wire [11:0] current_y=valid_s1 ? sample_y(samples_s1[1:0]) : 12'd376;
wire [11:0] previous_y=valid_s1 ? sample_y(samples_s1[3:2]) : 12'd376;
wire [11:0] min_y=current_y<previous_y ? current_y : previous_y;
wire [11:0] max_y=current_y>previous_y ? current_y : previous_y;
wire wave_hit=chart_s1 && ((y_s1==current_y || y_s1==current_y+1'b1) ||
              (!x_s1[0] && y_s1>=min_y && y_s1<=max_y));
wire grid_hit=chart_s1 && (x_s1[5:0]==0 || y_s1==356 || y_s1==376 || y_s1==396);
always @(posedge clk or posedge rst)begin
    if(rst)begin
        rgb_s1<=0;vs_s1<=0;de_s1<=0;hit_s1<=0;chart_s1<=0;header_s1<=0;
        valid_s1<=0;border_s1<=0;x_s1<=0;y_s1<=0;char_s1<=" ";col_s1<=0;row_s1<=0;
        rgb_out<=0;vs_out<=0;de_out<=0;
    end else begin
        rgb_s1<=rgb_in;vs_s1<=vs_in;de_s1<=de_in;
        hit_s1<=panel_hit;chart_s1<=chart_hit;header_s1<=header_hit;
        valid_s1<=display_valid;x_s1<=chart_x;y_s1<=line_y;
        border_s1<=pixel_x==48 || pixel_x==591 || line_y==320 || line_y==415;
        char_s1<=character;col_s1<=header_x[2:0];row_s1<=header_y[3:0];
        vs_out<=vs_s1;de_out<=de_s1;
        if(!de_s1)rgb_out<=0;
        else if(!hit_s1)rgb_out<=rgb_s1;
        else if(border_s1)rgb_out<=24'h327080;
        else if(header_s1 && font_pixel)rgb_out<=24'hf0f0f0;
        else if(wave_hit)rgb_out<=24'h00ffb0;
        else if(grid_hit)rgb_out<=24'h243848;
        else rgb_out<=24'h101820;
    end
end
endmodule
