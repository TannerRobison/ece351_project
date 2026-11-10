module tb_sng_experiment;
    timeunit 1ns;
    timeprecision 1ps;

    logic clk = 0;
    always #5 clk = ~clk;

    logic rst = 1, rx_valid = 0, tx_ready = 0;
    logic [7:0] rx_data = 0, tx_data;
    logic tx_valid;
    int loads = 0, samples = 0;

    sng_experiment #(
        .LUT_FILE_A("Python_Code/lut_a.mem"),
        .LUT_FILE_B("Python_Code/lut_b.mem"),
        .LUT_FILE_S("Python_Code/lut_s.mem"),
        .RX_TIMEOUT_CYCLES(8)
    ) dut (.*);

    always @(posedge clk) begin
        if (dut.load) loads++;
        if (dut.en)   samples++;
    end

    task automatic send_byte(input logic [7:0] data);
        @(negedge clk);
        rx_data = data;
        rx_valid = 1;
        @(negedge clk);
        rx_valid = 0;
    endtask

    task automatic send_word(input logic [15:0] data);
        send_byte(data[7:0]);
        send_byte(data[15:8]);
    endtask

    task automatic run_case(input logic [15:0] length,
                            input logic [79:0] expected);
        int prev_loads, prev_samples;
        prev_loads = loads;
        prev_samples = samples;
        send_byte(8'hA5);
        send_word(16'd1370);
        send_word(16'd1450);
        send_word(16'd1363);
        send_word(16'hACE1);
        send_word(16'h1D2C);
        send_word(16'h5EED);
        send_word(length);
        wait (tx_valid);
        @(negedge clk);

        if (loads != prev_loads + 1 || samples != prev_samples + int'(length))
            $fatal(1, "Bad LOAD or RUN cycle count for L=%0d", length);

        for (int i = 0; i < 10; i++) begin
            // Model the UART transmitter taking time to accept each byte.
            repeat (3) begin
                if (tx_valid !== 1'b1 || tx_data !== expected[8*i +: 8])
                    $fatal(1, "L=%0d byte %0d: expected %h, got %h (valid=%b)",
                           length, i, expected[8*i +: 8], tx_data, tx_valid);
                @(negedge clk);
            end
            tx_ready = 1;
            @(negedge clk);
            tx_ready = 0;
        end

        if (tx_valid !== 1'b0 || loads != prev_loads + 1 ||
            samples != prev_samples + int'(length))
            $fatal(1, "Extra activity after response for L=%0d", length);
        $display("PASS: L=%0d, counts A/B/S/mul/add = %0d/%0d/%0d/%0d/%0d",
                 length, expected[15:0], expected[31:16], expected[47:32],
                 expected[63:48], expected[79:64]);
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 0;
        send_byte(8'h00);  // Not a start byte.
        send_byte(8'hA5);
        send_byte(8'hAA);  // Incomplete packet.
        repeat (10) @(negedge clk);
        if (loads != 0 || samples != 0 || tx_valid !== 1'b0)
            $fatal(1, "Incomplete packet started an experiment");

        // Reference counts use the repo's LUTs and the specified seeds.
        // Expected words are concatenated as {add, mul, S, B, A}.
        run_case(16'd1,     {16'd1,     16'd0,     16'd1,     16'd1,     16'd0});
        run_case(16'd19,    {16'd13,    16'd9,     16'd5,     16'd16,    16'd11});
        run_case(16'd65535, {16'd46939, 16'd32465, 16'd32682, 16'd56045, 16'd37924});
        run_case(16'd0,     '0);
        $display("PASS: controller + three SNGs + arithmetic");
        $finish;
    end

    initial begin
        #800_000;
        $fatal(1, "Simulation timed out");
    end
endmodule
