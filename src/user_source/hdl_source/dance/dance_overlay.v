`timescale 1ns/1ps
// Two 16KiB caches (four byte lanes), explicit 32K BRAM inference.
// Three pixel clocks of matched RGB/VS/DE latency. Index 0 is transparent.
module dance_overlay #(parameter CLK_HZ=25000000,parameter FPS=12,parameter X=496,parameter Y=8,parameter STATUS_ENABLE=1)(
 input clk,input rst,input alarm,input loaded,input failed,input [2:0] diagnostic,
 output reg frame_toggle,output reg [7:0] frame_number,output reg frame_bank,input frame_ack,
 input mem_clk,input cache_we,input [12:0] cache_addr,input [31:0] cache_data,
 input sd_clk,input pal_we,input [7:0] pal_addr,input [15:0] pal_data,
 input [23:0] rgb_in,input vs_in,input de_in,
 output reg [23:0] rgb_out,output reg vs_out,output reg de_out,
 output reg [31:0] underruns,output reg [7:0] displayed_frame
);
reg [7:0] lane0[0:8191] /* synthesis ram_style=bram_32k */;
reg [7:0] lane1[0:8191] /* synthesis ram_style=bram_32k */;
reg [7:0] lane2[0:8191] /* synthesis ram_style=bram_32k */;
reg [7:0] lane3[0:8191] /* synthesis ram_style=bram_32k */;
function [15:0] palette_color;input [7:0] n;begin case(n)
8'd0:palette_color=16'h0000;
8'd1:palette_color=16'hffff;
8'd2:palette_color=16'hffff;
8'd3:palette_color=16'hffff;
8'd4:palette_color=16'hffff;
8'd5:palette_color=16'hffff;
8'd6:palette_color=16'hffff;
8'd7:palette_color=16'hffff;
8'd8:palette_color=16'hffff;
8'd9:palette_color=16'hffff;
8'd10:palette_color=16'hffff;
8'd11:palette_color=16'hffff;
8'd12:palette_color=16'hffff;
8'd13:palette_color=16'hffff;
8'd14:palette_color=16'hffff;
8'd15:palette_color=16'hffff;
8'd16:palette_color=16'hffff;
8'd17:palette_color=16'hffff;
8'd18:palette_color=16'hffff;
8'd19:palette_color=16'hffff;
8'd20:palette_color=16'hffff;
8'd21:palette_color=16'hffff;
8'd22:palette_color=16'hffff;
8'd23:palette_color=16'hffff;
8'd24:palette_color=16'hffff;
8'd25:palette_color=16'hffff;
8'd26:palette_color=16'hffff;
8'd27:palette_color=16'hffff;
8'd28:palette_color=16'hffff;
8'd29:palette_color=16'hffff;
8'd30:palette_color=16'hf7ff;
8'd31:palette_color=16'hf7ff;
8'd32:palette_color=16'hffff;
8'd33:palette_color=16'hffff;
8'd34:palette_color=16'hffff;
8'd35:palette_color=16'hffff;
8'd36:palette_color=16'hffff;
8'd37:palette_color=16'hffff;
8'd38:palette_color=16'hffff;
8'd39:palette_color=16'hffff;
8'd40:palette_color=16'hffff;
8'd41:palette_color=16'hffff;
8'd42:palette_color=16'hffff;
8'd43:palette_color=16'hffff;
8'd44:palette_color=16'hffff;
8'd45:palette_color=16'hffff;
8'd46:palette_color=16'hffff;
8'd47:palette_color=16'hffff;
8'd48:palette_color=16'hffff;
8'd49:palette_color=16'hffff;
8'd50:palette_color=16'hffff;
8'd51:palette_color=16'hffff;
8'd52:palette_color=16'hffff;
8'd53:palette_color=16'hffff;
8'd54:palette_color=16'hffff;
8'd55:palette_color=16'hffff;
8'd56:palette_color=16'hffff;
8'd57:palette_color=16'hffff;
8'd58:palette_color=16'hf7ff;
8'd59:palette_color=16'hffdf;
8'd60:palette_color=16'hffdf;
8'd61:palette_color=16'hffdf;
8'd62:palette_color=16'hffdf;
8'd63:palette_color=16'hffdf;
8'd64:palette_color=16'hffdf;
8'd65:palette_color=16'hf7df;
8'd66:palette_color=16'hf7df;
8'd67:palette_color=16'hf7df;
8'd68:palette_color=16'hf7df;
8'd69:palette_color=16'hffdf;
8'd70:palette_color=16'hffdf;
8'd71:palette_color=16'hffbe;
8'd72:palette_color=16'hf7bf;
8'd73:palette_color=16'hf7df;
8'd74:palette_color=16'hf7bf;
8'd75:palette_color=16'hf7be;
8'd76:palette_color=16'hf7bf;
8'd77:palette_color=16'hf79e;
8'd78:palette_color=16'hefdf;
8'd79:palette_color=16'hefbf;
8'd80:palette_color=16'hefbf;
8'd81:palette_color=16'hef9e;
8'd82:palette_color=16'hefdf;
8'd83:palette_color=16'he7bf;
8'd84:palette_color=16'hef9f;
8'd85:palette_color=16'he79f;
8'd86:palette_color=16'hef9e;
8'd87:palette_color=16'hef9e;
8'd88:palette_color=16'hef7d;
8'd89:palette_color=16'hef7e;
8'd90:palette_color=16'he77e;
8'd91:palette_color=16'he77e;
8'd92:palette_color=16'hdf7e;
8'd93:palette_color=16'hdf7e;
8'd94:palette_color=16'hef5d;
8'd95:palette_color=16'he73d;
8'd96:palette_color=16'he75e;
8'd97:palette_color=16'he73d;
8'd98:palette_color=16'hdf5e;
8'd99:palette_color=16'hdf5d;
8'd100:palette_color=16'hdf3e;
8'd101:palette_color=16'hdf3d;
8'd102:palette_color=16'he71c;
8'd103:palette_color=16'he71c;
8'd104:palette_color=16'hdf1d;
8'd105:palette_color=16'hdf1d;
8'd106:palette_color=16'hdefc;
8'd107:palette_color=16'hdefb;
8'd108:palette_color=16'hdedb;
8'd109:palette_color=16'hd79f;
8'd110:palette_color=16'hd75e;
8'd111:palette_color=16'hd73e;
8'd112:palette_color=16'hd73e;
8'd113:palette_color=16'hd71d;
8'd114:palette_color=16'hd71d;
8'd115:palette_color=16'hcf1e;
8'd116:palette_color=16'hd6fd;
8'd117:palette_color=16'hd6fd;
8'd118:palette_color=16'hcedd;
8'd119:palette_color=16'hd6dc;
8'd120:palette_color=16'hd6bb;
8'd121:palette_color=16'hd6ba;
8'd122:palette_color=16'hcebc;
8'd123:palette_color=16'hcebc;
8'd124:palette_color=16'hc77e;
8'd125:palette_color=16'hc73e;
8'd126:palette_color=16'hcefd;
8'd127:palette_color=16'hbefd;
8'd128:palette_color=16'hcedc;
8'd129:palette_color=16'hcebc;
8'd130:palette_color=16'hc6bc;
8'd131:palette_color=16'hbebd;
8'd132:palette_color=16'hb73e;
8'd133:palette_color=16'haf1e;
8'd134:palette_color=16'hb6dd;
8'd135:palette_color=16'haedd;
8'd136:palette_color=16'ha6fe;
8'd137:palette_color=16'ha6bd;
8'd138:palette_color=16'h96dd;
8'd139:palette_color=16'hd69a;
8'd140:palette_color=16'hce9b;
8'd141:palette_color=16'hc69c;
8'd142:palette_color=16'hc69b;
8'd143:palette_color=16'hce7a;
8'd144:palette_color=16'hce59;
8'd145:palette_color=16'hc67b;
8'd146:palette_color=16'hc65b;
8'd147:palette_color=16'hbe9c;
8'd148:palette_color=16'hbe7b;
8'd149:palette_color=16'hbe5b;
8'd150:palette_color=16'hbe5a;
8'd151:palette_color=16'hb69c;
8'd152:palette_color=16'hb65c;
8'd153:palette_color=16'hb65b;
8'd154:palette_color=16'hc618;
8'd155:palette_color=16'hbe3a;
8'd156:palette_color=16'hb63b;
8'd157:palette_color=16'hb61a;
8'd158:palette_color=16'hae3b;
8'd159:palette_color=16'hae1b;
8'd160:palette_color=16'hae1a;
8'd161:palette_color=16'hadfa;
8'd162:palette_color=16'hb5f9;
8'd163:palette_color=16'hadfa;
8'd164:palette_color=16'hadfa;
8'd165:palette_color=16'hadd9;
8'd166:palette_color=16'hadd9;
8'd167:palette_color=16'had98;
8'd168:palette_color=16'h9e9c;
8'd169:palette_color=16'h9e3b;
8'd170:palette_color=16'ha5da;
8'd171:palette_color=16'h9dfa;
8'd172:palette_color=16'ha5ba;
8'd173:palette_color=16'ha5b9;
8'd174:palette_color=16'h9dba;
8'd175:palette_color=16'h9db9;
8'd176:palette_color=16'ha599;
8'd177:palette_color=16'ha598;
8'd178:palette_color=16'h9d9a;
8'd179:palette_color=16'h9d78;
8'd180:palette_color=16'h9d59;
8'd181:palette_color=16'h9d58;
8'd182:palette_color=16'h8e7c;
8'd183:palette_color=16'h8dfb;
8'd184:palette_color=16'h959a;
8'd185:palette_color=16'h9579;
8'd186:palette_color=16'h9559;
8'd187:palette_color=16'h8d59;
8'd188:palette_color=16'h9558;
8'd189:palette_color=16'h8d38;
8'd190:palette_color=16'h765d;
8'd191:palette_color=16'h75dc;
8'd192:palette_color=16'h7d7a;
8'd193:palette_color=16'h657a;
8'd194:palette_color=16'h4e1e;
8'd195:palette_color=16'h3e1e;
8'd196:palette_color=16'h457c;
8'd197:palette_color=16'h9517;
8'd198:palette_color=16'h8d18;
8'd199:palette_color=16'h8d18;
8'd200:palette_color=16'h8d17;
8'd201:palette_color=16'h8519;
8'd202:palette_color=16'h84f9;
8'd203:palette_color=16'h8517;
8'd204:palette_color=16'h84f7;
8'd205:palette_color=16'h8cd7;
8'd206:palette_color=16'h84d7;
8'd207:palette_color=16'h7cd8;
8'd208:palette_color=16'h7cd7;
8'd209:palette_color=16'h84b6;
8'd210:palette_color=16'h84b6;
8'd211:palette_color=16'h7cb7;
8'd212:palette_color=16'h7c76;
8'd213:palette_color=16'h74f8;
8'd214:palette_color=16'h74b7;
8'd215:palette_color=16'h7497;
8'd216:palette_color=16'h7496;
8'd217:palette_color=16'h7477;
8'd218:palette_color=16'h7475;
8'd219:palette_color=16'h6c76;
8'd220:palette_color=16'h5cfa;
8'd221:palette_color=16'h4cfa;
8'd222:palette_color=16'h6498;
8'd223:palette_color=16'h4c98;
8'd224:palette_color=16'h3cda;
8'd225:palette_color=16'h3c79;
8'd226:palette_color=16'h1cba;
8'd227:palette_color=16'h7456;
8'd228:palette_color=16'h7435;
8'd229:palette_color=16'h6437;
8'd230:palette_color=16'h6435;
8'd231:palette_color=16'h6c16;
8'd232:palette_color=16'h6bf4;
8'd233:palette_color=16'h63f5;
8'd234:palette_color=16'h5c16;
8'd235:palette_color=16'h4c17;
8'd236:palette_color=16'h5bd5;
8'd237:palette_color=16'h4bd6;
8'd238:palette_color=16'h3c37;
8'd239:palette_color=16'h3bf7;
8'd240:palette_color=16'h2c18;
8'd241:palette_color=16'h1bf8;
8'd242:palette_color=16'h5bb4;
8'd243:palette_color=16'h5393;
8'd244:palette_color=16'h4b94;
8'd245:palette_color=16'h4b73;
8'd246:palette_color=16'h4395;
8'd247:palette_color=16'h4354;
8'd248:palette_color=16'h2b75;
8'd249:palette_color=16'h1396;
8'd250:palette_color=16'h4313;
8'd251:palette_color=16'h3b13;
8'd252:palette_color=16'h2af3;
8'd253:palette_color=16'h12f4;
8'd254:palette_color=16'h1a72;
8'd255:palette_color=16'h0000;
default:palette_color=0;endcase end endfunction
always @(posedge mem_clk)if(cache_we)begin
 lane0[cache_addr]<=cache_data[7:0];lane1[cache_addr]<=cache_data[15:8];
 lane2[cache_addr]<=cache_data[23:16];lane3[cache_addr]<=cache_data[31:24];end
// Palette is compiled from the verified same TF package, not rewritten at runtime.
(* async_reg="true" *)reg [2:0] ack_s,loaded_s,failed_s;
reg vs_d,de_d,alarm_d;reg [9:0] next_x;reg [8:0] y;
reg [1:0] state;reg active_bank,show,first,due,restart;
reg [25:0] phase;
wire frame_tick=vs_d&&!vs_in;
wire [9:0] x=de_d ? next_x : 10'd0;
wire inside=de_in&&x>=X&&x<X+128&&y>=Y&&y<Y+96;
wire [9:0] local_x=x-X;wire [8:0] local_y=y-Y;
wire [12:0] pixel_word={active_bank,local_y[6:0],local_x[6:2]};
always @(posedge clk or posedge rst)
 if(rst)begin ack_s<=0;loaded_s<=0;failed_s<=0;vs_d<=0;de_d<=0;alarm_d<=0;next_x<=0;y<=0;
 state<=0;active_bank<=1;show<=0;first<=1;due<=0;restart<=0;phase<=0;
 frame_toggle<=0;frame_number<=0;frame_bank<=0;underruns<=0;displayed_frame<=0;end
 else begin
  ack_s<={ack_s[1:0],frame_ack};loaded_s<={loaded_s[1:0],loaded};failed_s<={failed_s[1:0],failed};
  vs_d<=vs_in;de_d<=de_in;alarm_d<=alarm;
  if(vs_d!=vs_in)begin y<=0;next_x<=0;end
  else begin if(de_in)next_x<=x+1'b1;else next_x<=0;if(de_d&&!de_in)y<=y+1'b1;end
  if(alarm_d&&!alarm)begin restart<=1;show<=0;end
  if(!alarm&&show)begin
   if(phase>=CLK_HZ-FPS)begin phase<=phase+FPS-CLK_HZ;due<=1;end
   else phase<=phase+FPS;
  end
  if(failed_s[2])show<=0;
  if(restart&&state!=1)begin state<=0;restart<=0;first<=1;phase<=0;due<=0;end
  else case(state)
   0:if(loaded_s[2]&&!failed_s[2]&&!alarm)begin
    frame_number<=0;frame_bank<=!active_bank;frame_toggle<=!frame_toggle;state<=1;end
   1:begin
    if(ack_s[2]==frame_toggle)state<=2;
    if(frame_tick&&due&&!alarm&&!restart)underruns<=underruns+1'b1;
   end
   2:if(frame_tick&&!alarm&&!failed_s[2]&&(first||due))begin
    active_bank<=frame_bank;displayed_frame<=frame_number;show<=1;due<=0;
    if(first)phase<=0;first<=0;
    frame_number<=frame_number==35 ? 0 : frame_number+1'b1;
    frame_bank<=!frame_bank;frame_toggle<=!frame_toggle;state<=1;
   end
   default:state<=0;
  endcase
 end
reg [7:0] q0,q1,q2,q3;reg [1:0] sel1;
reg win1,opaque2,vs1,vs2,de1,de2;reg status1,status2;reg [23:0] stat_rgb1,stat_rgb2;
(* async_reg="true" *)reg [2:0] diag_m,diag_s;reg [23:0] bg1,bg2;reg [15:0] pal_q;
wire [7:0] index=sel1==0?q0:sel1==1?q1:sel1==2?q2:q3;
always @(posedge clk)begin
 q0<=lane0[pixel_word];q1<=lane1[pixel_word];q2<=lane2[pixel_word];q3<=lane3[pixel_word];
 pal_q<=palette_color(index);end
always @(posedge clk or posedge rst)
 if(rst)begin diag_m<=0;diag_s<=0;status1<=0;status2<=0;stat_rgb1<=0;stat_rgb2<=0;sel1<=0;win1<=0;opaque2<=0;vs1<=0;vs2<=0;de1<=0;de2<=0;bg1<=0;bg2<=0;rgb_out<=0;vs_out<=0;de_out<=0;end
 else begin
  diag_m<=diagnostic;diag_s<=diag_m;
  status1<=STATUS_ENABLE&&de_in&&x>=X&&x<X+128&&y>=Y+96&&y<Y+100&&!alarm;
  status2<=status1;stat_rgb2<=stat_rgb1;
  stat_rgb1<=failed_s[2] ? (diag_s==5 ? 24'hff00ff : 24'hff3030) :
    !loaded_s[2] ? 24'hffff00 : !show ? 24'h00aaff : 24'h00ff60;
  sel1<=local_x[1:0];win1<=inside&&show&&!alarm&&!failed_s[2];
  bg1<=rgb_in;vs1<=vs_in;de1<=de_in;
  opaque2<=win1&&index!=0;bg2<=bg1;vs2<=vs1;de2<=de1;
  rgb_out<=status2 ? stat_rgb2 : opaque2 ? {pal_q[15:11],pal_q[15:13],pal_q[10:5],pal_q[10:9],pal_q[4:0],pal_q[4:2]} : bg2;
  vs_out<=vs2;de_out<=de2;
 end
endmodule
