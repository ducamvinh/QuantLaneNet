`timescale 1ns / 1ps

module macc_8bit_dual #(
    parameter NUM_INPUTS = 20
)(
    o_data_a,
    o_data_b,
    o_valid,
    i_data_a,
    i_data_b,
    i_data_c,
    i_valid,
    clk,
    rst_n
);

    localparam ADDER_LAYERS      = $clog2(NUM_INPUTS);
    localparam OUTPUT_DATA_WIDTH = 16 + ADDER_LAYERS;

    output [OUTPUT_DATA_WIDTH-1:0] o_data_a;
    output [OUTPUT_DATA_WIDTH-1:0] o_data_b;
    output                         o_valid;
    input  [8*NUM_INPUTS-1:0]      i_data_a;
    input  [8*NUM_INPUTS-1:0]      i_data_b;
    input  [8*NUM_INPUTS-1:0]      i_data_c;
    input                          i_valid;
    input                          clk;
    input                          rst_n;

    genvar i, j, t;

    // Multipliers stage
    wire [16*NUM_INPUTS-1:0] mult_data_out[0:1];
    wire                     mult_valid_o;

    generate
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin : gen0
            wire mult_valid_o_;

            if (i == 0) begin : gen1
                assign mult_valid_o = mult_valid_o_;
            end

            mult_8bit_dual u_mult (
                .prod_ac (mult_data_out[0][(i+1)*16-1:i*16]),
                .prod_bc (mult_data_out[1][(i+1)*16-1:i*16]),
                .o_valid (mult_valid_o_),
                .a       (i_data_a[(i+1)*8-1:i*8]),
                .b       (i_data_b[(i+1)*8-1:i*8]),
                .c       (i_data_c[(i+1)*8-1:i*8]),
                .i_valid (i_valid),
                .clk     (clk),
                .rst_n   (rst_n)
            );
        end
    endgenerate

    // Adder tree stages
    wire valid_dummy;

    adder_tree #(
        .DATA_WIDTH (16),
        .NUM_INPUTS (NUM_INPUTS)
    ) u_adder_tree[1:0] (
        .o_data     ({o_data_b, o_data_a}),
        .o_valid    ({valid_dummy, o_valid}),
        .i_data     ({mult_data_out[1], mult_data_out[0]}),
        .i_valid    (mult_valid_o),
        .clk        (clk),
        .rst_n      (rst_n)
    );

endmodule
