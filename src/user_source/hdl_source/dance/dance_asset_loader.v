`timescale 1ns/1ps
// SD-domain whole-sector reader + stable-data word mailbox to memory domain.
module dance_asset_loader #(parameter TIMEOUT=200000000)(
 input clk,input rst,output sec_req,output [31:0] sec_addr,
 input [7:0] sec_data,input sec_valid,input sec_end,input sec_error,
 output reg word_toggle,output reg [20:0] word_addr,output reg [31:0] word_data,input word_ack,
 output pal_we,output [7:0] pal_addr,output [15:0] pal_data,
 output reg loaded,output reg failed
);
localparam IDLE=0,HEADER=1,GAP=2,PALETTE=3,PIXELS=4,DRAIN=5,DONE=6,ERROR=7;
reg [2:0] state;reg [31:0] lba,timer,crc,pcrc;
reg [9:0] count;reg [22:0] total;reg [7:0] low;
reg [1:0] phase;reg [23:0] pack;reg bad;
reg [31:0] sector_buf[0:127] /* synthesis ram_style=bram */;
reg [31:0] sector_q;reg [6:0] flush_index;reg [1:0] flush_phase;reg [20:0] next_addr;
always @(posedge clk)begin
 if(state==PIXELS&&sec_valid&&phase==3)sector_buf[count[8:2]]<={sec_data,pack};
 sector_q<=sector_buf[flush_index];
end
(* async_reg="true" *) reg [2:0] ack_s;
localparam [511:0] EXPECTED_HEADER=512'h00000000000000005582704d56cf3e04002760000000000200000001000000010000000100003000000000d20001000c00600080020000013145434e41445848;
function [31:0] crc_byte;
 input [31:0] c;input [7:0] b;reg [31:0] t;integer k;
 begin t=c^{24'd0,b};for(k=0;k<8;k=k+1)t=t[0] ? (t>>1)^32'hedb88320 : t>>1;crc_byte=t;end
endfunction
assign sec_req=(state==HEADER||state==PALETTE||state==PIXELS);
assign sec_addr=lba;
assign pal_we=state==PALETTE&&sec_valid&&count[0];
assign pal_addr=count[8:1];assign pal_data={sec_data,low};
wire pending=word_toggle!=ack_s[2];
always @(posedge clk or posedge rst)
 if(rst)begin state<=IDLE;lba<=32768;timer<=0;count<=0;total<=0;phase<=0;pack<=0;low<=0;
 crc<=32'hffffffff;pcrc<=32'hffffffff;bad<=0;word_toggle<=0;word_addr<=21'h0a0000;word_data<=0;loaded<=0;failed<=0;ack_s<=0;
 flush_index<=0;flush_phase<=0;next_addr<=21'h0a0000;end
 else begin
  ack_s<={ack_s[1:0],word_ack};
  if(state!=DONE&&state!=ERROR)begin
   if(sec_valid||sec_end||state==IDLE||state==GAP)timer<=0;
   else if(timer==TIMEOUT-1||sec_error)begin state<=ERROR;failed<=1;end
   else timer<=timer+1'b1;
  end
  if(sec_error&&state!=DONE)begin state<=ERROR;failed<=1;end
  else if(timer!=TIMEOUT-1)case(state)
   IDLE:state<=HEADER;
   HEADER:begin
    if(sec_valid)begin
     if(count<64&&sec_data!=EXPECTED_HEADER[count[5:0]*8 +:8])bad<=1;
     count<=count+1'b1;
    end
    if(sec_end)begin if(bad||count!=512)begin state<=ERROR;failed<=1;end
      else begin lba<=32769;state<=GAP;end end
   end
   GAP:if(!pending)begin count<=0;state<=lba==32769 ? PALETTE : PIXELS;end
   PALETTE:begin
    if(sec_valid)begin low<=sec_data;count<=count+1'b1;pcrc<=crc_byte(pcrc,sec_data);end
    if(sec_end)begin
     if(count!=512||pcrc!=32'haa7d8fb2)begin state<=ERROR;failed<=1;end
     else begin lba<=32770;state<=GAP;end
    end
   end
   PIXELS:begin
    if(sec_valid)begin
     count<=count+1'b1;total<=total+1'b1;phase<=phase+1'b1;crc<=crc_byte(crc,sec_data);
     pack<={sec_data,pack[23:8]};
    end
    if(sec_end)begin
     if(count!=512)begin state<=ERROR;failed<=1;end
     else if(total>2580480)begin state<=ERROR;failed<=1;end
     else begin flush_index<=0;flush_phase<=0;state<=DRAIN;end
    end
   end
   DRAIN:case(flush_phase)
    0:if(!pending)flush_phase<=1;
    1:begin word_addr<=next_addr;next_addr<=next_addr+1'b1;word_data<=sector_q;
      word_toggle<=!word_toggle;flush_phase<=2;end
    2:if(!pending)begin
      if(flush_index==127)begin
       if(total==2580480)begin
        if(crc!=32'ha930c1fb)begin state<=ERROR;failed<=1;end
        else begin loaded<=1;state<=DONE;end
       end else begin lba<=lba+1'b1;state<=GAP;end
      end else begin flush_index<=flush_index+1'b1;flush_phase<=0;end
    end
    default:flush_phase<=0;
   endcase
   default:;
  endcase
 end
endmodule
