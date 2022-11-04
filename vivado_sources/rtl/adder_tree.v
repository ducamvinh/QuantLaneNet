`timescale 1ns / 1ps

module adder_tree #(
    parameter DATA_WIDTH = 16,
    parameter NUM_INPUTS = 27
)(
    o_data,
    o_valid,
    i_data,
    i_valid,
    clk,
    rst_n
);

    localparam ADDER_LAYERS      = $clog2(NUM_INPUTS);
    localparam OUTPUT_DATA_WIDTH = DATA_WIDTH + ADDER_LAYERS;

    output [OUTPUT_DATA_WIDTH-1:0]     o_data;
    output                             o_valid;
    input  [DATA_WIDTH*NUM_INPUTS-1:0] i_data;
    input                              i_valid;
    input                              clk;
    input                              rst_n;

    genvar i, j;

    wire [OUTPUT_DATA_WIDTH*NUM_INPUTS-1:0] adder_stage_out [0:ADDER_LAYERS-1];
    reg  [0:0]                              adder_valid     [0:ADDER_LAYERS-1];

    generate
        for (i = 0; i < ADDER_LAYERS; i = i + 1) begin : gen0
            localparam _NUM_INPUTS  = num_inputs(NUM_INPUTS, i);
            localparam _NUM_OUTPUTS = (_NUM_INPUTS - 1) / 2 + 1;
            localparam INPUT_WIDTH  = DATA_WIDTH + i;
            localparam OUTPUT_WIDTH = DATA_WIDTH + i + 1;

            wire signed [INPUT_WIDTH-1:0]  adder_layer_in  [0:_NUM_INPUTS-1];
            wire signed [OUTPUT_WIDTH-1:0] adder_layer_out [0:_NUM_OUTPUTS-1];

            // Assign adders inputs
            for (j = 0; j < _NUM_INPUTS; j = j + 1) begin : gen1
                if (i == 0) begin : gen2
                    assign adder_layer_in[j] = i_data[(j+1)*INPUT_WIDTH-1:j*INPUT_WIDTH];
                end
                else begin : gen3
                    assign adder_layer_in[j] = adder_stage_out[i-1][(j+1)*INPUT_WIDTH-1:j*INPUT_WIDTH];
                end
            end

            // Instantiate adders
            for (j = 0; j < _NUM_OUTPUTS; j = j + 1) begin : gen4
                if (j * 2 + 1 != _NUM_INPUTS) begin : gen5
                    assign adder_layer_out[j] = adder_layer_in[j*2] + adder_layer_in[j*2+1];
                end
                else begin : gen6
                    assign adder_layer_out[j] = {adder_layer_in[j*2][INPUT_WIDTH-1], adder_layer_in[j*2]};
                end
            end

            // Determine valid in
            wire adder_layer_out_reg_en;

            if (i == 0) begin : gen7
                assign adder_layer_out_reg_en = i_valid;
            end
            else begin : gen8
                assign adder_layer_out_reg_en = adder_valid[i-1];
            end

            // Connect adder layer output
            for (j = 0; j < _NUM_OUTPUTS; j = j + 1) begin : gen9
                reg [OUTPUT_WIDTH-1:0] adder_layer_out_reg;
                assign adder_stage_out[i][(j+1)*OUTPUT_WIDTH-1:j*OUTPUT_WIDTH] = adder_layer_out_reg;

                always @ (posedge clk) begin
                    if (adder_layer_out_reg_en) begin
                        adder_layer_out_reg <= adder_layer_out[j];
                    end
                end
            end

            // Adder valid
            always @ (posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    adder_valid[i] <= 1'b0;
                end
                else begin
                    adder_valid[i] <= adder_layer_out_reg_en;
                end
            end
        end
    endgenerate

    assign o_data  = adder_stage_out [ADDER_LAYERS-1][OUTPUT_DATA_WIDTH-1:0];
    assign o_valid = adder_valid     [ADDER_LAYERS-1];

    //////////////////////////////////////////////////////////////////////////////////////////////////

    function integer num_inputs;
        input integer start_num_inputs;
        input integer stage;
        integer num_outputs;
        integer i;
        begin : num_inputs_calc
            num_inputs = start_num_inputs;
            for (i = 0; i < stage; i = i + 1) begin
                num_outputs = (num_inputs - 1) / 2 + 1;
                num_inputs = num_outputs;
            end
        end
    endfunction

endmodule
