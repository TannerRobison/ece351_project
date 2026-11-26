// Board wrapper for the EXISTING project controller and SNGs.
// demo_uart: 100 MHz, 115200 baud, 8 data bits, no parity, 1 stop bit.
module nexys4ddr_image_top (
    input logic CLK100MHZ,
    input logic CPU_RESETN,
    input logic UART_RX,
    output logic UART_TX
);
    (* ASYNC_REG = "TRUE" *) logic [1:0] reset_sync = 2'b00;
    always_ff @(posedge CLK100MHZ or negedge CPU_RESETN)
        if (!CPU_RESETN) reset_sync <= 2'b00;
        else reset_sync <= {reset_sync[0], 1'b1};
    wire rst = !reset_sync[1];
    logic rx_valid, tx_valid, tx_ready, tx_busy;
    logic [7:0] rx_data, tx_data;

    // Combinational handshake: on the SAME rising edge the controller
    // advances its response index and the idle UART captures that byte.
    // A registered start pulse without a holding adapter would lose bytes.
    assign tx_ready = !tx_busy && !rst;
    demo_uart u_uart (
        .clk(CLK100MHZ), .reset(rst), .rx(UART_RX), .tx(UART_TX),
        .received(rx_data), .rx_valid(rx_valid),
        .transmit(tx_data), .tx_start(tx_valid && tx_ready), .tx_busy(tx_busy)
    );
    sng_experiment u_experiment (
        .clk(CLK100MHZ), .rst(rst),
        .rx_valid(rx_valid), .rx_data(rx_data),
        .tx_valid(tx_valid), .tx_data(tx_data), .tx_ready(tx_ready)
    );
endmodule
