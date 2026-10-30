
module top(
    inout proximity_scl,
    inout proximity_sda,
    output proximity_gpio1,
    input                       clk,
    input                       ir_rx,          // J1 pin 1 / D14, 3.3V demodulated IR
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key2,           // 自动播放 开/关
    input                       key3_n,         // physical KEY3 B1
    input                       sw_param,       // SW1 C8: 0 brightness, 1 contrast
    input                       sw_direction,   // SW2 C7: 0 decrease, 1 increase
    input                       sw_adjust_en,   // SW3 C6: 1 apply adjustments
    input                       sw_osd_en,      // SW4 C5: 1 show parameter panel

    output                      BUZZER,        // H11, SW5 physical enable
    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

// V6.9 merged gesture control, optimized CRC, robot music and welcome speech. V6.7 fullscreen robot video: measured digit 0 (00 FF 19 E6). V6.6 volume: short-press UP/DOWN, shared transient HUD. V6.5.1: 32 video-frame ramps in each direction; detail uses 16.
parameter FADE_STEP = 8;
parameter DETAIL_FADE_STEP=16;
parameter PROX_ENTER_CM=20;
parameter PROX_EXIT_CM=25;
parameter AUTO_HOLD_SECONDS = 3;
parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;
parameter BUF2_ADDR     = FRAME_PIXELS*2;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire        display_valid;

wire alarm_active,alarm_muted;
wire rst_all;

// AV V5 interfaces: stable target-scene mailbox, grouped audio, true PCM FIFO.
wire [3:0] av_target_scene,av_voice_scene;
wire av_auto,av_voice_done,av_media_ready,av_scene_start,av_scene_start_toggle;
wire av_stream_reset,av_stream_ack,av_stream_ready,av_wr_rst,av_wr_en,av_fifo_full;
wire av_rd_rst,av_rd_en,av_rd_valid,av_fifo_empty;
wire [2:0] av_stream_group,av_subtitle_group;
wire av_subtitle_restart;
wire [15:0] av_wr_data,av_rd_data;
wire [12:0] av_fifo_used;
wire [31:0] av_media_errors,av_underruns;
wire av_music_n,av_music_active,av_prompt_n;
wire audio_mclk;
wire [23:0] audio_left_data;
wire [23:0] audio_raw_data;
wire audio_raw_valid;
wire [23:0] photo_audio_data,robot_audio_data;wire photo_audio_valid,robot_audio_valid;
wire robot_audio_reset,robot_audio_clip,robot_audio_ack,robot_audio_ready;
wire robot_audio_wr_rst,robot_audio_wr_en,robot_audio_full;
wire robot_audio_rd_rst,robot_audio_rd_en,robot_audio_rd_valid,robot_audio_empty;
wire [15:0] robot_audio_wr_data,robot_audio_rd_data;
wire [9:0] robot_audio_used;wire [31:0] robot_audio_underruns;
wire robot_target_clip;wire [6:0] robot_target_frame;
wire signed [15:0] av_pcm=audio_raw_data[23:8];
wire [4:0] volume_level;
wire volume_adjust_event;
wire robot_mode_requested,robot_display_target,robot_direct;
reg robot_display_video;
wire robot_media_muted=robot_mode_requested||robot_display_video;

reg [7:0] av_audio_div;
reg av_audio_toggle;
(* async_reg="true" *) reg [2:0] av_audio_sync;
wire av_sample_tick=av_audio_sync[2]^av_audio_sync[1];
always @(posedge audio_mclk or posedge rst_all)
 if(rst_all)begin av_audio_div<=0;av_audio_toggle<=0;end
 else if(av_audio_div==255)begin av_audio_div<=0;av_audio_toggle<=!av_audio_toggle;end
 else av_audio_div<=av_audio_div+1'b1;
always @(posedge video_clk or posedge rst_all)
 if(rst_all)av_audio_sync<=0;else av_audio_sync<={av_audio_sync[1:0],av_audio_toggle};

// Diagnostic: board KEY2 (B2) and KEY4 (C1); released=1, pressed=0.
reg [1:0] dbg_next_sync;
reg [1:0] dbg_auto_sync;
wire [6:0] dbg_next_segments;
wire [6:0] dbg_auto_segments;
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) begin
        dbg_next_sync <= 2'b11;
        dbg_auto_sync <= 2'b11;
    end else begin
        dbg_next_sync <= {dbg_next_sync[0], key1};
        dbg_auto_sync <= {dbg_auto_sync[0], key2};
    end
