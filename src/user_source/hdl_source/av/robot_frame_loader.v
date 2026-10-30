`timescale 1ns/1ps
// Whole-sector input, bounded RLE expansion, full-frame CRC and write completion
// are required before publishing. Never reset the shared SD card on cancellation.
module robot_frame_loader #(
 parameter integer TIMEOUT=100000000
)(input clk,rst,start,input clip,input [6:0] frame_number,
 output ready,output reg error,
 output sec_req,output [31:0] sec_addr,input [7:0] sec_data,
 input sec_valid,sec_end,sec_error,
 output write_req,input write_ack,write_ready,
 output write_en,output [31:0] write_data);
`include "robot_resources.vh"
localparam IDLE=0,HEADER=1,CHECK=2,ACK=3,ACK_LOW=4,READ=5,
 GAP=6,FETCH=7,DELAY=8,COUNT=9,INDEX=10,COLOR=11,EMIT=12,VERIFY=13,FAIL=14,CRC_RUN=15;
reg [3:0] state;
reg [16:0] lba;
reg [$clog2(TIMEOUT+1)-1:0] timer;
reg [31:0] crc,expected_crc;
reg crc_step;
reg crc_is_index;
// Four CRC bits per clock keep the combinational path short while reducing
// each compressed byte from eight CRC clocks to two.
function [31:0] crc4;
 input [31:0] value;
 reg [31:0] c;
 integer bit_no;
 begin
  c=value;
  for(bit_no=0;bit_no<4;bit_no=bit_no+1)
   c=c[0]?(c>>1)^32'hedb88320:(c>>1);
  crc4=c;
 end
