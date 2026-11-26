// sng.sv
//
// One complete stochastic number generator (one gray "SNG" box in Fig. 1 of
// the proposal): the voltage code picks a threshold T from this device's LUT,
// the LFSR + bit shuffle supplies a random value R, and the comparator outputs
// a 1 whenever R <= T. Over a run the fraction of 1s approximates
// P_switch(V_k) = T / (2^16 - 1).
//
// Settings for the three SNGs (TAPS/SHUFFLE_MAP verified in lfsr_shuffle.sv):
//   SNG A: LUT_FILE = "lut_a.mem", TAPS = 16'hB400, SHUFFLE_MAP = 64'h02A8_D316_79CE_4F5B
//   SNG B: LUT_FILE = "lut_b.mem", TAPS = 16'hD008, SHUFFLE_MAP = 64'hB649_A320_17F5_DEC8
//   SNG S: LUT_FILE = "lut_s.mem", TAPS = 16'h8016, SHUFFLE_MAP = 64'h809E_B7DF_C3A1_6524
//
// Usage from the control FSM:
//   LOAD: pulse load for one cycle with code and seed valid. T is latched and
//         the LFSR is seeded on the same clock edge.
//   RUN:  hold en high for L cycles; stoch_bit is one stream bit per cycle.
//
// stoch_bit is combinational from the LFSR state and T, so it is valid in
// the cycle right after load, before the first en step.

module sng #(
    parameter string       LUT_FILE    = "lut_a.mem",
    parameter logic [15:0] TAPS        = 16'hB400,
    parameter logic [63:0] SHUFFLE_MAP = 64'h02A8_D316_79CE_4F5B
) (
    input  logic        clk,
    input  logic        rst,        // synchronous, active high (LFSR only)
    input  logic        load,       // latch T from the LUT and load seed
    input  logic        en,         // advance the LFSR one step
    input  logic [10:0] code,       // voltage code, indexes the LUT
    input  logic [15:0] seed,
    output logic [15:0] threshold,  // latched T
    output logic        stoch_bit   // stochastic stream
);

    // Shuffled random value R, from the LFSR to the comparator.
    logic [15:0] r;

    // ---- LUT -> T ----
    //
    // Looks up this device's threshold for the voltage code. load is
    // the read enable, so T is captured on the LOAD cycle and then held
    // through RUN.
    sng_lut #(
        .LUT_FILE(LUT_FILE),
        .DEPTH   (2048),
        .WIDTH   (16)
    ) u_lut (
        .clk  (clk),
        .rd_en(load),
        .addr (code),
        .data (threshold)
    );

    // ---- LFSR -> shuffle -> R ----
    //
    // Pseudorandom source standing in for the memristor's intrinsic
    // randomness. load seeds it (same cycle T is latched), en steps it once
    // per stream bit, and the bit shuffle is applied inside the module.
    lfsr_shuffle #(
        .TAPS       (TAPS),
        .SHUFFLE_MAP(SHUFFLE_MAP)
    ) u_lfsr (
        .clk (clk),
        .rst (rst),
        .load(load),
        .en  (en),
        .seed(seed),
        .r   (r)
    );

    // ---- Comparator: R <= T ----
    //
    // Outputs 1 when the random value is at or below the threshold. Since R
    // is uniform over 1..65535, this is 1 with probability T / 65535, which
    // is the device's switching probability for this voltage code.
    sng_comparator #(
        .WIDTH(16)
    ) u_cmp (
        .random_value  (r),
        .threshold     (threshold),
        .stochastic_bit(stoch_bit)
    );

endmodule
