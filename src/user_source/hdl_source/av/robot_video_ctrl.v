`timescale 1ns/1ps
// Retain the current photo in one slot, and ping-pong the other TWO slots.
// Cache and reader mailboxes acknowledge before ownership or buffers change.
module robot_video_ctrl #(
 parameter integer CLK_HZ=50000000,FPS=12,REWIND_AFTER_PAUSE=0
)(input clk,rst,want_mode,near_active,pause,cache_suspended,
 input [1:0] photo_slot,input photo_request,
 input display_done_toggle,write_done_toggle,
 input loader_ready,loader_error,write_req,write_ack,
 output reg claim,output reg request_toggle,output reg [1:0] display_slot,
 output reg target_video,output reg valid_frame,output reg fault,
 output reg load_start,output reg clip,output reg [6:0] frame_number,
 output reg [1:0] write_slot,output [3:0] state_code,
 output reg target_clip,output reg [6:0] target_frame,
 output reg [31:0] late_frames);
localparam OFF=0,START=1,LOAD=2,READY=3,COMMIT=4,RESTORE=5,RESTORE_ACK=6,FAULT=7;
reg [2:0] state;
reg [1:0] keep_slot;
reg pause_old,rewind_pending;
reg source_seen,source_done,write_armed,write_done,wr_seen;
localparam integer PERIOD_BITS=$clog2(CLK_HZ/FPS+1);
reg [PERIOD_BITS-1:0] period_left;
localparam integer TIMEOUT_BITS=$clog2(CLK_HZ*2+1);
reg [TIMEOUT_BITS-1:0] load_age;
wire [1:0] slot_a=keep_slot==0?1:0;
wire [1:0] slot_b=keep_slot==2?1:2;
assign state_code=fault?4'he:claim?4'd6:4'd0;
always @(posedge clk or posedge rst)
 if(rst)begin
  pause_old<=0;rewind_pending<=0;target_clip<=0;target_frame<=0;
  state<=OFF;claim<=0;request_toggle<=0;display_slot<=0;target_video<=0;valid_frame<=0;
  fault<=0;load_start<=0;clip<=0;frame_number<=0;write_slot<=0;keep_slot<=0;
  source_seen<=0;source_done<=0;write_armed<=0;write_done<=0;wr_seen<=0;
  period_left<=0;late_frames<=0;load_age<=0;
 end else begin
  load_start<=0;pause_old<=pause;
  if(REWIND_AFTER_PAUSE&&pause_old&&!pause&&claim)rewind_pending<=1;
  if(state!=LOAD)load_age<=0;else if(load_age<CLK_HZ*2)load_age<=load_age+1'b1;
  if(!pause&&period_left!=0)period_left<=period_left-1'b1;
  if(state==LOAD)begin
   if(!loader_ready)source_seen<=1;
   if(source_seen&&loader_ready)source_done<=1;
   if(write_req&&write_ack)begin write_armed<=1;wr_seen<=write_done_toggle;end
   else if(write_armed&&write_done_toggle!=wr_seen)begin write_done<=1;wr_seen<=write_done_toggle;end
  end
  case(state)
   OFF:begin
    fault<=0;valid_frame<=0;
    if(want_mode&&cache_suspended&&!pause)begin
     claim<=1;keep_slot<=photo_slot;display_slot<=photo_slot;
     request_toggle<=photo_request;target_video<=0;period_left<=0;
     write_slot<=photo_slot==0?1:0;clip<=near_active;frame_number<=0;state<=START;
    end
   end
   START:if(!pause)begin
    if(!want_mode)state<=RESTORE;
    else if(loader_ready)begin
     if(clip!=near_active||rewind_pending)begin
      clip<=near_active;frame_number<=0;period_left<=0;rewind_pending<=0;
     end
     load_start<=1;source_seen<=0;source_done<=0;write_armed<=0;
     write_done<=0;wr_seen<=write_done_toggle;state<=LOAD;
    end
   end
   LOAD:begin
    if(loader_error||load_age==CLK_HZ*2)begin fault<=1;state<=FAULT;end
    else if(source_done&&write_done)state<=READY;
   end
   READY:if(!pause)begin
    if(!want_mode)state<=RESTORE;
    else if(clip!=near_active||rewind_pending)begin clip<=near_active;frame_number<=0;period_left<=0;state<=START;end
    else if(period_left==0||!valid_frame)begin
     target_clip<=clip;target_frame<=frame_number;
     display_slot<=write_slot;target_video<=1;request_toggle<=!request_toggle;
     period_left<=CLK_HZ/FPS-1;state<=COMMIT;
    end
   end
   COMMIT:if(display_done_toggle==request_toggle)begin
    valid_frame<=1;
    if(!want_mode)state<=RESTORE;
    else begin
     write_slot<=write_slot==slot_a?slot_b:slot_a;
     if(clip!=near_active||rewind_pending)begin clip<=near_active;frame_number<=0;period_left<=0;end
     else frame_number<=frame_number==(clip?71:47)?0:frame_number+1'b1;
     state<=START;
    end
   end
   RESTORE:if(!pause)begin
    display_slot<=keep_slot;target_video<=0;request_toggle<=!request_toggle;state<=RESTORE_ACK;
   end
   RESTORE_ACK:if(display_done_toggle==request_toggle)begin
    valid_frame<=0;
    if(want_mode)begin write_slot<=slot_a;clip<=near_active;frame_number<=0;period_left<=0;state<=START;end
    else begin claim<=0;state<=OFF;end
   end
   FAULT:if(!want_mode&&!pause)state<=RESTORE;
   default:state<=OFF;
  endcase
  if(state==LOAD&&period_left==1&&valid_frame&&!pause&&late_frames!=32'hffffffff)late_frames<=late_frames+1'b1;
 end
endmodule
