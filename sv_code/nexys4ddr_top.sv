// nexys4ddr_top.sv
//
// Board-level wrapper that puts one SNG on the Digilent Nexys 4 DDR
// (xc7a100tcsg324-1) for a switches-and-LEDs demo. Pin assignments are in
// constraints/nexys4ddr.xdc.
//
// Controls:
//   SW[10:0]   voltage code (indexes the LUT)
//   BTNC       load: latch T for the current code and reseed the LFSR
//   SW[15]     run: step the LFSR (1 = running, 0 = paused)
//   SW[14]     speed: 0 = slow tick (~4 Hz, one stream bit per blink),
//                     1 = one stream bit per 100 MHz clock
//   CPU_RESETN reset the LFSR and the tick divider (active low button)
//
// Outputs:
//   LED[15:0]  latched threshold T
//   LED16_R    stochastic stream bit. In slow mode it blinks on with
//              probability T / 65535 per tick; in fast mode it toggles far too
//              fast to see, so its brightness tracks T / 65535 instead.
//
// The seed is a fixed parameter: 16 switches are not enough for an 11-bit
// code and a 16-bit seed. Holding BTNC reloads the same seed every cycle, so
// the stream is frozen while the button is down and starts on release.
//
// LUT_FILE is a bare file name. Add Python_Code/lut_*.mem to the Vivado
// project as design sources so it resolves (see lut_to_fpga.md).

module nexys4ddr_top #(
    // SNG A settings from the sng.sv header. Swap in B or S to try another
    // device.
    parameter string       LUT_FILE    = "lut_a.mem",
    parameter logic [15:0] TAPS        = 16'hB400,
    parameter logic [63:0] SHUFFLE_MAP = 64'h02A8_D316_79CE_4F5B,
    parameter logic [15:0] SEED        = 16'hACE1,
    // 100 MHz / 25,000,000 = 4 Hz slow tick.
    parameter int          TICK_DIV    = 25_000_000
) (
    input  logic        CLK100MHZ,
    input  logic        CPU_RESETN,  // active low
    input  logic        BTNC,
    input  logic [15:0] SW,
    output logic [15:0] LED,
    output logic        LED16_R
);

    logic clk;
    assign clk = CLK100MHZ;

    // ---- Input synchronizers ----
    //
    // Buttons and switches are asynchronous to the clock, so each goes
    // through two flip-flops before the design uses it. The switch bus is
    // synchronized bit by bit, so bits can disagree for a cycle while a
    // switch moves. That only matters if load is high at that moment, and
    // load relatches every cycle it is held, so T settles to the final code.
    (* ASYNC_REG = "TRUE" *) logic [1:0]  rstn_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0]  btnc_sync;
    (* ASYNC_REG = "TRUE" *) logic [15:0] sw_meta, sw_sync;

    always_ff @(posedge clk) begin
        rstn_sync <= {rstn_sync[0], CPU_RESETN};
        btnc_sync <= {btnc_sync[0], BTNC};
        sw_meta   <= SW;
        sw_sync   <= sw_meta;
    end

    logic        rst, load, run, fast;
    logic [10:0] code;

    assign rst  = ~rstn_sync[1];
    assign load = btnc_sync[1];
    assign run  = sw_sync[15];
    assign fast = sw_sync[14];
    assign code = sw_sync[10:0];

    // ---- Slow tick ----
    //
    // One-cycle pulse every TICK_DIV clocks, so the stream can be watched one
    // bit at a time on LED16_R.
    localparam int CNT_W = $clog2(TICK_DIV);
    localparam logic [CNT_W-1:0] TICK_LAST = CNT_W'(TICK_DIV - 1);

    logic [CNT_W-1:0] tick_cnt;
    logic             tick;

    always_ff @(posedge clk) begin
        if (rst || tick_cnt == TICK_LAST)
            tick_cnt <= '0;
        else
            tick_cnt <= tick_cnt + 1'b1;
    end

    assign tick = (tick_cnt == TICK_LAST);

    // ---- SNG ----
    logic        en;
    logic [15:0] threshold;
    logic        stoch_bit;

    assign en = run && (fast || tick);

    sng #(
        .LUT_FILE   (LUT_FILE),
        .TAPS       (TAPS),
        .SHUFFLE_MAP(SHUFFLE_MAP)
    ) u_sng (
        .clk      (clk),
        .rst      (rst),
        .load     (load),
        .en       (en),
        .code     (code),
        .seed     (SEED),
        .threshold(threshold),
        .stoch_bit(stoch_bit)
    );

    // ---- Outputs ----
    //
    // stoch_bit is combinational, so register it before it leaves the chip.
    always_ff @(posedge clk)
        LED16_R <= stoch_bit;

    assign LED = threshold;

endmodule
