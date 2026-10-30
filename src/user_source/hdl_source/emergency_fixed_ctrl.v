`timescale 1ns/1ps
// Fixed keys measured on the user's physical remote. No learning or Flash state.
// Repeated full frames and NEC repeats maintain a held key but never act twice.
module emergency_fixed_ctrl #(
 parameter integer CLK_HZ=25000000, RELEASE_CYCLES=CLK_HZ/5
)(input wire clk,rst,input wire frame_valid,repeat_valid,frame_error,
 input wire [31:0] raw_bytes,output reg alarm_active,output reg alarm_muted,
 output reg key_event,output reg [7:0] last_command);
reg held_valid;
reg [7:0] held_command;
reg [31:0] quiet_cycles;
wire [7:0] command=raw_bytes[15:8];
wire known=command==8'h45 || command==8'h46 || command==8'h47 || command==8'h44;
wire matched=raw_bytes[31:24]==8'h00 && raw_bytes[23:16]==8'hff && known;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  held_valid<=0;held_command<=0;quiet_cycles<=0;
  alarm_active<=0;alarm_muted<=0;key_event<=0;last_command<=0;
 end else begin
  key_event<=0;
  if(quiet_cycles<RELEASE_CYCLES)quiet_cycles<=quiet_cycles+1'b1;
  else held_valid<=0;
  if(frame_error)held_valid<=0;
  else if(frame_valid)begin
   if(!matched)held_valid<=0;
   else begin
    held_valid<=1;held_command<=command;quiet_cycles<=0;
    if(!held_valid || held_command!=command || quiet_cycles>=RELEASE_CYCLES)begin
     key_event<=1;last_command<=command;
     case(command)
      8'h45:begin alarm_active<=1;alarm_muted<=0;end
      8'h46:begin alarm_active<=0;alarm_muted<=0;end
      8'h47:if(alarm_active)alarm_muted<=1;
      8'h44:if(alarm_active)alarm_muted<=0;
     endcase
    end
   end
  end else if(repeat_valid && held_valid && quiet_cycles<RELEASE_CYCLES)quiet_cycles<=0;
 end
end
endmodule
