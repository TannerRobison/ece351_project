`timescale 1ns/1ps

module tb_sng_comparator;

    logic [15:0] random_value;
    logic [15:0] threshold;
    logic        stochastic_bit;

    int unsigned ones_count;

    sng_comparator dut (
        .random_value  (random_value),
        .threshold     (threshold),
        .stochastic_bit(stochastic_bit)
    );

    task automatic check_case (
        input logic [15:0] test_random,
        input logic [15:0] test_threshold,
        input logic        expected
    );
        random_value = test_random;
        threshold    = test_threshold;
        #1;

        if (stochastic_bit !== expected) begin
            $fatal(1,
                "FAIL: random=%0d threshold=%0d expected=%b got=%b",
                random_value, threshold, expected, stochastic_bit
            );
        end
    endtask

    initial begin
        // Below, equal to, and above the threshold.
        check_case(16'd99,  16'd100, 1'b1);
        check_case(16'd100, 16'd100, 1'b1);
        check_case(16'd101, 16'd100, 1'b0);

        // Minimum and maximum thresholds.
        check_case(16'd1,     16'd0,     1'b0);
        check_case(16'd65535, 16'd0,     1'b0);
        check_case(16'd1,     16'd65535, 1'b1);
        check_case(16'd65535, 16'd65535, 1'b1);

        // Confirm unsigned behavior across the high-bit boundary.
        check_case(16'd32768, 16'd32767, 1'b0);
        check_case(16'd32767, 16'd32768, 1'b1);

        // Zero is a valid comparator input, even though the
        // intended maximal-length LFSR should never produce it.
        check_case(16'd0, 16'd0, 1'b1);

        // Exercise the complete intended LFSR value range.
        threshold  = 16'd32768;
        ones_count = 0;

        for (int unsigned r = 1; r <= 65535; r++) begin
            random_value = r[15:0];
            #1;

            if (stochastic_bit === 1'b1)
                ones_count++;
            else if (stochastic_bit !== 1'b0)
                $fatal(1, "Unknown output at random=%0d", r);
        end

        // Exactly 32768 values in 1..65535 satisfy R <= 32768.
        if (ones_count != 32768)
            $fatal(1, "Wrong ones count: %0d", ones_count);

        $display("PASS: All comparator tests passed.");
        $finish;
    end

endmodule
