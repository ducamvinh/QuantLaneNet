`timescale 1ns / 1ps

module macc_8bit_single_1_to_n #(
    parameter NUM_INPUTS = 9,
    parameter NUM_MACC   = 5
)(
    o_data,
    o_valid,
    input_n,
    input_common,
    i_valid,
    clk,
    rst_n
);

    localparam ADDER_LAYERS      = $clog2(NUM_INPUTS);
    localparam OUTPUT_DATA_WIDTH = 16 + ADDER_LAYERS;

    output [OUTPUT_DATA_WIDTH*NUM_MACC-1:0] o_data;
    output                                  o_valid;
    input  [8*NUM_INPUTS*NUM_MACC-1:0]      input_n;
    input  [8*NUM_INPUTS-1:0]               input_common;
    input                                   i_valid;
    input                                   clk;
    input                                   rst_n;

    genvar i, j;

    wire [16*NUM_INPUTS-1:0] mult_data[0:NUM_MACC-1];
    wire mult_valid;

    // Multiplier stages
    generate
        for (i = 0; i < NUM_MACC; i = i + 2) begin : gen0
            if (i != NUM_MACC - 1) begin : gen1
                wire [8*NUM_INPUTS-1:0] mult_in_a = input_n[(i+1)*8*NUM_INPUTS-1:(i+0)*8*NUM_INPUTS];
                wire [8*NUM_INPUTS-1:0] mult_in_b = input_n[(i+2)*8*NUM_INPUTS-1:(i+1)*8*NUM_INPUTS];

                for (j = 0; j < NUM_INPUTS; j = j + 1) begin : gen2
                    wire mult_valid_;

                    if (i == 0 && j == 0) begin : gen3
                        assign mult_valid = mult_valid_;
                    end

                    mult_8bit_dual u_mult_dual (
                        .prod_ac (mult_data[i][(j+1)*16-1:j*16]),
                        .prod_bc (mult_data[i+1][(j+1)*16-1:j*16]),
                        .o_valid (mult_valid_),
                        .a       (mult_in_a[(j+1)*8-1:j*8]),
                        .b       (mult_in_b[(j+1)*8-1:j*8]),
                        .c       (input_common[(j+1)*8-1:j*8]),
                        .i_valid (i_valid),
                        .clk     (clk),
                        .rst_n   (rst_n)
                    );
                end
            end
            else begin : gen4
                wire mult_valid_;

                if (i == 0) begin : gen5
                    assign mult_valid = mult_valid_;
                end

                mult_8bit_single_array #(
                    .NUM_INPUTS (NUM_INPUTS)
                ) u_mult_single (
                    .o_data     (mult_data[i]),
                    .o_valid    (mult_valid_),
                    .i_data_a   (input_n[(i+1)*8*NUM_INPUTS-1:(i+0)*8*NUM_INPUTS]),
                    .i_data_b   (input_common),
                    .i_valid    (i_valid),
                    .clk        (clk),
                    .rst_n      (rst_n)
                );
            end
        end
    endgenerate

    // Adder tree stages
    generate
        for (i = 0; i < NUM_MACC; i = i + 1) begin : gen6
            wire adder_valid;

            if (i == 0) begin : gen7
                assign o_valid = adder_valid;
            end

            adder_tree #(
                .DATA_WIDTH (16),
                .NUM_INPUTS (NUM_INPUTS)
            ) u_adder (
                .o_data     (o_data[(i+1)*OUTPUT_DATA_WIDTH-1:i*OUTPUT_DATA_WIDTH]),
                .o_valid    (adder_valid),
                .i_data     (mult_data[i]),
                .i_valid    (mult_valid),
                .clk        (clk),
                .rst_n      (rst_n)
            );
        end
    endgenerate

endmodule

(* use_dsp = "yes" *) module mult_8bit_single_array #(
    parameter NUM_INPUTS = 10
)(
    output reg [16*NUM_INPUTS-1:0] o_data,
    output                         o_valid,
    input      [8*NUM_INPUTS-1:0]  i_data_a,
    input      [8*NUM_INPUTS-1:0]  i_data_b,
    input                          i_valid,
    input                          clk,
    input                          rst_n
);

    reg [2:0] valid;
    assign o_valid = valid[2];

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            valid <= 3'b000;
        end
        else begin
            valid <= {valid[1:0], i_valid};
        end
    end

    genvar i;

    generate
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin : gen0
            reg signed [7:0]  i_data_a_;
            reg signed [7:0]  i_data_b_;
            reg signed [15:0] mult_prod;

            always @ (posedge clk) begin
                if (i_valid) begin
                    i_data_a_ <= i_data_a[(i+1)*8-1:i*8];
                    i_data_b_ <= i_data_b[(i+1)*8-1:i*8];
                end

                if (valid[0]) begin
                    mult_prod <= i_data_a_ * i_data_b_;
                end

                if (valid[1]) begin
                    o_data[(i+1)*16-1:i*16] <= mult_prod;
                end
            end
        end
    endgenerate

endmodule
