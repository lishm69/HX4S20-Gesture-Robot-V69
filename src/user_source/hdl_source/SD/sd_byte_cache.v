`timescale 1ns/1ps
// One complete sector is buffered before a consumer can read its bytes.
// req must remain asserted until valid, then drop for at least one clock.
module sd_byte_cache #(
    parameter integer TIMEOUT_CYCLES = 100000000
)(
    input wire clk, input wire rst,
    input wire req, input wire [31:0] sector, input wire [8:0] byte_index,
    output reg valid, output reg [7:0] data, output reg error,
    output reg sd_read, output reg [31:0] sd_addr,
    input wire [7:0] sd_data, input wire sd_valid, input wire sd_end
);
localparam IDLE=0,RECEIVE=1,GAP=2,FETCH=3,RETURN_BYTE=4,RELEASE=5;
reg [2:0] state;
reg [7:0] ram [0:511];
reg [8:0] index_latch;
reg [7:0] ram_q;
reg [9:0] byte_count;
reg [31:0] cached_sector,timer;
reg cached_valid;
reg [1:0] gap_count;
always @(posedge clk) begin
    if(state==RECEIVE && sd_valid && byte_count<512)
        ram[byte_count[8:0]]<=sd_data;
    ram_q<=ram[index_latch];
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=IDLE;valid<=0;data<=0;error<=0;sd_read<=0;sd_addr<=0;
        index_latch<=0;byte_count<=0;cached_sector<=0;cached_valid<=0;timer<=0;gap_count<=0;
    end else begin
        valid<=0;error<=0;
        case(state)
            IDLE: if(req) begin
                index_latch<=byte_index;
                if(cached_valid && cached_sector==sector) state<=FETCH;
                else begin
                    cached_valid<=0;sd_addr<=sector;sd_read<=1;
                    byte_count<=0;timer<=0;state<=RECEIVE;
                end
            end
            RECEIVE: begin
                if(sd_valid && byte_count<512) byte_count<=byte_count+1'b1;
                if(sd_end) begin
                    sd_read<=0;
                    if(byte_count==512 || (byte_count==511 && sd_valid)) begin
                        cached_valid<=1;cached_sector<=sd_addr;gap_count<=0;state<=GAP;
                    end else begin valid<=1;error<=1;state<=RELEASE;end
                end else if(timer>=TIMEOUT_CYCLES-1) begin
                    sd_read<=0;valid<=1;error<=1;state<=RELEASE;
                end else timer<=timer+1'b1;
            end
            GAP: begin
                if(gap_count==2) state<=FETCH;
                else gap_count<=gap_count+1'b1;
            end
            FETCH: state<=RETURN_BYTE;
            RETURN_BYTE: begin data<=ram_q;valid<=1;state<=RELEASE;end
            RELEASE: if(!req) state<=IDLE;
            default: state<=IDLE;
        endcase
    end
end
endmodule
