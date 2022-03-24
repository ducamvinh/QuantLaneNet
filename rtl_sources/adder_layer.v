`timescale 1ns / 1ps

module adder_layer #(
    parameter DATA_WIDTH = 32,
    parameter NUM_INPUTS = 9
)(
    o_data,
    i_data
);

    localparam NUM_OUTPUTS = (NUM_INPUTS - 1) / 2 + 1;

    output [DATA_WIDTH*NUM_OUTPUTS-1:0] o_data;
    input  [DATA_WIDTH*NUM_INPUTS-1:0]  i_data;

    wire signed [DATA_WIDTH-1:0] i_data_array[0:NUM_INPUTS-1];
    wire signed [DATA_WIDTH-1:0] o_data_array[0:NUM_OUTPUTS-1];

    genvar i;

    generate
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin : gen0
            assign i_data_array[i] = i_data[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH];
        end

        for (i = 0; i < NUM_OUTPUTS; i = i + 1) begin : gen1
            assign o_data[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH] = o_data_array[i];
        end

        for (i = 0; i < NUM_OUTPUTS - 1; i = i + 1) begin : gen2
            assign o_data_array[i] = i_data_array[2*i+1] + i_data_array[2*i];
        end

        if ((NUM_INPUTS / 2) < NUM_OUTPUTS) begin : gen3
            assign o_data_array[NUM_OUTPUTS-1] = i_data_array[NUM_INPUTS-1];
        end else begin : gen4
            assign o_data_array[NUM_OUTPUTS-1] = i_data_array[NUM_INPUTS-1] + i_data_array[NUM_INPUTS-2];
        end
    endgenerate

endmodule
