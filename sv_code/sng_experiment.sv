// Connect the byte-level FSM to three existing SNGs and the arithmetic.
// The UART RX/TX serializers connect to this module's byte ports.
module sng_experiment #(
    parameter string LUT_FILE_A = "lut_a.mem",
    parameter string LUT_FILE_B = "lut_b.mem",
    parameter string LUT_FILE_S = "lut_s.mem",
    parameter logic [7:0] START_BYTE = 8'hA5,
    parameter int RX_TIMEOUT_CYCLES = 1_000_000
) (
    input  logic       clk, rst,
    input  logic       rx_valid,
    input  logic [7:0] rx_data,
    output logic       tx_valid,
    output logic [7:0] tx_data,
    input  logic       tx_ready
);
    logic [10:0] code_a, code_b, code_s;
    logic [15:0] seed_a, seed_b, seed_s;
    logic        load, en, a, b, s;
    logic [4:0]  stream_bits;

    sng_controller #(
        .START_BYTE(START_BYTE), .RX_TIMEOUT_CYCLES(RX_TIMEOUT_CYCLES)
    ) u_controller (
        .clk(clk), .rst(rst),
        .rx_valid(rx_valid), .rx_data(rx_data),
        .tx_valid(tx_valid), .tx_data(tx_data), .tx_ready(tx_ready),
        .code_a(code_a), .code_b(code_b), .code_s(code_s),
        .seed_a(seed_a), .seed_b(seed_b), .seed_s(seed_s),
        .load(load), .en(en), .stream_bits(stream_bits)
    );

    sng #(.LUT_FILE(LUT_FILE_A),
          .TAPS(16'hB400), .SHUFFLE_MAP(64'h02A8_D316_79CE_4F5B)) u_a (
        .clk(clk), .rst(rst), .load(load), .en(en),
        .code(code_a), .seed(seed_a), .threshold(), .stoch_bit(a)
    );

    sng #(.LUT_FILE(LUT_FILE_B),
          .TAPS(16'hD008), .SHUFFLE_MAP(64'hB649_A320_17F5_DEC8)) u_b (
        .clk(clk), .rst(rst), .load(load), .en(en),
        .code(code_b), .seed(seed_b), .threshold(), .stoch_bit(b)
    );

    sng #(.LUT_FILE(LUT_FILE_S),
          .TAPS(16'h8016), .SHUFFLE_MAP(64'h809E_B7DF_C3A1_6524)) u_s (
        .clk(clk), .rst(rst), .load(load), .en(en),
        .code(code_s), .seed(seed_s), .threshold(), .stoch_bit(s)
    );

    assign stream_bits = {s ? b : a, a & b, s, b, a};
endmodule
