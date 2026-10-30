`timescale 1ns/1ps
// All PCM sample decisions run in the video domain. HDMI consumes native PCM;
// there is no internal I2S serialization / asynchronous multi-bit resampling.
module av_scene_player #(
 parameter integer MUTE_ENABLE=0,
 parameter integer VIDEO_HZ=25000000,
 parameter integer BEEP_SAMPLES=3840,
 parameter integer REPEAT_GAP_SAMPLES=72000
)(
 input mute_media,
 input clk,input rst,input sample_tick48,
 input image_req_toggle,input [3:0] target_scene,input scene_start,
 input alarm_active,input alarm_muted,input auto_enabled,
 output reg stream_reset,output reg [2:0] stream_group,
 input stream_reset_ack,input stream_ready,
 output media_ready,output fifo_rd_rst,output fifo_rd_en,
 input [15:0] fifo_rd_data,input fifo_rd_valid,input fifo_empty,
 output reg [3:0] voice_scene,output reg voice_done,
 output reg [2:0] subtitle_group,output reg subtitle_restart,
 output reg pcm_valid,output reg [23:0] pcm_sample,
 output music_buzzer_n,output music_active,output prompt_buzzer_n,
 output reg [31:0] underrun_count
);
`include "av_resources.vh"
(* async_reg="true" *) reg [2:0] req_sync;
(* async_reg="true" *) reg [1:0] ack_sync,ready_sync,auto_sync;
reg req_seen,alarm_d;
reg [3:0] prepared_scene;
reg [2:0] group_id;
reg committed,playing,prefetched,read_pending,repeat_start;
reg [2:0] state;
localparam WAIT_ACK1=0,WAIT_ACK0=1,PRIME=2,READY=3;
reg [31:0] remaining;
reg [16:0] gap_samples;
reg [15:0] beep_left;
reg [5:0] beep_phase;
reg [1:0] sub_sample;
reg signed [15:0] prefetched_sample,held_sample;
wire [2:0] requested_group=target_scene<5 ? target_scene[2:0] : 3'd5;
wire new_request=req_sync[2]!=req_seen;
wire media_muted=MUTE_ENABLE&&mute_media;
assign fifo_rd_rst=rst||stream_reset;
// Muting freezes consumption, but one sample must still prime a pending photo
// transition so video-mode entry cannot deadlock waiting for media_ready.
assign fifo_rd_en=group_id<5&&(state==PRIME||state==READY)&&!stream_reset&&
 !prefetched&&!read_pending&&!fifo_empty&&remaining!=0;
assign media_ready=group_id==5 ? 1'b1 : state==READY&&prefetched;
wire melody_n,melody_on;
buzzer_daoxiang_visual #(.CLK_HZ(VIDEO_HZ)) u_melody(
 .clk(clk),.rst(rst||group_id!=5||!committed||alarm_active||media_muted),
 .buzzer_n(melody_n),.audio_active(melody_on));
assign music_buzzer_n=group_id==5&&committed&&!alarm_active&&!media_muted ? melody_n : 1'b1;
assign music_active=group_id==5&&committed&&!alarm_active&&!media_muted&&melody_on;
assign prompt_buzzer_n=beep_left!=0&&!alarm_active&&!media_muted ? beep_phase>=24 : 1'b1;
wire alarm_n;
alarm_siren #(.CLK_HZ(VIDEO_HZ)) u_siren(.clk(clk),.rst(rst),
 .enable(alarm_active&&!alarm_muted),.buzzer_n(alarm_n));
always @(posedge clk or posedge rst)
 if(rst)begin req_sync<=0;ack_sync<=0;ready_sync<=0;auto_sync<=0;end
 else begin
  req_sync<={req_sync[1:0],image_req_toggle};
  ack_sync<={ack_sync[0],stream_reset_ack};ready_sync<={ready_sync[0],stream_ready};
  auto_sync<={auto_sync[0],auto_enabled};
 end
