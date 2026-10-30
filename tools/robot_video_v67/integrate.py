from pathlib import Path
import zipfile,re,shutil
R=Path('C:/Users/ASUS/Desktop/HX4S20_Refactored_20261023/HX4S20_Refactored_20261023')
H=R/'src/user_source/hdl_source'
Z=zipfile.ZipFile(R/'backup_before_robot_v67_20261028/V66_sources_and_release.zip')
def old(n):return Z.read('src/user_source/hdl_source/'+n).decode('utf-8-sig').replace('\r\n','\n')
def put(n,s):(H/n).write_text(s,encoding='utf-8')
# Safe photo suspension. Cancellation uses the existing producer-reset/sector-
# drain path. Invalidate all video-overwritten cache tags while preserving the
# pinned photo, its narration state, auto flag and logical scene.
s=old('av/av_cache_scheduler.v')
s=s.replace('HOLD_SECONDS=3,SCENES=7','HOLD_SECONDS=3,SCENES=7,SUSPEND_ENABLE=0')
s=s.replace(' input clk,rst,header_ok,',' input suspend,input resume_request_toggle,output reg suspended,\n input clk,rst,header_ok,')
s=s.replace('  cache_hits<=0;','  suspended<=0;cache_hits<=0;',1)
s=s.replace('auto_press&&header_ok&&!alarm','auto_press&&header_ok&&!alarm&&!(SUSPEND_ENABLE&&suspend)')
s=s.replace('next_press&&header_ok&&!alarm','next_press&&header_ok&&!alarm&&!(SUSPEND_ENABLE&&suspend)')
s=s.replace('  case(state)\n','''  if(SUSPEND_ENABLE&&suspend)begin
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
''',1)
s=s.replace('    bmp_reset<=0;write_armed<=0;','    if(!(SUSPEND_ENABLE&&suspend))bmp_reset<=0;write_armed<=0;',1)
s=s.replace('    if(header_ok&&!alarm)begin','    if(header_ok&&!alarm&&!(SUSPEND_ENABLE&&suspend)&&!suspended)begin',1)
s=s.replace('    end else if(display_needed&&','    end else if((SUSPEND_ENABLE&&suspend)||(display_needed&&',1)
s=s.replace('load_detail!=wanted_detail)&&!alarm)begin','load_detail!=wanted_detail)&&!alarm))begin',1)
put('av/av_cache_scheduler.v',s)

