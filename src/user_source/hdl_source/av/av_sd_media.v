`timescale 1ns/1ps
// Indexed raw-media player. All SD transactions are whole 512-byte sectors.
module av_sd_media #(
 parameter integer VIDEO_AUDIO_ENABLE=0,
 parameter integer VIDEO_ENABLE=0,
 parameter integer DANCE_ENABLE=0,
 parameter integer PROXIMITY_ENABLE=0,
 parameter integer CACHE_ENABLE=0,
 parameter integer SCALING_ENABLE=0,
 parameter integer CLK_FREQ_HZ=100000000,
 parameter integer AUTO_HOLD_SECONDS=3,
 parameter integer DEBOUNCE_MS=20,
 parameter integer IO_TIMEOUT_CYCLES=200000000
)(
 input video_mode,input video_near,output video_target,output direct_switch,
 output video_clip,output [6:0] video_frame,
 input robot_audio_reset,input robot_audio_clip,output robot_audio_ack,output robot_audio_ready,
 output robot_audio_wr_rst,output robot_audio_wr_en,output [15:0] robot_audio_wr_data,
 input robot_audio_full,input [9:0] robot_audio_used,
 input dance_req,input [31:0] dance_addr,output [7:0] dance_data,output dance_valid,output dance_end,output dance_error,
 input near_active,output target_detail,output reg display_detail,output request_scene_change,
 input clk,input rst,input key_next,input key_auto,input gesture_next,input alarm_active,
 output [3:0] state_code,output display_valid,
 output [3:0] current_image_number,output [3:0] image_total,output image_scan_done,
 input write_finish_toggle,output [1:0] write_buf_idx,
 output [1:0] disp_buf_idx,output image_req_toggle,
 input transition_done_toggle,output [3:0] target_scene,
 input scene_start_toggle,input voice_done,input [3:0] voice_scene,
 output reg auto_enabled,
 input stream_reset,input [2:0] stream_group,output stream_reset_ack,
 output reg stream_ready,output fifo_wr_rst,output fifo_wr_en,
 output [15:0] fifo_wr_data,input fifo_full,input [12:0] fifo_used,
 output [31:0] diagnostic_errors,
 output write_req,input write_req_ack,input write_ready,output write_en,output [31:0] write_data,
 output SD_nCS,output SD_DCLK,output SD_MOSI,input SD_MISO
);
`include "av_resources.vh"

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
wire robot_audio_req,robot_audio_fault;wire [31:0] robot_audio_addr;
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


wire key_next_press,next_press,auto_press;
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) u_next
 (.clk(clk),.rst(rst),.button_in(key_next),.press_pulse(key_next_press));
// Preserve the incoming V6.8 gesture event on the original next-picture path.
assign next_press=key_next_press||gesture_next;
key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) u_auto
 (.clk(clk),.rst(rst),.button_in(key_auto),.press_pulse(auto_press));
(* async_reg="true" *) reg [2:0] wr_sync,done_sync,start_sync,reset_sync;
(* async_reg="true" *) reg [1:0] alarm_sync,voice_done_sync;
(* async_reg="true" *) reg [3:0] voice_scene_m,voice_scene_s;
(* async_reg="true" *) reg [2:0] group_m,group_s;
reg reset_old,start_seen;
assign stream_reset_ack=reset_sync[2];
assign fifo_wr_rst=rst||reset_sync[2];
always @(posedge clk or posedge rst)
 if(rst)begin
  wr_sync<=0;done_sync<=0;start_sync<=0;reset_sync<=0;alarm_sync<=0;
  voice_done_sync<=0;voice_scene_m<=0;voice_scene_s<=0;group_m<=0;group_s<=0;reset_old<=0;
 end else begin
  wr_sync<={wr_sync[1:0],write_finish_toggle};done_sync<={done_sync[1:0],transition_done_toggle};
  start_sync<={start_sync[1:0],scene_start_toggle};reset_sync<={reset_sync[1:0],stream_reset};
  alarm_sync<={alarm_sync[0],alarm_active};voice_done_sync<={voice_done_sync[0],voice_done};
  voice_scene_m<=voice_scene;voice_scene_s<=voice_scene_m;group_m<=stream_group;group_s<=group_m;
  reset_old<=reset_sync[2];
 end
