`timescale 1ns/1ps

// tb_nexys4ddr_top.sv
//
// Self-checking testbench for the board top level (nexys4ddr_top). Drives
// the switches and buttons the way a person would and checks the LEDs and
// the seven-segment display.
//
// Tests:
//   1. Power-on: with no button pressed, A and B load the switch code and S
//      loads S_CODE.
//   2. Load A (BTNL) and B (BTNR) with different codes, run fast for one full
//      window, then for each display selection:
//        a, b, s:     measured 1s == T exactly (full LFSR period)
//        a & b, mux:  expected matches the testbench's own math, and
//                     measured is within TOL of expected
//      The display is read back from SEG/AN, not from internal signals.
//   3. BTNC loads both A and B.
//   The LED bits are checked every cycle: LED[3] = a & b, LED[4] = s ? b : a.
//
// Any failure stops the simulation with $fatal; otherwise it prints PASS.
// Run from the repo root so the LUT paths resolve.

module tb_nexys4ddr_top;

    // ---- Constants ----
    localparam int unsigned WINDOW = 65535;
    localparam logic [10:0] S_CODE = 11'd1363;
    // Allowed |measured - expected| for a & b and mux: 1% of 65535.
    localparam int          TOL    = 655;

    // ---- DUT signals ----
    logic        clk = 1'b0;
    logic        rstn = 1'b1;
    logic        btnc = 1'b0, btnl = 1'b0, btnr = 1'b0;
    logic [15:0] sw = '0;
    logic [15:0] led;
    logic [6:0]  seg;
    logic        dp;
    logic [7:0]  an;

    logic [15:0] lut_a [2048], lut_b [2048], lut_s [2048];

    // ---- Clock ----
    always #5 clk = ~clk;

    // ---- Device under test ----
    nexys4ddr_top #(
        .LUT_FILE_A("Python_Code/lut_a.mem"),
        .LUT_FILE_B("Python_Code/lut_b.mem"),
        .LUT_FILE_S("Python_Code/lut_s.mem"),
        .S_CODE    (S_CODE),
        .TICK_DIV  (10)
    ) dut (
        .CLK100MHZ (clk),
        .CPU_RESETN(rstn),
        .BTNC      (btnc),
        .BTNL      (btnl),
        .BTNR      (btnr),
        .SW        (sw),
        .LED       (led),
        .SEG       (seg),
        .DP        (dp),
        .AN        (an)
    );

    // ---- LED check ----
    //
    // LED is registered, so it shows last cycle's stream bits. Compare it
    // against its own a/b/s bits: product and MUX must follow every cycle.
    always @(negedge clk)
        if (led[3] !== (led[0] & led[1]) || led[4] !== (led[2] ? led[1] : led[0]))
            $fatal(1, "FAIL: LED bits inconsistent: %b", led[4:0]);

    // ---- Helper tasks ----

    // press: hold a button for a few clocks (past the synchronizer), then
    // release and let the load settle.
    task automatic press(ref logic btn);
        @(negedge clk) btn = 1'b1;
        repeat (4) @(negedge clk);
        btn = 1'b0;
        repeat (4) @(negedge clk);
    endtask

    // seg_to_hex: decode active-low segments back to a hex digit.
    function automatic int seg_to_hex(input logic [6:0] s);
        case (~s)
            7'h3F: return 'h0;  7'h06: return 'h1;  7'h5B: return 'h2;  7'h4F: return 'h3;
            7'h66: return 'h4;  7'h6D: return 'h5;  7'h7D: return 'h6;  7'h07: return 'h7;
            7'h7F: return 'h8;  7'h6F: return 'h9;  7'h77: return 'hA;  7'h7C: return 'hB;
            7'h39: return 'hC;  7'h5E: return 'hD;  7'h79: return 'hE;  7'h71: return 'hF;
            default: return -1;
        endcase
    endfunction

    // read_display: wait for each digit to be lit and decode it. Returns the
    // left and right halves as two 16-bit values.
    task automatic read_display(output logic [15:0] left, output logic [15:0] right);
        logic [31:0] v;
        int          d;
        for (int k = 0; k < 8; k++) begin
            do @(negedge clk); while (an !== ~(8'b1 << k));
            d = seg_to_hex(seg);
            if (d < 0) $fatal(1, "FAIL: digit %0d shows a non-hex pattern %b", k, seg);
            if (dp !== (k == 4 ? 1'b0 : 1'b1)) $fatal(1, "FAIL: decimal point wrong on digit %0d", k);
            v[4*k +: 4] = 4'(d);
        end
        {left, right} = v;
    endtask

    // check_window: select each stream on SW[13:11], read the display, and
    // check expected vs. measured. Assumes a full window has completed.
    task automatic check_window(input logic [10:0] code_a, input logic [10:0] code_b);
        logic [15:0] ta, tb, ts, exp_v [5], left, right;
        int          err;
        string       name [5] = '{"a", "b", "s", "a&b", "mux"};

        ta = lut_a[code_a];
        tb = lut_b[code_b];
        ts = lut_s[S_CODE];
        exp_v[0] = ta;
        exp_v[1] = tb;
        exp_v[2] = ts;
        exp_v[3] = 16'((32'(ta) * 32'(tb)) >> 16);
        exp_v[4] = 16'(((32'(16'hFFFF - ts) * 32'(ta)) + (32'(ts) * 32'(tb))) >> 16);

        for (int i = 0; i < 5; i++) begin
            sw[13:11] = 3'(i);
            repeat (4) @(negedge clk);
            read_display(left, right);
            if (left !== exp_v[i])
                $fatal(1, "FAIL: %s expected shows %h, should be %h", name[i], left, exp_v[i]);
            err = int'(right) - int'(left);
            if (i < 3 && err != 0)
                $fatal(1, "FAIL: %s measured %h != T %h", name[i], right, left);
            if (err > TOL || err < -TOL)
                $fatal(1, "FAIL: %s measured %h too far from expected %h", name[i], right, left);
            $display("  %-4s expected %h  measured %h  error %0d (%.3f%%)",
                     name[i], left, right, err, 100.0 * err / 65535.0);
        end
    endtask

    // ---- Test sequence ----
    initial begin
        $readmemh("Python_Code/lut_a.mem", lut_a);
        $readmemh("Python_Code/lut_b.mem", lut_b);
        $readmemh("Python_Code/lut_s.mem", lut_s);

        // ---- 1. Power-on load ----
        // No reset pressed: the synchronizer's initial value gives a reset,
        // and its release loads all three SNGs.
        sw[10:0] = 11'd1000;
        repeat (10) @(negedge clk);
        if (dut.t_a !== lut_a[1000] || dut.t_b !== lut_b[1000] || dut.t_s !== lut_s[S_CODE])
            $fatal(1, "FAIL: power-on load T = %h / %h / %h", dut.t_a, dut.t_b, dut.t_s);
        $display("power-on: T_A=%h T_B=%h T_S=%h (S_CODE %0d)", dut.t_a, dut.t_b, dut.t_s, S_CODE);

        // ---- 2. Separate A and B loads, fast run, display check ----
        sw[10:0] = 11'd1500;
        press(btnl);
        sw[10:0] = 11'd1342;
        press(btnr);
        if (dut.t_a !== lut_a[1500] || dut.t_b !== lut_b[1342])
            $fatal(1, "FAIL: BTNL/BTNR loads T_A=%h T_B=%h", dut.t_a, dut.t_b);

        sw[15] = 1'b1;   // run
        sw[14] = 1'b1;   // fast
        repeat (WINDOW + 20) @(negedge clk);
        $display("A code 1500, B code 1342:");
        check_window(11'd1500, 11'd1342);

        // ---- 3. BTNC loads both ----
        sw[10:0] = 11'd1200;
        press(btnc);
        if (dut.t_a !== lut_a[1200] || dut.t_b !== lut_b[1200])
            $fatal(1, "FAIL: BTNC load T_A=%h T_B=%h", dut.t_a, dut.t_b);
        repeat (WINDOW + 20) @(negedge clk);
        $display("A and B code 1200 (BTNC):");
        check_window(11'd1200, 11'd1200);

        $display("PASS");
        $finish;
    end

endmodule
