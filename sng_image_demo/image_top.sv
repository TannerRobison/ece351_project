module image_top (
    input logic clk,
    input logic reset_n,
    input logic uart_rx,
    output logic uart_tx
);
    (* ASYNC_REG = "TRUE" *) logic [1:0] reset_sync = 0;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) reset_sync <= 0;
        else reset_sync <= {reset_sync[0], 1'b1};
    end
    wire reset = !reset_sync[1];

    logic [15:0] lut_a [0:2047];
    logic [15:0] lut_b [0:2047];
    initial begin
        $readmemh("lut_a.mem", lut_a);
        $readmemh("lut_b.mem", lut_b);
    end

    logic [7:0] received, transmit;
    logic rx_valid, tx_start, tx_busy;
    demo_uart uart(.clk(clk), .reset(reset), .rx(uart_rx), .tx(uart_tx),
                   .received(received), .rx_valid(rx_valid), .transmit(transmit),
                   .tx_start(tx_start), .tx_busy(tx_busy));

    typedef enum logic [2:0] { RECEIVE, LOOKUP, COUNT, SEND_LO,
                               WAIT_LO_START, WAIT_LO_END, WAIT_HI } state_t;
    state_t state;
    logic [2:0] position;
    logic [10:0] code_a, code_b;
    logic [15:0] threshold_a, threshold_b;
    logic [15:0] random_a, random_b, samples, ones, result;
    wire product_bit = (random_a <= threshold_a) && (random_b <= threshold_b);
    wire [15:0] next_ones = ones + {15'b0, product_bit};

    always_ff @(posedge clk) begin
        threshold_a <= lut_a[code_a];
        threshold_b <= lut_b[code_b];
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= RECEIVE;
            position <= 0;
            code_a <= 0;
            code_b <= 0;
            random_a <= 16'h0001;
            random_b <= 16'hACE1;
            samples <= 0;
            ones <= 0;
            result <= 0;
            transmit <= 0;
            tx_start <= 0;
        end else begin
            tx_start <= 0;
            case (state)
                RECEIVE: if (rx_valid) begin
                    if (received == 8'hA5) position <= 1;
                    else if (received[7]) position <= 0;
                    else case (position)
                        1: begin code_a[6:0] <= received[6:0]; position <= 2; end
                        2: begin code_a[10:7] <= received[3:0]; position <= 3; end
                        3: begin code_b[6:0] <= received[6:0]; position <= 4; end
                        4: begin
                            code_b[10:7] <= received[3:0];
                            position <= 0;
                            state <= LOOKUP;
                        end
                        default: position <= 0;
                    endcase
                end
                LOOKUP: begin
                    samples <= 0;
                    ones <= 0;
                    state <= COUNT;
                end
                COUNT: begin
                    random_a <= (random_a >> 1) ^ (random_a[0] ? 16'hB400 : 16'h0000);
                    random_b <= (random_b >> 1) ^ (random_b[0] ? 16'hD008 : 16'h0000);
                    ones <= next_ones;
                    samples <= samples + 1'b1;
                    if (samples == 16'd65534) begin
                        result <= next_ones;
                        state <= SEND_LO;
                    end
                end
                SEND_LO: begin
                    transmit <= result[7:0];
                    tx_start <= 1;
                    state <= WAIT_LO_START;
                end
                WAIT_LO_START: if (tx_busy) state <= WAIT_LO_END;
                WAIT_LO_END: if (!tx_busy) begin
                    transmit <= result[15:8];
                    tx_start <= 1;
                    state <= WAIT_HI;
                end
                // A complete new UART frame takes longer than the remaining
                // fraction of the stop bit when the host reads the high byte.
                WAIT_HI: if (tx_busy) state <= RECEIVE;
                default: state <= RECEIVE;
            endcase
        end
    end
endmodule