# Media core: keep the existing SD-card instance and whole-sector arbitration.
s=old('av/av_sd_media.v')
s=s.replace(' parameter integer DANCE_ENABLE=0,',' parameter integer VIDEO_ENABLE=0,\n parameter integer DANCE_ENABLE=0,',1)
s=s.replace(' input dance_req,',' input video_mode,input video_near,output video_target,output direct_switch,\n input dance_req,',1)
# All photo producer/mailbox outputs remain internal, only the ownership mux
# drives the original public ports. This prevents multiple always-block drivers.
split=s.index('`include "av_resources.vh"')
header,body=s[:split],s[split:]
names=['write_req','write_en','write_data','write_buf_idx','disp_buf_idx','image_req_toggle','target_scene','target_detail','request_scene_change']
for name in names:body=re.sub(r'\b'+name+r'\b','photo_'+name,body)
# Named module ports must keep their original names on the left of each dot.
for name in names:body=body.replace('.photo_'+name+'(','.'+name+'(')
header=header.replace('output reg [1:0] write_buf_idx','output [1:0] write_buf_idx').replace('output reg [1:0] disp_buf_idx','output [1:0] disp_buf_idx')
header=header.replace('output reg image_req_toggle','output image_req_toggle').replace('output reg [3:0] target_scene','output [3:0] target_scene')
header=header.replace('output reg target_detail','output target_detail').replace('output reg request_scene_change','output request_scene_change')
decl='''
wire photo_write_req,photo_write_en;wire [31:0] photo_write_data;
reg [1:0] photo_write_buf_idx,photo_disp_buf_idx;
reg photo_image_req_toggle,photo_target_detail,photo_request_scene_change;
reg [3:0] photo_target_scene;
wire robot_claim,robot_suspend,cache_suspended,robot_req,robot_target,robot_valid,robot_fault;
wire [1:0] robot_display_slot,robot_write_slot;
wire robot_sec_req,robot_sec_valid,robot_sec_end;
wire [31:0] robot_sec_addr;
wire robot_write_req,robot_write_en;wire [31:0] robot_write_data;
wire [3:0] robot_state;
(* async_reg="true" *)reg [1:0] mode_sync;
always @(posedge clk or posedge rst)if(rst)mode_sync<=0;else mode_sync<={mode_sync[0],video_mode};
assign robot_suspend=VIDEO_ENABLE&&(mode_sync[1]||robot_claim);
assign write_req=robot_claim?robot_write_req:photo_write_req;
assign write_en=robot_claim?robot_write_en:photo_write_en;
assign write_data=robot_claim?robot_write_data:photo_write_data;
assign write_buf_idx=robot_claim?robot_write_slot:photo_write_buf_idx;
assign disp_buf_idx=robot_claim?robot_display_slot:photo_disp_buf_idx;
assign image_req_toggle=robot_claim?robot_req:photo_image_req_toggle;
assign video_target=robot_claim&&robot_target;
assign direct_switch=robot_claim;
assign target_scene=photo_target_scene;
assign target_detail=video_target?1'b0:photo_target_detail;
assign request_scene_change=robot_claim?1'b0:photo_request_scene_change;
generate if(VIDEO_ENABLE)begin:g_robot
 wire load_start,loader_ready,loader_error,clip;wire [6:0] frame_number;
 robot_video_ctrl #(.CLK_HZ(CLK_FREQ_HZ)) u_ctrl(
  .clk(clk),.rst(rst),.want_mode(mode_sync[1]),.near_active(video_near),.pause(alarm_sync[1]),
  .cache_suspended(cache_suspended),.photo_slot(photo_disp_buf_idx),.photo_request(photo_image_req_toggle),
  .display_done_toggle(done_sync[2]),.write_done_toggle(wr_sync[2]),
  .loader_ready(loader_ready),.loader_error(loader_error),.write_req(robot_write_req),.write_ack(write_req_ack),
  .claim(robot_claim),.request_toggle(robot_req),.display_slot(robot_display_slot),.target_video(robot_target),
  .valid_frame(robot_valid),.fault(robot_fault),.load_start(load_start),.clip(clip),.frame_number(frame_number),
  .write_slot(robot_write_slot),.state_code(robot_state),.late_frames());
 robot_frame_loader u_loader(.clk(clk),.rst(rst),.start(load_start),.clip(clip),.frame_number(frame_number),
  .ready(loader_ready),.error(loader_error),.sec_req(robot_sec_req),.sec_addr(robot_sec_addr),.sec_data(sector_data),
  .sec_valid(robot_sec_valid),.sec_end(robot_sec_end),.sec_error(bus_state==BUS_FAILED),
  .write_req(robot_write_req),.write_ack(write_req_ack&&robot_claim),.write_ready(write_ready),
  .write_en(robot_write_en),.write_data(robot_write_data));
end else begin:g_no_robot
 assign robot_claim=0;assign robot_req=0;assign robot_target=0;assign robot_valid=0;assign robot_fault=0;
 assign robot_display_slot=0;assign robot_write_slot=0;assign robot_sec_req=0;assign robot_sec_addr=0;
 assign robot_write_req=0;assign robot_write_en=0;assign robot_write_data=0;assign robot_state=0;
end endgenerate
'''
body=body.replace('wire next_press,auto_press;',decl+'\nwire next_press,auto_press;',1)
body=body.replace('assign display_valid=valid_image;','assign display_valid=valid_image||(robot_valid&&video_target);')
body=body.replace("assign state_code=errors!=0 ?", "assign state_code=robot_claim ? robot_state : errors!=0 ?")
body=body.replace('av_cache_scheduler #(.CLK_HZ(CLK_FREQ_HZ),','av_cache_scheduler #(.SUSPEND_ENABLE(VIDEO_ENABLE),.CLK_HZ(CLK_FREQ_HZ),',1)
body=body.replace(' .clk(clk),.rst(rst),.header_ok(header_ok),',' .suspend(robot_suspend),.resume_request_toggle(image_req_toggle),.suspended(cache_suspended),\n .clk(clk),.rst(rst),.header_ok(header_ok),',1)
body=body.replace(' .photo_write_req(photo_write_req)', ' .write_req(photo_write_req)')
# The scaler acknowledgement is not shared while the video engine owns writes.
body=body.replace('.write_req_ack(write_req_ack)', '.write_req_ack(write_req_ack&&!robot_claim)')
body=body.replace('.write_ack(write_req_ack),.write_done_toggle', '.write_ack(write_req_ack&&!robot_claim),.write_done_toggle')
body=body.replace('BUS_DANCE=6;', 'BUS_DANCE=6,BUS_ROBOT=7;')
body=body.replace('assign dance_data=sector_data;','assign robot_sec_valid=sector_valid&&bus_state==BUS_ROBOT;\nassign robot_sec_end=sector_end&&bus_state==BUS_ROBOT;\nassign dance_data=sector_data;')
body=body.replace('else if(header_ok&&!reset_sync[2]&&active_group<5', 'else if(header_ok&&robot_claim&&robot_sec_req)begin sd_addr<=robot_sec_addr;sd_req<=1;bus_state<=BUS_ROBOT;end\n     else if(header_ok&&!robot_claim&&!reset_sync[2]&&active_group<5')
body=body.replace('DANCE_ENABLE&&header_ok&&dance_req', 'DANCE_ENABLE&&header_ok&&!robot_suspend&&dance_req')
body=body.replace('else if(header_ok&&bmp_req)', 'else if(header_ok&&!robot_claim&&bmp_req)')
body=body.replace('BUS_HEADER,BUS_AUDIO,BUS_BMP,BUS_DANCE:begin','BUS_HEADER,BUS_AUDIO,BUS_BMP,BUS_DANCE,BUS_ROBOT:begin')
robot_block=body[body.index('generate if(VIDEO_ENABLE)'):body.index('end endgenerate',body.index('generate if(VIDEO_ENABLE)'))+len('end endgenerate')]
body=body.replace(robot_block,'',1).replace('sd_card_top u_sd(',robot_block+'\nsd_card_top u_sd(',1)
s=header+body
put('av/av_sd_media.v',s)

