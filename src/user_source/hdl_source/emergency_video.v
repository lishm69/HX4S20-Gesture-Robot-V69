`timescale 1ns/1ps
// Last stage before RGB-to-AXIS. Frame-atomic alarm/setup selection;
// exactly ONE clock of delay for RGB, VS and DE, including normal bypass.
// Alarm graphics are generated without a TF card or framebuffer read.
module emergency_video(
    input wire clk,input wire rst,input wire alarm_active,input wire [1:0] learn_state,
    input wire [23:0] rgb_in,input wire vs_in,input wire de_in,
    output reg [23:0] rgb_out,output reg vs_out,output reg de_out
);
reg vs_previous,de_previous,alarm_frame;
reg [1:0] mode_frame;
reg [11:0] next_x,line_y;
reg [7:0] ready_frames;
reg [7:0] animation;
wire frame_tick=vs_previous && !vs_in;
wire [11:0] pixel_x=de_previous ? next_x : 12'd0;
always @(posedge clk or posedge rst)begin
    if(rst)begin
        vs_previous<=1;de_previous<=0;alarm_frame<=0;mode_frame<=0;
        next_x<=0;line_y<=0;ready_frames<=0;animation<=0;
    end else begin
        vs_previous<=vs_in;de_previous<=de_in;
        if(frame_tick)begin
            next_x<=0;line_y<=0;alarm_frame<=alarm_active;mode_frame<=learn_state;
            animation<=animation+1'b1;
            if(learn_state!=2)ready_frames<=0;
            else if(ready_frames<180)ready_frames<=ready_frames+1'b1;
        end else begin
            if(de_in)next_x<=pixel_x+1'b1;else next_x<=0;
            if(de_previous && !de_in)line_y<=line_y+1'b1;
        end
    end
end
function [7:0] message_char;
    input [2:0] line_number;
    input [5:0] index;
    begin
        message_char=8'h20;
        case(line_number)
            3'd0:case(index)
                    6'd0:message_char="I";
                    6'd1:message_char="R";
                    6'd2:message_char=" ";
                    6'd3:message_char="S";
                    6'd4:message_char="E";
                    6'd5:message_char="T";
                    6'd6:message_char="U";
                    6'd7:message_char="P";
                    6'd8:message_char=":";
                    6'd9:message_char=" ";
                    6'd10:message_char="P";
                    6'd11:message_char="R";
                    6'd12:message_char="E";
                    6'd13:message_char="S";
                    6'd14:message_char="S";
                    6'd15:message_char=" ";
                    6'd16:message_char="1";
                    default:message_char=8'h20;
                endcase
            3'd1:case(index)
                    6'd0:message_char="R";
                    6'd1:message_char="E";
                    6'd2:message_char="L";
                    6'd3:message_char="E";
                    6'd4:message_char="A";
                    6'd5:message_char="S";
                    6'd6:message_char="E";
                    6'd7:message_char=" ";
                    6'd8:message_char="A";
                    6'd9:message_char="N";
                    6'd10:message_char="D";
                    6'd11:message_char=" ";
                    6'd12:message_char="W";
                    6'd13:message_char="A";
                    6'd14:message_char="I";
                    6'd15:message_char="T";
                    6'd16:message_char=" ";
                    6'd17:message_char="1";
                    6'd18:message_char=" ";
                    6'd19:message_char="S";
                    6'd20:message_char="E";
                    6'd21:message_char="C";
                    6'd22:message_char="O";
                    6'd23:message_char="N";
                    6'd24:message_char="D";
                    default:message_char=8'h20;
                endcase
            3'd2:case(index)
                    6'd0:message_char="I";
                    6'd1:message_char="R";
                    6'd2:message_char=" ";
                    6'd3:message_char="S";
                    6'd4:message_char="E";
                    6'd5:message_char="T";
                    6'd6:message_char="U";
                    6'd7:message_char="P";
                    6'd8:message_char=":";
                    6'd9:message_char=" ";
                    6'd10:message_char="P";
                    6'd11:message_char="R";
                    6'd12:message_char="E";
                    6'd13:message_char="S";
                    6'd14:message_char="S";
                    6'd15:message_char=" ";
                    6'd16:message_char="2";
                    default:message_char=8'h20;
                endcase
            3'd3:case(index)
                    6'd0:message_char="U";
                    6'd1:message_char="S";
                    6'd2:message_char="E";
                    6'd3:message_char=" ";
                    6'd4:message_char="A";
                    6'd5:message_char=" ";
                    6'd6:message_char="D";
                    6'd7:message_char="I";
                    6'd8:message_char="F";
                    6'd9:message_char="F";
                    6'd10:message_char="E";
                    6'd11:message_char="R";
                    6'd12:message_char="E";
                    6'd13:message_char="N";
                    6'd14:message_char="T";
                    6'd15:message_char=" ";
                    6'd16:message_char="K";
                    6'd17:message_char="E";
                    6'd18:message_char="Y";
                    default:message_char=8'h20;
                endcase
            3'd4:case(index)
                    6'd0:message_char="I";
                    6'd1:message_char="R";
                    6'd2:message_char=" ";
                    6'd3:message_char="R";
                    6'd4:message_char="E";
                    6'd5:message_char="A";
                    6'd6:message_char="D";
                    6'd7:message_char="Y";
                    6'd8:message_char=":";
                    6'd9:message_char=" ";
                    6'd10:message_char="1";
                    6'd11:message_char=" ";
                    6'd12:message_char="A";
                    6'd13:message_char="L";
                    6'd14:message_char="A";
                    6'd15:message_char="R";
                    6'd16:message_char="M";
                    6'd17:message_char=" ";
                    6'd18:message_char=" ";
                    6'd19:message_char="2";
                    6'd20:message_char=" ";
                    6'd21:message_char="C";
                    6'd22:message_char="L";
                    6'd23:message_char="E";
                    6'd24:message_char="A";
                    6'd25:message_char="R";
                    default:message_char=8'h20;
                endcase
            3'd5:case(index)
                    6'd0:message_char="E";
                    6'd1:message_char="M";
                    6'd2:message_char="E";
                    6'd3:message_char="R";
                    6'd4:message_char="G";
                    6'd5:message_char="E";
                    6'd6:message_char="N";
                    6'd7:message_char="C";
                    6'd8:message_char="Y";
                    default:message_char=8'h20;
                endcase
            3'd6:case(index)
                    6'd0:message_char="P";
                    6'd1:message_char="L";
                    6'd2:message_char="E";
                    6'd3:message_char="A";
                    6'd4:message_char="S";
                    6'd5:message_char="E";
                    6'd6:message_char=" ";
                    6'd7:message_char="E";
                    6'd8:message_char="V";
                    6'd9:message_char="A";
                    6'd10:message_char="C";
                    6'd11:message_char="U";
                    6'd12:message_char="A";
                    6'd13:message_char="T";
                    6'd14:message_char="E";
                    default:message_char=8'h20;
                endcase
            3'd7:case(index)
                    6'd0:message_char="U";
                    6'd1:message_char="S";
                    6'd2:message_char="E";
                    6'd3:message_char=" ";
                    6'd4:message_char="C";
                    6'd5:message_char="L";
                    6'd6:message_char="E";
                    6'd7:message_char="A";
                    6'd8:message_char="R";
                    6'd9:message_char=" ";
                    6'd10:message_char="K";
                    6'd11:message_char="E";
                    6'd12:message_char="Y";
                    6'd13:message_char=" ";
                    6'd14:message_char="T";
                    6'd15:message_char="O";
                    6'd16:message_char=" ";
                    6'd17:message_char="R";
                    6'd18:message_char="E";
                    6'd19:message_char="T";
                    6'd20:message_char="U";
                    6'd21:message_char="R";
                    6'd22:message_char="N";
                    default:message_char=8'h20;
                endcase
            default:message_char=8'h20;
        endcase
    end
endfunction
function [31:0] han_row;
    input [6:0] index;
    begin
        case(index)
            7'd0:han_row=32'b00000000000000000000000000000000;
            7'd1:han_row=32'b00000000000000000000000000000000;
            7'd2:han_row=32'b00000000000000000000000000000000;
            7'd3:han_row=32'b00000000011000000000000000000000;
            7'd4:han_row=32'b00001100011001111111111111100000;
            7'd5:han_row=32'b00001100011001111111111111100000;
            7'd6:han_row=32'b00001100011000011000000011100000;
            7'd7:han_row=32'b00001100011000001100000111000000;
            7'd8:han_row=32'b00001100011000001110011100000000;
            7'd9:han_row=32'b00001100011000000111111000000000;
            7'd10:han_row=32'b00001100011000001111111100000000;
            7'd11:han_row=32'b00001100011001111110011111111000;
            7'd12:han_row=32'b00001100011001110000000011110000;
            7'd13:han_row=32'b00000000000111110000000000000000;
            7'd14:han_row=32'b00000000011110000000011000000000;
            7'd15:han_row=32'b00000001111000000001111100000000;
            7'd16:han_row=32'b00000011111111111111100000000000;
            7'd17:han_row=32'b00000001111111111110000000000000;
            7'd18:han_row=32'b00000000000000110000010000000000;
            7'd19:han_row=32'b00000000000111000000001100000000;
            7'd20:han_row=32'b00000000111000011111111110000000;
            7'd21:han_row=32'b00000111111111111111111111100000;
            7'd22:han_row=32'b00000011111111101100000001110000;
            7'd23:han_row=32'b00000000001000001100010000100000;
            7'd24:han_row=32'b00000000111100001100111100000000;
            7'd25:han_row=32'b00000011111000001100011111000000;
            7'd26:han_row=32'b00001111100000001100000111100000;
            7'd27:han_row=32'b00011110000111111100000011110000;
            7'd28:han_row=32'b00001000000111111000000000100000;
            7'd29:han_row=32'b00000000000000000000000000000000;
            7'd30:han_row=32'b00000000000000000000000000000000;
            7'd31:han_row=32'b00000000000000000000000000000000;
            7'd32:han_row=32'b00000000000000000000000000000000;
            7'd33:han_row=32'b00000000000000000000000000000000;
            7'd34:han_row=32'b00000000000000000000000000000000;
            7'd35:han_row=32'b00000000000000000000000000000000;
            7'd36:han_row=32'b00000000000011000000000000000000;
            7'd37:han_row=32'b00000000000110000000000000000000;
            7'd38:han_row=32'b00000000001111111111100000000000;
            7'd39:han_row=32'b00000000011111111111100000000000;
            7'd40:han_row=32'b00000000110000000011000000000000;
            7'd41:han_row=32'b00000011100000000110000000000000;
            7'd42:han_row=32'b00000111111111111111111111100000;
            7'd43:han_row=32'b00011101111111111111111111100000;
            7'd44:han_row=32'b00001000000000000000000001100000;
            7'd45:han_row=32'b00000000000000000000000001100000;
            7'd46:han_row=32'b00000001111111111111111111100000;
            7'd47:han_row=32'b00000001111111111111111111100000;
            7'd48:han_row=32'b00000000000000000000000001100000;
            7'd49:han_row=32'b00000000000000000000000001100000;
            7'd50:han_row=32'b00000011111111111111111111100000;
            7'd51:han_row=32'b00000011111111111111111111100000;
            7'd52:han_row=32'b00000000000000110000000001100000;
            7'd53:han_row=32'b00000011001100111000000000100000;
            7'd54:han_row=32'b00000111001100011100001001110000;
            7'd55:han_row=32'b00000110001100001000001100111000;
            7'd56:han_row=32'b00001110001100000000001100011000;
            7'd57:han_row=32'b00011100001100000000011000011100;
            7'd58:han_row=32'b00001000001111111111111000001000;
            7'd59:han_row=32'b00000000000111111111110000000000;
            7'd60:han_row=32'b00000000000000000000000000000000;
            7'd61:han_row=32'b00000000000000000000000000000000;
            7'd62:han_row=32'b00000000000000000000000000000000;
            7'd63:han_row=32'b00000000000000000000000000000000;
            7'd64:han_row=32'b00000000000000000000000000000000;
            7'd65:han_row=32'b00000000000000000000000000000000;
            7'd66:han_row=32'b00000000000000000000000000000000;
            7'd67:han_row=32'b00000000000000000000010000000000;
            7'd68:han_row=32'b00000000000000000000111000000000;
            7'd69:han_row=32'b00011111111110000000011000000000;
            7'd70:han_row=32'b00011111111111111111111111111000;
            7'd71:han_row=32'b00000000001111111111111111111000;
            7'd72:han_row=32'b00000000011100000001100000000000;
            7'd73:han_row=32'b00000000111000000011000010000000;
            7'd74:han_row=32'b00000000110000001110000111000000;
            7'd75:han_row=32'b00001100110000011100000011100000;
            7'd76:han_row=32'b00001100110000110000011111100000;
            7'd77:han_row=32'b00001100110001111111111111110000;
            7'd78:han_row=32'b00001100110001111110000000111000;
            7'd79:han_row=32'b00001100111110000000000000010000;
            7'd80:han_row=32'b00001100111110110001100011000000;
            7'd81:han_row=32'b00001100110000110001100011000000;
            7'd82:han_row=32'b00001100110000110001100011000000;
            7'd83:han_row=32'b00001100110000110001100011000000;
            7'd84:han_row=32'b00001100110000110001100011000000;
            7'd85:han_row=32'b00001100110000110001100011000000;
            7'd86:han_row=32'b00001100110110110001100011001000;
            7'd87:han_row=32'b00001100111111100001100011001100;
            7'd88:han_row=32'b00001111111001100001100011001100;
            7'd89:han_row=32'b00011111000011100001100011001100;
            7'd90:han_row=32'b00011000000111000001100011001100;
            7'd91:han_row=32'b00000000001110000001100011111000;
            7'd92:han_row=32'b00000000000100000001100001111000;
            7'd93:han_row=32'b00000000000000000000000000000000;
            7'd94:han_row=32'b00000000000000000000000000000000;
            7'd95:han_row=32'b00000000000000000000000000000000;
            7'd96:han_row=32'b00000000000000000000000000000000;
            7'd97:han_row=32'b00000000000000000000000000000000;
            7'd98:han_row=32'b00000000000000000000000000000000;
            7'd99:han_row=32'b00000011000011000000011000000000;
            7'd100:han_row=32'b00000011000011000000011000000000;
            7'd101:han_row=32'b00000011000011000000110000000000;
            7'd102:han_row=32'b00011111111111111000110000000000;
            7'd103:han_row=32'b00011111111111111001110000000000;
            7'd104:han_row=32'b00000011000011000001111111111100;
            7'd105:han_row=32'b00000011000011000011111111111100;
            7'd106:han_row=32'b00000011000011000011100000110000;
            7'd107:han_row=32'b00111111111111111111100000110000;
            7'd108:han_row=32'b00111111111111111111100000110000;
            7'd109:han_row=32'b00000000000000000101100000110000;
            7'd110:han_row=32'b00001111111111111101100001100000;
            7'd111:han_row=32'b00001111111111110000110001100000;
            7'd112:han_row=32'b00001100000000110000110001100000;
            7'd113:han_row=32'b00001100000000110000110001100000;
            7'd114:han_row=32'b00001111111111110000010011100000;
            7'd115:han_row=32'b00001111111111110000011011000000;
            7'd116:han_row=32'b00001100000000110000011111000000;
            7'd117:han_row=32'b00001100000000110000001110000000;
            7'd118:han_row=32'b00001111111111110000011110000000;
            7'd119:han_row=32'b00001111111111110000011110000000;
            7'd120:han_row=32'b00001100000000110001111011000000;
            7'd121:han_row=32'b00001100000000110011110001100000;
            7'd122:han_row=32'b00001100001111110111100000111000;
            7'd123:han_row=32'b00001100001111101110000000011100;
            7'd124:han_row=32'b00000000000000000100000000001000;
            7'd125:han_row=32'b00000000000000000000000000000000;
            7'd126:han_row=32'b00000000000000000000000000000000;
            7'd127:han_row=32'b00000000000000000000000000000000;
            default:han_row=0;
        endcase
    end
endfunction
reg text_area,han_area,arrow_area,border_area;
reg [11:0] tx,ty;
reg [2:0] line_number;
reg [5:0] character_index;
reg [2:0] font_column;
reg [3:0] font_row;
reg [23:0] composed_rgb;
wire [7:0] character=message_char(line_number,character_index);
wire font_pixel;
hx4s20_osd_font u_font(.character(character),.column(font_column),.row(font_row),.pixel(font_pixel));
wire [11:0] han_x=pixel_x-12'd192;
wire [11:0] han_y=line_y-12'd32;
wire [31:0] han_bits=han_row({han_x[7:6],han_y[5:1]});
wire han_pixel=han_bits[31-han_x[5:1]];
// Repeating inward-free right arrows, translated slowly every two frames.
wire [5:0] arrow_x=pixel_x[5:0]-animation[6:1];
wire [6:0] arrow_dy=(line_y>=360) ? line_y-12'd360 : 12'd360-line_y;
always @* begin
    text_area=0;han_area=0;arrow_area=0;border_area=0;
    tx=0;ty=0;line_number=0;character_index=0;font_column=0;font_row=0;
    composed_rgb=rgb_in;
    if(alarm_frame)begin
        composed_rgb=24'h780014;
        border_area=(pixel_x<8 || pixel_x>=632 || line_y<8 || line_y>=472);
        han_area=(pixel_x>=192 && pixel_x<448 && line_y>=32 && line_y<96);
        if(pixel_x>=176 && pixel_x<464 && line_y>=120 && line_y<184)begin
            text_area=1;tx=pixel_x-176;ty=line_y-120;line_number=5;
            character_index=tx[10:5];font_column=tx[4:2];font_row=ty[5:2];
        end else if(pixel_x>=200 && pixel_x<440 && line_y>=224 && line_y<256)begin
            text_area=1;tx=pixel_x-200;ty=line_y-224;line_number=6;
            character_index=tx[9:4];font_column=tx[3:1];font_row=ty[4:1];
        end else if(pixel_x>=144 && pixel_x<496 && line_y>=432 && line_y<464)begin
            text_area=1;tx=pixel_x-144;ty=line_y-432;line_number=7;
            character_index=tx[9:4];font_column=tx[3:1];font_row=ty[4:1];
        end
        arrow_area=(line_y>=332 && line_y<=388 && pixel_x>=32 && pixel_x<608 &&
                    arrow_dy<=28 && arrow_x>=arrow_dy && arrow_x<arrow_dy+12);
        if(border_area || arrow_area)composed_rgb=24'hffe060;
        if((text_area && font_pixel) || (han_area && han_pixel))composed_rgb=24'hffffff;
    end else if((mode_frame!=2 || ready_frames<180) && line_y<64)begin
        composed_rgb=24'h102a40;
        if(pixel_x>=16 && pixel_x<624)begin
            text_area=1;tx=pixel_x-16;ty=line_y;
            character_index=tx[9:4];font_column=tx[3:1];font_row=ty[4:1];
            if(mode_frame==0)line_number=line_y<32 ? 0 : 1;
            else if(mode_frame==1)line_number=line_y<32 ? 2 : 3;
            else begin line_number=4;if(line_y>=32)text_area=0;end
            if(text_area && font_pixel)composed_rgb=24'hffffff;
        end
    end
end
always @(posedge clk or posedge rst)begin
    if(rst)begin rgb_out<=0;vs_out<=1;de_out<=0;end
    else begin
        vs_out<=vs_in;de_out<=de_in;
        rgb_out<=de_in ? composed_rgb : 24'd0;
    end
end
endmodule
