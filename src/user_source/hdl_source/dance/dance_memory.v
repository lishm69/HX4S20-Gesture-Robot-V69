`timescale 1ns/1ps
// One auxiliary SDRAM command per grant, with drain and yield intervals.
// Original background bursts run to completion before taking ownership.
module dance_memory #(parameter READ_TIMEOUT=1024)(
 input clk,input rst,input init_done,input refresh,input sdr_busy,input bg_busy,
 input load_toggle,input [20:0] load_addr,input [31:0] load_data,output reg load_ack,
 input frame_toggle,input [7:0] frame_number,input frame_bank,output reg frame_ack,
 output hold_bg,output own,output wr_en,output rd_en,output [20:0] addr,output [31:0] data,
 input rd_valid,input [31:0] rd_data,
 output reg cache_we,output reg [12:0] cache_addr,output reg [31:0] cache_data,
 output reg fault
);
(* async_reg="true" *)reg [2:0] load_s,frame_s;
(* async_reg="true" *)reg [20:0] addr_m,addr_s;
(* async_reg="true" *)reg [31:0] data_m,data_s;
(* async_reg="true" *)reg [7:0] num_m,num_s;
(* async_reg="true" *)reg bank_m,bank_s;
reg [2:0] state;reg [10:0] timer;reg [11:0] offset;reg filling,bank,write_mode;
reg [20:0] frame_base,command_addr;reg [31:0] command_data;reg command_toggle;
localparam IDLE=0,GRANT=1,ISSUE=2,WAIT_READ=3,DRAIN=4,YIELD=5;
assign hold_bg=state==GRANT||state==ISSUE||state==WAIT_READ||state==DRAIN;
assign own=state==ISSUE||state==WAIT_READ||state==DRAIN;
assign wr_en=state==ISSUE&&write_mode&&!refresh&&!sdr_busy;
assign rd_en=state==ISSUE&&!write_mode&&!refresh&&!sdr_busy;
assign addr=command_addr;assign data=command_data;
always @(posedge clk or posedge rst)
 if(rst)begin load_s<=0;frame_s<=0;addr_m<=0;addr_s<=0;data_m<=0;data_s<=0;
 num_m<=0;num_s<=0;bank_m<=0;bank_s<=0;load_ack<=0;frame_ack<=0;state<=IDLE;
 timer<=0;offset<=0;filling<=0;bank<=0;write_mode<=0;frame_base<=0;command_addr<=0;command_data<=0;command_toggle<=0;
 cache_we<=0;cache_addr<=0;cache_data<=0;fault<=0;end
 else begin
  load_s<={load_s[1:0],load_toggle};frame_s<={frame_s[1:0],frame_toggle};
  addr_m<=load_addr;addr_s<=addr_m;data_m<=load_data;data_s<=data_m;
  num_m<=frame_number;num_s<=num_m;bank_m<=frame_bank;bank_s<=bank_m;cache_we<=0;
  case(state)
   IDLE:begin
    timer<=0;
    if(init_done&&!fault)begin
     if(load_s[2]!=load_ack)begin
      command_addr<=addr_s;command_data<=data_s;write_mode<=1;command_toggle<=load_s[2];state<=GRANT;
     end else if(filling)begin command_addr<=frame_base+offset;write_mode<=0;state<=GRANT;end
     else if(frame_s[2]!=frame_ack)begin
      if(num_s>=210)fault<=1;
      else begin filling<=1;offset<=0;bank<=bank_s;frame_base<=21'h0a0000+num_s*21'd3072;command_toggle<=frame_s[2];end
     end
    end
   end
   GRANT:begin
    // Wait four quiet cycles after background pipelines have drained.
    if(bg_busy||sdr_busy||refresh)timer<=0;
    else if(timer==3)begin timer<=0;state<=ISSUE;end
    else timer<=timer+1'b1;
   end
   ISSUE:begin timer<=0;state<=refresh||sdr_busy ? GRANT : write_mode ? DRAIN : WAIT_READ;end
   WAIT_READ:begin
    if(rd_valid)begin
     cache_we<=1;cache_addr<={bank,offset};cache_data<=rd_data;
     if(offset==3071)begin filling<=0;frame_ack<=command_toggle;end
     else offset<=offset+1'b1;
     timer<=0;state<=DRAIN;
    end else if(timer==READ_TIMEOUT-1)begin fault<=1;state<=YIELD;timer<=0;end
    else timer<=timer+1'b1;
   end
   DRAIN:if(timer==15)begin
    if(write_mode)load_ack<=command_toggle;
    timer<=0;state<=YIELD;
   end else timer<=timer+1'b1;
   YIELD:if(timer==7)begin state<=IDLE;timer<=0;end else timer<=timer+1'b1;
   default:state<=IDLE;
  endcase
 end
endmodule