# Direct switch for already decoded video frames, preserving original fades
# verbatim when DIRECT_ENABLE is disabled or direct_switch is false.
s=old('transition_ctrl.v')
s=s.replace('parameter integer FAST_ENABLE=0,DETAIL_FADE_STEP=64','parameter integer FAST_ENABLE=0,DETAIL_FADE_STEP=64,DIRECT_ENABLE=0')
s=s.replace('    input wire fast_switch,','    input wire fast_switch,input wire direct_switch,',1)
s=s.replace("WAIT_FRAME = 3'd3, FADE_IN = 3'd4;","WAIT_FRAME = 3'd3, FADE_IN = 3'd4,DIRECT_SWITCH=3'd5,DIRECT_WAIT=3'd6;")
s=s.replace('                    if (have_image)\n','                    if(DIRECT_ENABLE&&direct_switch)state<=DIRECT_SWITCH;\n                    else if (have_image)\n',1)
s=s.replace('            default: begin\n','''            DIRECT_SWITCH:if(frame_tick)begin
                active_buf_index<=target_index;gain<=256;
                scene_start<=1;scene_start_toggle<=!scene_start_toggle;
                state<=DIRECT_WAIT;
            end
            DIRECT_WAIT:if(read_done_event&&read_index_sync==target_index)begin
                have_image<=1;done_toggle<=req_seen;state<=IDLE;
            end
            default: begin
''',1)
put('transition_ctrl.v',s)

# Silence normal PCM and event beeps during video; alarms retain priority.
s=old('av/av_scene_player.v')
s=s.replace(' parameter integer VIDEO_HZ=25000000,',' parameter integer MUTE_ENABLE=0,\n parameter integer VIDEO_HZ=25000000,',1)
s=s.replace(' input clk,input rst,input sample_tick48,',' input mute_media,\n input clk,input rst,input sample_tick48,',1)
s=s.replace('wire new_request=req_sync[2]!=req_seen;','wire new_request=req_sync[2]!=req_seen;\nwire media_muted=MUTE_ENABLE&&mute_media;')
# One prefetched sample is allowed while muted to settle an outstanding photo
# transition before the video player takes ownership of the SD bus.
s=s.replace('||alarm_active),','||alarm_active||media_muted),',1)
s=s.replace('group_id==5&&committed&&!alarm_active ?', 'group_id==5&&committed&&!alarm_active&&!media_muted ?')
s=s.replace('group_id==5&&committed&&!alarm_active&&melody_on;', 'group_id==5&&committed&&!alarm_active&&!media_muted&&melody_on;')
s=s.replace('beep_left!=0&&!alarm_active ?', 'beep_left!=0&&!alarm_active&&!media_muted ?')
s=s.replace('   end else if(group_id==5&&committed)begin','   end else if(media_muted)begin\n    pcm_sample<=0;\n   end else if(group_id==5&&committed)begin',1)
s=s.replace('  if(alarm_active)begin playing<=0;', '  if(media_muted)beep_left<=0;\n  if(alarm_active)begin playing<=0;',1)
put('av/av_scene_player.v',s)

