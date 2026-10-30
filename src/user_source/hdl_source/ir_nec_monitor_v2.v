`timescale 1ns/1ps
// Production receiver derived from the board-tested IR KEY TEST V2. Strict standard NEC.
// All outputs are synchronous to clk. raw_bytes are A,~A,C,~C in transmission
// byte order, each byte restored LSB-first. The screen also shows legacy bytes.
module ir_nec_monitor_v2 #(
    parameter integer CLK_HZ=25000000, FILTER_CYCLES=8
)(
    input wire clk,input wire rst,input wire ir_rx,
    output wire rx_level,output reg [31:0] edge_count,
    output reg [15:0] good_count,repeat_count,bad_count,orphan_count,
    output reg [3:0] bad_stage,output reg [13:0] bad_us,
    output reg [31:0] raw_bytes,output reg last_ok,output reg frame_valid,output reg repeat_valid,output reg frame_error,
    output reg [2:0] captured,
    output reg [31:0] capture1,capture2,capture3,capture4
);
localparam integer US_DIV=CLK_HZ/1000000;
localparam IDLE=0,HEAD_LOW=1,HEAD_HIGH=2,BIT_LOW=3,BIT_HIGH=4,TAIL=5,REP_LOW=6;
reg [1:0] rx_sync;
reg filtered,previous;
reg [7:0] filter_count,divider;
reg [13:0] duration_us;
reg [17:0] age_us;
reg cache_valid;
reg [2:0] state;
reg [5:0] bit_index;
reg [31:0] word_bits;
wire changed=(filtered!=previous);
wire rising=changed && filtered;
wire falling=changed && !filtered;
wire [31:0] received={word_bits[7:0],word_bits[15:8],word_bits[23:16],word_bits[31:24]};
wire check_ok=((word_bits[7:0]^word_bits[15:8])==8'hff) &&
              ((word_bits[23:16]^word_bits[31:24])==8'hff);
wire unseen=(captured==0 || received!=capture1) &&
            (captured<2 || received!=capture2) &&
            (captured<3 || received!=capture3) &&
            (captured<4 || received!=capture4);
assign rx_level=filtered;
task fail_frame;
    input [3:0] code;
    begin
        if(bad_count!=16'hffff)bad_count<=bad_count+1'b1;
        frame_error<=1;bad_stage<=code;bad_us<=duration_us;state<=IDLE;cache_valid<=0;
    end
endtask
always @(posedge clk or posedge rst)begin
    if(rst)begin
        rx_sync<=3;filtered<=1;previous<=1;filter_count<=0;divider<=0;
        duration_us<=0;age_us<=200001;cache_valid<=0;state<=IDLE;bit_index<=0;word_bits<=0;
        edge_count<=0;good_count<=0;repeat_count<=0;bad_count<=0;orphan_count<=0;
        bad_stage<=0;bad_us<=0;raw_bytes<=0;last_ok<=0;frame_valid<=0;repeat_valid<=0;frame_error<=0;
        captured<=0;capture1<=0;capture2<=0;capture3<=0;capture4<=0;
    end else begin
        rx_sync<={rx_sync[0],ir_rx};previous<=filtered;frame_valid<=0;repeat_valid<=0;frame_error<=0;
        if(rx_sync[1]==filtered)filter_count<=0;
        else if(filter_count==FILTER_CYCLES-1)begin filtered<=rx_sync[1];filter_count<=0;end
        else filter_count<=filter_count+1'b1;
        if(divider==US_DIV-1)begin
            divider<=0;
            if(duration_us<16000)duration_us<=duration_us+1'b1;
            if(age_us<200001)age_us<=age_us+1'b1;
        end else divider<=divider+1'b1;
        if(changed)begin
            duration_us<=0;divider<=0;
            if(edge_count!=32'hffffffff)edge_count<=edge_count+1'b1;
        end
        if(state!=IDLE && duration_us>=12000)fail_frame(4'd7);
        else case(state)
            IDLE:if(falling)state<=HEAD_LOW;
            HEAD_LOW:if(rising)begin
                if(duration_us>=8000 && duration_us<=10000)state<=HEAD_HIGH;
                else fail_frame(4'd1);
            end
            HEAD_HIGH:if(falling)begin
                if(duration_us>=3500 && duration_us<=5500)begin
                    state<=BIT_LOW;bit_index<=0;word_bits<=0;
                end else if(duration_us>=1700 && duration_us<=2800)state<=REP_LOW;
                else fail_frame(4'd2);
            end
            BIT_LOW:if(rising)begin
                if(duration_us>=350 && duration_us<=850)state<=BIT_HIGH;
                else fail_frame(4'd3);
            end
            BIT_HIGH:if(falling)begin
                if((duration_us>=350 && duration_us<=900) ||
                   (duration_us>=1200 && duration_us<=2100))begin
                    word_bits<={(duration_us>=1200),word_bits[31:1]};
                    if(bit_index==31)state<=TAIL;
                    else begin bit_index<=bit_index+1'b1;state<=BIT_LOW;end
                end else fail_frame(4'd4);
            end
            TAIL:if(rising)begin
                raw_bytes<=received;last_ok<=0;
                if(duration_us>=350 && duration_us<=850)begin
                    if(check_ok)begin
                        if(good_count!=16'hffff)good_count<=good_count+1'b1;
                        frame_valid<=1;last_ok<=1;cache_valid<=1;age_us<=0;state<=IDLE;
                        if(captured<4 && unseen)begin
                            case(captured)
                                0:capture1<=received;
                                1:capture2<=received;
                                2:capture3<=received;
                                3:capture4<=received;
                            endcase
                            captured<=captured+1'b1;
                        end
                    end else fail_frame(4'd6);
                end else fail_frame(4'd5);
            end
            REP_LOW:if(rising)begin
                if(duration_us>=350 && duration_us<=850)begin
                    if(cache_valid && age_us<=200000)begin
                        if(repeat_count!=16'hffff)repeat_count<=repeat_count+1'b1;
                        age_us<=0;repeat_valid<=1;
                    end else if(orphan_count!=16'hffff)orphan_count<=orphan_count+1'b1;
                    state<=IDLE;
                end else fail_frame(4'd5);
            end
            default:state<=IDLE;
        endcase
    end
end
endmodule
