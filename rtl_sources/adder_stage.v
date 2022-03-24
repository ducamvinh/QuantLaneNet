`timescale 1ns / 1ps

module adder_stage #(
    parameter DATA_WIDTH = 16,
    parameter NUM_INPUTS = 9
)(
    o_data,
    i_data
);

    localparam NUM_LAYERS = (NUM_INPUTS <= 2) ? 1 : 2;
    localparam NUM_OUTPUTS_MID = (NUM_INPUTS - 1) / 2 + 1;
    localparam NUM_OUTPUTS = (NUM_LAYERS == 2) ? (NUM_OUTPUTS_MID - 1) / 2 + 1 : NUM_OUTPUTS_MID;

    output [DATA_WIDTH*NUM_OUTPUTS-1:0]  o_data;
    input  [DATA_WIDTH*NUM_INPUTS-1:0]   i_data;

    // Layer 1
    wire [DATA_WIDTH*NUM_OUTPUTS_MID-1:0] layer_1_out;

    adder_layer #(
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_INPUTS (NUM_INPUTS)
    ) u_layer_0 (
        .o_data (layer_1_out),
        .i_data (i_data)
    );

    // Layer 2
    generate
        if (NUM_LAYERS == 2) begin : gen0
            adder_layer #(
                .DATA_WIDTH (DATA_WIDTH),
                .NUM_INPUTS (NUM_OUTPUTS_MID)
            ) u_layer_1 (
                .o_data (o_data),
                .i_data (layer_1_out)
            );
        end else begin : gen1
            assign o_data = layer_1_out;
        end
    endgenerate

endmodule
