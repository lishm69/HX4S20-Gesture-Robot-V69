
module video_rgb_to_axis_640x480(
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,

    output reg         O_video_user,
    output reg         O_video_valid,
    output reg         O_video_last,
    output reg  [23:0] O_video_data
);

// One clock of latency; VS changes arm SOF, DE rising identifies a row.
reg vs_previous, de_previous, frame_pending;
reg [10:0] column;
wire row_start = I_de && !de_previous;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        vs_previous<=0; de_previous<=0; frame_pending<=1; column<=0;
        O_video_user<=0; O_video_valid<=0; O_video_last<=0; O_video_data<=0;
    end else begin
        vs_previous<=I_vs; de_previous<=I_de;
        O_video_valid<=I_de; O_video_data<=I_rgb;
        O_video_user<=row_start && frame_pending;
        O_video_last<=I_de && column==11'd639;
        column<=!I_de ? 11'd0 : row_start ? 11'd1 : column+1'b1;
        if (row_start && frame_pending) frame_pending<=0;
        else if (vs_previous!=I_vs) frame_pending<=1;
    end
end
endmodule
