`timescale 1ns/1ps
// Six subtitle groups, shared deduplicated anti-aliased font ROM.
// Exactly two pixel clocks of RGB/VS/DE latency.
module av_subtitle #(
 parameter integer FRAME_DIV=2,parameter integer STEP_PIXELS=2,parameter integer H_ACTIVE=640
)(
 input clk,input rst,input vs,input de,input enable,
 input [2:0] group_id,input restart,input [23:0] rgb_in,
 output reg vs_out,output reg de_out,output reg [23:0] rgb_out
);
`include "av_subtitles.vh"
reg vs_d,de_d,restart_pending;
reg [9:0] x;
reg [8:0] y;
reg [15:0] scroll_offset,frame_count;
reg [2:0] active_group;
wire [15:0] text_width={3'd0,text_length(active_group),5'd0};
wire [15:0] span=H_ACTIVE+text_width;
always @(posedge clk or posedge rst)
 if(rst)begin vs_d<=0;de_d<=0;x<=0;y<=0;scroll_offset<=0;frame_count<=0;active_group<=0;restart_pending<=0;end
 else begin
  vs_d<=vs;de_d<=de;
  if(restart)restart_pending<=1;
  if(vs_d!=vs)begin x<=0;y<=0;end
  else if(de)x<=x+1'b1;
  else begin x<=0;if(de_d)y<=y==479 ? 0 : y+1'b1;end
  if(vs&&!vs_d)begin
   if(restart_pending||restart||active_group!=group_id)begin
    active_group<=group_id;scroll_offset<=0;frame_count<=0;restart_pending<=0;
   end else if(enable)begin
    if(frame_count==FRAME_DIV-1)begin
     frame_count<=0;
     scroll_offset<=scroll_offset+STEP_PIXELS>=span ? scroll_offset+STEP_PIXELS-span : scroll_offset+STEP_PIXELS;
    end else frame_count<=frame_count+1'b1;
   end
  end
 end
wire [16:0] text_space={7'd0,x}+{1'b0,scroll_offset};
wire [16:0] text_local=text_space-H_ACTIVE;
wire [8:0] text_y=y-9'd440;
wire [7:0] glyph=glyph_id(active_group,text_local[12:5]);
reg [63:0] row_bits;
always @(posedge clk)row_bits<=subtitle_rom[{glyph[6:0],text_y[4:0]}];
reg [5:0] bit_index;
reg band_s,text_s,enable_s,vs_s,de_s;
reg [23:0] rgb_s;
always @(posedge clk or posedge rst)
 if(rst)begin bit_index<=0;band_s<=0;text_s<=0;enable_s<=0;vs_s<=0;de_s<=0;rgb_s<=0;end
 else begin
  bit_index<={5'd31-text_local[4:0],1'b0};band_s<=y>=432&&y<480;
  text_s<=text_space>=H_ACTIVE&&text_space<H_ACTIVE+text_width&&y>=440&&y<472;
  enable_s<=enable;vs_s<=vs;de_s<=de;rgb_s<=rgb_in;
 end
wire [1:0] alpha=row_bits[bit_index +:2];
wire [23:0] dim={2'b00,rgb_s[23:18],2'b00,rgb_s[15:10],2'b00,rgb_s[7:2]};
function [7:0] blend;
 input [7:0] b;input [1:0] a;reg [9:0] sum;
 begin case(a)
  0:blend=b;
  1:begin sum={2'd0,b}+{1'd0,b,1'b0}+10'd255;blend=sum[9:2];end
  2:begin sum={2'd0,b}+10'd765;blend=sum[9:2];end
  default:blend=255;
 endcase end
endfunction
always @(posedge clk or posedge rst)
 if(rst)begin rgb_out<=0;vs_out<=0;de_out<=0;end
 else begin
  vs_out<=vs_s;de_out<=de_s;rgb_out<=rgb_s;
  if(enable_s&&de_s)begin
   if(band_s)rgb_out<=dim;
   if(text_s)rgb_out<={blend(dim[23:16],alpha),blend(dim[15:8],alpha),blend(dim[7:0],alpha)};
  end
 end
endmodule
