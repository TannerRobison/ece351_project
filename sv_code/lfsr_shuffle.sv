// lfsr_shuffle.sv
//
// Random source for one SNG: a maximal-length Fibonacci LFSR followed by a
// fixed bit shuffle (the "pi" block in Fig. 1 of the proposal). The shuffled
// value r is compared against the LUT threshold T in the SNG (1 when r <= T).
//
// Fixed at 16 bits, matching the 16-bit LUT thresholds.
//
// The LFSR steps through all 2^16 - 1 nonzero states and never reaches 0.
// The shuffle is only a rewiring of bits, so r also covers every nonzero
// value exactly once per period. That keeps P(r <= T) = T / (2^16 - 1).
//
// TAPS:        feedback mask, bit i set = state[i] is XORed into the feedback.
// SHUFFLE_MAP: one hex digit per output bit, read left to right as
//              r[15] .. r[0]; each digit is the state bit that drives that
//              output bit. 64'hFEDC_BA98_7654_3210 is the identity (no shuffle).
//
// Verified maximal-length (period 65,535) settings, one per SNG:
//   SNG A: TAPS = 16'hB400 (taps 16,14,13,11), SHUFFLE_MAP = 64'h02A8_D316_79CE_4F5B
//   SNG B: TAPS = 16'hD008 (taps 16,15,13,4),  SHUFFLE_MAP = 64'hB649_A320_17F5_DEC8
//   SNG S: TAPS = 16'h8016 (taps 16,5,3,2),    SHUFFLE_MAP = 64'h809E_B7DF_C3A1_6524
//
// Control priority: rst > load > en. A seed of 0 would lock the LFSR up, so
// loading 0 loads 1 instead.

module lfsr_shuffle #(
    parameter logic [15:0] TAPS        = 16'hB400,
    parameter logic [63:0] SHUFFLE_MAP = 64'h02A8_D316_79CE_4F5B
) (
    input  logic        clk,
    input  logic        rst,   // synchronous, active high
    input  logic        load,  // load seed into the LFSR
    input  logic        en,    // advance one step
    input  logic [15:0] seed,
    output logic [15:0] r      // shuffled random value
);

    // ---- SHUFFLE_MAP sanity check (compile time only, no hardware) ----
    //
    // SHUFFLE_MAP must use every bit index exactly once, or r is no longer
    // uniform. Walk the 16 hex digits of p (p[4*i +: 4] is the 4-bit digit for r[i])
    // and set the matching bit in seen. With 16 digits, seen ends up all 1s
    // only if no index is repeated or missing.
    function automatic bit shuffle_map_is_valid(logic [63:0] p);
        logic [15:0] seen;
        seen = '0;
        for (int i = 0; i < 16; i++)
            seen[p[4*i +: 4]] = 1'b1;
        return &seen;  // AND of all bits: 1 only if every index was seen
    endfunction

    // Evaluated while the design is elaborated. A bad SHUFFLE_MAP stops the
    // build with this message instead of silently giving a biased r.
    if (!shuffle_map_is_valid(SHUFFLE_MAP)) begin : g_bad_shuffle_map
        $error("lfsr_shuffle: SHUFFLE_MAP must use each bit index exactly once");
    end

    // ---- LFSR register ----
    logic [15:0] state;

    always_ff @(posedge clk) begin
        if (rst)
            // Reset to a known nonzero state.
            state <= 16'd1;
        else if (load)
            // Load the seed, swapping 0 for 1 so the LFSR can't lock up.
            state <= (seed == '0) ? 16'd1 : seed;
        else if (en)
            // One Fibonacci step: AND state with TAPS to pick out the tap
            // bits, XOR them together (^ reduction) to get the feedback bit,
            // then shift left and put the feedback bit in at bit 0.
            state <= {state[14:0], ^(state & TAPS)};
        // Otherwise hold the current state.
    end

    // ---- Bit shuffle ----
    //
    // Output bit r[i] is copied from the state bit named by SHUFFLE_MAP's
    // i-th hex digit. SHUFFLE_MAP is a constant, so this synthesizes to fixed
    // wiring, no logic.
    always_comb
        for (int i = 0; i < 16; i++)
            r[i] = state[SHUFFLE_MAP[4*i +: 4]];

endmodule
