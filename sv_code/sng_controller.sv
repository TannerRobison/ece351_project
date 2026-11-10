// Run controller at the UART byte boundary. See sng_controller.md for framing.
module sng_controller #(
    parameter logic [7:0] START_BYTE = 8'hA5,
    parameter int RX_TIMEOUT_CYCLES = 1_000_000  // >= 1; 10 ms at 100 MHz
) (
    input  logic        clk,
    input  logic        rst,       // synchronous, active high
    input  logic        rx_valid,  // one pulse per received byte
    input  logic [7:0]  rx_data,
    output logic        tx_valid,
    output logic [7:0]  tx_data,
    input  logic        tx_ready,  // byte accepted on edge with valid && ready

    output logic [10:0] code_a, code_b, code_s,
    output logic [15:0] seed_a, seed_b, seed_s,
    output logic        load,     // pulse to read LUTs and seed LFSRs
    output logic        en,       // step all LFSRs and count current bits
    input  logic [4:0]  stream_bits  // {scaled_add, multiply, s, b, a}
);
    typedef enum logic [2:0] {IDLE, RECEIVE, LOAD, RUN, REPORT} state_t;
    state_t state;

    localparam int TIMEOUT_W = RX_TIMEOUT_CYCLES > 1 ? $clog2(RX_TIMEOUT_CYCLES) : 1;
    localparam logic [TIMEOUT_W-1:0] TIMEOUT_LAST = TIMEOUT_W'(RX_TIMEOUT_CYCLES - 1);

    logic [TIMEOUT_W-1:0] idle_cycles;
    logic [3:0] rx_index, tx_index;
    logic [111:0] config_bytes;
    logic [15:0] run_length, remaining;
    logic [4:0][15:0] ones;
    logic [15:0] report_word;

    // Byte zero is the least significant byte of the first 16-bit field.
    assign {run_length, seed_s, seed_b, seed_a} = config_bytes[111:48];
    assign code_a = config_bytes[10:0];
    assign code_b = config_bytes[26:16];
    assign code_s = config_bytes[42:32];

    assign load = !rst && (state == LOAD);
    assign en = !rst && (state == RUN);
    assign tx_valid = !rst && (state == REPORT);
    assign report_word = ones[tx_index[3:1]];
    assign tx_data = tx_valid ? (tx_index[0] ? report_word[15:8] : report_word[7:0]) : 8'h00;

    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            config_bytes <= '0;
            idle_cycles  <= '0;
            rx_index     <= '0;
            tx_index     <= '0;
            remaining    <= '0;
            ones         <= '0;
        end else begin
            case (state)
                IDLE: if (rx_valid && rx_data == START_BYTE) begin
                    rx_index    <= '0;
                    idle_cycles <= '0;
                    state       <= RECEIVE;
                end

                RECEIVE: if (rx_valid) begin
                    config_bytes[8*rx_index +: 8] <= rx_data;
                    idle_cycles <= '0;
                    if (rx_index == 4'd13)
                        state <= LOAD;
                    else
                        rx_index <= rx_index + 1'b1;
                end else if (idle_cycles == TIMEOUT_LAST) begin
                    state <= IDLE;
                end else begin
                    idle_cycles <= idle_cycles + 1'b1;
                end

                LOAD: begin
                    // The SNG captures its synchronous LUT output and seed
                    // on this edge. The seeded sample is counted next edge.
                    ones      <= '0;
                    remaining <= run_length;
                    tx_index  <= '0;
                    if (run_length == 0)
                        state <= REPORT;
                    else
                        state <= RUN;
                end

                RUN: begin
                    for (int i = 0; i < 5; i++)
                        ones[i] <= ones[i] + 16'(stream_bits[i]);
                    remaining <= remaining - 1'b1;
                    // Count this last sample before presenting the result.
                    if (remaining == 16'd1)
                        state <= REPORT;
                end

                REPORT: if (tx_ready) begin
                    if (tx_index == 4'd9)
                        state <= IDLE;
                    else
                        tx_index <= tx_index + 1'b1;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
