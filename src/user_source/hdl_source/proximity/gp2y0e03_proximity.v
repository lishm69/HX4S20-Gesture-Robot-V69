`timescale 1ns/1ps
// Fixed-point distance in 1/16 cm. No multiplier/divider or RAM required.
module gp2y0e03_proximity #(
 parameter integer CLK_HZ=50000000, BUS_HZ=100000, STARTUP_MS=50, POLL_MS=50,
 parameter integer ENTER_CM=20, EXIT_CM=25, CONFIRM_SAMPLES=3, FAIL_POLLS=10,
 parameter integer IR_QUIET_MS=100, I2C_TIMEOUT_CYCLES=500000,
 parameter integer GESTURE_MIN_MS=100, GESTURE_MAX_MS=700,
 parameter integer GESTURE_COVER_CM=12, GESTURE_RELEASE_CM=18,
 parameter integer GESTURE_RELEASE_SAMPLES=2
)(
 input clk,input rst,input ir_inhibit,
 inout scl,inout sda,output wire gpio1,
 output reg near_active,output reg sample_valid,output reg [11:0] distance_q4,
 output reg sensor_fault,output reg gesture_next
);
localparam integer START_C=CLK_HZ/1000*STARTUP_MS;
localparam integer POLL_C=CLK_HZ/1000*POLL_MS;
localparam integer QUIET_C=CLK_HZ/1000*IR_QUIET_MS;
localparam integer MAX_C=START_C>POLL_C?START_C:POLL_C;
localparam integer CB=$clog2(MAX_C+2), QB=$clog2(QUIET_C+2);
// Include the first sample: N+1 readings span at least N poll intervals.
localparam integer GESTURE_MIN_SAMPLES=(GESTURE_MIN_MS+POLL_MS-1)/POLL_MS+1;
localparam integer GESTURE_MAX_SAMPLES=(GESTURE_MAX_MS+POLL_MS-1)/POLL_MS+1;
localparam integer GB=$clog2(GESTURE_MAX_SAMPLES+2);
localparam integer RB=$clog2(GESTURE_RELEASE_SAMPLES+1);
localparam WAIT_POWER=0,WAIT_POLL=1,LAUNCH=2,WAIT_READ=3;
reg [1:0] state;reg [CB-1:0] wait_count;reg [QB-1:0] quiet_count;
reg start,have_shift,reading_shift;reg [2:0] shift_bits;
reg [3:0] near_count,far_count,fail_count;
reg [GB-1:0] cover_count;
reg [RB-1:0] release_count;
reg [1:0] gap_count;
reg gesture_armed;
wire gesture_candidate=gesture_armed&&cover_count!=0&&cover_count<=GESTURE_MAX_SAMPLES;
(* async_reg="true" *)reg [1:0] ir_sync;
wire busy,done,error;wire [7:0] hi,lo;
wire [11:0] raw={hi,lo[3:0]};
wire [11:0] measured=raw>>shift_bits;
assign gpio1=!rst;
i2c_register_reader #(.CLK_HZ(CLK_HZ),.BUS_HZ(BUS_HZ),.TIMEOUT_CYCLES(I2C_TIMEOUT_CYCLES)) u_i2c(
 .clk(clk),.rst(rst),.start(start),.address(7'h40),
 .register_address(reading_shift?8'h35:8'h5e),.two_bytes(!reading_shift),
 .scl(scl),.sda(sda),.busy(busy),.done(done),.error(error),.data_high(hi),.data_low(lo));
always @(posedge clk or posedge rst)
 if(rst)begin ir_sync<=0;quiet_count<=0;end
 else begin
  ir_sync<={ir_sync[0],ir_inhibit};
  if(ir_sync[1])quiet_count<=QUIET_C;
  else if(quiet_count!=0)quiet_count<=quiet_count-1'b1;
 end
always @(posedge clk or posedge rst)
 if(rst)begin
  state<=WAIT_POWER;wait_count<=0;start<=0;have_shift<=0;reading_shift<=1;shift_bits<=2;
  near_active<=0;sample_valid<=0;distance_q4<=0;sensor_fault<=1;
  near_count<=0;far_count<=0;fail_count<=0;
  cover_count<=0;release_count<=0;gap_count<=0;gesture_armed<=1;gesture_next<=0;
 end else begin
  start<=0;sample_valid<=0;gesture_next<=0;
  if(quiet_count!=0||ir_sync[1])begin cover_count<=0;release_count<=0;gap_count<=0;end
  case(state)
   WAIT_POWER:if(wait_count>=START_C-1)begin wait_count<=0;state<=LAUNCH;end
    else wait_count<=wait_count+1'b1;
   WAIT_POLL:if(wait_count>=POLL_C-1)begin wait_count<=0;state<=LAUNCH;end
    else wait_count<=wait_count+1'b1;
   LAUNCH:if(!busy)begin reading_shift<=!have_shift;start<=1;state<=WAIT_READ;end
   WAIT_READ:if(done)begin
    state<=WAIT_POLL;wait_count<=0;
    if(error||(reading_shift&&hi[2:0]!=1&&hi[2:0]!=2))begin
     sensor_fault<=1;near_count<=0;far_count<=0;
     cover_count<=0;release_count<=0;gap_count<=0;
     if(fail_count<FAIL_POLLS)fail_count<=fail_count+1'b1;
     if(fail_count>=FAIL_POLLS-1)begin near_active<=0;have_shift<=0;end
    end else if(reading_shift)begin
     shift_bits<=hi[2:0];have_shift<=1;state<=LAUNCH;
    end else begin
     fail_count<=0;sensor_fault<=0;distance_q4<=measured;
     // A short cover followed by two clear readings is a wave. A long cover
     // belongs to the existing detail-view behavior. The sensor is specified
     // only from 4 cm upward; below-range values cannot start a gesture.
     if(quiet_count!=0||ir_sync[1])begin
      cover_count<=0;release_count<=0;gap_count<=0;
     end else if(measured<64)begin
      cover_count<=0;release_count<=0;gap_count<=0;
     end else if(measured<=GESTURE_COVER_CM*16)begin
      release_count<=0;gap_count<=0;
      if(gesture_armed)begin
       if(cover_count<=GESTURE_MAX_SAMPLES)cover_count<=cover_count+1'b1;
      end
     end else if(measured>=GESTURE_RELEASE_CM*16)begin
      gap_count<=0;
      if(gesture_armed&&cover_count>=GESTURE_MIN_SAMPLES&&
         cover_count<=GESTURE_MAX_SAMPLES)begin
       if(release_count>=GESTURE_RELEASE_SAMPLES-1)begin
        gesture_next<=1;gesture_armed<=0;cover_count<=0;release_count<=0;
       end else release_count<=release_count+1'b1;
      end else if(!gesture_armed)begin
       cover_count<=0;
       if(release_count>=GESTURE_RELEASE_SAMPLES-1)begin
        gesture_armed<=1;release_count<=0;
       end else release_count<=release_count+1'b1;
      end else begin cover_count<=0;release_count<=0;end
     end else begin
      release_count<=0;
      if(gap_count==2)begin cover_count<=0;gap_count<=0;end
      else begin
       gap_count<=gap_count+1'b1;
       if(cover_count!=0&&cover_count<=GESTURE_MAX_SAMPLES)
        cover_count<=cover_count+1'b1;
      end
     end
     // While a wave is in progress, keep the photo/detail latch stable.
     // A sustained cover can assert near after the gesture window expires.
     sample_valid<=measured>=64;
     if(quiet_count!=0||ir_sync[1]||measured<64||
        (!near_active&&(gesture_candidate||measured<=GESTURE_COVER_CM*16)&&
          cover_count<=GESTURE_MAX_SAMPLES))begin near_count<=0;far_count<=0;end
     else if(measured<ENTER_CM*16)begin
      far_count<=0;
      if(near_count<CONFIRM_SAMPLES)near_count<=near_count+1'b1;
      if(near_count>=CONFIRM_SAMPLES-1)near_active<=1;
     end else if(measured>EXIT_CM*16)begin
      near_count<=0;
      if(far_count<CONFIRM_SAMPLES)far_count<=far_count+1'b1;
      if(far_count>=CONFIRM_SAMPLES-1)near_active<=0;
     end else begin near_count<=0;far_count<=0;end
    end
   end
   default:state<=WAIT_POWER;
  endcase
 end
endmodule
