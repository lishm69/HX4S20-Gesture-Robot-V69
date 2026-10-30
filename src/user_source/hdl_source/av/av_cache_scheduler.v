`timescale 1ns/1ps
// Three complete SDRAM canvases. Payload for display/audio is independent of
// speculative loader metadata and stays stable for the complete toggle handshake.
module av_cache_scheduler #(
 parameter integer CLK_HZ=50000000,HOLD_SECONDS=3,SCENES=7,SUSPEND_ENABLE=0
)(
 input suspend,input resume_request_toggle,output reg suspended,
 input clk,rst,header_ok,details_available,near_active,next_press,auto_press,alarm,
 input voice_done,input [3:0] voice_scene,
 input bmp_ready,bmp_error,write_req,write_ack,
 input write_done_toggle,display_done_toggle,scene_start_toggle,input bmp_sector_busy,
 output reg bmp_start,output reg bmp_reset,
 output reg [3:0] load_scene,output reg load_detail,output reg [1:0] write_slot,
 output reg [3:0] target_scene,output reg target_detail,output reg [1:0] display_slot,
 output reg request_toggle,output reg scene_change,output reg display_valid,
 output reg [3:0] current_scene,output reg display_detail,output reg first_done,
 output reg auto_enabled,output reg [2:0] state,
 output reg [$clog2(CLK_HZ*HOLD_SECONDS+1)-1:0] hold_count
);
localparam IDLE=0,LOAD=1,TRANSITION=2,ERROR=3,CANCEL=4;
reg [2:0] valid,kind;
reg [3:0] tag[0:2];
reg source_seen,source_done,write_done,write_armed,wr_seen,start_seen;
reg next_pending,detail_failed,skip_recovery;
reg [3:0] recovery_scene;
reg [$clog2(CLK_HZ+1)-1:0] resume_count;
reg [4:0] cancel_wait;
wire near_now=details_available&&!detail_failed&&near_active;
wire [3:0] next_scene=current_scene==SCENES-1 ? 0 : current_scene+1'b1;
wire auto_due=first_done&&auto_enabled&&!near_now&&!display_detail&&resume_count==0&&
 ((current_scene<5&&voice_done&&voice_scene==current_scene)||
  (current_scene>=5&&hold_count>=CLK_HZ*HOLD_SECONDS-1));
wire [3:0] wanted_scene=skip_recovery ? recovery_scene : !first_done ? 0 :
 (next_pending||auto_due) ? next_scene : current_scene;
wire wanted_detail=near_now;
wire display_needed=!first_done||next_pending||auto_due||display_detail!=near_now;
reg [1:0] hit_wanted,hit_photo,hit_detail,hit_next,victim;
reg task_needed,foreground,task_detail;
reg [2:0] free_slots,obsolete_slots,replace_slots;
reg [3:0] task_scene;
integer i,j;
// Simulation counters have no hardware fanout and are removed by synthesis.
reg [31:0] cache_hits,loads_started,cancellations;
always @* begin
 hit_wanted=3;hit_photo=3;hit_detail=3;hit_next=3;
 for(i=0;i<3;i=i+1)if(valid[i])begin
  if(tag[i]==wanted_scene&&kind[i]==wanted_detail)hit_wanted=i;
  if(tag[i]==current_scene&&!kind[i])hit_photo=i;
  if(tag[i]==current_scene&&kind[i])hit_detail=i;
  if(tag[i]==next_scene&&!kind[i])hit_next=i;
 end
 task_needed=0;foreground=0;task_scene=wanted_scene;task_detail=wanted_detail;
 if(display_needed&&hit_wanted==3)begin task_needed=1;foreground=1;end
 else if(!display_needed&&first_done)begin
  if(hit_photo==3)begin task_needed=1;task_scene=current_scene;task_detail=0;end
  else if(details_available&&!detail_failed&&hit_detail==3)begin task_needed=1;task_scene=current_scene;task_detail=1;end
  else if(hit_next==3)begin task_needed=1;task_scene=next_scene;task_detail=0;end
 end
 // Evaluate eligibility in parallel; preserve original free/obsolete/foreground
 // priorities and the lowest eligible slot. Avoid cascading victim==3 muxes.
 for(i=0;i<3;i=i+1)begin
  free_slots[i]=(!display_valid||i!=display_slot)&&!valid[i];
  obsolete_slots[i]=i!=display_slot&&tag[i]!=current_scene&&!(tag[i]==task_scene&&kind[i]!=task_detail);
  replace_slots[i]=i!=display_slot&&!(tag[i]==task_scene&&kind[i]!=task_detail);
 end
 if(|free_slots)victim=free_slots[0]?0:free_slots[1]?1:2;
 else if(|obsolete_slots)victim=obsolete_slots[0]?0:obsolete_slots[1]?1:2;
 else if(foreground&&(|replace_slots))victim=replace_slots[0]?0:replace_slots[1]?1:2;
 else victim=3;
end
always @(posedge clk or posedge rst)
 if(rst)begin
  valid<=0;kind<=0;for(j=0;j<3;j=j+1)tag[j]<=0;
  state<=IDLE;bmp_start<=0;bmp_reset<=0;load_scene<=0;load_detail<=0;write_slot<=0;
  target_scene<=0;target_detail<=0;display_slot<=0;request_toggle<=0;scene_change<=1;
  display_valid<=0;current_scene<=0;display_detail<=0;first_done<=0;auto_enabled<=0;
  hold_count<=0;resume_count<=0;next_pending<=0;detail_failed<=0;skip_recovery<=0;recovery_scene<=0;
  source_seen<=0;source_done<=0;write_done<=0;write_armed<=0;wr_seen<=0;start_seen<=0;cancel_wait<=0;
  suspended<=0;cache_hits<=0;loads_started<=0;cancellations<=0;
 end else begin
  bmp_start<=0;
  if(scene_start_toggle!=start_seen)begin
   start_seen<=scene_start_toggle;current_scene<=target_scene;display_detail<=target_detail;
  end
  if(auto_press&&header_ok&&!alarm&&!(SUSPEND_ENABLE&&suspend))begin auto_enabled<=!auto_enabled;hold_count<=0;end
  if(next_press&&header_ok&&!alarm&&!(SUSPEND_ENABLE&&suspend))next_pending<=1;
  if(near_now||display_detail)resume_count<=CLK_HZ;
  else if(resume_count!=0)resume_count<=resume_count-1'b1;
  if(alarm||auto_press)begin hold_count<=0;if(alarm)next_pending<=0;end
  else if(near_now||display_detail||(state==TRANSITION&&!scene_change))hold_count<=hold_count;
  else if(auto_enabled&&first_done&&current_scene>=5&&state!=TRANSITION)begin
   if(hold_count<CLK_HZ*HOLD_SECONDS)hold_count<=hold_count+1'b1;
  end else hold_count<=0;
  if(SUSPEND_ENABLE&&suspend)begin
   hold_count<=hold_count;resume_count<=resume_count;next_pending<=0;
   if(state==IDLE)begin
    bmp_reset<=1;
    // Cache payload/slot stays pinned until the video reader restores it.
    request_toggle<=resume_request_toggle;
    for(j=0;j<3;j=j+1)if(!display_valid||j!=display_slot)valid[j]<=0;
    if(!bmp_sector_busy)suspended<=1;
   end
  end else if(SUSPEND_ENABLE&&suspended)begin suspended<=0;bmp_reset<=0;end
  case(state)
   IDLE:begin
    if(!(SUSPEND_ENABLE&&suspend))bmp_reset<=0;write_armed<=0;wr_seen<=write_done_toggle;
    if(header_ok&&!alarm&&!(SUSPEND_ENABLE&&suspend)&&!suspended)begin
     if(display_needed&&hit_wanted!=3)begin
      target_scene<=wanted_scene;target_detail<=wanted_detail;display_slot<=hit_wanted;
      scene_change<=!first_done||wanted_scene!=current_scene;
      request_toggle<=!request_toggle;display_valid<=1;state<=TRANSITION;cache_hits<=cache_hits+1'b1;
      if(!first_done||wanted_scene!=current_scene)begin next_pending<=0;hold_count<=0;skip_recovery<=0;end
     end else if(task_needed&&victim!=3&&bmp_ready)begin
      load_scene<=task_scene;load_detail<=task_detail;write_slot<=victim;
      valid[victim]<=0;source_seen<=0;source_done<=0;write_done<=0;
      bmp_start<=1;state<=LOAD;loads_started<=loads_started+1'b1;
     end
    end
   end
   LOAD:begin
    if(!bmp_ready)source_seen<=1;
    if(source_seen&&bmp_ready)source_done<=1;
    if(write_req&&write_ack)begin write_armed<=1;wr_seen<=write_done_toggle;end
    else if(write_armed&&write_done_toggle!=wr_seen)begin write_done<=1;wr_seen<=write_done_toggle;end
    if(source_done&&write_done)begin
     tag[write_slot]<=load_scene;kind[write_slot]<=load_detail;valid[write_slot]<=1;
     state<=IDLE;
    end else if((SUSPEND_ENABLE&&suspend)||(display_needed&&(load_scene!=wanted_scene||load_detail!=wanted_detail)&&!alarm))begin
     // Reset only the producer/cache, then drain the already-owned physical
     // sector. The partial hidden framebuffer remains invalid. Its FIFO is
     // cleared by the next full-frame request after the active SDRAM burst.
     bmp_reset<=1;state<=CANCEL;cancel_wait<=0;write_armed<=0;
     cancellations<=cancellations+1'b1;
    end
   end
   CANCEL:begin
    if(cancel_wait!=31)cancel_wait<=cancel_wait+1'b1;
    if(cancel_wait>=8&&!bmp_sector_busy)begin bmp_reset<=0;state<=IDLE;wr_seen<=write_done_toggle;end
   end
   TRANSITION:if(display_done_toggle==request_toggle)begin
    current_scene<=target_scene;display_detail<=target_detail;first_done<=1;state<=IDLE;
    if(scene_change)hold_count<=0;
   end
   ERROR:if(next_press&&!alarm)begin
    recovery_scene<=load_scene==SCENES-1 ? 0 : load_scene+1'b1;
    skip_recovery<=1;next_pending<=1;state<=IDLE;
   end
   default:state<=IDLE;
  endcase
  if(bmp_error&&state==LOAD)begin
   valid[write_slot]<=0;source_done<=0;write_done<=0;write_armed<=0;
   if(load_detail)begin detail_failed<=1;state<=IDLE;end
   else state<=ERROR;
  end
 end
endmodule
