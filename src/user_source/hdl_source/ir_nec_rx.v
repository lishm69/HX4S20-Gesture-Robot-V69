`timescale 1ns/1ps
// Demodulated active-low NEC receiver, normal and extended address formats.
// Single clock, 1-us clock enable; input is synchronized and glitch filtered.
// A frame is published only after its final mark AND command complement pass.
module ir_nec_rx #(
    parameter integer CLK_HZ=25000000,
    parameter integer FILTER_CYCLES=8
)(
    input wire clk, input wire rst, input wire ir_rx,
    output reg frame_valid, output reg repeat_valid,
    output reg [15:0] address, output reg [7:0] command
);
localparam integer US_DIV=CLK_HZ/1000000;
localparam IDLE=0,HEADER_MARK=1,HEADER_SPACE=2,DATA_MARK=3,
           DATA_SPACE=4,TRAILER=5,REPEAT_MARK=6;
reg [1:0] ir_sync;
reg ir_filtered,ir_previous;
reg [7:0] filter_count;
reg [7:0] us_divider;
reg [13:0] duration_us;
reg [2:0] state;
reg [5:0] bit_count;
reg [31:0] shift_word;
wire edge_seen=(ir_filtered!=ir_previous);
wire rising=edge_seen && ir_filtered;
wire falling=edge_seen && !ir_filtered;
always @(posedge clk or posedge rst)begin
    if(rst)begin
        ir_sync<=2'b11;ir_filtered<=1;ir_previous<=1;filter_count<=0;
        us_divider<=0;duration_us<=0;state<=IDLE;bit_count<=0;shift_word<=0;
        frame_valid<=0;repeat_valid<=0;address<=0;command<=0;
    end else begin
        ir_sync<={ir_sync[0],ir_rx};ir_previous<=ir_filtered;
        if(ir_sync[1]==ir_filtered)filter_count<=0;
        else if(filter_count==FILTER_CYCLES-1)begin
            ir_filtered<=ir_sync[1];filter_count<=0;
        end else filter_count<=filter_count+1'b1;
        frame_valid<=0;repeat_valid<=0;
        if(us_divider==US_DIV-1)begin
            us_divider<=0;
            if(duration_us<14'd16000)duration_us<=duration_us+1'b1;
        end else us_divider<=us_divider+1'b1;
        if(edge_seen)begin duration_us<=0;us_divider<=0;end
        if(state!=IDLE && duration_us>=14'd12000)state<=IDLE;
        else case(state)
            IDLE:if(falling)state<=HEADER_MARK;
            HEADER_MARK:if(rising)begin
                if(duration_us>=8000 && duration_us<=10000)state<=HEADER_SPACE;
                else state<=IDLE;
            end
            HEADER_SPACE:if(falling)begin
                if(duration_us>=3500 && duration_us<=5500)begin
                    state<=DATA_MARK;bit_count<=0;shift_word<=0;
                end else if(duration_us>=1700 && duration_us<=2800)state<=REPEAT_MARK;
                else state<=IDLE;
            end
            DATA_MARK:if(rising)begin
                if(duration_us>=350 && duration_us<=800)state<=DATA_SPACE;
                else state<=IDLE;
            end
            DATA_SPACE:if(falling)begin
                if((duration_us>=350 && duration_us<=900) ||
                   (duration_us>=1200 && duration_us<=2100))begin
                    // NEC sends each byte least significant bit first.
                    shift_word<={(duration_us>=1200),shift_word[31:1]};
                    if(bit_count==31)state<=TRAILER;
                    else begin bit_count<=bit_count+1'b1;state<=DATA_MARK;end
                end else state<=IDLE;
            end
            TRAILER:if(rising)begin
                if(duration_us>=350 && duration_us<=800 &&
                   (shift_word[23:16]^shift_word[31:24])==8'hff)begin
                    address<=shift_word[15:0];command<=shift_word[23:16];frame_valid<=1;
                end
                state<=IDLE;
            end
            REPEAT_MARK:if(rising)begin
                if(duration_us>=350 && duration_us<=800)repeat_valid<=1;
                state<=IDLE;
            end
            default:state<=IDLE;
        endcase
    end
end
endmodule
