`timescale 1ns/1ps
// Measured remote: address 00/FF, UP 18/E7, DOWN 52/AD.
// One event per press. Repeats maintain the held state and never step.
module ir_volume_ctrl #(
 parameter integer CLK_HZ=25000000,RELEASE_CYCLES=CLK_HZ/5,
 parameter [4:0] RESET_LEVEL=5'd16
)(input wire clk,rst,input wire frame_valid,repeat_valid,frame_error,
 input wire [31:0] raw_bytes,output reg [4:0] level,output reg adjust_event);
localparam integer AGE_BITS=$clog2(RELEASE_CYCLES+1);
reg [AGE_BITS-1:0] age;
reg held;
reg [7:0] held_command;
wire [7:0] command=raw_bytes[15:8];
wire matched=raw_bytes[31:24]==8'h00 && raw_bytes[23:16]==8'hff &&
 (raw_bytes[15:8]^raw_bytes[7:0])==8'hff &&
 (command==8'h18 || command==8'h52);
always @(posedge clk or posedge rst)begin
 if(rst)begin level<=RESET_LEVEL;adjust_event<=0;age<=0;held<=0;held_command<=0;end
 else begin
  adjust_event<=0;
  if(age<RELEASE_CYCLES)age<=age+1'b1;
  else held<=0;
  // Errors cannot become presses or release a still-held key immediately.
  // With no valid traffic the release timer still expires normally.
  if(!frame_error)begin
   if(frame_valid)begin
    if(!matched)held<=0;
    else begin
     held<=1;held_command<=command;age<=0;
     if(!held || held_command!=command || age>=RELEASE_CYCLES)begin
      adjust_event<=1;
      if(command==8'h18 && level<16)level<=level+1'b1;
      else if(command==8'h52 && level>0)level<=level-1'b1;
     end
    end
   end else if(repeat_valid && held && age<RELEASE_CYCLES)age<=0;
  end
 end
end
endmodule
