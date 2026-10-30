`timescale 1ns/1ps
// 800/1200Hz alternating every 0.5s. Active-low board transistor output.
module alarm_siren #(parameter integer CLK_HZ=50000000)(
    input wire clk,input wire rst,input wire enable,output wire buzzer_n
);
reg [25:0] cadence;
reg [15:0] tone_count;
reg high_tone,tone;
wire [15:0] half_period=high_tone ? CLK_HZ/2400-1 : CLK_HZ/1600-1;
always @(posedge clk or posedge rst)begin
    if(rst)begin cadence<=0;tone_count<=0;high_tone<=0;tone<=0;end
    else if(!enable)begin cadence<=0;tone_count<=0;high_tone<=0;tone<=0;end
    else begin
        if(cadence==CLK_HZ/2-1)begin cadence<=0;high_tone<=~high_tone;tone_count<=0;end
        else begin
            cadence<=cadence+1'b1;
            if(tone_count>=half_period)begin tone_count<=0;tone<=~tone;end
            else tone_count<=tone_count+1'b1;
        end
    end
end
assign buzzer_n=enable ? ~tone : 1'b1;
endmodule
