from pathlib import Path
R=Path('C:/Users/ASUS/Desktop/HX4S20_Refactored_20261023/HX4S20_Refactored_20261023')
V=R/'verification/robot_v67'
old=(V/'tb_cache_board.sv').read_text()
head=old[:old.index('// Shorten voice sample count only;')].replace('module tb_cache_board;','module tb_robot_board;')
head=head.replace('initial force dut.proximity_near=close;','initial begin force dut.proximity_near=close;force dut.robot_near=close;end')
head+='defparam dut.u_video_mode_ctrl.RELEASE_CYCLES=200000;\ndefparam dut.sd_card_bmp_m0.g_robot.u_ctrl.CLK_HZ=50000000;\ndefparam dut.sd_card_bmp_m0.g_robot.u_ctrl.FPS=50000;\n'
helpers=old[old.index('task auto_key;'):old.index('integer ordinary_steps=')]
tail=old[old.index('module sys_pll('):]
tail=tail.replace('../../doc/video_v65/HDMI_AV_V65_LogoLoop_TF_RAW.img','../../doc/robot_v67/HDMI_AV_V67_Robot_TF_RAW.img')
start=tail.index('assign write_ready=1;');end=tail.index('\nendmodule',start)
tail=tail[:start]+r'''reg [31:0] memory[0:921599];
reg [2:0] req_r,finish_sync;
reg finish_toggle=0,finish_seen=0;
integer rc,wr_count=0,wr_delay=0,clock_count=0;
reg writing=0;reg [1:0] writing_slot=0;
reg [2:0] valid_slots=0;
assign write_ready=clock_count%13>2;
assign bg_busy=0;assign App_rd_en=0;assign App_rd_addr=0;assign App_wr_en=0;assign App_wr_addr=0;assign App_wr_din=0;assign App_wr_dm=0;
always @(posedge write_clk)begin
 clock_count<=clock_count+1;
 if(rst)begin writing<=0;write_req_ack<=0;wr_count<=0;wr_delay<=0;finish_toggle<=0;valid_slots<=0;end
 else begin
  if(write_req&&!write_req_ack)begin
   writing_slot<=write_addr_index;wr_count<=0;write_req_ack<=1;writing<=0;wr_delay<=0;
   valid_slots[write_addr_index]<=0;
  end else if(write_req_ack&&!write_req)begin write_req_ack<=0;writing<=1;end
  if(write_en)begin
   if(!write_ready||!writing||wr_count>=307200)$fatal(1,"frame writer contract count=%d slot=%d",wr_count,writing_slot);
   if(tb_robot_board.dut.sd_card_bmp_m0.robot_claim&&writing_slot==tb_robot_board.dut.sd_card_bmp_m0.g_robot.u_ctrl.keep_slot)$fatal(1,"video overwrote preserved photo");
   if(tb_robot_board.dut.robot_display_video&&writing_slot==read_active_index)$fatal(1,"writing active reader slot");
   memory[writing_slot*307200+wr_count]<=write_data;wr_count<=wr_count+1;
   if(wr_count==307199)begin writing<=0;wr_delay<=16;valid_slots[writing_slot]<=1;end
  end
  if(wr_delay>0)begin wr_delay<=wr_delay-1;if(wr_delay==1)finish_toggle<=!finish_toggle;end
 end
end
always @(posedge mem_clk or posedge rst)begin
 if(rst)begin req_r<=0;rc<=0;read_req_ack<=0;read_finish<=0;write_finish<=0;read_active_index<=0;finish_sync<=0;finish_seen<=0;end
 else begin
  req_r<={req_r[1:0],read_req};read_finish<=0;
  finish_sync<={finish_sync[1:0],finish_toggle};finish_seen<=finish_sync[2];
  write_finish<=finish_sync[2]!=finish_seen;
  if(rc==0&&req_r[2])begin read_req_ack<=1;read_active_index<=read_addr_index;rc<=1;end
  else if(rc!=0)begin
   if(!req_r[2])read_req_ack<=0;
   rc<=rc+1;if(rc==80)begin read_finish<=1;rc<=0;end
  end
 end
end
always @(posedge read_clk)begin
 if(rst)read_data<=0;
 else if(valid_slots[read_active_index])read_data<=memory[read_active_index*307200];
 else read_data<=0;
end
'''+tail[end:]
main=r'''
task repeat_packet;
begin irpulse(0,9000);irpulse(1,2250);irpulse(0,562);irpulse(1,60000);end endtask
integer video_commits=0,last_frame=-1;reg last_clip=0;
reg [1:0] saved_slot;integer saved_scene,old_commits;reg saved_auto;
always @(posedge dut.video_clk)if(!dut.rst_all)begin
 if(dut.sd_card_bmp_m0.robot_fault)$fatal(1,"robot fault ctrl=%d loader=%d pixels=%d payload=%d",dut.sd_card_bmp_m0.g_robot.u_ctrl.state,dut.sd_card_bmp_m0.g_robot.u_loader.state,dut.sd_card_bmp_m0.g_robot.u_loader.pixels,dut.sd_card_bmp_m0.g_robot.u_loader.payload_used);
 if(dut.av_scene_start&&dut.robot_display_target)begin
  video_commits++;last_frame=dut.sd_card_bmp_m0.g_robot.u_ctrl.frame_number;
  last_clip=dut.sd_card_bmp_m0.g_robot.u_ctrl.clip;
  $display("VIDEO commit=%d clip=%b frame=%d t=%t",video_commits,last_clip,last_frame,$time);
 end
 if(dut.robot_display_video)begin
  if(dut.u_osd_scroll.enable||dut.u_audio_visual.enable||!dut.u_dance_overlay.alarm)$fatal(1,"old decoration visible in video mode");
  if(!dut.alarm_active&&dut.audio_valid&&dut.audio_left_data!==0)$fatal(1,"old audio leaks into silent video");
 end
end
task quiet_gap;begin irpulse(1,210000);end endtask
task check_video_ui;
begin
 repeat(600)@(negedge dut.video_clk);
 if(!dut.robot_display_video||dut.detail_display_video)$fatal(1,"video/detail state");
 if(!dut.u_parameter_osd.osd_enable)$fatal(1,"parameter popup disabled by video");
end endtask
initial begin
 #101;rst_n=1;
 wait(dut.current_image_number==1&&dut.sd_card_bmp_m0.photo_state==0);
 packet(8'h19);wait(dut.robot_mode_requested);
 repeat_packet;repeat_packet;repeat_packet;repeat_packet;
 wait(dut.robot_display_video&&dut.sd_card_bmp_m0.robot_valid);
 saved_slot=dut.sd_card_bmp_m0.g_robot.u_ctrl.keep_slot;saved_scene=dut.current_image_number;saved_auto=dut.av_auto;
 check_video_ui;old_commits=video_commits;
 repeat_packet;repeat_packet;packet(8'h19);
 if(!dut.robot_mode_requested)$fatal(1,"held0 toggled mode");
 wait(video_commits>=old_commits+2);if(last_clip||last_frame<1)$fatal(1,"idle not advancing");
 param_key;repeat(1000)@(negedge dut.video_clk);
 if(dut.display_brightness!=8)$fatal(1,"video brightness adjustment");
 sel=1;repeat(12)@(negedge dut.video_clk);param_key;repeat(1000)@(negedge dut.video_clk);
 if(dut.display_contrast!=288)$fatal(1,"video contrast adjustment %d",dut.display_contrast);sel=0;
 packet(8'h52);wait(dut.volume_level==15);check_video_ui;
 if(!dut.u_parameter_osd.show_frame||dut.u_parameter_osd.kind_frame!=2)$fatal(1,"volume HUD missing in video");
 auto_key;@(negedge dut.sd_card_clk);key_next=0;repeat(15)@(negedge dut.sd_card_clk);key_next=1;
 if(dut.av_auto!=saved_auto||dut.current_image_number!=saved_scene)$fatal(1,"photo controls advanced suspended scene");
 close=1;wait(last_clip&&last_frame==0);wait(last_clip&&last_frame>=1);
 close=0;wait(!last_clip&&last_frame==0);
 packet(8'h45);if(!dut.alarm_active)$fatal(1,"alarm not accepted in video");
 repeat(600)@(negedge dut.video_clk);if(!dut.u_emergency_video.alarm_frame||dut.u_parameter_osd.show_frame)$fatal(1,"alarm display priority");
 packet(8'h47);repeat(600)@(negedge dut.video_clk);
 if(!dut.alarm_muted||dut.audio_left_data!==0||buzzer!==1)$fatal(1,"alarm mute in video");
 packet(8'h44);if(dut.alarm_muted)$fatal(1,"alarm unmute in video");
 packet(8'h46);if(dut.alarm_active)$fatal(1,"alarm clear in video");
 old_commits=video_commits;wait(video_commits>old_commits);
 quiet_gap;packet(8'h19);wait(!dut.robot_mode_requested);
 wait(!dut.sd_card_bmp_m0.robot_claim&&!dut.robot_display_video);
 if(dut.disp_buf_idx!=saved_slot||dut.current_image_number!=saved_scene||dut.av_auto!=saved_auto)$fatal(1,"photo restoration failed");
 if(dut.display_brightness!=8||dut.display_contrast!=288||dut.volume_level!=15)$fatal(1,"parameters lost across modes");
 wait(dut.u_dance_stream.loaded);if(dut.u_dance_stream.failed)$fatal(1,"small video not restored");
 // Enter while a new scene is waiting for freshly primed audio. Video muting
 // must let this outstanding photo transition settle before taking ownership.
 @(negedge dut.sd_card_clk);key_next=0;repeat(15)@(negedge dut.sd_card_clk);key_next=1;
 wait(dut.sd_card_bmp_m0.photo_state==2&&dut.logical_scene_change);
 force dut.u_av_player.state=0;force dut.u_av_player.stream_reset=1;
 quiet_gap;close=1;packet(8'h19);wait(dut.robot_mode_requested);
 release dut.u_av_player.state;release dut.u_av_player.stream_reset;
 wait(dut.robot_display_video&&last_clip&&last_frame==0);
 check_video_ui;quiet_gap;packet(8'h19);wait(!dut.sd_card_bmp_m0.robot_claim&&!dut.robot_display_video);
 wait(dut.detail_display_video);close=0;wait(!dut.detail_display_video);
 if(dut.sd_card_bmp_m0.robot_fault||dut.av_media_errors)$fatal(1,"media errors");
 $display("PASS tb_robot_board: actual top, real new TF image, full written frame memory model, measured serial digit0 and hold filtering, advancing idle/welcome, near/far clip0, hidden subtitles/spectrum/small video, brightness/contrast/volume HUD, silent PCM, ignored photo keys, alarm1/3/4/2, preserved photo slot/scene/auto/parameters, old animation restoration and near-mode reentry (%d video commits)",video_commits);$finish;
end
initial begin #(64'd1200000000);$fatal(1,"robot top timeout mode=%b display=%b ctrl=%d loader=%d photo=%d",dut.robot_mode_requested,dut.robot_display_video,dut.sd_card_bmp_m0.g_robot.u_ctrl.state,dut.sd_card_bmp_m0.g_robot.u_loader.state,dut.sd_card_bmp_m0.photo_state);end
endmodule
'''
(V/'tb_robot_board.sv').write_text(head+helpers+main+tail,encoding='utf-8')
early=r'''
task repeat_packet;
begin irpulse(0,9000);irpulse(1,2250);irpulse(0,562);irpulse(1,60000);end endtask
reg saw_invalid_restore=0;
always @(posedge dut.video_clk)if(!dut.rst_all)begin
 if(dut.sd_card_bmp_m0.robot_fault)$fatal(1,"early mode video fault");
 if(dut.sd_card_bmp_m0.robot_claim&&!dut.sd_card_bmp_m0.robot_target&&
    dut.sd_card_bmp_m0.robot_valid&&!dut.sd_card_bmp_m0.valid_image)begin
  saw_invalid_restore=1;
  if(dut.display_valid)$fatal(1,"uninitialized photo exposed on early exit");
 end
end
initial begin
 #101;rst_n=1;packet(8'h19);repeat_packet;repeat_packet;repeat_packet;repeat_packet;
 wait(dut.robot_display_video&&dut.sd_card_bmp_m0.robot_valid);
 if(dut.sd_card_bmp_m0.valid_image)$fatal(1,"early entry case was not exercised");
 irpulse(1,210000);packet(8'h19);
 wait(!dut.sd_card_bmp_m0.robot_claim&&!dut.robot_display_video);
 if(!saw_invalid_restore)$fatal(1,"invalid-photo restore not exercised");
 wait(dut.current_image_number==1&&dut.sd_card_bmp_m0.photo_state==0);
 if(!dut.display_valid||dut.av_media_errors)$fatal(1,"first photo did not recover");
 $display("PASS tb_robot_early: serial digit0 before first photo load, interrupted initial scaler, successful video entry, black instead of uninitialized pinned slot on exit, and initial photo recovery");$finish;
end
initial begin #(64'd600000000);$fatal(1,"early entry timeout");end
endmodule
'''
(V/'tb_robot_early.sv').write_text((head+helpers+early+tail).replace('tb_robot_board','tb_robot_early'),encoding='utf-8')
print(V/'tb_robot_board.sv')
