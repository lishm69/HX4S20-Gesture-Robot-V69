`timescale 1ns/1ps
// Four digital RGB levels after photo fade and OSD composition.
// Physical KEY3 is active low. One debounced press advances one level;
// a held key does not repeat. Commit at VS falling edge to avoid a split frame.
module video_brightness4 #(
    parameter integer CLK_FREQ_HZ = 25_000_000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        key_n,
    input  wire        vs_in,
    input  wire        de_in,
    input  wire [23:0] rgb_in,
    output reg         vs_out,
    output reg         de_out,
    output reg  [23:0] rgb_out,
    output reg  [1:0]  level_applied
);
wire press_pulse;
reg [1:0] level_requested;
reg vs_d;
wire frame_tick = vs_d && !vs_in;
wire [1:0] next_level = level_requested + 2'd1;

key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(20)) u_key (
    .clk(clk),.rst(rst),.button_in(key_n),.press_pulse(press_pulse)
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        vs_d            <= 1'b0;
        level_requested <= 2'd0;
        level_applied   <= 2'd0;
    end else begin
        vs_d <= vs_in;
        if (press_pulse)
            level_requested <= next_level;
        if (frame_tick && !de_in)
            level_applied <= press_pulse ? next_level : level_requested;
    end
end

// All intermediate terms are wide enough. No additional multipliers are used.
function [7:0] dim_channel;
    input [7:0] channel;
    input [1:0] level;
    reg [9:0] triple;
    begin
        triple = {1'b0,channel,1'b0} + {2'b0,channel};
        case (level)
            2'd0: dim_channel = channel;             // 100%
            2'd1: dim_channel = triple[9:2];         // floor(channel * 3/4)
            2'd2: dim_channel = {1'b0,channel[7:1]}; // 50%
            2'd3: dim_channel = {2'b0,channel[7:2]}; // 25%
        endcase
    end
endfunction

// RGB and its qualifiers share one registered pixel stage.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        vs_out  <= 1'b0;
        de_out  <= 1'b0;
        rgb_out <= 24'd0;
    end else begin
        vs_out <= vs_in;
        de_out <= de_in;
        if (de_in)
            rgb_out <= {dim_channel(rgb_in[23:16],level_applied),
                        dim_channel(rgb_in[15:8],level_applied),
                        dim_channel(rgb_in[7:0],level_applied)};
        else
            rgb_out <= 24'd0;
    end
end
endmodule
