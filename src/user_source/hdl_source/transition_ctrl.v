`timescale 1ns/1ps
// Mailboxes are bundled-data toggle handshakes. The sender holds each index
// stable until done_toggle acknowledges the request. Frame completion comes
// from the SDRAM reader, tagged with the index actually latched by that reader.
module transition_ctrl #(
    parameter integer FADE_STEP = 8, parameter integer AV_ENABLE = 0,
    parameter integer FAST_ENABLE=0,DETAIL_FADE_STEP=64,DIRECT_ENABLE=0
)(
    input wire fast_switch,input wire direct_switch,
    input  wire       clk,
    input  wire       rst,
    input  wire       video_vs,             // VGA mode: active-low VS
    input  wire       image_req_toggle,     // asynchronous, sd_card_clk domain
    input  wire [1:0] image_buf_index,
    input  wire       read_done_toggle,     // asynchronous, ext_mem_clk domain
    input  wire [1:0] read_done_index,
    output reg  [1:0] active_buf_index,
    output reg  [8:0] gain,
    output reg        done_toggle,
    input wire media_ready, input wire pause,
    output reg scene_start,output reg scene_start_toggle,
    output wire       busy
);
localparam [2:0] IDLE = 3'd0, FADE_OUT = 3'd1, BLACK_SWITCH = 3'd2,
                 WAIT_FRAME = 3'd3, FADE_IN = 3'd4,DIRECT_SWITCH=3'd5,DIRECT_WAIT=3'd6;
// Clamp a bad parameter to a valid step; the endpoint is always exactly 256.
localparam [8:0] STEP = (FADE_STEP < 1) ? 9'd1 :
                        (FADE_STEP > 256) ? 9'd256 : FADE_STEP;
localparam [8:0] DETAIL_STEP=(DETAIL_FADE_STEP<1)?9'd1:(DETAIL_FADE_STEP>256)?9'd256:DETAIL_FADE_STEP;
reg [8:0] active_step;
reg [2:0] state;
(* async_reg = "true" *) reg [2:0] req_sync;
(* async_reg = "true" *) reg [2:0] read_done_sync;
(* async_reg = "true" *) reg [1:0] image_index_meta, image_index_sync;
(* async_reg = "true" *) reg [1:0] read_index_meta, read_index_sync;
reg req_seen, read_done_seen;
reg [1:0] target_index;
reg have_image;
reg frame_confirmed;
reg vs_d;
wire frame_tick = vs_d && !video_vs;
wire read_done_event = read_done_sync[2] ^ read_done_seen;
assign busy = (state != IDLE);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        req_sync         <= 3'b000;
        read_done_sync   <= 3'b000;
        image_index_meta <= 2'd0;
        image_index_sync <= 2'd0;
        read_index_meta  <= 2'd0;
        read_index_sync  <= 2'd0;
        read_done_seen   <= 1'b0;
        vs_d             <= 1'b0;
    end else begin
        req_sync         <= {req_sync[1:0], image_req_toggle};
        read_done_sync   <= {read_done_sync[1:0], read_done_toggle};
        image_index_meta <= image_buf_index;
        image_index_sync <= image_index_meta;
        read_index_meta  <= read_done_index;
        read_index_sync  <= read_index_meta;
        read_done_seen   <= read_done_sync[2];
        vs_d             <= video_vs;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        active_step<=STEP;
        state            <= IDLE;
        req_seen         <= 1'b0;
        target_index     <= 2'd0;
        active_buf_index <= 2'd0;
        gain             <= 9'd0;
        done_toggle      <= 1'b0;
        have_image       <= 1'b0;
        frame_confirmed<=0;scene_start<=0;scene_start_toggle<=0;
    end else begin
        scene_start<=0;
        if(!AV_ENABLE||!pause)begin
        case (state)
            IDLE: begin
                if (req_sync[2] != req_seen) begin
                    req_seen     <= req_sync[2];
                    active_step<=FAST_ENABLE&&fast_switch ? DETAIL_STEP : STEP;
                    target_index <= image_index_sync;
                    if(DIRECT_ENABLE&&direct_switch)state<=DIRECT_SWITCH;
                    else if (have_image)
                        state <= FADE_OUT;
                    else
                        state <= BLACK_SWITCH; // first picture fades in from black
                end
            end
            FADE_OUT: begin
                if (frame_tick) begin
                    if (gain <= active_step) begin
                        gain  <= 9'd0;
                        state <= BLACK_SWITCH;
                    end else
                        gain <= gain - active_step;
                end
            end
            BLACK_SWITCH: begin
                // Never replace a buffer while any visible gain remains.
                // The normal read request may already have latched the old
                // index at this VS edge; WAIT_FRAME safely covers that case.
                if (frame_tick) begin
                    active_buf_index <= target_index;
                    state <= WAIT_FRAME;
                    frame_confirmed<=0;
                end
            end
            WAIT_FRAME: begin
                // A complete read of the requested buffer proves that the
                // address/FIFO switch has occurred. Keep transmitting black
                // until then, and start the fade only at a later frame edge.
                if(read_done_event&&read_index_sync==target_index)frame_confirmed<=1;
                if((frame_confirmed||(read_done_event&&read_index_sync==target_index))&&(!AV_ENABLE||media_ready))
                    state<=FADE_IN;
            end
            FADE_IN: begin
                if (frame_tick) begin
                    if(gain==0)begin scene_start<=1;scene_start_toggle<=!scene_start_toggle;end
                    if (gain >= (9'd256 - active_step)) begin
                        gain        <= 9'd256;
                        have_image  <= 1'b1;
                        done_toggle <= req_seen;
                        state       <= IDLE;
                    end else
                        gain <= gain + active_step;
                end
            end
            DIRECT_SWITCH:if(frame_tick)begin
                active_buf_index<=target_index;gain<=256;
                scene_start<=1;scene_start_toggle<=!scene_start_toggle;
                state<=DIRECT_WAIT;
            end
            DIRECT_WAIT:if(read_done_event&&read_index_sync==target_index)begin
                have_image<=1;done_toggle<=req_seen;state<=IDLE;
            end
            default: begin
                state <= IDLE;
                gain  <= 9'd0;
            end
        endcase
        end
    end
end
endmodule
