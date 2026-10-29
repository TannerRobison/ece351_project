module sng_comparator #(
    parameter int WIDTH = 16
) (
    input  logic [WIDTH-1:0] random_value,
    input  logic [WIDTH-1:0] threshold,
    output logic             stochastic_bit
);

    assign stochastic_bit = (random_value <= threshold);

endmodule