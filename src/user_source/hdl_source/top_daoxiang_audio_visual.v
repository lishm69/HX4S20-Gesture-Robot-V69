
module top(
    input                       clk,
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

parameter FADE_STEP = 8;
parameter AUTO_HOLD_SECONDS = 3;
parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;

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

wire rst_all;
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
wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_left_data;
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

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .AUTO_HOLD_SECONDS (AUTO_HOLD_SECONDS),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (4'd8)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_all),
    .key_next          (key1),
    .key_auto          (key2),
    .state_code        (state_code),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),
    .current_image_number(current_image_number),
    .image_total       (image_total),
    .image_scan_done   (image_scan_done),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),
    .image_req_toggle  (image_req_toggle),
    .transition_done_toggle (transition_done_toggle),

    .write_req         (sd_card_write_req),
    .write_req_ack     (write_ack_sd_sync[2]),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

seg_decoder u_seg_image_number(.bin_data(current_image_number), .seg_data(seg_image_number));
seg_decoder u_seg_image_total(.bin_data(image_total), .seg_data(seg_image_total));

// Diagnostic build only. Holding physical KEY2 bypasses the photo fade.
// SD-domain progress code: 0 scanning/loading; 1 frame committed, waiting
// for fade; 2 fade running; 3 full brightness. A second digit records whether
// the SDRAM reader has ever completed a frame (0/1).
reg dbg_read_seen_mem;
reg [1:0] dbg_read_seen_sync;
reg [8:0] dbg_gain_meta, dbg_gain_sync;
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all) dbg_read_seen_mem <= 1'b0;
    else if (video_read_finish) dbg_read_seen_mem <= 1'b1;
end
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) begin
        dbg_read_seen_sync <= 2'b00;
        dbg_gain_meta <= 9'd0;
        dbg_gain_sync <= 9'd0;
    end else begin
        dbg_read_seen_sync <= {dbg_read_seen_sync[0],dbg_read_seen_mem};
        dbg_gain_meta <= fade_gain;
        dbg_gain_sync <= dbg_gain_meta;
    end
end
wire [3:0] dbg_progress = !display_valid ? 4'd0 :
    dbg_gain_sync==0 ? 4'd1 : dbg_gain_sync==256 ? 4'd3 : 4'd2;
