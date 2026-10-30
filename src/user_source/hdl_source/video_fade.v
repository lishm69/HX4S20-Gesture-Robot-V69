`timescale 1ns/1ps
// One registered pixel stage. Keep RGB and video qualifiers aligned.
// gain=256 is unity; gain=0 is black. The controller changes it in blanking.
module video_fade (
    input  wire        clk,
    input  wire        rst,
    input  wire [8:0]  gain,
    input  wire [23:0] rgb_in,
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire        de_in,
    output reg  [23:0] rgb_out,
    output reg         hs_out,
    output reg         vs_out,
    output reg         de_out
);
function [7:0] apply_gain;
    input [7:0] channel;
    input [8:0] factor;
    reg [16:0] product;
    begin product=channel*factor; apply_gain=product[15:8]; end
endfunction
integer channel;
always @(posedge clk or posedge rst) begin
    if (rst) begin rgb_out<=0; hs_out<=0; vs_out<=0; de_out<=0; end
    else begin
        {hs_out,vs_out,de_out}<={hs_in,vs_in,de_in};
        for (channel=0;channel<3;channel=channel+1)
            rgb_out[channel*8 +: 8]<=de_in ? apply_gain(rgb_in[channel*8 +: 8],gain) : 8'd0;
    end
end
endmodule
