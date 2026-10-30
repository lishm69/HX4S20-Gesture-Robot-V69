`timescale 1ns/1ps
// Three pixel clocks for RGB/VS/DE, including normal bypass. Mode is sampled
// only at falling VS; emergency pixels never depend on TF/framebuffer contents.
module emergency_ui_v2(input wire clk,rst,input wire alarm_active,alarm_muted,
 input wire [23:0] rgb_in,input wire vs_in,de_in,
 output reg [23:0] rgb_out,output reg vs_out,de_out);
reg vs_previous,de_previous,alarm_frame,muted_frame;
reg [11:0] next_x,line_y;
wire frame_tick=vs_previous && !vs_in;
wire [11:0] pixel_x=de_previous ? next_x : 12'd0;
always @(posedge clk or posedge rst)begin
 if(rst)begin vs_previous<=1;de_previous<=0;alarm_frame<=0;muted_frame<=0;next_x<=0;line_y<=0;end
 else begin
  vs_previous<=vs_in;de_previous<=de_in;
  if(frame_tick)begin next_x<=0;line_y<=0;alarm_frame<=alarm_active;muted_frame<=alarm_muted;end
  else begin
   if(de_in)next_x<=pixel_x+1'b1;else next_x<=0;
   if(de_previous && !de_in)line_y<=line_y+1'b1;
  end
 end
end
function [5:0] message_glyph;
 input [2:0] message;input [4:0] index;
 begin message_glyph=0;case(message)
  3'd0:case(index)
   5'd0:message_glyph=6'd1;
   5'd1:message_glyph=6'd2;
   5'd2:message_glyph=6'd3;
   5'd3:message_glyph=6'd4;
   default:message_glyph=0;endcase
  3'd1:case(index)
   5'd0:message_glyph=6'd5;
   5'd1:message_glyph=6'd6;
   5'd2:message_glyph=6'd7;
   5'd3:message_glyph=6'd8;
   5'd4:message_glyph=6'd9;
   5'd5:message_glyph=6'd10;
   5'd6:message_glyph=6'd11;
   5'd7:message_glyph=6'd12;
   5'd8:message_glyph=6'd13;
   5'd9:message_glyph=6'd14;
   5'd10:message_glyph=6'd15;
   5'd11:message_glyph=6'd16;
   5'd12:message_glyph=6'd17;
   default:message_glyph=0;endcase
  3'd2:case(index)
   5'd0:message_glyph=6'd4;
   5'd1:message_glyph=6'd3;
   5'd2:message_glyph=6'd18;
   5'd3:message_glyph=6'd19;
   5'd4:message_glyph=6'd20;
   5'd5:message_glyph=6'd21;
   default:message_glyph=0;endcase
  3'd3:case(index)
   5'd0:message_glyph=6'd19;
   5'd1:message_glyph=6'd9;
   5'd2:message_glyph=6'd22;
   5'd3:message_glyph=6'd23;
   5'd4:message_glyph=6'd24;
   5'd5:message_glyph=6'd23;
   5'd6:message_glyph=6'd3;
   5'd7:message_glyph=6'd4;
   5'd8:message_glyph=6'd25;
   5'd9:message_glyph=6'd6;
   5'd10:message_glyph=6'd7;
   default:message_glyph=0;endcase
  3'd4:case(index)
   5'd0:message_glyph=6'd11;
   5'd1:message_glyph=6'd26;
   5'd2:message_glyph=6'd27;
   5'd3:message_glyph=6'd28;
   5'd4:message_glyph=6'd3;
   5'd5:message_glyph=6'd4;
   5'd6:message_glyph=6'd23;
   5'd7:message_glyph=6'd23;
   5'd8:message_glyph=6'd11;
   5'd9:message_glyph=6'd29;
   5'd10:message_glyph=6'd9;
   5'd11:message_glyph=6'd22;
   default:message_glyph=0;endcase
  3'd5:case(index)
   5'd0:message_glyph=6'd11;
   5'd1:message_glyph=6'd26;
   5'd2:message_glyph=6'd27;
   5'd3:message_glyph=6'd28;
   5'd4:message_glyph=6'd3;
   5'd5:message_glyph=6'd4;
   5'd6:message_glyph=6'd23;
   5'd7:message_glyph=6'd23;
   5'd8:message_glyph=6'd11;
   5'd9:message_glyph=6'd30;
   5'd10:message_glyph=6'd31;
   5'd11:message_glyph=6'd32;
   5'd12:message_glyph=6'd18;
   5'd13:message_glyph=6'd22;
   default:message_glyph=0;endcase
  3'd6:case(index)
   5'd0:message_glyph=6'd33;
   5'd1:message_glyph=6'd3;
   5'd2:message_glyph=6'd4;
   default:message_glyph=0;endcase
 default:message_glyph=0;endcase end
endfunction
// Identical glyph rows, moved from combinational case LUTs to two 32K BRAMs.
reg [31:0] alarm_glyph_rom[0:2047] /* synthesis ram_style=bram_32k */;
initial $readmemh("alarm_glyph_rows.hex",alarm_glyph_rom);

reg [7:0] caption_char;
always @* begin caption_char=" ";case((pixel_x-12'd248)>>4)
   4'd0:caption_char="E";
   4'd1:caption_char="M";
   4'd2:caption_char="E";
   4'd3:caption_char="R";
   4'd4:caption_char="G";
   4'd5:caption_char="E";
   4'd6:caption_char="N";
   4'd7:caption_char="C";
   4'd8:caption_char="Y";
 default:caption_char=" ";endcase end
wire caption_pixel;
wire [3:0] caption_row=(line_y-12'd206)>>1;
wire [2:0] caption_col=(pixel_x-12'd248)>>1;
hx4s20_osd_font u_caption_font(.character(caption_char),.row(caption_row),.column(caption_col),.pixel(caption_pixel));
reg [5:0] glyph_a;reg [4:0] row_a,col_a;
reg [23:0] base_a,ink_a,base_b,ink_b;
reg [31:0] bitmap_b;reg [4:0] col_b;
reg vs_a,de_a,vs_b,de_b;
always @(posedge clk)bitmap_b<=alarm_glyph_rom[{glyph_a,row_a}];
always @(posedge clk or posedge rst)begin
 if(rst)begin
  glyph_a<=0;row_a<=0;col_a<=0;base_a<=0;ink_a<=0;
  base_b<=0;ink_b<=0;col_b<=0;
  vs_a<=1;de_a<=0;vs_b<=1;de_b<=0;vs_out<=1;de_out<=0;rgb_out<=0;
 end else begin
  vs_a<=vs_in;de_a<=de_in;vs_b<=vs_a;de_b<=de_a;vs_out<=vs_b;de_out<=de_b;
  glyph_a<=0;row_a<=0;col_a<=0;ink_a<=24'hffffff;
  base_a<=de_in ? rgb_in : 24'h000000;
  if(de_in && alarm_frame)begin
   base_a<=24'h780014;
   if(pixel_x<8 || pixel_x>=632 || line_y<8 || line_y>=472)base_a<=24'hffe060;
   if(line_y>=206 && line_y<238 && pixel_x>=248 && pixel_x<392 && caption_pixel)base_a<=24'hffe060;
   // Centered warning triangle, generated without multiplication/DSPs.
   if(line_y>=32 && line_y<108 && pixel_x>=320-((line_y-32)>>1) && pixel_x<=320+((line_y-32)>>1))begin
    base_a<=24'hffe060;
    if(pixel_x>=317 && pixel_x<=323 && ((line_y>=54 && line_y<84) || (line_y>=91 && line_y<98)))base_a<=24'h780014;
   end
  if(pixel_x>=192 && pixel_x<448 && line_y>=134 && line_y<198)begin
   glyph_a<=message_glyph(3'd0,(pixel_x-12'd192)>>6);
   row_a<=(line_y-12'd134)>>1;
   col_a<=(pixel_x-12'd192)>>1;ink_a<=24'hffffff;
  end

  if(pixel_x>=112 && pixel_x<528 && line_y>=258 && line_y<290)begin
   glyph_a<=message_glyph(3'd1,(pixel_x-12'd112)>>5);
   row_a<=(line_y-12'd258)>>0;
   col_a<=(pixel_x-12'd112)>>0;ink_a<=24'hffffff;
  end

   if(line_y>=318 && line_y<366 && pixel_x>=48 && pixel_x<592)begin
    if(muted_frame)base_a<=24'hffc048;
    else if(line_y<320 || line_y>=364 || pixel_x<50 || pixel_x>=590)base_a<=24'hffe060;
   end
   if(muted_frame)begin
  if(pixel_x>=144 && pixel_x<496 && line_y>=326 && line_y<358)begin
   glyph_a<=message_glyph(3'd3,(pixel_x-12'd144)>>5);
   row_a<=(line_y-12'd326)>>0;
   col_a<=(pixel_x-12'd144)>>0;ink_a<=24'h382010;
  end

  if(pixel_x>=96 && pixel_x<544 && line_y>=408 && line_y<440)begin
   glyph_a<=message_glyph(3'd5,(pixel_x-12'd96)>>5);
   row_a<=(line_y-12'd408)>>0;
   col_a<=(pixel_x-12'd96)>>0;ink_a<=24'hffffff;
  end

   end else begin
  if(pixel_x>=224 && pixel_x<416 && line_y>=326 && line_y<358)begin
   glyph_a<=message_glyph(3'd2,(pixel_x-12'd224)>>5);
   row_a<=(line_y-12'd326)>>0;
   col_a<=(pixel_x-12'd224)>>0;ink_a<=24'hffffff;
  end

  if(pixel_x>=128 && pixel_x<512 && line_y>=408 && line_y<440)begin
   glyph_a<=message_glyph(3'd4,(pixel_x-12'd128)>>5);
   row_a<=(line_y-12'd408)>>0;
   col_a<=(pixel_x-12'd128)>>0;ink_a<=24'hffffff;
  end

   end
  end
  col_b<=col_a;base_b<=base_a;ink_b<=ink_a;
  rgb_out<=de_b ? (bitmap_b[31-col_b] ? ink_b : base_b) : 24'h000000;
 end
end
endmodule
