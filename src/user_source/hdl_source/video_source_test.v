// Refactored from the supplied official example; port timing is unchanged.
module video_source_test #(
    parameter HTOTAL=2200, HACTIVE=1920, HFP=88, HSA=44, HBP=148,
    parameter VTOTAL=1125, VACTIVE=1080, VFP=4, VSA=5, VBP=36
)(
    input I_clk, I_rst, I_tpg_trig_en,
    output reg O_video_user, O_video_valid, O_video_last,
    output wire [23:0] O_video_data, input I_video_ready
);
localparam VBLANK=VTOTAL-VACTIVE, HBLANK=HTOTAL-HACTIVE;
reg running;
reg [13:0] column, line;
reg [7:0] ramp;
wire line_end = column==HTOTAL-1;
wire visible = line>=VBLANK && column>=HBLANK;
// Like the reference, this free-running source does not use I_video_ready.
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) running<=0;
    else if (I_tpg_trig_en) running<=1;
end
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        column<=0; line<=0;
        O_video_user<=0; O_video_valid<=0; O_video_last<=0;
    end else if (!running) begin
        column<=0; line<=0;
        O_video_user<=0; O_video_valid<=0; O_video_last<=0;
    end else begin
        column<=line_end ? 14'd0 : column+1'b1;
        if (line_end) line<=line==VTOTAL-1 ? 14'd0 : line+1'b1;
        O_video_valid<=visible;
        O_video_user<=line==VBLANK && column==HBLANK;
        O_video_last<=line>=VBLANK && line_end;
    end
end
always @(posedge I_clk)
    ramp<=O_video_valid ? ramp+1'b1 : 8'd0;
assign O_video_data={16'd0,ramp};
endmodule