wire [6:0] dbg_progress_segments, dbg_read_segments;
seg_decoder u_dbg_progress(.bin_data(dbg_progress),.seg_data(dbg_progress_segments));
seg_decoder u_dbg_read(.bin_data({3'b0,dbg_read_seen_sync[1]}),.seg_data(dbg_read_segments));
reg [1:0] dbg_bypass_sync;
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) dbg_bypass_sync <= 2'b11;
    else dbg_bypass_sync <= {dbg_bypass_sync[0],key1};
end
wire [8:0] dbg_effective_gain = !dbg_bypass_sync[1] ? 9'd256 : fade_gain;

// Run scanning in the SD clock domain, avoiding an asynchronous multi-bit bus.
seg_scan #(.CLK_FREQ(100000000)) seg_scan_m0(
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
assign vout_data = display_valid ? vout_data_raw : 24'd0;

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (video_read_finish),
    .read_active_index (video_read_active_index),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (24'd0),
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
    .write_addr_2      (24'd0),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// Board buzzer: SW5 down connects, SW5 up physically disconnects.
// User-supplied numbered-score melody, independent of picture/card/audio paths.
wire buzzer_audio_active;
buzzer_daoxiang_visual #(.CLK_HZ(50_000_000)) u_buzzer_daoxiang (
    .clk(clk), .rst(rst_all), .buzzer_n(BUZZER), .audio_active(buzzer_audio_active)
);

// ===================== 音频：内部 I2S 测试音 =====================
hdmi_audio_tone_i2s_64fs #(
    .PHASE_INC (32'd39370534),
    .AMP       (24'sd2000000)
) u_hdmi_audio_tone_i2s_64fs (
    .I_mclk      (audio_mclk),
    .I_rst       (rst_all),
    .O_i2s_BCLK  (audio_i2s_bclk),
    .O_i2s_LRCK  (audio_i2s_lrck),
    .O_i2s_DOUT  (audio_i2s_dout)
);

I2S_receiver u_I2S_receiver(
    .I_clk              (video_clk),
    .I_rst              (rst_all),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_left_data),
    .O_audio_right_data (audio_right_data)
);

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
transition_ctrl #(.FADE_STEP(FADE_STEP)) u_transition_ctrl (
    .clk(video_clk), .rst(rst_all), .video_vs(vs),
    .image_req_toggle(image_req_toggle), .image_buf_index(disp_buf_idx),
    .read_done_toggle(read_done_toggle_mem), .read_done_index(read_done_index_mem),
    .active_buf_index(active_buf_index), .gain(fade_gain),
    .done_toggle(transition_done_toggle), .busy()
);
// Reuse the U-disk controls before fade so a positive brightness setting
// cannot turn the fade's black endpoint gray. Both OSD layers are after fade.
wire [23:0] adjusted_rgb;
wire adjusted_hs, adjusted_vs, adjusted_de;
wire signed [8:0] display_brightness;
wire [8:0] display_contrast;
wire display_adjust_enable, display_osd_enable, display_select_contrast, display_increase;
hx4s20_picture_controls #(.CLK_HZ(25_000_000),.VS_ACTIVE_LOW(1'b1)) u_picture_controls (
    .clk(video_clk), .rst(rst_all), .key3_n(key3_n),
    .sw_param(sw_param), .sw_direction(sw_direction),
    .sw_adjust_en(sw_adjust_en), .sw_osd_en(sw_osd_en),
    .rgb_in(vout_data), .hs_in(hs), .vs_in(vs), .de_in(de),
    .rgb_out(adjusted_rgb), .hs_out(adjusted_hs), .vs_out(adjusted_vs), .de_out(adjusted_de),
    .brightness(display_brightness), .contrast_q8(display_contrast),
    .active_adjust_enable(display_adjust_enable), .active_osd_enable(display_osd_enable),
    .active_select_contrast(display_select_contrast), .active_increase(display_increase)
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
osd_scroll #(
    .FRAME_DIV   (2),
    .STEP_PIXELS (2)
) u_osd_scroll (
    .clk      (video_clk),
    .rst      (rst_all),
    .vs       (fade_vs),
    .de       (fade_de),
    .enable   (1'b1),
    .rgb_in   (fade_rgb),
    .vs_out   (scroll_vs),
    .de_out   (scroll_de),
    .rgb_out  (scroll_rgb)
);

wire [23:0] parameter_rgb;
wire parameter_vs, parameter_de;
hx4s20_osd_overlay #(.VS_ACTIVE_LOW(1'b1),.OSD_X(16),.OSD_Y(16)) u_parameter_osd (
    .clk(video_clk), .rst(rst_all),
    .brightness(display_brightness), .contrast_q8(display_contrast),
    .adjust_enable(display_adjust_enable), .osd_enable(display_osd_enable),
    .select_contrast(display_select_contrast), .increase(display_increase),
    .rgb_in(scroll_rgb), .hs_in(1'b0), .vs_in(scroll_vs), .de_in(scroll_de),
    .rgb_out(parameter_rgb), .hs_out(), .vs_out(parameter_vs), .de_out(parameter_de)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
// Display the actual buzzer drive, after all existing photo and OSD stages.
wire [23:0] audio_visual_rgb;
wire audio_visual_vs,audio_visual_de;
audio_wave_overlay u_audio_visual (
    .clk(video_clk), .rst(rst_all),
    .buzzer_n(BUZZER), .audio_active(buzzer_audio_active),
    .enable(display_osd_enable),
    .rgb_in(parameter_rgb), .vs_in(parameter_vs), .de_in(parameter_de),
    .rgb_out(audio_visual_rgb), .vs_out(audio_visual_vs), .de_out(audio_visual_de)
);

video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (audio_visual_vs),
    .I_de          (audio_visual_de),
    .I_rgb         (audio_visual_rgb),
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
