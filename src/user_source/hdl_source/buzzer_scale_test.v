`timescale 1ns/1ps
// Independent public-domain C-major scale, not a recording or melody from
// any commercial song. SW5 is a physical connection outside the FPGA.
// Low BUZZER activates the board transistor; high is silent.
module buzzer_scale_test #(
    parameter integer CLK_HZ = 50_000_000
)(
    input wire clk,
    input wire rst,
    output wire buzzer_n
);
function integer bits_for;
    input integer value;
    integer t;
    begin
        bits_for=0;
        for(t=value-1;t>0;t=t>>1)bits_for=bits_for+1;
        if(bits_for<1)bits_for=1;
    end
endfunction
localparam integer TICK_CYCLES = CLK_HZ/20; // 50 ms
localparam integer TICK_W = bits_for(TICK_CYCLES);
localparam integer DIV_W = bits_for(CLK_HZ/(2*523)+1);
reg [TICK_W-1:0] tick_count;
reg [DIV_W-1:0] half_count;
reg [3:0] note_index;
reg [2:0] note_tick;
reg square;
wire tone_on = note_index<8 && note_tick<5;
reg [DIV_W-1:0] half_period;
always @* begin
    case(note_index)
        0:half_period=CLK_HZ/(2*523);  // C5
        1:half_period=CLK_HZ/(2*587);  // D5
        2:half_period=CLK_HZ/(2*659);  // E5
        3:half_period=CLK_HZ/(2*698);  // F5
        4:half_period=CLK_HZ/(2*784);  // G5
        5:half_period=CLK_HZ/(2*880);  // A5
        6:half_period=CLK_HZ/(2*988);  // B5
        7:half_period=CLK_HZ/(2*1047); // C6
        default:half_period=CLK_HZ/(2*523);
    endcase
end
assign buzzer_n = rst || !tone_on ? 1'b1 : ~square;
always @(posedge clk or posedge rst) begin
    if(rst)begin
        tick_count<=0;note_tick<=0;note_index<=0;
        half_count<=0;square<=0;
    end else begin
        if(tick_count==TICK_CYCLES-1)begin
            tick_count<=0;
            if(note_tick==5)begin
                note_tick<=0;
                note_index<=note_index==8 ? 4'd0 : note_index+1'b1;
            end else note_tick<=note_tick+1'b1;
        end else tick_count<=tick_count+1'b1;
        if(!tone_on)begin half_count<=0;square<=0;end
        else if(half_count==half_period-1)begin half_count<=0;square<=~square;end
        else half_count<=half_count+1'b1;
    end
end
endmodule
