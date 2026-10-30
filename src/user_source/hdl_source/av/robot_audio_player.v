`timescale 1ns/1ps
// Audio starts only on the committed first video frame. It is re-anchored on
// every loop and clip change; an alarm/exit immediately silences and drains it.
module robot_audio_player(
 input clk,rst,sample_tick48,enable,scene_start,target_video,target_clip,
 input [6:0] target_frame,
 output reg stream_reset,output reg stream_clip,
 input reset_ack,stream_ready,
 output fifo_reset,output fifo_read,input [15:0] fifo_data,
 input fifo_valid,fifo_empty,
 output reg [23:0] pcm_sample,output reg pcm_valid,
 output reg [31:0] underruns
);
(* async_reg="true" *)reg [1:0] ack_sync,ready_sync;
always @(posedge clk or posedge rst)
 if(rst)begin ack_sync<=3;ready_sync<=0;end
 else begin ack_sync<={ack_sync[0],reset_ack};ready_sync<={ready_sync[0],stream_ready};end
localparam HOLD=0,RESET=1,ACK_LOW=2,PRIME=3,PLAY=4,DONE=5;
reg [2:0] state,phase;
reg prefetched,read_pending;
reg [15:0] prefetched_sample,held_sample,remaining;
assign fifo_reset=rst||stream_reset;
assign fifo_read=enable&&(state==PRIME||state==PLAY)&&!stream_reset&&
 !prefetched&&!read_pending&&!fifo_empty&&remaining!=0;
always @(posedge clk or posedge rst)
 if(rst)begin
  state<=HOLD;phase<=0;stream_reset<=1;stream_clip<=0;
  prefetched<=0;read_pending<=0;prefetched_sample<=0;held_sample<=0;
  remaining<=0;pcm_sample<=0;pcm_valid<=0;underruns<=0;
 end else begin
  pcm_valid<=sample_tick48;
  if(fifo_read)read_pending<=1;
  if(fifo_valid&&!stream_reset)begin prefetched_sample<=fifo_data;prefetched<=1;read_pending<=0;end
  case(state)
   RESET:if(ack_sync[1])begin stream_reset<=0;state<=ACK_LOW;end
   ACK_LOW:if(!ack_sync[1])state<=PRIME;
   PRIME:if(ready_sync[1]&&prefetched)begin state<=PLAY;phase<=0;end
   default:begin end
  endcase
  if(sample_tick48)begin
   pcm_sample<=0;
   if(enable&&state==PLAY)begin
    if(phase==0)begin
     if(remaining==0)begin state<=DONE;held_sample<=0;end
     else if(prefetched)begin
      held_sample<=prefetched_sample;pcm_sample<={prefetched_sample,8'd0};
      prefetched<=0;remaining<=remaining-1'b1;phase<=1;
     end else begin held_sample<=0;underruns<=underruns+1'b1;end
    end else begin pcm_sample<={held_sample,8'd0};phase<=phase==5?0:phase+1'b1;end
   end
  end
  if(!enable)begin
   state<=HOLD;stream_reset<=1;prefetched<=0;read_pending<=0;held_sample<=0;
   phase<=0;remaining<=0;pcm_sample<=0;
  end else if(scene_start&&target_video&&target_frame==0)begin
   stream_clip<=target_clip;stream_reset<=1;state<=RESET;
   prefetched<=0;read_pending<=0;held_sample<=0;phase<=0;
   remaining<=target_clip?16'd48000:16'd32000;pcm_sample<=0;
  end
 end
endmodule