s=old('top_daoxiang_sidebars.v')
s=s.replace('// V6.6 volume:', '// V6.7 fullscreen robot video: measured digit 0 (00 FF 19 E6). V6.6 volume:',1)
s=s.replace('wire volume_adjust_event;', '''wire volume_adjust_event;
wire robot_mode_requested,robot_display_target,robot_direct;
reg robot_display_video;
wire robot_media_muted=robot_mode_requested||robot_display_video;
''',1)
s=s.replace('.clk(sd_card_clk),.rst(rst_all),\n .sec_req(dance_sec_req)', '.clk(sd_card_clk),.rst(rst_all||robot_mode_requested),\n .sec_req(dance_sec_req)',1)
s=s.replace('reg detail_display_video;','''reg detail_display_video;
reg robot_near,robot_sensor_seen;
always @(posedge sd_card_clk or posedge rst_all)
 if(rst_all)begin robot_near<=0;robot_sensor_seen<=0;end
 else begin
  if(proximity_valid)robot_sensor_seen<=1;
  if(robot_sensor_seen&&!proximity_fault)robot_near<=proximity_near;
 end
always @(posedge video_clk or posedge rst_all)
 if(rst_all)robot_display_video<=0;
 else if(av_scene_start)robot_display_video<=robot_display_target;
''',1)
s=s.replace('av_sd_media #(.CACHE_ENABLE(1)', 'av_sd_media #(.VIDEO_ENABLE(1),.CACHE_ENABLE(1)',1)
s=s.replace(' .near_active(proximity_near),.target_detail', ' .video_mode(robot_mode_requested),.video_near(robot_near),.video_target(robot_display_target),.direct_switch(robot_direct),\n .near_active(proximity_near),.target_detail',1)
s=s.replace('reg [1:0] alarm_system_sync,muted_system_sync;', '''ir_video_mode_ctrl u_video_mode_ctrl(.clk(video_clk),.rst(ir_reset),
 .frame_valid(ir_frame_valid),.repeat_valid(ir_repeat_valid),.frame_error(ir_frame_error),
 .raw_bytes(ir_raw_bytes),.video_mode(robot_mode_requested),.press_event());
reg [1:0] alarm_system_sync,muted_system_sync;''',1)
s=s.replace('av_scene_player u_av_player(.clk', 'av_scene_player #(.MUTE_ENABLE(1)) u_av_player(.mute_media(robot_media_muted),.clk',1)
s=s.replace('.DETAIL_FADE_STEP(DETAIL_FADE_STEP)) u_transition_ctrl', '.DETAIL_FADE_STEP(DETAIL_FADE_STEP),.DIRECT_ENABLE(1)) u_transition_ctrl',1)
s=s.replace('    .fast_switch(!logical_scene_change),','    .direct_switch(robot_direct),.fast_switch(!logical_scene_change),',1)
s=s.replace('.enable   (!detail_display_video)', '.enable   (!detail_display_video&&!robot_display_video)')
s=s.replace('.enable(display_osd_enable&&!detail_display_video)', '.enable(display_osd_enable&&!detail_display_video&&!robot_display_video)')
s=s.replace('.alarm(alarm_active||detail_display_video)', '.alarm(alarm_active||detail_display_video||robot_display_video||robot_mode_requested)')
put('top_daoxiang_sidebars.v',s)

# Register new source files in both active TD project entries.
for name in ['HDMI_Side_Spectrum.al','HDMI_Side_Spectrum..10.23.al']:
 p=R/'src/td_project'/name;s=Z.read('src/td_project/'+name).decode('utf-8-sig')
 entries=''
 for n,f in enumerate(['ir_video_mode_ctrl.v','robot_frame_loader.v','robot_video_ctrl.v'],150):
  entries+=f'''            <File Path="../user_source/hdl_source/av/{f}"><FileInfo>
                <Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&R" Val="true"/>
                <Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="{n}"/>
            </FileInfo></File>\n'''
 s=s.replace('        </Verilog>',entries+'        </Verilog>',1);p.write_text(s,encoding='utf-8')
print('Integrated V6.7 sources and TD project; original V6.6 safely backed up.')
