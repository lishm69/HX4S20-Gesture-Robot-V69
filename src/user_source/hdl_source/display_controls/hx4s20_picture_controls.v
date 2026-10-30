`timescale 1ns/1ps
// First integration block: raw board inputs + RGB -> adjusted RGB and state.
// Feed this output to the existing video_fade, then hx4s20_osd_overlay.
module hx4s20_picture_controls #(
    parameter integer CLK_HZ=25000000,
    parameter integer DEBOUNCE_CYCLES=CLK_HZ/50,
    parameter integer LONG_PRESS_CYCLES=CLK_HZ,
    parameter VS_ACTIVE_LOW=1'b1
)(
    input wire clk, input wire rst,
    input wire key3_n,
    input wire sw_param, input wire sw_direction,
    input wire sw_adjust_en, input wire sw_osd_en,
    input wire [23:0] rgb_in,
    input wire hs_in, input wire vs_in, input wire de_in,
    output wire [23:0] rgb_out,
    output wire hs_out, output wire vs_out, output wire de_out,
    output wire signed [8:0] brightness,
    output wire [8:0] contrast_q8,
    output wire active_adjust_enable, output wire active_osd_enable,
    output wire active_select_contrast, output wire active_increase,
    output wire ui_adjust_event, output wire ui_adjust_contrast
);
wire key_db,select_db,increase_db,adjust_db,osd_db;
wire short_event,long_event;
assign ui_adjust_event=short_event | long_event;
reg vs_d;
wire frame_tick=VS_ACTIVE_LOW ? (vs_d && !vs_in) : (!vs_d && vs_in);
always @(posedge clk or posedge rst) begin
    if(rst) vs_d<=VS_ACTIVE_LOW ? 1'b0 : 1'b1;
    else vs_d<=vs_in;
end
hx4s20_input_filter #(.STABLE_CYCLES(DEBOUNCE_CYCLES),.RESET_VALUE(1'b1))
    u_key(.clk(clk),.rst(rst),.async_in(key3_n),.stable_out(key_db));
hx4s20_input_filter #(.STABLE_CYCLES(DEBOUNCE_CYCLES))
    u_select(.clk(clk),.rst(rst),.async_in(sw_param),.stable_out(select_db));
hx4s20_input_filter #(.STABLE_CYCLES(DEBOUNCE_CYCLES))
    u_direction(.clk(clk),.rst(rst),.async_in(sw_direction),.stable_out(increase_db));
hx4s20_input_filter #(.STABLE_CYCLES(DEBOUNCE_CYCLES))
    u_adjust(.clk(clk),.rst(rst),.async_in(sw_adjust_en),.stable_out(adjust_db));
hx4s20_input_filter #(.STABLE_CYCLES(DEBOUNCE_CYCLES))
    u_osd(.clk(clk),.rst(rst),.async_in(sw_osd_en),.stable_out(osd_db));
hx4s20_param_ctrl #(.LONG_PRESS_CYCLES(LONG_PRESS_CYCLES)) u_params (
    .clk(clk),.rst(rst),.frame_tick(frame_tick),.key_n(key_db),
    .select_contrast(select_db),.increase(increase_db),
    .adjust_enable(adjust_db),.osd_enable(osd_db),
    .brightness(brightness),.contrast_q8(contrast_q8),
    .active_adjust_enable(active_adjust_enable),.active_osd_enable(active_osd_enable),
    .active_select_contrast(active_select_contrast),.active_increase(active_increase),
    .short_pulse(short_event),.long_pulse(long_event),.event_contrast(ui_adjust_contrast)
);
hx4s20_image_adjust u_pixels (
    .clk(clk),.rst(rst),.enable(active_adjust_enable),
    .brightness(brightness),.contrast_q8(contrast_q8),.rgb_in(rgb_in),
    .hs_in(hs_in),.vs_in(vs_in),.de_in(de_in),
    .rgb_out(rgb_out),.hs_out(hs_out),.vs_out(vs_out),.de_out(de_out)
);
endmodule
