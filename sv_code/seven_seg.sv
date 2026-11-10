// seven_seg.sv
//
// Drives the Nexys 4 DDR's 8-digit seven-segment display with a 32-bit value
// as 8 hex digits. The digits share one set of segment lines, so they are lit
// one at a time, fast enough that they all look on at once.
//
// Segments and anodes are active low on this board.
// seg[0] = CA (top) ... seg[6] = CG (middle). an[0] is the rightmost digit.
//
// REFRESH_BITS sets the scan rate: each digit is lit for 2^(REFRESH_BITS-3)
// clocks. The default 20 gives 1.3 ms per digit at 100 MHz, about 95 Hz for
// the whole display, which is flicker free.

module seven_seg #(
    parameter int REFRESH_BITS = 20
) (
    input  logic        clk,
    input  logic [31:0] value,   // digit i shows value[4*i +: 4]
    input  logic [7:0]  dp_on,   // light the decimal point of digit i
    output logic [6:0]  seg,     // active low
    output logic        dp,      // active low
    output logic [7:0]  an       // active low
);

    // ---- Digit scan ----
    //
    // The top 3 bits of a free running counter pick the digit to light.
    logic [REFRESH_BITS-1:0] refresh_cnt = '0;
    logic [2:0]              digit;
    logic [3:0]              nibble;

    always_ff @(posedge clk)
        refresh_cnt <= refresh_cnt + 1'b1;

    assign digit  = refresh_cnt[REFRESH_BITS-1 -: 3];
    assign nibble = value[4*digit +: 4];

    // ---- Hex to segments ----
    //
    // Patterns are written active high as {g,f,e,d,c,b,a}, then inverted.
    logic [6:0] seg_on;

    always_comb
        case (nibble)
            4'h0: seg_on = 7'b011_1111;
            4'h1: seg_on = 7'b000_0110;
            4'h2: seg_on = 7'b101_1011;
            4'h3: seg_on = 7'b100_1111;
            4'h4: seg_on = 7'b110_0110;
            4'h5: seg_on = 7'b110_1101;
            4'h6: seg_on = 7'b111_1101;
            4'h7: seg_on = 7'b000_0111;
            4'h8: seg_on = 7'b111_1111;
            4'h9: seg_on = 7'b110_1111;
            4'hA: seg_on = 7'b111_0111;
            4'hB: seg_on = 7'b111_1100;
            4'hC: seg_on = 7'b011_1001;
            4'hD: seg_on = 7'b101_1110;
            4'hE: seg_on = 7'b111_1001;
            4'hF: seg_on = 7'b111_0001;
        endcase

    // ---- Outputs ----
    //
    // Registered so the pins switch cleanly, one clock after the scan
    // counter moves.
    always_ff @(posedge clk) begin
        seg <= ~seg_on;
        dp  <= ~dp_on[digit];
        an  <= ~(8'b1 << digit);
    end

endmodule