endfunction
reg [15:0] payload_bytes,payload_used;
reg [18:0] pixels;
reg [9:0] received,consume;
reg [8:0] run_left;
reg [7:0] count_byte;
reg [5:0] palette_index;
reg [15:0] color_q;
reg [7:0] sector_q;
reg job_clip;reg [6:0] job_frame;
reg bad_header;
reg [7:0] expected_header;
// Validate fixed fields as they arrive instead of storing 192 comparison bits.
always @* begin
 expected_header=0;
 case(received)
  0:expected_header=8'h48;1:expected_header=8'h58;
  2:expected_header=8'h52;3:expected_header=8'h42;
  4:expected_header=8'h56;5:expected_header=8'h30;
  6:expected_header=8'h30;7:expected_header=8'h31;
  8:expected_header=1;9:expected_header={7'd0,job_clip};
  10:expected_header={1'b0,job_frame};11:expected_header=12;
  12:expected_header=8'h80;13:expected_header=2;
  14:expected_header=8'he0;15:expected_header=1;
  25:expected_header=8'hb0;26:expected_header=4;
  28:expected_header=ROBOT_ASSET_ID[7:0];29:expected_header=ROBOT_ASSET_ID[15:8];
  30:expected_header=ROBOT_ASSET_ID[23:16];31:expected_header=ROBOT_ASSET_ID[31:24];
 endcase
end
(* ram_style="block" *) reg [7:0] sector_ram[0:511];
(* ram_style="block" *) reg [15:0] palette[0:63];
initial $readmemh("robot_palette.hex",palette);
always @(posedge clk)begin
 if(sec_valid&&(state==READ))sector_ram[received[8:0]]<=sec_data;
 sector_q<=sector_ram[consume[8:0]];
 color_q<=palette[palette_index];
end
assign ready=state==IDLE;
assign sec_req=state==HEADER||state==READ;
assign sec_addr={15'd0,lba};
assign write_req=state==ACK;
assign write_en=state==EMIT&&write_ready;
assign write_data={{color_q[15:11],color_q[15:13]},
                    {color_q[10:5],color_q[10:9]},
                    {color_q[4:0],color_q[4:2]},8'd0};
always @(posedge clk or posedge rst)
 if(rst)begin
  state<=IDLE;error<=0;lba<=0;timer<=0;crc<=32'hffffffff;expected_crc<=0;
  crc_step<=0;crc_is_index<=0;
  payload_bytes<=0;payload_used<=0;pixels<=0;received<=0;consume<=0;run_left<=0;
  count_byte<=0;palette_index<=0;job_clip<=0;job_frame<=0;bad_header<=0;
 end else begin
  error<=0;
  if(state==IDLE)timer<=0;
  else if(sec_valid||write_en)timer<=0;
  else if(timer<TIMEOUT)timer<=timer+1'b1;
  if(state!=IDLE&&state!=FAIL&&(sec_error||timer==TIMEOUT||
     ((state==HEADER||state==READ)&&sec_valid&&received>=512)))state<=FAIL;
  else case(state)
   IDLE:if(start)begin
    job_clip<=clip;job_frame<=frame_number;
    lba<=(clip?ROBOT_BASE_B:ROBOT_BASE_A)+({25'd0,frame_number}<<ROBOT_STRIDE_SHIFT);
    received<=0;payload_used<=0;pixels<=0;crc<=32'hffffffff;bad_header<=0;
    payload_bytes<=0;expected_crc<=0;state<=HEADER;
   end
   HEADER:begin
    if(sec_valid)begin
     received<=received+1'b1;
     if(received==16||received==17)payload_bytes[received[0]*8 +:8]<=sec_data;
     else if(received>=20&&received<24)expected_crc[received[1:0]*8 +:8]<=sec_data;
     else if(sec_data!=expected_header)bad_header<=1;
    end
    if(sec_end)state<=CHECK;
   end
   CHECK:begin
    if(received!=512||bad_header||
       payload_bytes==0||payload_bytes[0]||payload_bytes>ROBOT_MAX_BYTES||
       job_frame>=(job_clip?72:48))state<=FAIL;
    else state<=ACK;
   end
   ACK:if(write_ack)state<=ACK_LOW;
   ACK_LOW:if(!write_ack)begin lba<=lba+1'b1;received<=0;state<=READ;end
   READ:begin
    if(sec_valid)received<=received+1'b1;
    if(sec_end)begin
     if(received!=512)state<=FAIL;
     else begin consume<=0;state<=GAP;end
    end
   end
   GAP:state<=FETCH;
   FETCH:state<=DELAY;
   DELAY:state<=COUNT;
   COUNT:begin
    count_byte<=sector_q;crc<=crc^{24'd0,sector_q};consume<=consume+1'b1;
    payload_used<=payload_used+1'b1;crc_step<=0;crc_is_index<=0;state<=CRC_RUN;
   end
   // The synchronous sector read observes the incremented address only now.
   INDEX:state<=COLOR;
   COLOR:begin
    if(sector_q[7:6]!=0||pixels+{1'b0,count_byte}+1>307200)state<=FAIL;
    else begin
     palette_index<=sector_q[5:0];run_left<={1'b0,count_byte}+1'b1;
     crc<=crc^{24'd0,sector_q};consume<=consume+1'b1;payload_used<=payload_used+1'b1;
     crc_step<=0;crc_is_index<=1;state<=CRC_RUN;
    end
   end
   VERIFY:state<=EMIT;
   CRC_RUN:begin
    crc<=crc4(crc);
    if(crc_step)state<=crc_is_index?VERIFY:INDEX;
    else crc_step<=crc_step+1'b1;
   end
   EMIT:if(write_ready)begin
    pixels<=pixels+1'b1;run_left<=run_left-1'b1;
    if(run_left==1)begin
     if(payload_used==payload_bytes)begin
      if(pixels!=307199||(~crc)!=expected_crc)state<=FAIL;
      else state<=IDLE;
     end else if(payload_used>payload_bytes||pixels==307199)state<=FAIL;
     else if(consume==512)begin lba<=lba+1'b1;received<=0;state<=READ;end
     else state<=FETCH;
    end
   end
   FAIL:begin error<=1;state<=IDLE;end
   default:state<=FAIL;
  endcase
 end
endmodule