always @(posedge clk or posedge rst)
 if(rst)begin
  stream_reset<=1;stream_group<=7;req_seen<=0;prepared_scene<=0;group_id<=7;
  state<=WAIT_ACK1;committed<=0;playing<=0;prefetched<=0;read_pending<=0;
  remaining<=0;gap_samples<=0;beep_left<=0;beep_phase<=0;sub_sample<=0;
  held_sample<=0;prefetched_sample<=0;voice_scene<=0;voice_done<=0;
  subtitle_group<=0;subtitle_restart<=0;pcm_valid<=0;pcm_sample<=0;
  repeat_start<=0;alarm_d<=0;underrun_count<=0;
 end else begin
  pcm_valid<=sample_tick48;subtitle_restart<=0;alarm_d<=alarm_active;
  if(fifo_rd_en)read_pending<=1;
  if(fifo_rd_valid)begin prefetched_sample<=$signed(fifo_rd_data);prefetched<=1;read_pending<=0;end
  case(state)
   WAIT_ACK1:if(ack_sync[1])begin stream_reset<=0;state<=WAIT_ACK0;end
   WAIT_ACK0:if(!ack_sync[1])state<=PRIME;
   PRIME:if(ready_sync[1]&&prefetched)begin
    state<=READY;
    if(repeat_start)begin playing<=1;repeat_start<=0;voice_done<=0;end
   end
   default:begin end
  endcase
  if(sample_tick48)begin
   pcm_sample<=0;
   if(alarm_active)begin
    if(!alarm_muted)pcm_sample<=alarm_n ? -24'sd2048000 : 24'sd2048000;
   end else if(media_muted)begin
    pcm_sample<=0;
   end else if(group_id==5&&committed)begin
    if(melody_on)pcm_sample<=melody_n ? -24'sd1536000 : 24'sd1536000;
   end else if(beep_left!=0)begin
    beep_left<=beep_left-1'b1;
    beep_phase<=beep_phase==47 ? 0 : beep_phase+1'b1;
    pcm_sample<=beep_phase>=24 ? -24'sd1024000 : 24'sd1024000;
   end else if(playing&&state==READY)begin
    if(sub_sample==0)begin
     if(remaining==0)begin playing<=0;voice_done<=1;gap_samples<=0;held_sample<=0;end
     else if(prefetched)begin
      held_sample<=prefetched_sample;pcm_sample<={prefetched_sample,8'd0};
      prefetched<=0;remaining<=remaining-1'b1;sub_sample<=1;
     end else begin underrun_count<=underrun_count+1'b1;held_sample<=0;end
    end else begin
     pcm_sample<={held_sample,8'd0};sub_sample<=sub_sample==2 ? 0 : sub_sample+1'b1;
    end
   end else if(voice_done&&committed&&group_id<5&&!auto_sync[1]&&state==READY)begin
    if(gap_samples==REPEAT_GAP_SAMPLES-1)begin
     stream_reset<=1;state<=WAIT_ACK1;remaining<=av_audio_samples({1'b0,group_id});
     prefetched<=0;read_pending<=0;gap_samples<=0;repeat_start<=1;sub_sample<=0;
     voice_done<=0;
    end else gap_samples<=gap_samples+1'b1;
   end
  end
  if(new_request)begin
   req_seen<=req_sync[2];prepared_scene<=target_scene;
   if(requested_group!=group_id)begin
    group_id<=requested_group;stream_group<=requested_group;
    stream_reset<=1;state<=WAIT_ACK1;prefetched<=0;read_pending<=0;committed<=0;
    playing<=0;voice_done<=0;repeat_start<=0;beep_left<=0;sub_sample<=0;
    remaining<=av_audio_samples({1'b0,requested_group});
   end
  end
  if(scene_start)begin
   committed<=1;
   if(subtitle_group!=group_id||group_id<5)begin subtitle_group<=group_id;subtitle_restart<=1;end
   if(group_id<5)begin
    voice_scene<=prepared_scene;voice_done<=0;playing<=1;sub_sample<=0;
    beep_left<=BEEP_SAMPLES;beep_phase<=0;gap_samples<=0;
   end
  end
  if(media_muted)beep_left<=0;
  if(alarm_active)begin playing<=0;voice_done<=0;beep_left<=0;end
  if(alarm_d&&!alarm_active)begin
   subtitle_restart<=1;
   if(group_id<5)begin
    stream_reset<=1;state<=WAIT_ACK1;remaining<=av_audio_samples({1'b0,group_id});
    prefetched<=0;read_pending<=0;repeat_start<=committed;sub_sample<=0;voice_done<=0;
   end
  end
 end
endmodule
