`timescale 1ns/1ps
// Sector-boundary arbitration with the video loader. One 512-sample FIFO is
// enough because audio has priority whenever a complete sector can fit.
module robot_audio_sd(
 input clk,rst,stream_reset,stream_clip,
 output reset_ack,output fifo_reset,output reg ready,output reg fault,
 input fifo_full,input [9:0] fifo_used,
 output fifo_write,output [15:0] fifo_data,
 output reg sec_req,output reg [31:0] sec_addr,
 input [7:0] sec_data,input sec_valid,sec_end,sec_error
);
`include "robot_audio_resources.vh"
(* async_reg="true" *)reg [2:0] reset_sync;
(* async_reg="true" *)reg [1:0] clip_sync;
always @(posedge clk or posedge rst)
 if(rst)begin reset_sync<=7;clip_sync<=0;end
 else begin reset_sync<={reset_sync[1:0],stream_reset};clip_sync<={clip_sync[0],stream_clip};end
assign reset_ack=reset_sync[2];
assign fifo_reset=rst||reset_sync[2];
localparam IDLE=0,HEADER=1,PCM=2,GAP=3,DONE=4;
reg [2:0] state;
reg pending,kill,clip,header_bad;
reg [9:0] byte_count;
reg [15:0] written;
reg [7:0] low_byte;
wire [15:0] total=clip?16'd48000:16'd32000;
function [7:0] header_byte;
 input [9:0] n;input c;
 begin case(n)
 0:header_byte="H";1:header_byte="X";2:header_byte="R";3:header_byte="B";
 4:header_byte="A";5:header_byte="0";6:header_byte="0";7:header_byte="1";
 8:header_byte=1;12:header_byte=8'h40;13:header_byte=8'h1f;
 16:header_byte=c?8'h80:8'h00;17:header_byte=c?8'hbb:8'h7d;
 20:header_byte={7'd0,c};default:header_byte=0;
 endcase end
endfunction
assign fifo_write=state==PCM&&sec_valid&&byte_count[0]&&!kill&&
 !reset_sync[2]&&!fifo_full&&written<total;
assign fifo_data={sec_data,low_byte};
always @(posedge clk or posedge rst)
 if(rst)begin
  state<=IDLE;pending<=1;kill<=0;clip<=0;header_bad<=0;byte_count<=0;
  written<=0;low_byte<=0;ready<=0;fault<=0;sec_req<=0;sec_addr<=0;
 end else begin
  if(reset_sync[2])begin pending<=1;ready<=0;if(sec_req)kill<=1;end
  if(!reset_sync[2]&&!kill&&!fault&&written>=256)ready<=1;
  if(sec_valid&&sec_req)begin
   byte_count<=byte_count+1'b1;
   if(state==HEADER&&sec_data!=header_byte(byte_count,clip))header_bad<=1;
   if(state==PCM)begin
    if(!byte_count[0])low_byte<=sec_data;
    else if(fifo_write)written<=written+1'b1;
    else if(!kill&&!reset_sync[2]&&written<total)begin fault<=1;ready<=0;kill<=1;end
   end
  end
  case(state)
   IDLE:if(!reset_sync[2]&&pending)begin
    clip<=clip_sync[1];sec_addr<=clip_sync[1]?ROBOT_AUDIO_B:ROBOT_AUDIO_A;
    written<=0;byte_count<=0;kill<=0;header_bad<=0;fault<=0;ready<=0;
    sec_req<=1;pending<=0;state<=HEADER;
   end
   HEADER,PCM:begin
    if(sec_error)begin fault<=1;ready<=0;sec_req<=0;state<=DONE;end
    else if(sec_end)begin
     sec_req<=0;
     if(kill||reset_sync[2])begin ready<=0;state<=IDLE;end
     else if(byte_count!=512||(state==HEADER&&header_bad))begin fault<=1;ready<=0;state<=DONE;end
     else begin sec_addr<=sec_addr+1'b1;state<=GAP;end
    end
   end
   GAP:begin
    byte_count<=0;
    if(reset_sync[2]||kill)state<=IDLE;
    else if(written>=total)state<=DONE;
    else if(fifo_used<=256&&!fifo_full)begin sec_req<=1;state<=PCM;end
   end
   DONE:if(reset_sync[2])state<=IDLE;
   default:state<=IDLE;
  endcase
 end
endmodule
