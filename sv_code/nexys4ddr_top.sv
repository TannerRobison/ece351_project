// nexys4ddr_top.sv
//
// Board-level wrapper for the Digilent Nexys 4 DDR (xc7a100tcsg324-1) that
// runs the full datapath from the report with switches, buttons, LEDs, and
// the seven-segment display. Pin assignments are in
// constraints/nexys4ddr.xdc.
//
// Datapath:
//   SNG A -> a, SNG B -> b   operand streams
//   SNG S -> s               MUX select, fixed at S's code closest to 0.5
//   a & b                    stochastic multiply  (P = Pa * Pb)
//   s ? b : a                stochastic scaled add (P = (1-Ps) Pa + Ps Pb)
//
// Controls:
//   SW[10:0]   voltage code for A and B loads
//   BTNL       load A: latch T_A for SW[10:0] and reseed A's LFSR
//   BTNR       load B
//   BTNC       load A and B together
//   CPU_RESETN reset (active low button). On release, A and B load SW[10:0]
//              and S loads S_CODE. The same happens at power-on.
//   SW[13:11]  display select: 0 = a, 1 = b, 2 = s, 3 = a & b, 4 = mux
//   SW[14]     speed: 0 = slow tick (~4 Hz, one stream bit per blink),
//                     1 = one stream bit per 100 MHz clock
//   SW[15]     run: step the LFSRs (1 = running, 0 = paused)
//
// Outputs:
//   LED[4:0]   live bits a, b, s, a & b, mux. In slow mode they blink one bit
//              per tick; in fast mode their brightness tracks each stream's
//              probability.
//   7-segment  left 4 digits: expected 1s per 65,535 bits for the selected
//                stream, in hex. For a, b, s this is T.
//              right 4 digits: measured 1s, in hex.
//                fast mode: 1s in the last complete window of 65,535 stream
//                  bits. That is one full LFSR period, so for a, b, s every
//                  R value is seen once and the count equals T exactly. For
//                  a & b and mux it is close, and the difference is the
//                  stochastic computation error.
//                slow mode: running count since the last load.
//
// Holding a load button reloads the same seed every cycle, so that SNG's
// stream is frozen while the button is down and starts on release.
//
// LUT_FILE_* are bare file names. Add Python_Code/lut_*.mem to the Vivado
// project as design sources so they resolve (see lut_to_fpga.md).

