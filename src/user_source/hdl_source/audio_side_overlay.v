`timescale 1ns/1ps
// Two vertical ribbons of 32 HORIZONTAL inward-growing bars.
// x = 10..53 and 586..629; y = TOP_Y..TOP_Y+319, four rows per ten pixels; transparent gaps.
// Low frequencies at bottom; same spectrum mirrored, not stereo channels.
// Frame-atomic height smoothing and enable; exactly two pixel-clock latency.
module audio_side_overlay #(
    parameter integer TOP_Y=108,parameter integer SAMPLE_DIV=1563, parameter integer USE_PCM=0
)(
    input wire clk, input wire rst,
    input wire buzzer_n, input wire audio_active,
    input wire signed [15:0] pcm_sample, input wire enable,
    input wire [23:0] rgb_in, input wire vs_in, input wire de_in,
    output reg [23:0] rgb_out, output reg vs_out, output reg de_out
);
wire [191:0] spectrum_levels;
wire spectrum_valid,sample_overrun,spectrum_active;
audio_spectrum32 #(.SAMPLE_DIV(SAMPLE_DIV),.USE_PCM(USE_PCM)) u_spectrum(
    .clk(clk),.rst(rst),.buzzer_n(buzzer_n),.audio_active(audio_active),.pcm_sample(pcm_sample),
    .levels(spectrum_levels),.result_active(spectrum_active),.result_valid(spectrum_valid),.sample_overrun(sample_overrun)
);
reg vs_d,de_d,show_frame;
reg [11:0] next_x,line_y;
wire frame_tick=vs_d && !vs_in;
wire [11:0] pixel_x=de_d ? next_x : 12'd0;
reg [4:0] lane_index;
reg [3:0] lane_phase;
reg [5:0] display_width [0:31];
reg [5:0] peak_width [0:31];
reg [3:0] peak_hold [0:31];
reg [5:0] next_width;
// Snapshot at VS and share one smoothing/peak datapath across all 32 lanes.
// 32 clocks are well inside the vertical blank, before any visible pixel.
reg [191:0] levels_snapshot;
reg active_snapshot,update_busy;
reg [4:0] update_index;
wire [5:0] selected_energy=(levels_snapshot>>(update_index*6));
integer i;
// An 8-pixel resting ribbon while a tone plays keeps the enclosing shape.
// Only the extension encodes energy; rests release all the way to zero.
function [5:0] ribbon_target;
    input [5:0] energy_width;
    input playing;
    begin
        if(!playing)ribbon_target=0;
        else if(energy_width>36)ribbon_target=44;
        else ribbon_target=energy_width+6'd8;
    end
endfunction
function [5:0] approach;
    input [5:0] current,target;
    reg [6:0] delta;
    begin
        if(target>current)begin delta=target-current;approach=current+((delta+1'b1)>>1);end
        else if(current>target+7'd2)approach=current-2;
        else approach=target;
    end
endfunction
always @(posedge clk or posedge rst)begin
    if(rst)begin
        vs_d<=0;de_d<=0;show_frame<=0;next_x<=0;line_y<=0;
        lane_index<=0;lane_phase<=0;levels_snapshot<=0;active_snapshot<=0;update_busy<=0;update_index<=0;
        for(i=0;i<32;i=i+1)begin display_width[i]<=0;peak_width[i]<=0;peak_hold[i]<=0;end
    end else begin
        vs_d<=vs_in;de_d<=de_in;
        if(update_busy)begin
            next_width=approach(display_width[update_index],ribbon_target(selected_energy,active_snapshot));
            display_width[update_index]<=next_width;
            if(next_width>=peak_width[update_index])begin peak_width[update_index]<=next_width;peak_hold[update_index]<=12;end
            else if(peak_hold[update_index]!=0)peak_hold[update_index]<=peak_hold[update_index]-1'b1;
            else if(peak_width[update_index]!=0)peak_width[update_index]<=peak_width[update_index]-1'b1;
            if(update_index==31)update_busy<=0;else update_index<=update_index+1'b1;
        end
        if(frame_tick)begin
            next_x<=0;line_y<=0;lane_index<=0;lane_phase<=0;show_frame<=enable;
            levels_snapshot<=spectrum_levels;active_snapshot<=spectrum_active;
            update_busy<=1;update_index<=0;
        end else begin
            if(de_in)next_x<=pixel_x+1'b1;else next_x<=0;
            if(de_d && !de_in)begin
                line_y<=line_y+1'b1;
                if(line_y==TOP_Y-1)begin lane_index<=0;lane_phase<=0;end
                else if(line_y>=TOP_Y && line_y<TOP_Y+320)begin
                    if(lane_phase==9)begin lane_phase<=0;lane_index<=lane_index+1'b1;end
                    else lane_phase<=lane_phase+1'b1;
                end
            end
        end
    end
end
// Mirror distances: left x=10+d, right x=629-d. Exclude all other pixels.
wire side=(pixel_x>=10 && pixel_x<54) || (pixel_x>=586 && pixel_x<630);
wire [5:0] distance_in=pixel_x<320 ? pixel_x-12'd10 : 12'd629-pixel_x;

reg [23:0] rgb_s1;
reg vs_s1,de_s1,bar_row_s1,show_s1,cap_row_s1;
reg [5:0] distance_s1,width_s1,peak_s1;
wire bar_hit=show_s1 && bar_row_s1 && distance_s1<width_s1 &&
 (cap_row_s1 || (distance_s1!=0 && distance_s1+1<width_s1));
wire peak_hit=show_s1 && bar_row_s1 && peak_s1>width_s1+2 &&
 (distance_s1+1==peak_s1 || distance_s1+2==peak_s1);
function [23:0] gradient;
 input [3:0] step;
 begin case(step)
 0:gradient=24'h16d9f4;1:gradient=24'h24cff5;2:gradient=24'h32c5f6;
 3:gradient=24'h40bbf7;4:gradient=24'h4eb1f8;5:gradient=24'h5ca7f9;
 6:gradient=24'h6a9dfa;7:gradient=24'h7893fb;8:gradient=24'h8689fc;
 9:gradient=24'h947ffd;default:gradient=24'ha275ff;
 endcase end
endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin
  rgb_s1<=0;vs_s1<=0;de_s1<=0;bar_row_s1<=0;show_s1<=0;
  cap_row_s1<=0;distance_s1<=0;width_s1<=0;peak_s1<=0;
  rgb_out<=0;vs_out<=0;de_out<=0;
 end else begin
  rgb_s1<=rgb_in;vs_s1<=vs_in;de_s1<=de_in;
  show_s1<=show_frame;distance_s1<=distance_in;
  width_s1<=display_width[5'd31-lane_index];peak_s1<=peak_width[5'd31-lane_index];
  bar_row_s1<=de_in && side && line_y>=TOP_Y && line_y<TOP_Y+320 && lane_phase>=3 && lane_phase<=6;
  cap_row_s1<=lane_phase==4 || lane_phase==5;
  vs_out<=vs_s1;de_out<=de_s1;
  if(!de_s1)rgb_out<=0;
  else if(peak_hit)rgb_out<=24'he0c4ff;
  else if(bar_hit)rgb_out<=gradient(distance_s1[5:2]);
  // Transparent background: preserve the original pixel outside bar/peak ink.
  else rgb_out<=rgb_s1;
 end
end
endmodule
