`timescale 1ns/1ps
// 128-point windowed DFT, bins 1..32; real sampled H11 digital drive.
// Fs = 25 MHz / 1563 = 15994.88 Hz; bin spacing = 124.96 Hz.
// One shared registered 18x18 multiplier, not 32 parallel FFT engines.
// RAM is overwritten on sample zero, so uninitialized RAM is never consumed.
module audio_spectrum32 #(
    parameter integer SAMPLE_DIV = 1563, parameter integer USE_PCM=0
)(
    input wire clk, input wire rst,
    input wire buzzer_n, input wire audio_active,
    input wire signed [15:0] pcm_sample,
    output reg [191:0] levels,
    output reg result_active,
    output reg result_valid,
    output reg sample_overrun
);
reg [2:0] buz_sync, active_sync;
reg [15:0] sample_count;
wire sample_tick = sample_count == SAMPLE_DIV-1;
reg [6:0] sample_index, phase;
reg [4:0] bin_index;
reg signed [6:0] held_sample;
wire signed [11:0] pcm_windowed=$signed(pcm_sample[15:10])*$signed({1'b0,hann(sample_index)});
reg signed [23:0] real_mem [0:31];
reg signed [23:0] imag_mem [0:31];
reg signed [23:0] real_acc, imag_acc, next_real;
reg signed [17:0] mul_a, mul_b, imag_component;
reg signed [35:0] product;
reg [35:0] real_power;
wire [36:0] power_sum = {1'b0,real_power} + {1'b0,product};
reg [191:0] pending_levels;
reg window_active;
reg [3:0] state;
localparam WAIT_SAMPLE=0, READ_BIN=1, WAIT_REAL=2, ADD_REAL=3,
           WAIT_IMAG=4, ADD_IMAG=5, POWER_READ=6, POWER_WAIT_REAL=7,
           POWER_REAL=8, POWER_WAIT_IMAG=9, POWER_IMAG=10, PUBLISH=11;

function [10:0] quarter_sine;
    input [5:0] address;
    begin
        case(address)
                        6'd0:quarter_sine=11'd0;
            6'd1:quarter_sine=11'd50;
            6'd2:quarter_sine=11'd100;
            6'd3:quarter_sine=11'd150;
            6'd4:quarter_sine=11'd200;
            6'd5:quarter_sine=11'd249;
            6'd6:quarter_sine=11'd297;
            6'd7:quarter_sine=11'd345;
            6'd8:quarter_sine=11'd392;
            6'd9:quarter_sine=11'd438;
            6'd10:quarter_sine=11'd483;
            6'd11:quarter_sine=11'd526;
            6'd12:quarter_sine=11'd569;
            6'd13:quarter_sine=11'd610;
            6'd14:quarter_sine=11'd650;
            6'd15:quarter_sine=11'd688;
            6'd16:quarter_sine=11'd724;
            6'd17:quarter_sine=11'd759;
            6'd18:quarter_sine=11'd792;
            6'd19:quarter_sine=11'd822;
            6'd20:quarter_sine=11'd851;
            6'd21:quarter_sine=11'd878;
            6'd22:quarter_sine=11'd903;
            6'd23:quarter_sine=11'd926;
            6'd24:quarter_sine=11'd946;
            6'd25:quarter_sine=11'd964;
            6'd26:quarter_sine=11'd980;
            6'd27:quarter_sine=11'd993;
            6'd28:quarter_sine=11'd1004;
            6'd29:quarter_sine=11'd1013;
            6'd30:quarter_sine=11'd1019;
            6'd31:quarter_sine=11'd1023;
            6'd32:quarter_sine=11'd1024;
            default:quarter_sine=0;
        endcase
    end
endfunction
function signed [11:0] sine;
    input [6:0] angle;
    reg [5:0] address;
    reg signed [11:0] magnitude;
    begin
        address=angle[5] ? (6'd32-{1'b0,angle[4:0]}) : {1'b0,angle[4:0]};
        magnitude=$signed({1'b0,quarter_sine(address)});
        sine=angle[6] ? -magnitude : magnitude;
    end
endfunction
function [4:0] hann;
    input [6:0] sample;
    reg [5:0] address;
    begin
        address=sample[6] ? 7'd127-sample : sample[5:0];
        case(address)
                        6'd0:hann=5'd0;
            6'd1:hann=5'd0;
            6'd2:hann=5'd0;
            6'd3:hann=5'd0;
            6'd4:hann=5'd0;
            6'd5:hann=5'd0;
            6'd6:hann=5'd1;
            6'd7:hann=5'd1;
            6'd8:hann=5'd1;
            6'd9:hann=5'd2;
            6'd10:hann=5'd2;
            6'd11:hann=5'd2;
            6'd12:hann=5'd3;
            6'd13:hann=5'd3;
            6'd14:hann=5'd4;
            6'd15:hann=5'd4;
            6'd16:hann=5'd5;
            6'd17:hann=5'd5;
            6'd18:hann=5'd6;
            6'd19:hann=5'd6;
            6'd20:hann=5'd7;
            6'd21:hann=5'd8;
            6'd22:hann=5'd8;
            6'd23:hann=5'd9;
            6'd24:hann=5'd10;
            6'd25:hann=5'd10;
            6'd26:hann=5'd11;
            6'd27:hann=5'd12;
            6'd28:hann=5'd13;
            6'd29:hann=5'd13;
            6'd30:hann=5'd14;
            6'd31:hann=5'd15;
            6'd32:hann=5'd16;
            6'd33:hann=5'd16;
            6'd34:hann=5'd17;
            6'd35:hann=5'd18;
            6'd36:hann=5'd19;
            6'd37:hann=5'd19;
            6'd38:hann=5'd20;
            6'd39:hann=5'd21;
            6'd40:hann=5'd22;
            6'd41:hann=5'd22;
            6'd42:hann=5'd23;
            6'd43:hann=5'd24;
            6'd44:hann=5'd24;
            6'd45:hann=5'd25;
            6'd46:hann=5'd26;
            6'd47:hann=5'd26;
            6'd48:hann=5'd27;
            6'd49:hann=5'd27;
            6'd50:hann=5'd28;
            6'd51:hann=5'd28;
            6'd52:hann=5'd29;
            6'd53:hann=5'd29;
            6'd54:hann=5'd29;
            6'd55:hann=5'd30;
            6'd56:hann=5'd30;
            6'd57:hann=5'd30;
            6'd58:hann=5'd30;
            6'd59:hann=5'd31;
            6'd60:hann=5'd31;
            6'd61:hann=5'd31;
            6'd62:hann=5'd31;
            6'd63:hann=5'd31;
            default:hann=0;
        endcase
    end
endfunction
// Log power maps a useful dynamic range into 0..44 pixels, with a noise gate.
function [5:0] power_to_width;
    input [36:0] energy;
    integer bit_index,highest,width;
    begin
        highest=0;
        for(bit_index=0;bit_index<37;bit_index=bit_index+1)
            if(energy[bit_index])highest=bit_index;
        width=(highest-10)*3;
        if(energy<37'd2048)power_to_width=0;
        else if(width>44)power_to_width=44;
        else power_to_width=width;
    end
endfunction

// Only one multiplication expression, reused for DFT and squared magnitude.
always @(posedge clk) product <= mul_a * mul_b;
always @(posedge clk or posedge rst) begin
    if(rst)begin
        buz_sync<=3'b111;active_sync<=0;sample_count<=0;
        sample_index<=0;phase<=0;bin_index<=0;held_sample<=0;
        real_acc<=0;imag_acc<=0;next_real<=0;mul_a<=0;mul_b<=0;
        imag_component<=0;real_power<=0;pending_levels<=0;
        levels<=0;result_active<=0;window_active<=0;result_valid<=0;sample_overrun<=0;state<=WAIT_SAMPLE;
    end else begin
        buz_sync<={buz_sync[1:0],buzzer_n};
        active_sync<={active_sync[1:0],audio_active};
        result_valid<=0;
        if(sample_tick)begin
            sample_count<=0;
            if(state!=WAIT_SAMPLE)sample_overrun<=1;
        end else sample_count<=sample_count+1'b1;
        case(state)
            WAIT_SAMPLE:if(sample_tick)begin
                window_active<=window_active || active_sync[2];
                if(USE_PCM)held_sample<=pcm_windowed >>> 5;
                else if(!active_sync[2])held_sample<=0;
                else if(!buz_sync[2])held_sample<=$signed({2'b00,hann(sample_index)});
                else held_sample<=-$signed({2'b00,hann(sample_index)});
                bin_index<=0;phase<=sample_index;state<=READ_BIN;
            end
            READ_BIN:begin
                real_acc<=sample_index==0 ? 24'sd0 : real_mem[bin_index];
                imag_acc<=sample_index==0 ? 24'sd0 : imag_mem[bin_index];
                mul_a<=held_sample;mul_b<=sine(phase+7'd32);
                state<=WAIT_REAL;
            end
            WAIT_REAL:state<=ADD_REAL;
            ADD_REAL:begin
                next_real<=real_acc+product;
                mul_b<=-sine(phase);state<=WAIT_IMAG;
            end
            WAIT_IMAG:state<=ADD_IMAG;
            ADD_IMAG:begin
                real_mem[bin_index]<=next_real;
                imag_mem[bin_index]<=imag_acc+product;
                if(bin_index==31)begin
                    if(sample_index==127)begin bin_index<=0;state<=POWER_READ;end
                    else begin sample_index<=sample_index+1'b1;state<=WAIT_SAMPLE;end
                end else begin
                    bin_index<=bin_index+1'b1;phase<=phase+sample_index;state<=READ_BIN;
                end
            end
            POWER_READ:begin
                // Max scaled component < 16k; signed 18 bits leaves margin.
                mul_a<=$signed(real_mem[bin_index]) >>> 8;
                mul_b<=$signed(real_mem[bin_index]) >>> 8;
                imag_component<=$signed(imag_mem[bin_index]) >>> 8;
                state<=POWER_WAIT_REAL;
            end
            POWER_WAIT_REAL:state<=POWER_REAL;
            POWER_REAL:begin
                real_power<=product;mul_a<=imag_component;mul_b<=imag_component;
                state<=POWER_WAIT_IMAG;
            end
            POWER_WAIT_IMAG:state<=POWER_IMAG;
            POWER_IMAG:begin
                pending_levels[bin_index*6 +: 6]<=power_to_width(power_sum);
                if(bin_index==31)state<=PUBLISH;
                else begin bin_index<=bin_index+1'b1;state<=POWER_READ;end
            end
            PUBLISH:begin
                levels<=pending_levels;result_valid<=1;
                result_active<=window_active;window_active<=0;
                sample_index<=0;state<=WAIT_SAMPLE;
            end
            default:state<=WAIT_SAMPLE;
        endcase
    end
end
endmodule
