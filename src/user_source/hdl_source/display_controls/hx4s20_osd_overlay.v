`timescale 1ns/1ps
// C-style transient HUD. Three cycles RGB/VS/DE; timeout counts actual frames.
module hx4s20_osd_overlay #(
 parameter integer OSD_X=180,OSD_Y=304,POPUP_FRAMES=120,
 parameter VOLUME_ENABLE=0,
 parameter VS_ACTIVE_LOW=1'b1,
 parameter [23:0] BACKGROUND_RGB=24'h0c1426,TEXT_RGB=24'hf0f5ff,SELECTED_RGB=24'h21d9ef
)(input wire clk,rst,input wire signed [8:0] brightness,input wire [8:0] contrast_q8,
 input wire adjust_enable,osd_enable,select_contrast,increase,
 input wire adjust_event,event_contrast,alarm_active,
 input wire volume_event,input wire [4:0] volume_level,
 input wire [23:0] rgb_in,input wire hs_in,vs_in,de_in,
 output reg [23:0] rgb_out,output reg hs_out,vs_out,de_out);
reg vs_d,de_d,pending_event,show_frame;
reg [1:0] pending_kind,kind_frame;
reg [11:0] next_x,line_y;
reg [15:0] remaining;
reg [4:0] fill_steps;
reg [7:0] n0,n1,n2,n3,n4,n5;
wire frame_tick=VS_ACTIVE_LOW ? (vs_d && !vs_in) : (!vs_d && vs_in);
wire [11:0] x=de_d ? next_x : 12'd0;
wire [11:0] rx=x-OSD_X,ry=line_y-OSD_Y;
wire volume_trigger=VOLUME_ENABLE && volume_event;
wire [1:0] selected_kind=pending_event ? pending_kind : kind_frame;
wire [10:0] volume_percent_scaled=volume_level*11'd100+11'd8;
wire [6:0] volume_percent=volume_percent_scaled[10:4];
wire popup_allowed=selected_kind==2 || (osd_enable && adjust_enable);
wire [8:0] magnitude=brightness[8] ? -brightness : brightness;
wire [19:0] contrast_scaled=contrast_q8*20'd1000;
wire [11:0] tenths=contrast_scaled[19:8];
wire signed [9:0] brightness_offset=$signed(brightness)+10'sd64;
wire [8:0] contrast_offset=contrast_q8-9'd128;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  vs_d<=0;de_d<=0;next_x<=0;line_y<=0;remaining<=0;
  pending_event<=0;pending_kind<=0;kind_frame<=0;show_frame<=0;fill_steps<=8;
  n0<=32;n1<=32;n2<=32;n3<=32;n4<=32;n5<=32;
 end else begin
  vs_d<=vs_in;de_d<=de_in;
  if(frame_tick)begin
   next_x<=0;line_y<=0;
   if(pending_event)begin remaining<=POPUP_FRAMES;kind_frame<=pending_kind;end
   else if(remaining!=0)remaining<=remaining-1'b1;
   pending_event<=0;
   show_frame<=popup_allowed && !alarm_active && (pending_event || remaining>1);
   if(selected_kind==2)begin
    fill_steps<=volume_level;
    n0<=32;n1<=volume_percent>=100 ? "1" : " ";
    n2<=volume_percent>=10 ? 48+(volume_percent/10)%10 : " ";
    n3<=48+volume_percent%10;n4<="%";n5<=32;
   end else if(selected_kind==1)begin
    fill_steps<=contrast_offset[8:4];
    n0<=48+tenths/1000;n1<=48+(tenths/100)%10;n2<=48+(tenths/10)%10;
    n3<=".";n4<=48+tenths%10;n5<="%";
   end else begin
    fill_steps<=brightness_offset[7:3];
    n0<=brightness[8]?"-":"+";n1<=48+magnitude/100;
    n2<=48+(magnitude/10)%10;n3<=48+magnitude%10;n4<=32;n5<=32;
   end
  end else begin
   if(de_in)next_x<=x+1'b1;else next_x<=0;
   if(de_d && !de_in)line_y<=line_y+1'b1;
  end
  if(adjust_event && osd_enable && adjust_enable)begin pending_event<=1;pending_kind<={1'b0,event_contrast};end
  if(volume_trigger)begin pending_event<=1;pending_kind<=2;end
  if(alarm_active || ((!osd_enable || !adjust_enable) && !volume_trigger &&
    !(pending_event && pending_kind==2) && kind_frame!=2))begin remaining<=0;pending_event<=0;end
 end
end
function [23:0] label_row;
 input [3:0] glyph;input [4:0] row;
 begin case({glyph,row})
9'd1:label_row=24'h007800;
9'd2:label_row=24'h003800;
9'd3:label_row=24'h3ffff8;
9'd4:label_row=24'h3ffff8;
9'd6:label_row=24'h0fffe0;
9'd7:label_row=24'h0fffe0;
9'd8:label_row=24'h0e00e0;
9'd9:label_row=24'h0fffe0;
9'd10:label_row=24'h0fffe0;
9'd12:label_row=24'h3ffff8;
9'd13:label_row=24'h3ffff8;
9'd14:label_row=24'h380038;
9'd15:label_row=24'h39ff38;
9'd16:label_row=24'h03ff00;
9'd17:label_row=24'h038700;
9'd18:label_row=24'h078718;
9'd19:label_row=24'h7f071c;
9'd20:label_row=24'h3e07f8;
9'd21:label_row=24'h1803f8;
9'd33:label_row=24'h003c00;
9'd34:label_row=24'h001c00;
9'd35:label_row=24'h1ffffc;
9'd36:label_row=24'h1ffffc;
9'd37:label_row=24'h180000;
9'd38:label_row=24'h18e0c0;
9'd39:label_row=24'h1bfff8;
9'd40:label_row=24'h1bfff8;
9'd41:label_row=24'h18e0c0;
9'd42:label_row=24'h18ffc0;
9'd43:label_row=24'h18ffc0;
9'd44:label_row=24'h180000;
9'd45:label_row=24'h180000;
9'd46:label_row=24'h1bfff0;
9'd47:label_row=24'h3bfff0;
9'd48:label_row=24'h38e0e0;
9'd49:label_row=24'h3873c0;
9'd50:label_row=24'h383f80;
9'd51:label_row=24'h707ff8;
9'd52:label_row=24'h37fff8;
9'd53:label_row=24'h138078;
9'd66:label_row=24'h000070;
9'd67:label_row=24'h000070;
9'd68:label_row=24'h3fe070;
9'd69:label_row=24'h3fe070;
9'd70:label_row=24'h3ffffc;
9'd71:label_row=24'h00dffc;
9'd72:label_row=24'h11dffc;
9'd73:label_row=24'h39c070;
9'd74:label_row=24'h3dc870;
9'd75:label_row=24'h1fbc70;
9'd76:label_row=24'h0f9e70;
9'd77:label_row=24'h0f8e70;
9'd78:label_row=24'h078770;
9'd79:label_row=24'h078470;
9'd80:label_row=24'h0fc070;
9'd81:label_row=24'h1fe070;
9'd82:label_row=24'h3ce070;
9'd83:label_row=24'h78cff0;
9'd84:label_row=24'h3007f0;
9'd85:label_row=24'h2007e0;
9'd97:label_row=24'h1c1e00;
9'd98:label_row=24'h1c1e00;
9'd99:label_row=24'h1c1e00;
9'd100:label_row=24'h1c1e10;
9'd101:label_row=24'h1c1e38;
9'd102:label_row=24'h1c1e78;
9'd103:label_row=24'h1fdef0;
9'd104:label_row=24'h1fdfe0;
9'd105:label_row=24'h1fdfc0;
9'd106:label_row=24'h1c1f80;
9'd107:label_row=24'h1c1e00;
9'd108:label_row=24'h1c1e00;
9'd109:label_row=24'h1c1e00;
9'd110:label_row=24'h1c1e10;
9'd111:label_row=24'h1c1e3c;
9'd112:label_row=24'h1cde38;
9'd113:label_row=24'h1fde38;
9'd114:label_row=24'h3fde38;
9'd115:label_row=24'h3f0ff8;
9'd116:label_row=24'h1c0ff8;
9'd117:label_row=24'h1007e0;
9'd128:label_row=24'h003800;
9'd129:label_row=24'h001800;
9'd130:label_row=24'h1ffff8;
9'd131:label_row=24'h100008;
9'd132:label_row=24'h030180;
9'd133:label_row=24'h018180;
9'd134:label_row=24'h01c180;
9'd135:label_row=24'h008300;
9'd136:label_row=24'h3ffffe;
9'd139:label_row=24'h07ffe0;
9'd140:label_row=24'h07ffe0;
9'd141:label_row=24'h060060;
9'd142:label_row=24'h060060;
9'd143:label_row=24'h07ffe0;
9'd144:label_row=24'h060060;
9'd145:label_row=24'h060060;
9'd146:label_row=24'h060060;
9'd147:label_row=24'h07ffe0;
9'd148:label_row=24'h060060;
9'd160:label_row=24'h0fffe0;
9'd161:label_row=24'h07ffe0;
9'd162:label_row=24'h040020;
9'd163:label_row=24'h07ffe0;
9'd164:label_row=24'h040020;
9'd165:label_row=24'h07ffe0;
9'd167:label_row=24'h7ffffe;
9'd168:label_row=24'h7ffffe;
9'd170:label_row=24'h0ffff0;
9'd171:label_row=24'h0c1830;
9'd172:label_row=24'h0ffff0;
9'd173:label_row=24'h0c1830;
9'd174:label_row=24'h0ffff0;
9'd175:label_row=24'h001800;
9'd176:label_row=24'h001800;
9'd177:label_row=24'h0ffff0;
9'd178:label_row=24'h001800;
9'd179:label_row=24'h3ffffc;
9'd180:label_row=24'h3ffffc;
 default:label_row=0;endcase end
endfunction
reg [23:0] base,ink;reg [3:0] glyph;reg [4:0] glyph_x,glyph_y;
reg [7:0] ascii;reg [2:0] acol;reg [3:0] arow;
integer segment;
always @* begin
 base=de_in?rgb_in:24'h000000;ink=TEXT_RGB;
 glyph=15;glyph_x=0;glyph_y=0;ascii=32;acol=0;arow=0;segment=0;
 if(show_frame && de_in && rx<280 && ry<112 &&
    !((rx<3 || rx>=277) && (ry<3 || ry>=109)))begin
  base=BACKGROUND_RGB;
  if(ry==0 || ry==111 || rx==0 || rx==279)base=24'h24718d;
  if(ry==1 && rx>=8 && rx<272)base=SELECTED_RGB;
  // 24x24 brightness sun or half-filled contrast icon.
  if(rx>=20 && rx<44 && ry>=14 && ry<38)begin
   if(kind_frame==2)begin
    // Speaker body, cone and one wave; a cross denotes mute.
    if((rx>=22 && rx<27 && ry>=23 && ry<30) ||
       (rx>=27 && rx<33 && ry>=23-(rx-27) && ry<30+(rx-27)))base=SELECTED_RGB;
    if(fill_steps!=0)begin
     if((rx==36 && ry>=23 && ry<30) || (rx==39 && ry>=20 && ry<33))base=SELECTED_RGB;
    end else if(rx>=35 && rx<42 && (ry==rx-12 || ry==64-rx))base=24'hff9f7a;
   end else if(kind_frame==1)begin
    if(rx>=26 && rx<38 && ry>=20 && ry<32 && (rx<32 || rx==37 || ry==20 || ry==31))base=SELECTED_RGB;
   end else if((rx>=27 && rx<37 && ry>=21 && ry<31 && !( (rx==27 || rx==36) && (ry==21 || ry==30))) ||
      (rx>=30 && rx<34 && (ry<18 || ry>=34)) ||
      (ry>=24 && ry<28 && (rx<24 || rx>=40)) ||
      ((rx>=23 && rx<26 || rx>=38 && rx<41) && (ry>=17 && ry<20 || ry>=32 && ry<35)))base=SELECTED_RGB;
  end
  if(ry>=12 && ry<36 && rx>=52 && rx<(kind_frame==1?124:100))begin
   glyph_y=ry-12;
   if(rx<76)begin glyph=kind_frame==2?4:kind_frame==1?2:0;glyph_x=rx-52;end
   else if(rx<100)begin glyph=kind_frame==2?5:kind_frame==1?3:1;glyph_x=rx-76;end
   else begin glyph=1;glyph_x=rx-100;end
  end
  if(ry>=12 && ry<44 && rx>=176 && rx<272)begin
   arow=(ry-12)>>1;acol=(rx-176)>>1;
   case((rx-176)>>4)0:ascii=n0;1:ascii=n1;2:ascii=n2;3:ascii=n3;4:ascii=n4;5:ascii=n5;endcase
  end
  // Sixteen discrete segments; the center marker denotes 0 / 100%.
  if(ry>=56 && ry<76 && rx>=28 && rx<252)begin
   segment=(rx-28)/14;
   if(((rx-28)%14)<12)begin
    base=24'h26344b;
    if(segment<fill_steps)base=kind_frame==1?24'ha879ff:SELECTED_RGB;
   end
  end
  if(kind_frame!=2 && (ry>=50 && ry<54 || ry>=78 && ry<82) && rx>=139 && rx<141)base=24'hcbd6ee;
  if(ry>=88 && ry<104 && rx>=28 && rx<244)begin
   arow=ry-88;acol=(rx-28)%8;
   if(kind_frame==2)begin
    case((rx-28)>>3)
     0:ascii="U";1:ascii="P";2:ascii=":";3:ascii="+";
     6:ascii="D";7:ascii="O";8:ascii="W";9:ascii="N";10:ascii=":";11:ascii="-";
    endcase
   end else begin
   case((rx-28)>>3)
    0:ascii="K";1:ascii="E";2:ascii="Y";3:ascii="3";4:ascii=":";5:ascii="S";6:ascii="T";7:ascii="E";8:ascii="P";
    11:ascii="H";12:ascii="O";13:ascii="L";14:ascii="D";15:ascii=":";16:ascii="R";17:ascii="E";18:ascii="S";19:ascii="E";20:ascii="T";
   endcase
   end
   ink=24'h8da6c5;
  end
 end
end
reg [23:0] base1,ink1,base2,ink2,bits1;
reg [4:0] col1;reg [7:0] char1;reg [2:0] ac1;reg [3:0] ar1;
reg hs1,vs1,de1,hs2,vs2,de2,text2;
wire ascii_pixel;
hx4s20_osd_font u_font(.character(char1),.column(ac1),.row(ar1),.pixel(ascii_pixel));
always @(posedge clk or posedge rst)begin
 if(rst)begin
  base1<=0;ink1<=0;base2<=0;ink2<=0;bits1<=0;col1<=0;char1<=32;ac1<=0;ar1<=0;
  hs1<=0;vs1<=0;de1<=0;hs2<=0;vs2<=0;de2<=0;text2<=0;
  rgb_out<=0;hs_out<=0;vs_out<=0;de_out<=0;
 end else begin
  base1<=base;ink1<=ink;bits1<=label_row(glyph,glyph_y);col1<=glyph_x;
  char1<=ascii;ac1<=acol;ar1<=arow;hs1<=hs_in;vs1<=vs_in;de1<=de_in;
  base2<=base1;ink2<=ink1;text2<=bits1[23-col1] | ascii_pixel;hs2<=hs1;vs2<=vs1;de2<=de1;
  rgb_out<=de2?(text2?ink2:base2):24'h0;hs_out<=hs2;vs_out<=vs2;de_out<=de2;
 end
end
endmodule
