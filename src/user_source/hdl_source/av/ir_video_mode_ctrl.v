`timescale 1ns/1ps
// Physical digit 0 measured 2026-10-28: 00 FF 19 E6. One toggle per press.
module ir_video_mode_ctrl #(
 parameter integer CLK_HZ=25000000,RELEASE_CYCLES=CLK_HZ/5
)(input clk,rst,frame_valid,repeat_valid,frame_error,input [31:0] raw_bytes,
 output reg video_mode,output reg press_event);
localparam integer AGE_BITS=$clog2(RELEASE_CYCLES+1);
reg [AGE_BITS-1:0] age;
reg held;
wire matched=raw_bytes==32'h00ff19e6;
always @(posedge clk or posedge rst)
 if(rst)begin age<=0;held<=0;video_mode<=0;press_event<=0;end
 else begin
  press_event<=0;
  if(age<RELEASE_CYCLES)age<=age+1'b1;else held<=0;
  if(!frame_error)begin
   if(frame_valid)begin
    if(!matched)held<=0;
    else begin
     held<=1;age<=0;
     if(!held||age>=RELEASE_CYCLES)begin video_mode<=!video_mode;press_event<=1;end
    end
   end else if(repeat_valid&&held&&age<RELEASE_CYCLES)age<=0;
  end
 end
endmodule
