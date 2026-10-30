`timescale 1ns/1ps
// Unsigned restoring divider. Configuration only: never used per pixel.
module scale_divider (
    input wire clk, input wire rst, input wire start,
    input wire [31:0] numerator, input wire [31:0] denominator,
    output reg [31:0] quotient, output reg done, output reg busy
);
reg [31:0] dividend, divisor, remainder;
reg [5:0] count;
wire [32:0] trial = {remainder, dividend[31]};
wire [32:0] difference = trial - {1'b0,divisor};
always @(posedge clk or posedge rst) begin
    if (rst) begin
        quotient<=0;done<=0;busy<=0;dividend<=0;divisor<=1;remainder<=0;count<=0;
    end else begin
        done<=0;
        if (start && !busy) begin
            dividend<=numerator;divisor<=denominator;remainder<=0;quotient<=0;
            count<=31;busy<=1;
        end else if (busy) begin
            dividend<={dividend[30:0],1'b0};
            if (!difference[32]) begin
                remainder<=difference[31:0];
                quotient<={quotient[30:0],1'b1};
            end else begin
                remainder<=trial[31:0];quotient<={quotient[30:0],1'b0};
            end
            if(count==0) begin busy<=0;done<=1;end
            else count<=count-1'b1;
        end
    end
end
endmodule