end
seg_decoder u_dbg_next(.bin_data({3'b000,dbg_next_sync[1]}),.seg_data(dbg_next_segments));
seg_decoder u_dbg_auto(.bin_data({3'b000,dbg_auto_sync[1]}),.seg_data(dbg_auto_segments));

wire [3:0]  state_code;
// OSD integration interface: all three signals are in sd_card_clk domain.
// Transfer coherently and align to the displayed framebuffer before OSD use.
wire [3:0] current_image_number;
wire [3:0] image_total;
wire image_scan_done;
wire [6:0] seg_image_number;
wire [6:0] seg_image_total;
wire [6:0]  seg_data_0;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;
wire image_req_toggle;
wire transition_done_toggle;
wire [1:0] active_buf_index;
wire [8:0] fade_gain;
wire video_read_finish;
wire [1:0] video_read_active_index;
reg read_done_toggle_mem;
reg [1:0] read_done_index_mem;

always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all) begin
        read_done_toggle_mem <= 1'b0;
        read_done_index_mem <= 2'd0;
    end else if (video_read_finish) begin
        read_done_index_mem <= video_read_active_index;
        read_done_toggle_mem <= ~read_done_toggle_mem;
    end
end


wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_pll_lock;

wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 音频链路

assign rst_all = ~rst_n | ~audio_pll_lock;

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (1'b0)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (1'b0)
);

// 复用你 I2S->HDMI 工程里的 PLL，只取 12.288MHz 音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);


// V6 transparent dancer: one physical SD and SDRAM controller, shared by ownership.
wire dance_sec_req,dance_sec_valid,dance_sec_end,dance_sec_error;
wire [31:0] dance_sec_addr;wire [7:0] dance_sec_data;
wire dance_load_toggle,dance_load_ack,dance_loaded,dance_failed;
wire [20:0] dance_load_addr;wire [31:0] dance_load_data;
wire dance_pal_we;wire [7:0] dance_pal_addr;wire [15:0] dance_pal_data;
wire dance_frame_toggle,dance_frame_ack,dance_frame_bank;
wire [7:0] dance_frame_number,dance_displayed_frame;
wire dance_hold,dance_own,dance_wr_en,dance_rd_en,dance_bg_busy,dance_mem_fault;
wire [20:0] dance_addr;wire [31:0] dance_data;
wire dance_cache_we;wire [12:0] dance_cache_addr;wire [31:0] dance_cache_data;
wire [31:0] dance_underruns;
wire [2:0] dance_diagnostic;
reg [7:0] dance_sd_data_q;
reg dance_sd_valid_q,dance_sd_end_q,dance_sd_error_q;
always @(posedge sd_card_clk or posedge rst_all)
 if(rst_all)begin dance_sd_data_q<=0;dance_sd_valid_q<=0;dance_sd_end_q<=0;dance_sd_error_q<=0;end
 else begin dance_sd_data_q<=dance_sec_data;dance_sd_valid_q<=dance_sec_valid;
  dance_sd_end_q<=dance_sec_end;dance_sd_error_q<=dance_sec_error;end
dance_stream_loader u_dance_stream(.clk(sd_card_clk),.rst(rst_all||robot_mode_requested),
 .sec_req(dance_sec_req),.sec_addr(dance_sec_addr),.sec_data(dance_sd_data_q),.sec_valid(dance_sd_valid_q),.sec_end(dance_sd_end_q),.sec_error(dance_sd_error_q),
 .frame_toggle(dance_frame_toggle),.frame_number(dance_frame_number),.frame_bank(dance_frame_bank),.frame_ack(dance_frame_ack),
 .cache_we(dance_cache_we),.cache_addr(dance_cache_addr),.cache_data(dance_cache_data),.loaded(dance_loaded),.failed(dance_failed),.diagnostic(dance_diagnostic));
assign dance_hold=1'b0;assign dance_own=1'b0;assign dance_mem_fault=1'b0;
assign dance_wr_en=1'b0;assign dance_rd_en=1'b0;assign dance_addr=21'd0;assign dance_data=32'd0;
// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// Cross-domain ACK levels must not feed multi-bit state decoders directly.
(* async_reg = "true" *) reg [2:0] write_ack_sd_sync;
(* async_reg = "true" *) reg [2:0] read_ack_video_sync;
always @(posedge sd_card_clk or posedge rst_all) begin
    if(rst_all) write_ack_sd_sync <= 3'b000;
    else write_ack_sd_sync <= {write_ack_sd_sync[1:0],sd_card_write_req_ack};
end
always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) read_ack_video_sync <= 3'b000;
    else read_ack_video_sync <= {read_ack_video_sync[1:0],video_read_req_ack};
end

// Proximity sensor and media share the 50MHz SD clock; no distance CDC bus.
wire proximity_near,proximity_valid,proximity_fault,proximity_gesture_next;
wire [11:0] proximity_distance_q4;
wire detail_target,detail_display_sd,logical_scene_change;
reg detail_display_video;
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

gp2y0e03_proximity #(.CLK_HZ(50000000),.ENTER_CM(PROX_ENTER_CM),.EXIT_CM(PROX_EXIT_CM)) u_proximity(
 .clk(sd_card_clk),.rst(rst_all),.ir_inhibit(!ir_rx),.scl(proximity_scl),.sda(proximity_sda),
 .gpio1(proximity_gpio1),.near_active(proximity_near),.sample_valid(proximity_valid),
 .distance_q4(proximity_distance_q4),.sensor_fault(proximity_fault),.gesture_next(proximity_gesture_next));
// Bundled target_detail is held stable from image request through done acknowledgement.
always @(posedge video_clk or posedge rst_all)
 if(rst_all)detail_display_video<=0;
 else if(av_scene_start)detail_display_video<=detail_target;

// ===================== TF 多图扫描与缓存（双缓冲） =====================
wire sd_card_write_ready;
av_sd_media #(.VIDEO_AUDIO_ENABLE(1),.VIDEO_ENABLE(1),.CACHE_ENABLE(1),.PROXIMITY_ENABLE(1),.SCALING_ENABLE(1),.DANCE_ENABLE(1),.CLK_FREQ_HZ(50000000),.AUTO_HOLD_SECONDS(AUTO_HOLD_SECONDS)) sd_card_bmp_m0(
 .robot_audio_reset(robot_audio_reset),.robot_audio_clip(robot_audio_clip),
 .robot_audio_ack(robot_audio_ack),.robot_audio_ready(robot_audio_ready),
 .robot_audio_wr_rst(robot_audio_wr_rst),.robot_audio_wr_en(robot_audio_wr_en),.robot_audio_wr_data(robot_audio_wr_data),
 .robot_audio_full(robot_audio_full),.robot_audio_used(robot_audio_used),
 .video_clip(robot_target_clip),.video_frame(robot_target_frame),
 .video_mode(robot_mode_requested),.video_near(robot_near),.video_target(robot_display_target),.direct_switch(robot_direct),
 .near_active(proximity_near),.target_detail(detail_target),.display_detail(detail_display_sd),
 .request_scene_change(logical_scene_change),
 .dance_req(dance_sec_req),.dance_addr(dance_sec_addr),.dance_data(dance_sec_data),
 .dance_valid(dance_sec_valid),.dance_end(dance_sec_end),.dance_error(dance_sec_error),
 .clk(sd_card_clk),.rst(rst_all),.key_next(key1),.key_auto(key2),.gesture_next(proximity_gesture_next),.alarm_active(alarm_active),
 .state_code(state_code),.display_valid(display_valid),.current_image_number(current_image_number),
 .image_total(image_total),.image_scan_done(image_scan_done),
 .write_finish_toggle(frame_write_toggle_mem),.write_buf_idx(write_buf_idx),.disp_buf_idx(disp_buf_idx),
 .image_req_toggle(image_req_toggle),.transition_done_toggle(transition_done_toggle),.target_scene(av_target_scene),
 .scene_start_toggle(av_scene_start_toggle),.voice_done(av_voice_done),.voice_scene(av_voice_scene),.auto_enabled(av_auto),
 .stream_reset(av_stream_reset),.stream_group(av_stream_group),.stream_reset_ack(av_stream_ack),.stream_ready(av_stream_ready),
 .fifo_wr_rst(av_wr_rst),.fifo_wr_en(av_wr_en),.fifo_wr_data(av_wr_data),.fifo_full(av_fifo_full),.fifo_used(av_fifo_used),
 .diagnostic_errors(av_media_errors),.write_req(sd_card_write_req),.write_req_ack(write_ack_sd_sync[2]),
 .write_ready(sd_card_write_ready),.write_en(sd_card_write_en),.write_data(sd_card_write_data),
 .SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso));