reg valid_image,first_done,next_pending,source_busy,source_done,write_done;
reg [3:0] current_scene;
// Size the saturated hold counter to its actual maximum (29 bits at 100MHz/3s).
localparam integer HOLD_COUNT_BITS=$clog2(CLK_FREQ_HZ*AUTO_HOLD_SECONDS+1);
reg [HOLD_COUNT_BITS-1:0] hold_count;
reg [31:0] task_timeout;
reg [2:0] photo_state;
localparam PHOTO_IDLE=0,PHOTO_LOAD=1,PHOTO_TRANSITION=2,PHOTO_ERROR=3;
reg bmp_start;
wire bmp_ready,bmp_load_error;
// HXAV5PCM already stores image LBAs at byte 32 + scene*16.
// Read these at boot so replacing differently sized BMPs never needs an RTL rebuild.
reg [31:0] image_lba [0:6];
// V1 detail extension is a contiguous bank of seven 640x480 RGB888 BMPs.
// Fixed 1801-sector stride avoids another seven-entry dynamic address mux.
wire [3:0] cache_load_scene;
wire cache_load_detail,cache_bmp_reset,bmp_bus_owned;
wire [3:0] loading_scene=CACHE_ENABLE?cache_load_scene:photo_target_scene;
wire loading_detail=CACHE_ENABLE?cache_load_detail:photo_target_detail;
reg [31:0] detail_base;
reg [13:0] detail_offset;
always @* case(loading_scene)
 0:detail_offset=0;1:detail_offset=1801;2:detail_offset=3602;3:detail_offset=5403;
 4:detail_offset=7204;5:detail_offset=9005;default:detail_offset=10806;
endcase
wire [31:0] detail_selected=detail_base+detail_offset;
reg detail_header_ok;
reg [9:0] byte_count;
reg detail_extension_bad;
reg [31:0] card_sectors;
reg [7:0] detail_expected_byte;
always @* case(byte_count[3:0])
 0:detail_expected_byte=8'h48;1:detail_expected_byte=8'h58;2:detail_expected_byte=8'h44;
 3:detail_expected_byte=8'h45;4:detail_expected_byte=8'h54;5:detail_expected_byte=8'h41;
 6:detail_expected_byte=8'h49;7:detail_expected_byte=8'h4c;8:detail_expected_byte=1;
 12:detail_expected_byte=7;default:detail_expected_byte=0;
endcase
wire [31:0] selected_lba=PROXIMITY_ENABLE&&loading_detail ? detail_selected : image_lba[loading_scene[2:0]];
wire [31:0] bmp_base=(selected_lba>2048)?selected_lba:av_image_sector(loading_scene);
integer image_i;
wire bmp_req;
wire [31:0] bmp_addr;
wire [7:0] sector_data;
wire sector_valid,sector_end,sd_init_done;
wire [3:0] bmp_state;
reg [31:0] errors;
reg header_ok,header_checked;
assign diagnostic_errors=errors;
assign state_code=robot_claim ? robot_state : errors!=0 ? 4'he : !header_checked ? 4'd0 : !header_ok ? 4'hf :
 photo_state==PHOTO_LOAD ? 4'd2 : photo_state==PHOTO_TRANSITION ? 4'd3 : auto_enabled ? 4'd5 : 4'd4;
// On exit before the first photo has ever loaded, do not expose the pinned
// (still invalid) photo slot merely because a previous video frame was valid.
assign display_valid=valid_image||(robot_valid&&video_target);
assign current_image_number=valid_image ? current_scene+1'b1 : 4'd0;
assign image_total=header_ok ? AV_SCENES : 0;
assign image_scan_done=header_checked&&header_ok;
wire voice_finished=voice_done_sync[1]&&voice_scene_s==current_scene;
reg detail_failed,skip_recovery;
wire effective_near=PROXIMITY_ENABLE&&detail_header_ok&&!detail_failed&&near_active;
wire [3:0] next_scene=current_scene==AV_SCENES-1 ? 0 : current_scene+1'b1;
reg [$clog2(CLK_FREQ_HZ+1)-1:0] resume_count;
reg near_previous;
wire auto_due=auto_enabled&&!effective_near&&!display_detail&&resume_count==0&&
 ((current_scene<5&&voice_finished)||(current_scene>=5&&hold_count>=CLK_FREQ_HZ*AUTO_HOLD_SECONDS-1));