module nexys4ddr_top #(
    // SNG settings from the sng.sv header.
    parameter string       LUT_FILE_A    = "lut_a.mem",
    parameter logic [15:0] TAPS_A        = 16'hB400,
    parameter logic [63:0] SHUFFLE_MAP_A = 64'h02A8_D316_79CE_4F5B,
    parameter logic [15:0] SEED_A        = 16'hACE1,

    parameter string       LUT_FILE_B    = "lut_b.mem",
    parameter logic [15:0] TAPS_B        = 16'hD008,
    parameter logic [63:0] SHUFFLE_MAP_B = 64'hB649_A320_17F5_DEC8,
    parameter logic [15:0] SEED_B        = 16'h1D2C,

    parameter string       LUT_FILE_S    = "lut_s.mem",
    parameter logic [15:0] TAPS_S        = 16'h8016,
    parameter logic [63:0] SHUFFLE_MAP_S = 64'h809E_B7DF_C3A1_6524,
    parameter logic [15:0] SEED_S        = 16'h5EED,
    // Entry of lut_s.mem closest to 0.5: T = 0x7FAA.
    parameter logic [10:0] S_CODE        = 11'd1363,

    // 100 MHz / 25,000,000 = 4 Hz slow tick.
    parameter int          TICK_DIV      = 25_000_000
) (
    input  logic        CLK100MHZ,
    input  logic        CPU_RESETN,  // active low
    input  logic        BTNC,
    input  logic        BTNL,
    input  logic        BTNR,
    input  logic [15:0] SW,
    output logic [15:0] LED,
    output logic [6:0]  SEG,         // CA..CG, active low
    output logic        DP,          // active low
    output logic [7:0]  AN           // active low, AN[0] = rightmost digit
);

    logic clk;
    assign clk = CLK100MHZ;

    // ---- Input synchronizers ----
    //
    // Buttons and switches are asynchronous to the clock, so each goes
    // through two flip-flops before the design uses it. The switch bus is
    // synchronized bit by bit, so bits can disagree for a cycle while a
    // switch moves. That only matters if a load is high at that moment, and
    // a load relatches every cycle it is held, so T settles to the final code.
    //
    // rstn_sync starts at 0 when the FPGA is configured, so rst is high for
    // the first two cycles. That is the power-on reset.
    (* ASYNC_REG = "TRUE" *) logic [1:0]  rstn_sync = '0;
    (* ASYNC_REG = "TRUE" *) logic [1:0]  btnc_sync, btnl_sync, btnr_sync;
    (* ASYNC_REG = "TRUE" *) logic [15:0] sw_meta, sw_sync;

    always_ff @(posedge clk) begin
        rstn_sync <= {rstn_sync[0], CPU_RESETN};
        btnc_sync <= {btnc_sync[0], BTNC};
        btnl_sync <= {btnl_sync[0], BTNL};
        btnr_sync <= {btnr_sync[0], BTNR};
        sw_meta   <= SW;
        sw_sync   <= sw_meta;
    end

    logic        rst, run, fast;
    logic [10:0] code;
    logic [2:0]  sel;

    assign rst  = ~rstn_sync[1];
    assign run  = sw_sync[15];
    assign fast = sw_sync[14];
    assign sel  = sw_sync[13:11];
    assign code = sw_sync[10:0];

    // ---- Loads ----
    //
    // rst_release is a one-cycle pulse on the first cycle after reset ends.
    // It loads all three SNGs, so they start with a threshold and their own
    // seed instead of the reset LFSR state.
    logic rst_d = 1'b1;
    logic rst_release;
    logic load_a, load_b, load_s, any_load;

    always_ff @(posedge clk)
        rst_d <= rst;

    assign rst_release = rst_d && !rst;

    assign load_a   = btnl_sync[1] || btnc_sync[1] || rst_release;
    assign load_b   = btnr_sync[1] || btnc_sync[1] || rst_release;
    assign load_s   = rst_release;
    assign any_load = load_a || load_b || load_s;

    // ---- Slow tick ----
    //
    // One-cycle pulse every TICK_DIV clocks, so the streams can be watched one
    // bit at a time on the LEDs.
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

    // ---- SNGs ----
    //
    // All three share the clock, reset, and en, so their streams stay in step.
    logic        en;
    logic [15:0] t_a, t_b, t_s;
    logic        a, b, s;

    assign en = run && (fast || tick);

    sng #(
        .LUT_FILE   (LUT_FILE_A),
        .TAPS       (TAPS_A),
        .SHUFFLE_MAP(SHUFFLE_MAP_A)
    ) u_sng_a (
        .clk      (clk),
        .rst      (rst),
        .load     (load_a),
        .en       (en),
        .code     (code),
        .seed     (SEED_A),
        .threshold(t_a),
        .stoch_bit(a)
    );

    sng #(
        .LUT_FILE   (LUT_FILE_B),
        .TAPS       (TAPS_B),
        .SHUFFLE_MAP(SHUFFLE_MAP_B)
    ) u_sng_b (
        .clk      (clk),
        .rst      (rst),
        .load     (load_b),
        .en       (en),
        .code     (code),
        .seed     (SEED_B),
        .threshold(t_b),
        .stoch_bit(b)
    );

    sng #(
        .LUT_FILE   (LUT_FILE_S),
        .TAPS       (TAPS_S),
        .SHUFFLE_MAP(SHUFFLE_MAP_S)
    ) u_sng_s (
        .clk      (clk),
        .rst      (rst),
        .load     (load_s),
        .en       (en),
        .code     (S_CODE),
        .seed     (SEED_S),
        .threshold(t_s),
        .stoch_bit(s)
    );

    // ---- Stochastic arithmetic ----
    //
    // Multiply is one AND gate. Scaled add is a 2:1 MUX with s as the select.
    localparam int N_STREAM = 5;  // index 0 = a, 1 = b, 2 = s, 3 = a & b, 4 = mux

    logic [N_STREAM-1:0] bits;

    assign bits = {s ? b : a, a & b, s, b, a};

    // ---- Ones counters ----
    //
    // Counts the stream bits (cycles with en high) and how many of each
    // stream are 1. Any load restarts the count, since it changes a threshold
    // and reseeds an LFSR. After WINDOW bits each ones count is saved in
    // ones_window and the counters restart.
    localparam int WINDOW = 65_535;  // one full LFSR period

    logic [15:0] bit_cnt;                   // stream bits so far in this window
    logic [15:0] ones_cnt    [N_STREAM];    // 1s so far in this window
    logic [15:0] ones_window [N_STREAM];    // 1s in the last complete window

    always_ff @(posedge clk) begin
        if (rst || any_load) begin
            bit_cnt     <= '0;
            ones_cnt    <= '{default: '0};
            ones_window <= '{default: '0};
        end else if (en) begin
            if (bit_cnt == 16'(WINDOW - 1)) begin
                bit_cnt <= '0;
                for (int i = 0; i < N_STREAM; i++) begin
                    ones_window[i] <= ones_cnt[i] + 16'(bits[i]);
                    ones_cnt[i]    <= '0;
                end
            end else begin
                bit_cnt <= bit_cnt + 1'b1;
                for (int i = 0; i < N_STREAM; i++)
                    ones_cnt[i] <= ones_cnt[i] + 16'(bits[i]);
            end
        end
    end

    // ---- Expected counts ----
    //
    // Expected 1s per 65,535 bits for each stream. The products divide by
    // 2^16 instead of 65,535, which is off by at most a couple of counts.
    //   a & b: T_A * T_B / 65535
    //   mux:   ((65535 - T_S) * T_A + T_S * T_B) / 65535
    // Thresholds only change on a load, so a couple of pipeline registers
    // here cost nothing visible and keep the multiplies off the critical path.
    logic [31:0] prod_ab, prod_sa, prod_sb, sum_mux;
    logic [15:0] exp_val [N_STREAM];

    always_ff @(posedge clk) begin
        prod_ab <= t_a * t_b;
        prod_sa <= 16'(16'hFFFF - t_s) * t_a;
        prod_sb <= t_s * t_b;
    end

    // Can't overflow: the two weights add to 65535, so the sum is at most
    // 65535 * 65535 < 2^32.
    assign sum_mux = prod_sa + prod_sb;

    always_ff @(posedge clk) begin
        exp_val[0] <= t_a;
        exp_val[1] <= t_b;
        exp_val[2] <= t_s;
        exp_val[3] <= prod_ab[31:16];
        exp_val[4] <= sum_mux[31:16];
    end

    // ---- Outputs ----
    //
    // The stream bits are combinational, so register them before they leave
    // the chip.
    always_ff @(posedge clk)
        LED <= {{(16 - N_STREAM){1'b0}}, bits};

    // Left half: expected. Right half: measured. Selections 5-7 show zeros.
    logic [31:0] disp;

    always_comb
        if (sel < 3'(N_STREAM))
            disp = {exp_val[sel], fast ? ones_window[sel] : ones_cnt[sel]};
        else
            disp = '0;

    // Decimal point on digit 4 separates expected from measured.
    seven_seg u_seg (
        .clk  (clk),
        .value(disp),
        .dp_on(8'b0001_0000),
        .seg  (SEG),
        .dp   (DP),
        .an   (AN)
    );

endmodule
