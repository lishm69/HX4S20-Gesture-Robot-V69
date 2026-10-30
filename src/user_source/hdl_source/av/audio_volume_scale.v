`timescale 1ns/1ps
// Exact signed attenuation: 0=mute, 16=unity. One clock of PCM/valid latency.
// Alarm bypass preserves the existing alarm/mute semantics at every volume.
module audio_volume_scale(input wire clk,rst,input wire [4:0] level,
 input wire alarm_active,input wire valid_in,input wire signed [23:0] pcm_in,
 output reg valid_out,output reg signed [23:0] pcm_out);
wire signed [29:0] product=pcm_in*$signed({1'b0,level});
always @(posedge clk or posedge rst)begin
 if(rst)begin valid_out<=0;pcm_out<=0;end
 else begin
  valid_out<=valid_in;
  if(valid_in)pcm_out<=alarm_active ? pcm_in : (product >>> 4);
 end
end
endmodule
