`timescale 1ns/1ps

// tb_sng.sv
//
// Self-checking testbench for the full SNG (LUT + LFSR/shuffle + comparator).
// Builds all three SNGs (A, B, S) with their real LUTs and LFSR settings and
// drives them together, the way the control FSM will.
//
// Tests:
//   1. Full-period count: over one LFSR period the number of 1s equals T
//      exactly, for several voltage codes.
//   2. Short stream: at L = 1024 the fraction of 1s is close to T / 65535.
//   3. Reload: loading the same code and seed again repeats the stream.
//   4. Freeze: with en low, the LFSR doesn't move.
//
// Any failure stops the simulation with $fatal; otherwise it prints PASS.
// Run from the repo root so the LUT paths resolve.
//
// Waveforms: pass +wave to dump tb_sng.fst (or +wave=<file> to pick the
// name). Open it with GTKWave using the saved view in sv_code/tb_sng.gtkw.

module tb_sng;

    // ---- Constants and DUT signals ----
    localparam int unsigned PERIOD = 65535;  // LFSR period, 2^16 - 1
    localparam int          N_SNG  = 3;      // index 0 = A, 1 = B, 2 = S

    // Control lines are shared by all three SNGs, like in the real design.
    // Per-SNG signals are arrays indexed by N_SNG.
    logic        clk = 1'b0;
    logic        rst, load, en;
    logic [10:0] code [N_SNG];
    logic [15:0] seed [N_SNG];
    logic [15:0] threshold [N_SNG];
    logic        stoch_bit [N_SNG];

    // Reference copies of the LUTs. $readmemh needs a whole array, so load
    // each file separately, then gather them into lut[] for indexing.
    logic [15:0] lut_a [2048], lut_b [2048], lut_s [2048];
    logic [15:0] lut [N_SNG][2048];

    // ---- Clock ----
    // 10 ns period (100 MHz, the Basys 3 oscillator).
    always #5 clk = ~clk;

    // ---- Devices under test ----
    // One SNG per stream, each with its own LUT file, taps and shuffle.

    sng #(
        .LUT_FILE   ("Python_Code/lut_a.mem"),
        .TAPS       (16'hB400),
        .SHUFFLE_MAP(64'h02A8_D316_79CE_4F5B)
    ) dut_a (
        .clk, .rst, .load, .en,
        .code(code[0]), .seed(seed[0]),
        .threshold(threshold[0]), .stoch_bit(stoch_bit[0])
    );

    sng #(
        .LUT_FILE   ("Python_Code/lut_b.mem"),
        .TAPS       (16'hD008),
        .SHUFFLE_MAP(64'hB649_A320_17F5_DEC8)
    ) dut_b (
        .clk, .rst, .load, .en,
        .code(code[1]), .seed(seed[1]),
        .threshold(threshold[1]), .stoch_bit(stoch_bit[1])
    );

    sng #(
        .LUT_FILE   ("Python_Code/lut_s.mem"),
        .TAPS       (16'h8016),
        .SHUFFLE_MAP(64'h809E_B7DF_C3A1_6524)
    ) dut_s (
        .clk, .rst, .load, .en,
        .code(code[2]), .seed(seed[2]),
        .threshold(threshold[2]), .stoch_bit(stoch_bit[2])
    );

    // ---- Helper tasks ----
    //
    // Inputs change on the falling edge, away from the active edge.

    // load_all: emulates the FSM's LOAD state. Puts code c on every SNG,
    // gives each its own seed, and pulses load for one clock. After the
    // edge, checks that each SNG latched the T value from its own LUT.
    task automatic load_all(input logic [10:0] c, input logic [15:0] s [N_SNG]);
        @(negedge clk);
        for (int i = 0; i < N_SNG; i++) begin
            code[i] = c;
            seed[i] = s[i];
        end
        load = 1'b1;
        en   = 1'b0;
        @(negedge clk);
        load = 1'b0;
        for (int i = 0; i < N_SNG; i++)
            if (threshold[i] !== lut[i][c])
                $fatal(1, "FAIL: SNG %0d code=%0d T=%h expected %h",
                       i, c, threshold[i], lut[i][c]);
    endtask

    // run: emulates the FSM's RUN state. Holds en high for len cycles and
    // counts the 1s on each stream, like the hardware ones counters. Each
    // cycle it samples the current bit, then waits for the clock edge that
    // steps the LFSR to the next value. Fails on an X/Z output.
    task automatic run(input int unsigned len, output int unsigned ones [N_SNG]);
        for (int i = 0; i < N_SNG; i++) ones[i] = 0;
        en = 1'b1;
        for (int unsigned n = 0; n < len; n++) begin
            for (int i = 0; i < N_SNG; i++) begin
                if (stoch_bit[i] === 1'b1)      ones[i]++;
                else if (stoch_bit[i] !== 1'b0) $fatal(1, "FAIL: SNG %0d output is X", i);
            end
            @(negedge clk);
        end
        en = 1'b0;
    endtask

    // ---- Waveform dump ----
    //
    // Only when +wave is given, so normal runs stay fast and leave no file.
    // Dumps every signal in the testbench and the three SNGs.
    string wave_file;
    initial begin
        if ($value$plusargs("wave=%s", wave_file) || $test$plusargs("wave")) begin
            if (wave_file == "") wave_file = "tb_sng.fst";
            $dumpfile(wave_file);
            $dumpvars(0, tb_sng);
        end
    end

    // ---- Test variables ----

    // Which test is running (1-4, matching the header list), so each
    // section is easy to find in the waveform. 0 = reset.
    int unsigned   test_id = 0;
    int unsigned   ones [N_SNG];
    logic [15:0]   seeds [N_SNG];
    logic [10:0]   half_code;
    logic [10:0]   codes [$];
    logic          trace1 [64], trace2 [64];
    logic [15:0]   r_frozen;
    real           p_meas, p_exp;

    // ---- Test sequence ----
    initial begin
        // Load the reference LUTs from the same files the DUTs use.
        $readmemh("Python_Code/lut_a.mem", lut_a);
        $readmemh("Python_Code/lut_b.mem", lut_b);
        $readmemh("Python_Code/lut_s.mem", lut_s);
        lut[0] = lut_a;
        lut[1] = lut_b;
        lut[2] = lut_s;

        // Hold reset for two clocks with every input at a known value.
        rst  = 1'b1;
        load = 1'b0;
        en   = 1'b0;
        for (int i = 0; i < N_SNG; i++) begin
            code[i] = '0;
            seed[i] = '0;
        end
        repeat (2) @(negedge clk);
        rst = 1'b0;

        // Each LFSR gets its own nonzero seed.
        seeds = '{16'hACE1, 16'h1D2B, 16'h7F31};

        // Find the code in LUT A closest to probability 0.5 (T near 32767),
        // the same way switchingmodel.py picks the select-stream code.
        // Each side of the < is |T - 32767| for that entry.
        half_code = 0;
        for (int k = 0; k < 2048; k++)
            if ((lut[0][k] > 32767 ? lut[0][k] - 32767 : 32767 - lut[0][k]) <
                (lut[0][half_code] > 32767 ? lut[0][half_code] - 32767 : 32767 - lut[0][half_code]))
                half_code = 11'(k);

        // ---- Exact full-period check ----
        // One period visits every nonzero R once, so the number of R <= T
        // in 1..65535 is exactly T. Covers both ends of the table, the 0.5
        // code, and points along the curve.
        test_id = 1;
        codes = '{11'd0, 11'd512, 11'd1024, half_code, 11'd1500, 11'd1800, 11'd2047};
        foreach (codes[j]) begin
            load_all(codes[j], seeds);
            run(PERIOD, ones);
            for (int i = 0; i < N_SNG; i++)
                if (ones[i] != 32'(threshold[i]))
                    $fatal(1, "FAIL: SNG %0d code=%0d ones=%0d expected %0d",
                           i, codes[j], ones[i], threshold[i]);
            $display("code %4d: T = %5d / %5d / %5d  full-period counts match",
                     codes[j], threshold[0], threshold[1], threshold[2]);
        end

        // ---- Short-stream sanity check, L = 2^10 ----
        // A shorter run won't match exactly; it should land within a few
        // standard deviations of T / 65535. 4 sigma at p = 0.5 is about
        // 0.0625, so 0.07 allows normal noise but catches a broken stream.
        test_id = 2;
        load_all(half_code, seeds);
        run(1024, ones);
        for (int i = 0; i < N_SNG; i++) begin
            p_meas = real'(ones[i]) / 1024.0;
            p_exp  = real'(threshold[i]) / real'(PERIOD);
            if (p_meas - p_exp > 0.07 || p_exp - p_meas > 0.07)
                $fatal(1, "FAIL: SNG %0d L=1024 p=%f expected %f", i, p_meas, p_exp);
            $display("L=1024, SNG %0d: p = %f (expected %f)", i, p_meas, p_exp);
        end

        // ---- Reload mid-run repeats the stream ----
        // Record 64 bits after a load, run elsewhere and load a different
        // code, then reload the original code and seed. The same 64 bits
        // must come out, proving load fully resets both T and the LFSR.
        test_id = 3;
        load_all(half_code, seeds);
        en = 1'b1;
        for (int n = 0; n < 64; n++) begin trace1[n] = stoch_bit[0]; @(negedge clk); end
        run(1000, ones);  // wander off somewhere else in the sequence
        load_all(11'd2047, seeds);  // different T in between
        load_all(half_code, seeds);
        en = 1'b1;
        for (int n = 0; n < 64; n++) begin trace2[n] = stoch_bit[0]; @(negedge clk); end
        en = 1'b0;
        if (trace1 != trace2)
            $fatal(1, "FAIL: reload with same code and seed did not repeat the stream");

        // ---- en low freezes the LFSR ----
        // en is low after the last test. Peek at SNG A's R through the
        // hierarchy and check it holds steady for 10 clocks.
        test_id = 4;
        r_frozen = dut_a.r;
        repeat (10) begin
            @(negedge clk);
            if (dut_a.r !== r_frozen)
                $fatal(1, "FAIL: LFSR moved while en was low");
        end

        // Reaching here means every check above passed.
        $display("PASS: All SNG tests passed.");
        $finish;
    end

endmodule
