module sng_comparator (
    input  logic [15:0] random_value,
    input  logic [15:0] threshold,
    output logic        stochastic_bit
);

    assign stochastic_bit = (random_value <= threshold);

endmodule
