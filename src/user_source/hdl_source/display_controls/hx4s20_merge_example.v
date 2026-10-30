`timescale 1ns/1ps
// Integration template, NOT a complete board top.
// Dependency: the existing main project's video_fade.v (one registered stage).
// Replace the old video_fade instance with this chain; do not cascade two fades.
module hx4s20_merge_example #(
    parameter integer CLK_HZ=25000000,
    parameter integer DEBOUNCE_CYCLES=CLK_HZ/50,
    parameter integer LONG_PRESS_CYCLES=CLK_HZ,
    parameter VS_ACTIVE_LOW=1'b1,
    parameter integer OSD_X=16,
    parameter integer OSD_Y=16
)(
    input wire clk, input wire rst,
    input wire key3_n,
    input wire sw_param, input wire sw_direction,
    input wire sw_adjust_en, input wire sw_osd_en,
    input wire [8:0] fade_gain,
    input wire [23:0] rgb_in,
    input wire hs_in, input wire vs_in, input wire de_in,
    output wire [23:0] rgb_out,
    output wire hs_out, output wire vs_out, output wire de_out
);
wire [23:0] adjusted_rgb,faded_rgb;
wire adjusted_hs,adjusted_vs,adjusted_de;
wire faded_hs,faded_vs,faded_de;
wire signed [8:0] brightness;
wire [8:0] contrast_q8;
wire adjust_en,osd_en,select_contrast,increase;
hx4s20_picture_controls #(
    .CLK_HZ(CLK_HZ),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
    .LONG_PRESS_CYCLES(LONG_PRESS_CYCLES),.VS_ACTIVE_LOW(VS_ACTIVE_LOW)
) u_controls (
    .clk(clk),.rst(rst),.key3_n(key3_n),
    .sw_param(sw_param),.sw_direction(sw_direction),
    .sw_adjust_en(sw_adjust_en),.sw_osd_en(sw_osd_en),
    .rgb_in(rgb_in),.hs_in(hs_in),.vs_in(vs_in),.de_in(de_in),
    .rgb_out(adjusted_rgb),.hs_out(adjusted_hs),.vs_out(adjusted_vs),.de_out(adjusted_de),
    .brightness(brightness),.contrast_q8(contrast_q8),
    .active_adjust_enable(adjust_en),.active_osd_enable(osd_en),
    .active_select_contrast(select_contrast),.active_increase(increase)
);
video_fade u_existing_fade (
    .clk(clk),.rst(rst),.gain(fade_gain),
    .rgb_in(adjusted_rgb),.hs_in(adjusted_hs),.vs_in(adjusted_vs),.de_in(adjusted_de),
    .rgb_out(faded_rgb),.hs_out(faded_hs),.vs_out(faded_vs),.de_out(faded_de)
);
hx4s20_osd_overlay #(.VS_ACTIVE_LOW(VS_ACTIVE_LOW),.OSD_X(OSD_X),.OSD_Y(OSD_Y)) u_osd (
    .clk(clk),.rst(rst),.brightness(brightness),.contrast_q8(contrast_q8),
    .adjust_enable(adjust_en),.osd_enable(osd_en),
    .select_contrast(select_contrast),.increase(increase),
    .rgb_in(faded_rgb),.hs_in(faded_hs),.vs_in(faded_vs),.de_in(faded_de),
    .rgb_out(rgb_out),.hs_out(hs_out),.vs_out(vs_out),.de_out(de_out)
);
endmodule
