module demo_uart (
    input logic clk, reset, rx,
    output logic tx,
    output logic [7:0] received,
    output logic rx_valid,
    input logic [7:0] transmit,
    input logic tx_start,
    output logic tx_busy
);
    // 100 MHz / 115200, rounded to the nearest clock.
    localparam int BIT_CLKS = 868;
    (* ASYNC_REG = "TRUE" *) logic [1:0] rx_sync;
    logic [9:0] rx_timer, tx_timer;
    logic [3:0] rx_index, tx_left;
    logic [7:0] rx_shift;
    logic [9:0] tx_shift;
    typedef enum logic [1:0] { IDLE, START, DATA, STOP } rx_state_t;
    rx_state_t rx_state;

    assign tx_busy = (tx_left != 0);
    assign tx = tx_shift[0];

    always_ff @(posedge clk) begin
        if (reset) begin
            rx_sync <= 2'b11;
            rx_state <= IDLE;
            rx_timer <= 0;
            rx_index <= 0;
            rx_shift <= 0;
            received <= 0;
            rx_valid <= 0;
            tx_timer <= 0;
            tx_left <= 0;
            tx_shift <= '1;
        end else begin
            rx_sync <= {rx_sync[0], rx};
            rx_valid <= 0;
            if (rx_state == IDLE) begin
                if (!rx_sync[1]) begin
                    rx_timer <= 10'(BIT_CLKS / 2 - 1);
                    rx_state <= START;
                end
            end else if (rx_timer != 0) begin
                rx_timer <= rx_timer - 1'b1;
            end else begin
                rx_timer <= 10'(BIT_CLKS - 1);
                case (rx_state)
                    START: begin
                        rx_index <= 0;
                        rx_state <= rx_sync[1] ? IDLE : DATA;
                    end
                    DATA: begin
                        rx_shift <= {rx_sync[1], rx_shift[7:1]};
                        rx_index <= rx_index + 1'b1;
                        if (rx_index == 7) rx_state <= STOP;
                    end
                    STOP: begin
                        if (rx_sync[1]) begin
                            received <= rx_shift;
                            rx_valid <= 1;
                        end
                        rx_state <= IDLE;
                    end
                    default: rx_state <= IDLE;
                endcase
            end

            if (!tx_busy) begin
                if (tx_start) begin
                    tx_shift <= {1'b1, transmit, 1'b0};
                    tx_left <= 10;
                    tx_timer <= 10'(BIT_CLKS - 1);
                end
            end else if (tx_timer == 0) begin
                tx_shift <= {1'b1, tx_shift[9:1]};
                tx_left <= tx_left - 1'b1;
                tx_timer <= 10'(BIT_CLKS - 1);
            end else begin
                tx_timer <= tx_timer - 1'b1;
            end
        end
    end
endmodule
