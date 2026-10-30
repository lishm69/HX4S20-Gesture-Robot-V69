`timescale 1ns/1ps
// Volatile two-key learning at each reset; no guessed product-specific codes.
// Setup: first complete frame -> ALARM; release >=250ms; different key from
// the SAME address -> CLEAR. Learning a key never activates the alarm.
module emergency_ctrl #(
    parameter integer CLK_HZ=25000000,
    parameter integer RELEASE_CYCLES=CLK_HZ/4
)(
    input wire clk,input wire rst,
    input wire frame_valid,input wire repeat_valid,
    input wire [15:0] address,input wire [7:0] command,
    output reg alarm_active,output reg [1:0] learn_state,
    output reg [15:0] learned_address,
    output reg [7:0] alarm_command,output reg [7:0] clear_command
);
reg [31:0] quiet_cycles;
always @(posedge clk or posedge rst)begin
    if(rst)begin
        alarm_active<=0;learn_state<=0;learned_address<=0;
        alarm_command<=0;clear_command<=0;quiet_cycles<=0;
    end else begin
        if(frame_valid || repeat_valid)quiet_cycles<=0;
        else if(quiet_cycles<RELEASE_CYCLES)quiet_cycles<=quiet_cycles+1'b1;
        if(frame_valid)case(learn_state)
            0:begin learned_address<=address;alarm_command<=command;learn_state<=1;end
            1:if(quiet_cycles>=RELEASE_CYCLES && address==learned_address && command!=alarm_command)begin
                clear_command<=command;learn_state<=2;alarm_active<=0;
            end
            2:if(address==learned_address)begin
                if(command==alarm_command)alarm_active<=1;
                else if(command==clear_command)alarm_active<=0;
            end
            default:begin learn_state<=0;alarm_active<=0;end
        endcase
    end
end
endmodule