av_pcm_fifo u_av_fifo(.wr_clk(sd_card_clk),.wr_rst(av_wr_rst),.wr_en(av_wr_en),.wr_data(av_wr_data),
 .full(av_fifo_full),.wr_used(av_fifo_used),.rd_clk(video_clk),.rd_rst(av_rd_rst),
 .rd_en(av_rd_en),.rd_data(av_rd_data),.rd_valid(av_rd_valid),.empty(av_fifo_empty));

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

seg_decoder u_seg_image_number(.bin_data(current_image_number), .seg_data(seg_image_number));
seg_decoder u_seg_image_total(.bin_data(image_total), .seg_data(seg_image_total));

// Production status stays in the SD domain; no asynchronous gain telemetry.
wire [8:0] dbg_effective_gain=fade_gain;
wire [6:0] dbg_progress_segments,dbg_read_segments;
seg_decoder u_av_status(.bin_data(state_code),.seg_data(dbg_progress_segments));
seg_decoder u_av_auto_status(.bin_data({3'd0,av_auto}),.seg_data(dbg_read_segments));
// Run scanning in the SD clock domain, avoiding an asynchronous multi-bit bus.
seg_scan #(.CLK_FREQ(50000000)) seg_scan_m0(
    .clk               (sd_card_clk),
    .rst_n             (~rst_all),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,seg_image_number}),
    .seg_data_1        (8'b10111111),
    .seg_data_2        ({1'b1,seg_image_total}),
    .seg_data_3        ({1'b1,dbg_progress_segments}),
    .seg_data_4        ({1'b1,dbg_read_segments}),
    .seg_data_5        ({1'b1,seg_data_0})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_req          (video_read_req),
    .read_req_ack      (read_ack_video_sync[2]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
(* async_reg="true" *) reg [1:0] av_display_sync;
always @(posedge video_clk or posedge rst_all)
 if(rst_all)av_display_sync<=0;else av_display_sync<={av_display_sync[0],display_valid};
assign vout_data=av_display_sync[1] ? vout_data_raw : 24'd0;

frame_read_write #(
    .WRITE_V_FLIP     (0), // scaler outputs top-down rows for either BMP storage order
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .aux_hold(dance_hold),.bg_busy(dance_bg_busy),
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en&&!dance_own),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (video_read_finish),
    .read_active_index (video_read_active_index),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (BUF2_ADDR),
    .read_addr_3       (24'd0),
    .read_addr_index   (active_buf_index),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (BUF2_ADDR),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_ready       (sd_card_write_ready),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (dance_own ? dance_wr_en : App_wr_en),
    .App_wr_addr       (dance_own ? dance_addr : App_wr_addr),
    .App_wr_dm         (dance_own ? 4'd0 : App_wr_dm),
    .App_wr_din        (dance_own ? dance_data : App_wr_din),
    .App_rd_en         (dance_own ? dance_rd_en : App_rd_en),
    .App_rd_addr       (dance_own ? dance_addr : App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);


// IR and emergency state use the video clock. Reset assertion is immediate,
// release is synchronized locally. Alarm crosses to the 50-MHz buzzer domain
// only as a stable level through two registers (never as an unacknowledged pulse).
reg [2:0] ir_reset_pipe;
always @(negedge video_clk or posedge rst_all)begin
    if(rst_all)ir_reset_pipe<=3'b111;
    else ir_reset_pipe<={ir_reset_pipe[1:0],1'b0};
end
wire ir_reset=ir_reset_pipe[2];
wire ir_frame_valid,ir_repeat_valid,ir_frame_error;
wire [31:0] ir_raw_bytes;
ir_nec_monitor_v2 u_ir_receiver(.clk(video_clk),.rst(ir_reset),.ir_rx(ir_rx),
 .frame_valid(ir_frame_valid),.repeat_valid(ir_repeat_valid),.frame_error(ir_frame_error),.raw_bytes(ir_raw_bytes));
emergency_fixed_ctrl u_emergency_ctrl(.clk(video_clk),.rst(ir_reset),
 .frame_valid(ir_frame_valid),.repeat_valid(ir_repeat_valid),.frame_error(ir_frame_error),
 .raw_bytes(ir_raw_bytes),.alarm_active(alarm_active),.alarm_muted(alarm_muted),.key_event(),.last_command());
ir_volume_ctrl u_volume_ctrl(.clk(video_clk),.rst(ir_reset),
 .frame_valid(ir_frame_valid),.repeat_valid(ir_repeat_valid),.frame_error(ir_frame_error),
 .raw_bytes(ir_raw_bytes),.level(volume_level),.adjust_event(volume_adjust_event));
ir_video_mode_ctrl u_video_mode_ctrl(.clk(video_clk),.rst(ir_reset),
 .frame_valid(ir_frame_valid),.repeat_valid(ir_repeat_valid),.frame_error(ir_frame_error),
 .raw_bytes(ir_raw_bytes),.video_mode(robot_mode_requested),.press_event());
reg [1:0] alarm_system_sync,muted_system_sync;
reg [2:0] alarm_reset_pipe;
always @(posedge clk or posedge rst_all)begin
 if(rst_all)begin alarm_system_sync<=0;muted_system_sync<=0;alarm_reset_pipe<=3'b111;end
 else begin
  alarm_system_sync<={alarm_system_sync[0],alarm_active};
  muted_system_sync<={muted_system_sync[0],alarm_muted};
  alarm_reset_pipe<={alarm_reset_pipe[1:0],1'b0};
 end
end
wire melody_buzzer_n,siren_buzzer_n;
alarm_siren u_alarm_siren(.clk(clk),.rst(alarm_reset_pipe[2]),
 .enable(alarm_system_sync[1]&&!muted_system_sync[1]),.buzzer_n(siren_buzzer_n));
(* async_reg="true" *) reg [1:0] av_prompt_sync;
always @(posedge clk or posedge rst_all)
 if(rst_all)av_prompt_sync<=2'b11;else av_prompt_sync<={av_prompt_sync[0],av_prompt_n};
// Normal melody now goes through HDMI only; buzzer carries event prompt / alarm.
assign BUZZER=alarm_system_sync[1] ? (muted_system_sync[1] ? 1'b1 : siren_buzzer_n) : av_prompt_sync[1];
assign melody_buzzer_n=av_music_n;
wire buzzer_audio_active=av_music_active;
av_scene_player #(.MUTE_ENABLE(1)) u_av_player(.mute_media(robot_media_muted),.clk(video_clk),.rst(rst_all),.sample_tick48(av_sample_tick),
 .image_req_toggle(image_req_toggle),.target_scene(av_target_scene),.scene_start(av_scene_start&&logical_scene_change),
 .alarm_active(alarm_active),.alarm_muted(alarm_muted),.auto_enabled(av_auto),
 .stream_reset(av_stream_reset),.stream_group(av_stream_group),.stream_reset_ack(av_stream_ack),.stream_ready(av_stream_ready),
 .media_ready(av_media_ready),.fifo_rd_rst(av_rd_rst),.fifo_rd_en(av_rd_en),.fifo_rd_data(av_rd_data),
 .fifo_rd_valid(av_rd_valid),.fifo_empty(av_fifo_empty),.voice_scene(av_voice_scene),.voice_done(av_voice_done),
 .subtitle_group(av_subtitle_group),.subtitle_restart(av_subtitle_restart),.pcm_valid(photo_audio_valid),.pcm_sample(photo_audio_data),
 .music_buzzer_n(av_music_n),.music_active(av_music_active),.prompt_buzzer_n(av_prompt_n),.underrun_count(av_underruns));
// Target clip/frame is held stable with the existing image request mailbox
// until the frame-boundary commit and reader acknowledgement have completed.
wire robot_audio_enable=robot_mode_requested&&!alarm_active&&
 (robot_display_video||(av_scene_start&&robot_display_target));
av_pcm_fifo #(.AW(9)) u_robot_audio_fifo(
 .wr_clk(sd_card_clk),.wr_rst(robot_audio_wr_rst),.wr_en(robot_audio_wr_en),.wr_data(robot_audio_wr_data),
 .full(robot_audio_full),.wr_used(robot_audio_used),.rd_clk(video_clk),.rd_rst(robot_audio_rd_rst),
 .rd_en(robot_audio_rd_en),.rd_data(robot_audio_rd_data),.rd_valid(robot_audio_rd_valid),.empty(robot_audio_empty));
robot_audio_player u_robot_audio_player(.clk(video_clk),.rst(rst_all),.sample_tick48(av_sample_tick),
 .enable(robot_audio_enable),.scene_start(av_scene_start),.target_video(robot_display_target),
 .target_clip(robot_target_clip),.target_frame(robot_target_frame),
 .stream_reset(robot_audio_reset),.stream_clip(robot_audio_clip),.reset_ack(robot_audio_ack),.stream_ready(robot_audio_ready),
 .fifo_reset(robot_audio_rd_rst),.fifo_read(robot_audio_rd_en),.fifo_data(robot_audio_rd_data),
 .fifo_valid(robot_audio_rd_valid),.fifo_empty(robot_audio_empty),.pcm_sample(robot_audio_data),
 .pcm_valid(robot_audio_valid),.underruns(robot_audio_underruns));
assign audio_raw_valid=photo_audio_valid;
assign audio_raw_data=alarm_active?photo_audio_data:robot_media_muted?robot_audio_data:photo_audio_data;
audio_volume_scale u_volume_scale(.clk(video_clk),.rst(rst_all),.level(volume_level),
 .alarm_active(alarm_active),.valid_in(audio_raw_valid),.pcm_in(audio_raw_data),
 .valid_out(audio_valid),.pcm_out(audio_left_data));
assign audio_right_data=audio_left_data;

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// Reuse the documented fade controller. OSD is downstream and remains visible.
transition_ctrl #(.FADE_STEP(FADE_STEP),.AV_ENABLE(1),.FAST_ENABLE(1),.DETAIL_FADE_STEP(DETAIL_FADE_STEP),.DIRECT_ENABLE(1)) u_transition_ctrl (
    .direct_switch(robot_direct),.fast_switch(!logical_scene_change),.clk(video_clk), .rst(rst_all), .video_vs(vs),
    .image_req_toggle(image_req_toggle), .image_buf_index(disp_buf_idx),
    .read_done_toggle(read_done_toggle_mem), .read_done_index(read_done_index_mem),
    .active_buf_index(active_buf_index), .gain(fade_gain),
    .media_ready(av_media_ready||!logical_scene_change),.pause(alarm_active),.scene_start(av_scene_start),.scene_start_toggle(av_scene_start_toggle),
    .done_toggle(transition_done_toggle), .busy()
);
// Reuse the U-disk controls before fade so a positive brightness setting
// cannot turn the fade's black endpoint gray. Both OSD layers are after fade.
wire [23:0] adjusted_rgb;
wire adjusted_hs, adjusted_vs, adjusted_de;
wire signed [8:0] display_brightness;
wire [8:0] display_contrast;
wire display_adjust_enable, display_osd_enable, display_select_contrast, display_increase;
wire ui_adjust_event,ui_adjust_contrast;
hx4s20_picture_controls #(.CLK_HZ(25_000_000),.VS_ACTIVE_LOW(1'b1)) u_picture_controls (
    .clk(video_clk), .rst(rst_all), .key3_n(key3_n),
    .sw_param(sw_param), .sw_direction(sw_direction),
    .sw_adjust_en(sw_adjust_en), .sw_osd_en(sw_osd_en),
    .rgb_in(vout_data), .hs_in(hs), .vs_in(vs), .de_in(de),
    .rgb_out(adjusted_rgb), .hs_out(adjusted_hs), .vs_out(adjusted_vs), .de_out(adjusted_de),
    .brightness(display_brightness), .contrast_q8(display_contrast),
    .active_adjust_enable(display_adjust_enable), .active_osd_enable(display_osd_enable),
    .active_select_contrast(display_select_contrast), .active_increase(display_increase),
    .ui_adjust_event(ui_adjust_event),.ui_adjust_contrast(ui_adjust_contrast)
);

wire [23:0] fade_rgb;
wire fade_vs, fade_de;
video_fade u_video_fade (
    .clk(video_clk), .rst(rst_all), .gain(dbg_effective_gain), .rgb_in(adjusted_rgb),
    .hs_in(adjusted_hs), .vs_in(adjusted_vs), .de_in(adjusted_de), .rgb_out(fade_rgb),
    .hs_out(), .vs_out(fade_vs), .de_out(fade_de)
);

// Bottom subtitle; RGB, VS and DE are delayed together by one pixel clock.
wire [23:0] scroll_rgb;
wire scroll_vs;
wire scroll_de;
av_subtitle #(
    .FRAME_DIV   (1),
    .STEP_PIXELS (2)
) u_osd_scroll (
    .clk      (video_clk),
    .rst      (rst_all),
    .vs       (fade_vs),
    .de       (fade_de),
    .enable   (!detail_display_video&&!robot_display_video),
    .group_id(av_subtitle_group),.restart(av_subtitle_restart),
    .rgb_in   (fade_rgb),
    .vs_out   (scroll_vs),
    .de_out   (scroll_de),
    .rgb_out  (scroll_rgb)
);

wire [23:0] parameter_rgb;
wire parameter_vs, parameter_de;
hx4s20_osd_overlay #(.VOLUME_ENABLE(1),.VS_ACTIVE_LOW(1'b1),.OSD_X(180),.OSD_Y(304)) u_parameter_osd (
    .clk(video_clk), .rst(rst_all),
    .brightness(display_brightness), .contrast_q8(display_contrast),
    .adjust_enable(display_adjust_enable), .osd_enable(display_osd_enable&&!detail_display_video),
    .select_contrast(display_select_contrast), .increase(display_increase),
    .adjust_event(ui_adjust_event),.event_contrast(ui_adjust_contrast),.alarm_active(alarm_active),
    .volume_event(volume_adjust_event),.volume_level(volume_level),
    .rgb_in(scroll_rgb), .hs_in(1'b0), .vs_in(scroll_vs), .de_in(scroll_de),
    .rgb_out(parameter_rgb), .hs_out(), .vs_out(parameter_vs), .de_out(parameter_de)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
// Mirror 32 measured frequency bins at the sides, after photo and OSD stages.
wire [23:0] audio_visual_rgb;
wire audio_visual_vs,audio_visual_de;
audio_side_overlay #(.USE_PCM(1)) u_audio_visual (
    .clk(video_clk), .rst(rst_all),
    .buzzer_n(melody_buzzer_n), .audio_active(av_pcm!=0),.pcm_sample(av_pcm),
    .enable(display_osd_enable&&!detail_display_video&&!robot_display_video),
    .rgb_in(parameter_rgb), .vs_in(parameter_vs), .de_in(parameter_de),
    .rgb_out(audio_visual_rgb), .vs_out(audio_visual_vs), .de_out(audio_visual_de)
);

wire [23:0] dance_rgb;wire dance_vs,dance_de;
dance_overlay u_dance_overlay(.diagnostic(dance_diagnostic),.clk(video_clk),.rst(rst_all),.alarm(alarm_active||detail_display_video||robot_display_video||robot_mode_requested),.loaded(dance_loaded),.failed(dance_failed||dance_mem_fault),
 .frame_toggle(dance_frame_toggle),.frame_number(dance_frame_number),.frame_bank(dance_frame_bank),.frame_ack(dance_frame_ack),
 .mem_clk(sd_card_clk),.cache_we(dance_cache_we),.cache_addr(dance_cache_addr),.cache_data(dance_cache_data),
 .sd_clk(sd_card_clk),.pal_we(dance_pal_we),.pal_addr(dance_pal_addr),.pal_data(dance_pal_data),
 .rgb_in(audio_visual_rgb),.vs_in(audio_visual_vs),.de_in(audio_visual_de),
 .rgb_out(dance_rgb),.vs_out(dance_vs),.de_out(dance_de),.underruns(dance_underruns),.displayed_frame(dance_displayed_frame));
wire [23:0] emergency_rgb;
wire emergency_vs,emergency_de;
emergency_ui_v2 u_emergency_video(.clk(video_clk),.rst(ir_reset),
    .alarm_active(alarm_active),.alarm_muted(alarm_muted),
    .rgb_in(dance_rgb),.vs_in(dance_vs),.de_in(dance_de),
    .rgb_out(emergency_rgb),.vs_out(emergency_vs),.de_out(emergency_de));

video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (emergency_vs),
    .I_de          (emergency_de),
    .I_rgb         (emergency_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_all),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_all),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_all),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