generate if(CACHE_ENABLE)begin : g_cache
wire c_start,c_target_detail,c_display_detail,c_change,c_valid,c_first,c_auto,c_req;
wire [1:0] c_write_slot,c_display_slot;
wire [3:0] c_target_scene,c_current_scene;
wire [2:0] c_state;
wire [HOLD_COUNT_BITS-1:0] c_hold;
av_cache_scheduler #(.SUSPEND_ENABLE(VIDEO_ENABLE),.CLK_HZ(CLK_FREQ_HZ),.HOLD_SECONDS(AUTO_HOLD_SECONDS)) u_cache(
 .suspend(robot_suspend),.resume_request_toggle(image_req_toggle),.suspended(cache_suspended),
 .clk(clk),.rst(rst),.header_ok(header_ok),.details_available(PROXIMITY_ENABLE&&detail_header_ok),
 .near_active(near_active),.next_press(next_press),.auto_press(auto_press),.alarm(alarm_sync[1]),
 .voice_done(voice_done_sync[1]),.voice_scene(voice_scene_s),.bmp_ready(bmp_ready),.bmp_error(bmp_load_error),
 .write_req(photo_write_req),.write_ack(write_req_ack&&!robot_claim),.write_done_toggle(wr_sync[2]),
 .display_done_toggle(done_sync[2]),.scene_start_toggle(start_sync[2]),.bmp_sector_busy(bmp_bus_owned),
 .bmp_start(c_start),.bmp_reset(cache_bmp_reset),.load_scene(cache_load_scene),.load_detail(cache_load_detail),
 .write_slot(c_write_slot),.target_scene(c_target_scene),.target_detail(c_target_detail),.display_slot(c_display_slot),
 .request_toggle(c_req),.scene_change(c_change),.display_valid(c_valid),.current_scene(c_current_scene),
 .display_detail(c_display_detail),.first_done(c_first),.auto_enabled(c_auto),.state(c_state),.hold_count(c_hold));
always @* begin
 bmp_start=c_start;photo_write_buf_idx=c_write_slot;photo_target_scene=c_target_scene;photo_target_detail=c_target_detail;
 photo_disp_buf_idx=c_display_slot;photo_image_req_toggle=c_req;photo_request_scene_change=c_change;valid_image=c_valid;
 current_scene=c_current_scene;display_detail=c_display_detail;first_done=c_first;auto_enabled=c_auto;
 photo_state=c_state;hold_count=c_hold;
