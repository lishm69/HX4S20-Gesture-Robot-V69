`timescale 1ns/1ps
// V6.1: read one animation frame into the non-display BRAM bank.
// Whole-sector ownership remains in av_sd_media. No animation SDRAM accesses.
module dance_stream_loader #(parameter TIMEOUT=200000000)(
 input clk,input rst,output sec_req,output [31:0] sec_addr,
 input [7:0] sec_data,input sec_valid,input sec_end,input sec_error,
 input frame_toggle,input [7:0] frame_number,input frame_bank,output reg frame_ack,
 output reg cache_we,output reg [12:0] cache_addr,output reg [31:0] cache_data,
 output reg loaded,output reg failed,output reg [2:0] diagnostic
);
localparam HEADER=0,GAP=1,IDLE=2,PIXELS=3,VERIFY=4,ERROR=5;
reg [2:0] state;reg [31:0] lba,timer,crc,crc_target;reg [9:0] count;
reg [4:0] sector_index;reg [11:0] word_index;reg [23:0] pack;
reg bad,bank,job;reg [7:0] number;
(* async_reg="true" *)reg [2:0] req_s;
(* async_reg="true" *)reg [7:0] num_m,num_s;
(* async_reg="true" *)reg bank_m,bank_s;
localparam [511:0] EXPECTED_HEADER=512'h0000000000000000f7d4f96c2ad7e7f00006c0000000000200000001000000010000000100003000000000240001000c00600080020000013145434e41445848;
function [31:0] expected_crc;input [7:0] n;begin case(n)
8'd0:expected_crc=32'hc1b97b54;
8'd1:expected_crc=32'h6738b8b0;
8'd2:expected_crc=32'h10bb49cf;
8'd3:expected_crc=32'h004eb6b9;
8'd4:expected_crc=32'h39a81149;
8'd5:expected_crc=32'h75da7513;
8'd6:expected_crc=32'h0313b5d3;
8'd7:expected_crc=32'h5fa8c61d;
8'd8:expected_crc=32'hf3d53798;
8'd9:expected_crc=32'h2d43fd70;
8'd10:expected_crc=32'hde2089ac;
8'd11:expected_crc=32'hd76d7737;
8'd12:expected_crc=32'hcfeacdb9;
8'd13:expected_crc=32'h4a295293;
8'd14:expected_crc=32'h6eeb7403;
8'd15:expected_crc=32'hd4271d4f;
8'd16:expected_crc=32'hb9d3b1df;
8'd17:expected_crc=32'h52fb7057;
8'd18:expected_crc=32'he63518f5;
8'd19:expected_crc=32'h34a4a727;
8'd20:expected_crc=32'h867a4ec9;
8'd21:expected_crc=32'hcb031c3c;
8'd22:expected_crc=32'hc0e31780;
8'd23:expected_crc=32'h1604afa0;
8'd24:expected_crc=32'h7d697d66;
8'd25:expected_crc=32'ha7a02812;
8'd26:expected_crc=32'hcc5948e3;
8'd27:expected_crc=32'hacca33b1;
8'd28:expected_crc=32'h45a6ff93;
8'd29:expected_crc=32'h7e0b49b0;
8'd30:expected_crc=32'h75da7513;
8'd31:expected_crc=32'h2d7c2486;
8'd32:expected_crc=32'hb1ef0513;
8'd33:expected_crc=32'hd72944eb;
8'd34:expected_crc=32'h4ea2e82e;
8'd35:expected_crc=32'h4c816dbf;
default:expected_crc=0;endcase end endfunction
function [31:0] crc_byte;
 input [31:0] c;input [7:0] b;reg [31:0] t;integer k;
 begin t=c^{24'd0,b};for(k=0;k<8;k=k+1)t=t[0]?(t>>1)^32'hedb88320:t>>1;crc_byte=t;end
endfunction
assign sec_req=state==HEADER||state==PIXELS;assign sec_addr=lba;
always @(posedge clk or posedge rst)
 if(rst)begin state<=HEADER;lba<=32768;timer<=0;crc<=32'hffffffff;count<=0;sector_index<=0;word_index<=0;pack<=0;bad<=0;
 bank<=0;job<=0;number<=0;crc_target<=0;req_s<=0;num_m<=0;num_s<=0;bank_m<=0;bank_s<=0;frame_ack<=0;
 cache_we<=0;cache_addr<=0;cache_data<=0;loaded<=0;failed<=0;diagnostic<=0;end
 else begin
  crc_target<=expected_crc(number);
  req_s<={req_s[1:0],frame_toggle};num_m<=frame_number;num_s<=num_m;bank_m<=frame_bank;bank_s<=bank_m;cache_we<=0;
  if(state==HEADER||state==PIXELS)begin
   if(sec_valid||sec_end)timer<=0;
   else if(timer==TIMEOUT-1)begin state<=ERROR;failed<=1;diagnostic<=4;end
   else timer<=timer+1'b1;
  end else timer<=0;
  if(sec_error)begin state<=ERROR;failed<=1;diagnostic<=4;end
  else if(timer!=TIMEOUT-1)case(state)
   HEADER:begin
    if(sec_valid)begin count<=count+1'b1;if(count<64&&sec_data!=EXPECTED_HEADER[count[5:0]*8 +:8])bad<=1;end
    if(sec_end)begin if(bad||count!=512)begin failed<=1;state<=ERROR;diagnostic<=3;end
      else begin loaded<=1;state<=GAP;diagnostic<=1;end end
   end
   GAP:begin count<=0;state<=loaded&&word_index==0&&sector_index==0 ? IDLE : PIXELS;end
   IDLE:if(req_s[2]!=frame_ack)begin
    if(num_s>=36)begin failed<=1;state<=ERROR;diagnostic<=3;end
    else begin bank<=bank_s;job<=req_s[2];number<=num_s;
     lba<=32770+num_s*32'd24;word_index<=0;sector_index<=0;count<=0;crc<=32'hffffffff;state<=PIXELS;diagnostic<=1;end
   end
   PIXELS:begin
    if(sec_valid)begin
     count<=count+1'b1;pack<={sec_data,pack[23:8]};crc<=crc_byte(crc,sec_data);
     if(count[1:0]==3)begin cache_we<=1;cache_addr<={bank,word_index};cache_data<={sec_data,pack};word_index<=word_index+1'b1;end
    end
    if(sec_end)begin
     if(count!=512)begin failed<=1;state<=ERROR;diagnostic<=4;end
     else if(sector_index==23)state<=VERIFY;
     else begin sector_index<=sector_index+1'b1;lba<=lba+1'b1;state<=GAP;end
    end
   end
   VERIFY:begin
    if(word_index!=3072||crc!=crc_target)begin failed<=1;state<=ERROR;diagnostic<=5;end
    else begin frame_ack<=job;state<=IDLE;diagnostic<=2;end
   end
   default:;
  endcase
 end
endmodule
