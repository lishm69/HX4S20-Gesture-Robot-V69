`timescale 1ns/1ps
// True dual-clock BRAM FIFO; Gray pointers, synchronous read with valid.
module av_pcm_fifo #(parameter AW=12)(
 input wr_clk,input wr_rst,input wr_en,input [15:0] wr_data,
 output full,output [AW:0] wr_used,
 input rd_clk,input rd_rst,input rd_en,output reg [15:0] rd_data,
 output reg rd_valid,output empty
);
reg [15:0] mem[0:(1<<AW)-1] /* synthesis ram_style = bram */;
reg [AW:0] wp,wg,rp,rg;
(* async_reg="true" *) reg [AW:0] rgs1,rgs2,wgs1,wgs2;
function [AW:0] ungray;
 input [AW:0] g;integer k;
 begin ungray[AW]=g[AW];for(k=AW-1;k>=0;k=k-1)ungray[k]=ungray[k+1]^g[k];end
endfunction
assign full=(wg=={~rgs2[AW:AW-1],rgs2[AW-2:0]});
assign empty=(rg==wgs2);
assign wr_used=wp-ungray(rgs2);
always @(posedge wr_clk)if(wr_en&&!full&&!wr_rst)mem[wp[AW-1:0]]<=wr_data;
always @(posedge rd_clk)if(rd_en&&!empty&&!rd_rst)rd_data<=mem[rp[AW-1:0]];
always @(posedge wr_clk or posedge wr_rst)
 if(wr_rst)begin wp<=0;wg<=0;rgs1<=0;rgs2<=0;end
 else begin
  rgs1<=rg;rgs2<=rgs1;
  if(wr_en&&!full)begin wp<=wp+1'b1;wg<=((wp+1'b1)>>1)^(wp+1'b1);end
 end
always @(posedge rd_clk or posedge rd_rst)
 if(rd_rst)begin rp<=0;rg<=0;wgs1<=0;wgs2<=0;rd_valid<=0;end
 else begin
  wgs1<=wg;wgs2<=wgs1;rd_valid<=rd_en&&!empty;
  if(rd_en&&!empty)begin rp<=rp+1'b1;rg<=((rp+1'b1)>>1)^(rp+1'b1);end
 end
endmodule
