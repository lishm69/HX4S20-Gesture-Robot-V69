`timescale 1ns/1ps
// Monophonic conversion of the visible vocal melody on the user-supplied page.
// SW5 is outside the FPGA: it only physically connects the H11 output.
module buzzer_daoxiang #(
    parameter integer CLK_HZ=50_000_000
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
localparam integer BPM=82;
localparam integer EVENT_COUNT=111;
// Use 64-bit constant arithmetic: 50,000,000 * 60 exceeds signed 32-bit range.
localparam [63:0] TICK_WIDE=(64'd60*CLK_HZ)/(BPM*8);
localparam integer TICK_CYCLES=TICK_WIDE;
localparam integer TICK_W=bits_for(TICK_CYCLES);
localparam integer GAP_CYCLES=CLK_HZ/125; // eight milliseconds, inside note time
localparam [1:0] ADDRESS=0,FETCH=1,PLAY=2;
reg [1:0] state;
reg [6:0] event_index;
wire [25:0] rom_data;
reg [16:0] half_period,half_count;
reg [7:0] duration_ticks,elapsed_ticks;
reg [TICK_W-1:0] tick_count;
reg end_gap,square;
wire gap_now=end_gap && elapsed_ticks==duration_ticks-1 &&
             tick_count>=TICK_CYCLES-GAP_CYCLES;
wire tone_on=state==PLAY && half_period!=0 && !gap_now;
assign buzzer_n=rst || !tone_on ? 1'b1 : ~square;
daoxiang_score_rom #(.CLK_HZ(CLK_HZ)) u_score(.clk(clk),.address(event_index),.data(rom_data));
always @(posedge clk or posedge rst) begin
    if(rst)begin
        state<=ADDRESS;event_index<=0;half_period<=0;half_count<=0;
        duration_ticks<=1;elapsed_ticks<=0;tick_count<=0;end_gap<=0;square<=0;
    end else begin
        case(state)
            ADDRESS:state<=FETCH;
            FETCH:begin
                end_gap<=rom_data[25];duration_ticks<=rom_data[24:17];half_period<=rom_data[16:0];
                elapsed_ticks<=0;tick_count<=0;half_count<=0;square<=0;state<=PLAY;
            end
            PLAY:begin
                if(tick_count==TICK_CYCLES-1)begin
                    tick_count<=0;
                    if(elapsed_ticks==duration_ticks-1)begin
                        event_index<=event_index==EVENT_COUNT-1 ? 7'd0 : event_index+1'b1;
                        state<=ADDRESS;elapsed_ticks<=0;
                    end else elapsed_ticks<=elapsed_ticks+1'b1;
                end else tick_count<=tick_count+1'b1;
            end
            default:begin state<=ADDRESS;event_index<=0;half_period<=0;end
        endcase
        if(!tone_on)begin half_count<=0;square<=0;end
        else if(half_count==half_period-1)begin half_count<=0;square<=~square;end
        else half_count<=half_count+1'b1;
    end
end
endmodule
