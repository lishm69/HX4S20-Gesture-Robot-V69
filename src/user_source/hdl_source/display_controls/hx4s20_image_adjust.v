`timescale 1ns/1ps
// Four registered stages, one pixel/clock. Output qualifiers have the same
// four-stage latency in adjustment and bypass modes. RGB is zero in blanking.
module hx4s20_image_adjust (
    input wire clk, input wire rst,
    input wire enable,
    input wire signed [8:0] brightness,
    input wire [8:0] contrast_q8,
    input wire [23:0] rgb_in,
    input wire hs_in, input wire vs_in, input wire de_in,
    output reg [23:0] rgb_out,
    output wire hs_out, output wire vs_out, output wire de_out
);
// Shared control pipeline; identical arithmetic for each RGB channel.
reg signed [8:0] centered[0:2];
reg signed [18:0] product[0:2], value[0:2];
reg signed [9:0] contrast_s1;
reg signed [8:0] brightness_s1, brightness_s2;
reg [23:0] raw_s1, raw_s2, raw_s3;
reg [2:0] enabled;
reg [3:0] hs_pipe, vs_pipe, de_pipe;
assign hs_out=hs_pipe[3];
assign vs_out=vs_pipe[3];
assign de_out=de_pipe[3];
function [7:0] saturate;
    input signed [18:0] v;
    begin saturate=v<0 ? 8'd0 : v>255 ? 8'd255 : v[7:0]; end
endfunction
integer c;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        contrast_s1<=256; brightness_s1<=0; brightness_s2<=0;
        raw_s1<=0; raw_s2<=0; raw_s3<=0; enabled<=0;
        hs_pipe<=0; vs_pipe<=0; de_pipe<=0; rgb_out<=0;
        for(c=0;c<3;c=c+1) begin centered[c]<=0; product[c]<=0; value[c]<=0; end
    end else begin
        hs_pipe<={hs_pipe[2:0],hs_in};
        vs_pipe<={vs_pipe[2:0],vs_in};
        de_pipe<={de_pipe[2:0],de_in};
        contrast_s1<=$signed({1'b0,contrast_q8});
        brightness_s1<=brightness; brightness_s2<=brightness_s1;
        raw_s1<=rgb_in; raw_s2<=raw_s1; raw_s3<=raw_s2;
        enabled<={enabled[1:0],enable};
        for(c=0;c<3;c=c+1) begin
            centered[c]<=$signed({1'b0,rgb_in[c*8 +: 8]})-9'sd128;
            product[c]<=centered[c]*contrast_s1;
            value[c]<=(product[c] >>> 8)+19'sd128+$signed({{10{brightness_s2[8]}},brightness_s2});
            rgb_out[c*8 +: 8]<=!de_pipe[2] ? 8'd0 :
                enabled[2] ? saturate(value[c]) : raw_s3[c*8 +: 8];
        end
    end
end
endmodule
