`timescale 1ns/1ps
// Verilog-2001. Asynchronous input -> two FF synchronizer -> stable-time filter.
module hx4s20_input_filter #(
    parameter integer STABLE_CYCLES = 500000,
    parameter RESET_VALUE = 1'b0
)(
    input wire clk, input wire rst,
    input wire async_in, output reg stable_out
);
function integer bits_for;
    input integer value;
    integer t;
    begin
        bits_for=0;
        for(t=value-1;t>0;t=t>>1) bits_for=bits_for+1;
        if(bits_for<1) bits_for=1;
    end
endfunction
localparam integer COUNT_W = bits_for(STABLE_CYCLES);
// Keep the synchronizer explicit and portable across TD and simulators.
reg sync_meta, sync_data;
reg [COUNT_W-1:0] count;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        sync_meta<=RESET_VALUE;sync_data<=RESET_VALUE;
        stable_out<=RESET_VALUE;count<=0;
    end else begin
        sync_meta<=async_in;sync_data<=sync_meta;
        if(sync_data==stable_out) count<=0;
        else if(count==STABLE_CYCLES-1) begin
            stable_out<=sync_data;count<=0;
        end else count<=count+1'b1;
    end
end
endmodule
