`timescale 1ns/1ps
// Inputs must already be synchronized/debounced into clk.
// Pending settings change on key events; outputs commit only on frame_tick.
module hx4s20_param_ctrl #(
    parameter integer LONG_PRESS_CYCLES = 25000000
)(
    input wire clk, input wire rst, input wire frame_tick,
    input wire key_n,
    input wire select_contrast, input wire increase,
    input wire adjust_enable, input wire osd_enable,
    output reg signed [8:0] brightness,
    output reg [8:0] contrast_q8,
    output reg active_adjust_enable, output reg active_osd_enable,
    output reg active_select_contrast, output reg active_increase,
    output reg short_pulse, output reg long_pulse, output reg event_contrast
);
function integer bits_for;
    input integer value;
    integer t;
    begin
        bits_for=0;
        for(t=value-1;t>0;t=t>>1) bits_for=bits_for+1;
        if(bits_for<1) bits_for=1;
    end
endfunction
localparam integer HOLD_W=bits_for(LONG_PRESS_CYCLES);
reg signed [8:0] pending_brightness;
reg [8:0] pending_contrast;
reg key_d, held, long_fired;
reg press_contrast, press_increase, press_enabled;
reg [HOLD_W-1:0] hold_count;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        pending_brightness<=9'sd0;pending_contrast<=9'd256;
        brightness<=9'sd0;contrast_q8<=9'd256;
        active_adjust_enable<=0;active_osd_enable<=0;
        active_select_contrast<=0;active_increase<=0;
        key_d<=1;held<=0;long_fired<=0;
        press_contrast<=0;press_increase<=0;press_enabled<=0;
        hold_count<=0;short_pulse<=0;long_pulse<=0;event_contrast<=0;
    end else begin
        key_d<=key_n;short_pulse<=0;long_pulse<=0;
        if(frame_tick) begin
            brightness<=pending_brightness;contrast_q8<=pending_contrast;
            active_adjust_enable<=adjust_enable;
            active_osd_enable<=osd_enable;
            active_select_contrast<=select_contrast;
            active_increase<=increase;
        end
        // Disabling adjustment cancels an in-progress gesture, without losing
        // the saved settings. A switch moved mid-gesture cannot retarget it.
        if(!adjust_enable) press_enabled<=0;
        if(key_d && !key_n) begin
            held<=1;long_fired<=0;hold_count<=0;
            press_contrast<=select_contrast;
            press_increase<=increase;press_enabled<=adjust_enable;
        end else if(!key_n && held && !long_fired) begin
            if(hold_count==LONG_PRESS_CYCLES-1) begin
                long_fired<=1;
                if(press_enabled && adjust_enable) begin
                    long_pulse<=1;event_contrast<=press_contrast;
                    if(press_contrast) pending_contrast<=9'd256;
                    else pending_brightness<=9'sd0;
                end
            end else hold_count<=hold_count+1'b1;
        end else if(!key_d && key_n) begin
            held<=0;hold_count<=0;
            if(held && !long_fired && press_enabled && adjust_enable) begin
                short_pulse<=1;event_contrast<=press_contrast;
                if(press_contrast) begin
                    if(press_increase) begin
                        if(pending_contrast<9'd384)
                            pending_contrast<=pending_contrast+9'd32;
                    end else if(pending_contrast>9'd128)
                        pending_contrast<=pending_contrast-9'd32;
                end else begin
                    if(press_increase) begin
                        if(pending_brightness<9'sd64)
                            pending_brightness<=pending_brightness+9'sd8;
                    end else if(pending_brightness > -9'sd64)
                        pending_brightness<=pending_brightness-9'sd8;
                end
            end
        end
    end
end
endmodule