end
end else begin : g_no_cache
assign cache_load_scene=0;assign cache_load_detail=0;assign cache_bmp_reset=0;
if(PROXIMITY_ENABLE)begin : g_proximity_control
always @(posedge clk or posedge rst)
 if(rst)begin
  detail_failed<=0;skip_recovery<=0;photo_target_detail<=0;display_detail<=0;photo_request_scene_change<=1;near_previous<=0;resume_count<=0;
  photo_state<=PHOTO_IDLE;valid_image<=0;first_done<=0;next_pending<=0;
  source_busy<=0;source_done<=0;write_done<=0;bmp_start<=0;
  photo_write_buf_idx<=0;photo_disp_buf_idx<=0;photo_image_req_toggle<=0;photo_target_scene<=0;
  current_scene<=0;auto_enabled<=0;hold_count<=0;task_timeout<=0;start_seen<=0;
 end else begin
  bmp_start<=0;near_previous<=effective_near;
  // A completed narration while near must not skip the restored photo instantly.
  // Timed scenes retain their exact hold counter; this is only a resume grace.
  if(effective_near||display_detail)resume_count<=CLK_FREQ_HZ;
  else if(resume_count!=0)resume_count<=resume_count-1'b1;
  if(start_sync[2]!=start_seen)begin
   start_seen<=start_sync[2];current_scene<=photo_target_scene;display_detail<=photo_target_detail;
  end
  if(auto_press&&header_ok&&!alarm_sync[1])begin auto_enabled<=!auto_enabled;hold_count<=0;end
  if(next_press&&header_ok&&!alarm_sync[1])next_pending<=1;
  if(alarm_sync[1]||auto_press)begin hold_count<=0;if(alarm_sync[1])next_pending<=0;end
  else if(effective_near||display_detail||(photo_state==PHOTO_TRANSITION&&!photo_request_scene_change))hold_count<=hold_count;
  else if(auto_enabled&&photo_state!=PHOTO_TRANSITION&&first_done&&current_scene>=5)begin
   if(hold_count<CLK_FREQ_HZ*AUTO_HOLD_SECONDS)hold_count<=hold_count+1'b1;
  end else hold_count<=0;
  case(photo_state)
   PHOTO_IDLE:begin
    task_timeout<=0;
    if(header_ok&&bmp_ready&&!alarm_sync[1]&&
      (!first_done||next_pending||display_detail!=effective_near||(auto_enabled&&!effective_near)))begin
     photo_target_scene<=!first_done ? 0 : next_pending ? next_scene :
       display_detail!=effective_near ? current_scene : next_scene;
     photo_target_detail<=effective_near;
     photo_write_buf_idx<=!first_done ? 0 : {1'b0,!photo_disp_buf_idx[0]};
     bmp_start<=1;source_busy<=0;source_done<=0;write_done<=0;photo_state<=PHOTO_LOAD;
    end
   end
   PHOTO_LOAD:begin
    if(!bmp_ready)source_busy<=1;
    if(source_busy&&bmp_ready)source_done<=1;
    if(wr_sync[2]!=wr_sync[1])write_done<=1;
    if(source_done&&write_done&&!alarm_sync[1])begin
     if(photo_target_detail==effective_near&&
       ((!first_done&&(photo_target_scene==0||skip_recovery))||
        (first_done&&skip_recovery&&next_pending)||
        (first_done&&photo_target_scene==current_scene&&photo_target_detail!=display_detail)||
        (first_done&&photo_target_scene==next_scene&&(next_pending||auto_due))))begin
      // Only a logical scene change can restart speech or clear its timer.
      skip_recovery<=0;photo_request_scene_change<=!first_done||photo_target_scene!=current_scene;
      if(!first_done||photo_target_scene!=current_scene)begin next_pending<=0;hold_count<=0;end
      photo_disp_buf_idx<=photo_write_buf_idx;photo_image_req_toggle<=!photo_image_req_toggle;
      valid_image<=1;photo_state<=PHOTO_TRANSITION;
     end else if(photo_target_detail!=effective_near||
       (display_detail!=effective_near&&photo_target_scene!=current_scene&&!next_pending)||
       (photo_target_scene==current_scene&&photo_target_detail==display_detail))begin
      // Finish/drain an in-flight framebuffer, then discard stale prefetch.
      // It is never displayed and can safely be overwritten in the hidden bank.
      photo_state<=PHOTO_IDLE;source_busy<=0;source_done<=0;write_done<=0;
     end
    end
   end
   PHOTO_ERROR:if(next_press&&!alarm_sync[1])begin
    photo_target_scene<=photo_target_scene==AV_SCENES-1 ? 0 : photo_target_scene+1'b1;
    skip_recovery<=1;photo_target_detail<=effective_near;bmp_start<=1;source_busy<=0;source_done<=0;write_done<=0;
    task_timeout<=0;next_pending<=1;photo_state<=PHOTO_LOAD;
   end
   PHOTO_TRANSITION:if(done_sync[2]==photo_image_req_toggle)begin
    current_scene<=photo_target_scene;display_detail<=photo_target_detail;first_done<=1;photo_state<=PHOTO_IDLE;
    if(photo_request_scene_change)hold_count<=0;
   end
   default:photo_state<=PHOTO_IDLE;
  endcase
  if(bmp_load_error)begin
   source_done<=0;write_done<=0;
   if(photo_target_detail)begin detail_failed<=1;photo_state<=PHOTO_IDLE;end
   else photo_state<=PHOTO_ERROR;
  end
 end
end else begin : g_legacy_control
wire legacy_auto_due=auto_enabled&&((current_scene<5&&voice_finished)||
 (current_scene>=5&&hold_count>=CLK_FREQ_HZ*AUTO_HOLD_SECONDS-1));
always @(posedge clk or posedge rst)
 if(rst)begin
  photo_target_detail<=0;display_detail<=0;photo_request_scene_change<=1;
  photo_state<=PHOTO_IDLE;valid_image<=0;first_done<=0;next_pending<=0;
  source_busy<=0;source_done<=0;write_done<=0;bmp_start<=0;
  photo_write_buf_idx<=0;photo_disp_buf_idx<=0;photo_image_req_toggle<=0;photo_target_scene<=0;
  current_scene<=0;auto_enabled<=0;hold_count<=0;task_timeout<=0;start_seen<=0;
 end else begin
  bmp_start<=0;
  if(start_sync[2]!=start_seen)begin start_seen<=start_sync[2];current_scene<=photo_target_scene;end
  if(auto_press&&header_ok&&!alarm_sync[1])begin auto_enabled<=!auto_enabled;hold_count<=0;end
  if(next_press&&header_ok&&!alarm_sync[1])next_pending<=1;
  if(alarm_sync[1]||auto_press)begin hold_count<=0;if(alarm_sync[1])next_pending<=0;end
  else if(auto_enabled&&photo_state!=PHOTO_TRANSITION&&first_done&&current_scene>=5)begin
   if(hold_count<CLK_FREQ_HZ*AUTO_HOLD_SECONDS)hold_count<=hold_count+1'b1;
  end else hold_count<=0;
  case(photo_state)
   PHOTO_IDLE:begin
    task_timeout<=0;
    // Prepare next framebuffer while the current voice / three-second hold runs.
    if(header_ok&&bmp_ready&&!alarm_sync[1]&&(!first_done||next_pending||auto_enabled))begin
     photo_target_scene<=!first_done ? 0 : (current_scene==AV_SCENES-1 ? 0 : current_scene+1'b1);
     photo_write_buf_idx<=!first_done ? 0 : {1'b0,!photo_disp_buf_idx[0]};
     bmp_start<=1;source_busy<=0;source_done<=0;write_done<=0;
     photo_state<=PHOTO_LOAD;if(!first_done)hold_count<=0;
    end
   end
   PHOTO_LOAD:begin
    if(!bmp_ready)source_busy<=1;
    if(source_busy&&bmp_ready)source_done<=1;
    if(wr_sync[2]!=wr_sync[1])write_done<=1;
    if(source_done&&write_done&&!alarm_sync[1]&&(!first_done||next_pending||legacy_auto_due))begin
     photo_disp_buf_idx<=photo_write_buf_idx;photo_image_req_toggle<=!photo_image_req_toggle;
     valid_image<=1;photo_state<=PHOTO_TRANSITION;next_pending<=0;hold_count<=0;
    end
    if(task_timeout<IO_TIMEOUT_CYCLES*4)task_timeout<=task_timeout+1'b1;
   end
   PHOTO_ERROR:begin
    // Keep the last complete framebuffer. A fresh NEXT skips the rejected image.
    if(next_press&&!alarm_sync[1])begin
     photo_target_scene<=photo_target_scene==AV_SCENES-1 ? 0 : photo_target_scene+1'b1;
     bmp_start<=1;source_busy<=0;source_done<=0;write_done<=0;task_timeout<=0;
     photo_state<=PHOTO_LOAD;
    end
   end
   PHOTO_TRANSITION:begin
    if(done_sync[2]==photo_image_req_toggle)begin
     current_scene<=photo_target_scene;first_done<=1;photo_state<=PHOTO_IDLE;hold_count<=0;
    end
   end
   default:photo_state<=PHOTO_IDLE;
  endcase
  if(bmp_load_error)begin photo_state<=PHOTO_ERROR;source_done<=0;write_done<=0;end
 end

end end endgenerate

// Scale once while loading, then display the completed 640x480 SDRAM canvas.
wire bmp_sector_valid,bmp_sector_end;
wire [23:0] bmp_pixel;
generate if(SCALING_ENABLE)begin : g_scale
bmp_scaled_loader #(.MAX_SRC_WIDTH(2048),.MAX_SRC_HEIGHT(2048),.BILINEAR(1),
 .IO_TIMEOUT_CYCLES(IO_TIMEOUT_CYCLES)) u_bmp(
 .clk(clk),.rst(rst||cache_bmp_reset),.ready(bmp_ready),
 .scan_start(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0),.scan_target_count(3'd0),
 .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),
 .load_start(bmp_start),.load_sector(bmp_base),.sd_init_done(sd_init_done&&header_ok),
 .state_code(bmp_state),.bmp_width(16'd640),.bmp_height(16'd480),
 .write_req(photo_write_req),.write_req_ack(write_req_ack&&!robot_claim),.write_ready(write_ready),.load_error(bmp_load_error),
 .sd_sec_read(bmp_req),.sd_sec_read_addr(bmp_addr),.sd_sec_read_data(sector_data),
 .sd_sec_read_data_valid(bmp_sector_valid),.sd_sec_read_end(bmp_sector_end),
 .bmp_data_wr_en(photo_write_en),.bmp_data(bmp_pixel));
end else begin : g_legacy
assign bmp_load_error=1'b0;
bmp_read u_bmp(.clk(clk),.rst(rst||cache_bmp_reset),.ready(bmp_ready),
 .scan_start(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0),.scan_target_count(4'd0),
 .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),
 .load_start(bmp_start),.load_sector(bmp_base),.sd_init_done(sd_init_done&&header_ok),
 .state_code(bmp_state),.bmp_width(16'd640),.bmp_height(16'd480),
 .write_req(photo_write_req),.write_req_ack(write_req_ack&&!robot_claim),.sd_sec_read(bmp_req),.sd_sec_read_addr(bmp_addr),
 .sd_sec_read_data(sector_data),.sd_sec_read_data_valid(bmp_sector_valid),.sd_sec_read_end(bmp_sector_end),
 .bmp_data_wr_en(photo_write_en),.bmp_data(bmp_pixel));
end endgenerate
assign photo_write_data={bmp_pixel,8'd0};

// Owner is held through a sector and an explicit gap; endpoints cannot consume each other's data.
localparam BUS_IDLE=0,BUS_HEADER=1,BUS_AUDIO=2,BUS_BMP=3,BUS_GAP=4,BUS_FAILED=5,BUS_DANCE=6,BUS_ROBOT=7,BUS_ROBOT_AUDIO=8;
reg [3:0] bus_state;
assign bmp_bus_owned=(bus_state==BUS_BMP);
reg last_dance;
assign robot_sec_valid=sector_valid&&bus_state==BUS_ROBOT;
assign robot_sec_end=sector_end&&bus_state==BUS_ROBOT;
assign dance_data=sector_data;
assign dance_valid=sector_valid&&bus_state==BUS_DANCE;
assign dance_end=sector_end&&bus_state==BUS_DANCE;
assign dance_error=bus_state==BUS_FAILED;
reg sd_req;
reg [31:0] sd_addr,bus_timeout;
reg [63:0] magic;
reg [31:0] audio_addr,audio_written,audio_total;
reg [7:0] low_byte;
reg kill_audio_sector;
reg [2:0] active_group;
assign bmp_sector_valid=sector_valid&&bus_state==BUS_BMP;
assign bmp_sector_end=sector_end&&bus_state==BUS_BMP;
assign fifo_wr_en=sector_valid&&bus_state==BUS_AUDIO&&byte_count[0]&&
 !reset_sync[2]&&!kill_audio_sector&&!fifo_full&&audio_written<audio_total;
assign fifo_wr_data={sector_data,low_byte};
always @(posedge clk or posedge rst)
 if(rst)begin
  last_dance<=0;bus_state<=BUS_IDLE;sd_req<=0;sd_addr<=2048;byte_count<=0;bus_timeout<=0;
  for(image_i=0;image_i<7;image_i=image_i+1)begin
   image_lba[image_i]<=av_image_sector(image_i);
  end
  detail_base<=0;detail_header_ok<=0;detail_extension_bad<=0;card_sectors<=0;
  magic<=0;header_checked<=0;header_ok<=0;audio_addr<=0;audio_written<=0;audio_total<=0;
  low_byte<=0;kill_audio_sector<=0;active_group<=7;stream_ready<=0;errors<=0;
 end else begin
  if(bmp_load_error)errors<=errors+1'b1;
  if(reset_sync[2])begin
   stream_ready<=0;
   if(bus_state==BUS_AUDIO)kill_audio_sector<=1;
  end
  if(reset_old&&!reset_sync[2])begin
   active_group<=group_s;audio_addr<=av_audio_sector({1'b0,group_s});
   audio_total<=av_audio_samples({1'b0,group_s});audio_written<=0;
  end
  if(!reset_sync[2]&&active_group<5&&
    (fifo_used>=1024||audio_written==audio_total&&audio_total!=0))stream_ready<=1;
  if(sector_valid)begin
   byte_count<=byte_count+1'b1;
   if(bus_state==BUS_HEADER&&byte_count<8)magic[byte_count[2:0]*8 +:8]<=sector_data;
   if(bus_state==BUS_HEADER&&byte_count>=32&&byte_count<132&&byte_count[3:2]==0)
    image_lba[(byte_count[7:4]-2)][byte_count[1:0]*8 +:8]<=sector_data;
   if(PROXIMITY_ENABLE&&bus_state==BUS_HEADER)begin
    if(byte_count>=256&&byte_count<272&&sector_data!=detail_expected_byte)detail_extension_bad<=1;
    if(byte_count>=272&&byte_count<276)detail_base[byte_count[1:0]*8 +:8]<=sector_data;
    if(byte_count>=20&&byte_count<24)card_sectors[byte_count[1:0]*8 +:8]<=sector_data;
   end
   if(bus_state==BUS_AUDIO)begin
    if(!byte_count[0])low_byte<=sector_data;
    else if(fifo_wr_en)audio_written<=audio_written+1'b1;
   end
  end
  case(bus_state)
   BUS_IDLE:begin
    byte_count<=0;bus_timeout<=0;kill_audio_sector<=0;
    if(sd_init_done)begin
     if(!header_checked)begin sd_addr<=2048;sd_req<=1;bus_state<=BUS_HEADER;end
     else if(VIDEO_AUDIO_ENABLE&&header_ok&&robot_claim&&robot_audio_req)begin
      sd_addr<=robot_audio_addr;sd_req<=1;bus_state<=BUS_ROBOT_AUDIO;
     end
     else if(header_ok&&robot_claim&&robot_sec_req)begin sd_addr<=robot_sec_addr;sd_req<=1;bus_state<=BUS_ROBOT;end
     else if(header_ok&&!robot_claim&&!reset_sync[2]&&active_group<5&&audio_written<audio_total&&fifo_used<3072)begin
      sd_addr<=audio_addr;sd_req<=1;bus_state<=BUS_AUDIO;
     end else if(DANCE_ENABLE&&header_ok&&!robot_suspend&&dance_req&&(!bmp_req||!last_dance))begin
      sd_addr<=dance_addr;sd_req<=1;bus_state<=BUS_DANCE;last_dance<=1;
     end else if(header_ok&&!robot_claim&&bmp_req)begin sd_addr<=bmp_addr;sd_req<=1;bus_state<=BUS_BMP;last_dance<=0;end
    end
   end
   BUS_HEADER,BUS_AUDIO,BUS_BMP,BUS_DANCE,BUS_ROBOT,BUS_ROBOT_AUDIO:begin
    if(sector_end)begin
     sd_req<=0;bus_state<=BUS_GAP;
     if(bus_state==BUS_HEADER)begin
      header_checked<=1;header_ok<=magic==AV_MAGIC&&byte_count==512;
      detail_header_ok<=PROXIMITY_ENABLE&&byte_count==512&&!detail_extension_bad&&
       card_sectors>14655&&detail_base>2048&&detail_base<=card_sectors-12607;
     end
     if(bus_state==BUS_AUDIO&&!kill_audio_sector&&!reset_sync[2])audio_addr<=audio_addr+1'b1;
    end else if(bus_timeout==IO_TIMEOUT_CYCLES-1)begin
     sd_req<=0;bus_state<=BUS_FAILED;errors<=errors+1'b1;
    end else bus_timeout<=bus_timeout+1'b1;
   end
   BUS_GAP:bus_state<=BUS_IDLE;
   default:sd_req<=0;
  endcase
 end
generate if(VIDEO_ENABLE)begin:g_robot
 wire load_start,loader_ready,loader_error,clip;wire [6:0] frame_number;
 robot_video_ctrl #(.REWIND_AFTER_PAUSE(VIDEO_AUDIO_ENABLE),.CLK_HZ(CLK_FREQ_HZ)) u_ctrl(
  .clk(clk),.rst(rst),.want_mode(mode_sync[1]),.near_active(video_near),.pause(alarm_sync[1]),
  .cache_suspended(cache_suspended),.photo_slot(photo_disp_buf_idx),.photo_request(photo_image_req_toggle),
  .display_done_toggle(done_sync[2]),.write_done_toggle(wr_sync[2]),
  .loader_ready(loader_ready),.loader_error(loader_error),.write_req(robot_write_req),.write_ack(write_req_ack),
  .claim(robot_claim),.request_toggle(robot_req),.display_slot(robot_display_slot),.target_video(robot_target),
  .valid_frame(robot_valid),.fault(robot_fault),.load_start(load_start),.clip(clip),.frame_number(frame_number),
  .target_clip(video_clip),.target_frame(video_frame),
  .write_slot(robot_write_slot),.state_code(robot_state),.late_frames());
 robot_frame_loader u_loader(.clk(clk),.rst(rst),.start(load_start),.clip(clip),.frame_number(frame_number),
  .ready(loader_ready),.error(loader_error),.sec_req(robot_sec_req),.sec_addr(robot_sec_addr),.sec_data(sector_data),
  .sec_valid(robot_sec_valid),.sec_end(robot_sec_end),.sec_error(bus_state==BUS_FAILED),
  .write_req(robot_write_req),.write_ack(write_req_ack&&robot_claim),.write_ready(write_ready),
  .write_en(robot_write_en),.write_data(robot_write_data));
end else begin:g_no_robot
 assign video_clip=0;assign video_frame=0;
 assign robot_claim=0;assign robot_req=0;assign robot_target=0;assign robot_valid=0;assign robot_fault=0;
 assign robot_display_slot=0;assign robot_write_slot=0;assign robot_sec_req=0;assign robot_sec_addr=0;
 assign robot_write_req=0;assign robot_write_en=0;assign robot_write_data=0;assign robot_state=0;
end endgenerate
generate if(VIDEO_AUDIO_ENABLE)begin:g_robot_audio
 robot_audio_sd u_audio(.clk(clk),.rst(rst),.stream_reset(robot_audio_reset),.stream_clip(robot_audio_clip),
  .reset_ack(robot_audio_ack),.fifo_reset(robot_audio_wr_rst),.ready(robot_audio_ready),.fault(robot_audio_fault),
  .fifo_full(robot_audio_full),.fifo_used(robot_audio_used),.fifo_write(robot_audio_wr_en),.fifo_data(robot_audio_wr_data),
  .sec_req(robot_audio_req),.sec_addr(robot_audio_addr),.sec_data(sector_data),
  .sec_valid(sector_valid&&bus_state==BUS_ROBOT_AUDIO),.sec_end(sector_end&&bus_state==BUS_ROBOT_AUDIO),
  .sec_error(bus_state==BUS_FAILED));
end else begin:g_no_robot_audio
 assign robot_audio_ack=0;assign robot_audio_ready=0;assign robot_audio_wr_rst=1;
 assign robot_audio_wr_en=0;assign robot_audio_wr_data=0;assign robot_audio_req=0;
 assign robot_audio_addr=0;assign robot_audio_fault=0;
end endgenerate
sd_card_top u_sd(.clk(clk),.rst(rst),.SD_nCS(SD_nCS),.SD_DCLK(SD_DCLK),.SD_MOSI(SD_MOSI),.SD_MISO(SD_MISO),
 .sd_init_done(sd_init_done),.sd_sec_read(sd_req),.sd_sec_read_addr(sd_addr),
 .sd_sec_read_data(sector_data),.sd_sec_read_data_valid(sector_valid),.sd_sec_read_end(sector_end),
 .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
endmodule
