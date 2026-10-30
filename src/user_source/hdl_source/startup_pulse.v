// One-shot startup delay. Counter width and CNT_MAX edge cases match the source.
module startup_pulse #(parameter [19:0] CNT_MAX=20'd100000)(
    input I_clk, I_rst, output reg O_pulse
);
reg [19:0] count;
reg done;
wire terminal_count=count==CNT_MAX-1'b1;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin count<=0; done<=0; O_pulse<=0; end
    else begin
        O_pulse<=!done && terminal_count;
        if (!done) begin
            if (terminal_count) done<=1;
            else count<=count+1'b1;
        end
    end
end
endmodule
