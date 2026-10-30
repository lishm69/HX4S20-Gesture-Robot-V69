`timescale 1ns/1ps
// Single-master open-drain register reads, repeated START and 1/2-byte burst.
// Every ACK is checked; released SCL is sampled for clock stretching.
module i2c_register_reader #(
 parameter integer CLK_HZ=50000000, BUS_HZ=100000,
 parameter integer TIMEOUT_CYCLES=500000
)(
 input clk,input rst,input start,input [6:0] address,input [7:0] register_address,input two_bytes,
 inout scl,inout sda,output wire busy,output reg done,output reg error,
 output reg [7:0] data_high,output reg [7:0] data_low
);
localparam integer DIV0=CLK_HZ/(BUS_HZ*4);
localparam integer DIV=DIV0<2?2:DIV0;
localparam integer DB=$clog2(DIV+1),TB=$clog2(TIMEOUT_CYCLES+1);
localparam IDLE=0,START_FREE=1,START_EDGE=2,TX_LOW=3,TX_RISE=4,TX_HIGH=5,TX_FALL=6,
 ACK_LOW=7,ACK_RISE=8,ACK_HIGH=9,ACK_FALL=10,RS_LOW=11,RS_RISE=12,RS_EDGE=13,
 RX_LOW=14,RX_RISE=15,RX_HIGH=16,RX_FALL=17,MA_LOW=18,MA_RISE=19,MA_HIGH=20,MA_FALL=21,
 STOP_LOW=22,STOP_RISE=23,STOP_RELEASE=24,FINISH=25,REC_LOW=26,REC_RISE=27,REC_HIGH=28;
reg [4:0] state;
reg [DB-1:0] divider;
reg [TB-1:0] stretch_count;
reg [7:0] tx,rx,reg_latched;
reg [6:0] addr_latched;
reg [2:0] bit_index;
reg [1:0] tx_index;
reg byte_index,want_two,nack_seen;
reg [3:0] recover_count;
(* async_reg="true" *) reg [1:0] scl_sync,sda_sync;
reg scl_low,sda_low;
assign scl=scl_low?1'b0:1'bz;
assign sda=sda_low?1'b0:1'bz;
assign busy=state!=IDLE;
wire tick=divider==DIV-1;
always @* begin
 scl_low=0;sda_low=0;
 case(state)
  START_EDGE,RS_EDGE: sda_low=1;
  TX_LOW,TX_FALL:begin scl_low=1;sda_low=!tx[bit_index];end
  TX_RISE,TX_HIGH:sda_low=!tx[bit_index];
  ACK_LOW,ACK_FALL,RS_LOW,RX_LOW,RX_FALL,REC_LOW:scl_low=1;
  MA_LOW,MA_FALL:begin scl_low=1;sda_low=want_two&&!byte_index;end
  MA_RISE,MA_HIGH:sda_low=want_two&&!byte_index;
  STOP_LOW:begin scl_low=1;sda_low=1;end
  STOP_RISE:sda_low=1;
  default:begin end
 endcase
end
always @(posedge clk or posedge rst)
 if(rst)begin scl_sync<=3;sda_sync<=3;end
 else begin scl_sync<={scl_sync[0],scl};sda_sync<={sda_sync[0],sda};end
always @(posedge clk or posedge rst)
 if(rst)begin
  state<=IDLE;divider<=0;stretch_count<=0;done<=0;error<=0;tx<=0;rx<=0;
  reg_latched<=0;addr_latched<=0;bit_index<=7;tx_index<=0;byte_index<=0;
  want_two<=0;nack_seen<=0;data_high<=0;data_low<=0;recover_count<=0;
 end else begin
  done<=0;
  if(state==IDLE)divider<=0;
  else divider<=tick?0:divider+1'b1;
  if(!busy||scl_low||scl_sync[1])stretch_count<=0;
  else if(stretch_count<TIMEOUT_CYCLES)stretch_count<=stretch_count+1'b1;
  if(state==IDLE)begin
   if(start)begin
    error<=0;reg_latched<=register_address;addr_latched<=address;want_two<=two_bytes;
    tx<={address,1'b0};tx_index<=0;bit_index<=7;byte_index<=0;rx<=0;
    state<=START_FREE;recover_count<=0;
   end
  end else if(stretch_count==TIMEOUT_CYCLES-1)begin
   error<=1;state<=FINISH;
  end else if(tick)begin
   case(state)
    START_FREE:if(scl_sync[1])begin
     if(sda_sync[1])state<=START_EDGE;
     else begin error<=1;state<=REC_LOW;end
    end
    START_EDGE:state<=TX_LOW;
    TX_LOW:state<=TX_RISE;
    TX_RISE:if(scl_sync[1])state<=TX_HIGH;
    TX_HIGH:state<=TX_FALL;
    TX_FALL:if(bit_index==0)state<=ACK_LOW;else begin bit_index<=bit_index-1'b1;state<=TX_LOW;end
    ACK_LOW:state<=ACK_RISE;
    ACK_RISE:if(scl_sync[1])state<=ACK_HIGH;
    ACK_HIGH:begin nack_seen<=sda_sync[1];state<=ACK_FALL;end
    ACK_FALL:begin
     bit_index<=7;
     if(nack_seen)begin error<=1;state<=STOP_LOW;end
     else case(tx_index)
      0:begin tx<=reg_latched;tx_index<=1;state<=TX_LOW;end
      1:state<=RS_LOW;
      default:begin rx<=0;state<=RX_LOW;end
     endcase
    end
    RS_LOW:state<=RS_RISE;
    RS_RISE:if(scl_sync[1])state<=RS_EDGE;
    RS_EDGE:begin tx<={addr_latched,1'b1};tx_index<=2;state<=TX_LOW;end
    RX_LOW:state<=RX_RISE;
    RX_RISE:if(scl_sync[1])state<=RX_HIGH;
    RX_HIGH:begin rx<={rx[6:0],sda_sync[1]};state<=RX_FALL;end
    RX_FALL:if(bit_index==0)begin
     if(byte_index)data_low<=rx;else data_high<=rx;
     state<=MA_LOW;
    end else begin bit_index<=bit_index-1'b1;state<=RX_LOW;end
    MA_LOW:state<=MA_RISE;
    MA_RISE:if(scl_sync[1])state<=MA_HIGH;
    MA_HIGH:state<=MA_FALL;
    MA_FALL:if(want_two&&!byte_index)begin byte_index<=1;bit_index<=7;rx<=0;state<=RX_LOW;end
     else state<=STOP_LOW;
    STOP_LOW:state<=STOP_RISE;
    STOP_RISE:if(scl_sync[1])state<=STOP_RELEASE;
    STOP_RELEASE:state<=FINISH;
    FINISH:begin done<=1;state<=IDLE;end
    REC_LOW:state<=REC_RISE;
    REC_RISE:if(scl_sync[1])state<=REC_HIGH;
    REC_HIGH:if(recover_count==8)state<=STOP_LOW;
     else begin recover_count<=recover_count+1'b1;state<=REC_LOW;end
    default:begin error<=1;state<=FINISH;end
   endcase
  end
 end
endmodule
