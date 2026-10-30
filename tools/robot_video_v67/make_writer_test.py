from pathlib import Path
R=Path('C:/Users/ASUS/Desktop/HX4S20_Refactored_20261023/HX4S20_Refactored_20261023')
V=R/'verification/robot_v67'
s=(V/'tb_robot_loader.sv').read_text().replace('module tb_robot_loader;','module tb_robot_writer;')
s=s.replace('sec_error=0,wack=0;','sec_error=0;wire wack;')
s=s.replace('reg [15:0] expected[0:307199];','')
s=s.replace('wire wready=cycle%11>2;',r'''reg [15:0] expected[0:307199];
reg mc=0;always #20 mc=~mc;
wire wready,raw_ack,wfinish,mem_we;wire[20:0] mem_addr;wire[31:0] mem_data;
reg[1:0] slot=0;reg[2:0] ack_sync=0;integer sink_pixels=0,finished_frames=0;reg stressed=0;
always @(posedge clk)ack_sync<={ack_sync[1:0],raw_ack};assign wack=ack_sync[2];
frame_read_write #(.WRITE_V_FLIP(0)) fb(
 .aux_hold(1'b0),.bg_busy(),.rst(rst),.mem_clk(mc),.Sdr_init_done(!rst),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .App_rd_en(),.App_rd_addr(),.Sdr_rd_en(1'b0),.Sdr_rd_dout(32'd0),
 .read_clk(clk),.read_req(1'b0),.read_req_ack(),.read_finish(),.read_active_index(),
 .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd614400),.read_addr_3(21'd0),
 .read_addr_index(2'd0),.read_len(21'd307200),.read_en(1'b0),.read_data(),
 .App_wr_en(mem_we),.App_wr_addr(mem_addr),.App_wr_din(mem_data),.App_wr_dm(),
 .write_clk(clk),.write_req(wreq),.write_req_ack(raw_ack),.write_ready(wready),.write_finish(wfinish),
 .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd614400),.write_addr_3(21'd0),
 .write_addr_index(slot),.write_len(21'd307200),.write_en(wen),.write_data(data));
always @(posedge clk)if(!rst&&fb.write_fifo_afull)stressed<=1;
always @(posedge mc)if(!rst)begin
 if(mem_we)begin
  if(sink_pixels>=307200||mem_addr!==slot*307200+sink_pixels||mem_data!=={
   {expected[sink_pixels][15:11],expected[sink_pixels][15:13]},
   {expected[sink_pixels][10:5],expected[sink_pixels][10:9]},
   {expected[sink_pixels][4:0],expected[sink_pixels][4:2]},8'd0})
   $fatal(1,"physical writer stream mismatch slot=%d pixel=%d addr=%d data=%h",slot,sink_pixels,mem_addr,mem_data);
  sink_pixels++;
 end
 if(wfinish)begin if(sink_pixels!=307200)$fatal(1,"early writer completion");finished_frames++;end
end
''')
start=s.index('initial forever begin\n @(negedge clk);\n if(wreq')
end=s.index('task run_frame',start)
s=s[:start]+s[end:]
s=s.replace('ack_count=0;','ack_count=0;',1)
s=s.replace('job_begin=cycle;start=1;', 'sink_pixels=0;job_begin=cycle;start=1;')
s=s.replace('wait(!ready);wait(ready);repeat(3)', 'wait(!ready);wait(ready);wait(wfinish);repeat(3)')
s=s.replace(' ||ack_count!=1','')
s=s.replace(' || ack_count!=1','').replace('||ack_count!=1','')
start=s.index('initial begin\n repeat(5)');end=s.index('initial begin #900000000',start)
s=s[:start]+'''initial begin
 repeat(5)@(negedge clk);rst=0;
 slot=0;run_frame(0,0,"clip0_frame0_rgb565.hex",0);
 slot=1;run_frame(0,27,"clip0_frame27_rgb565.hex",0);
 slot=2;run_frame(1,19,"clip1_frame19_rgb565.hex",0);
 if(!stressed||finished_frames!=3)$fatal(1,"no FIFO pressure or missing frame completion");
 $display("PASS tb_robot_writer: actual RLE loader to production frame_read_write/frame_fifo_write_wavefix, 921600 pixel/data/address checks across three SDRAM slots, slower memory clock, FIFO full throttling, ordered bursts and real write-finish events");$finish;
end
'''+s[end:]
(V/'tb_robot_writer.sv').write_text(s,encoding='utf-8')
fifo=(R/'verification/scaling_v62/tb_backpressure.sv').read_text().split('module tb_backpressure;')[0]
(V/'fifo_models.v').write_text(fifo,encoding='utf-8')
