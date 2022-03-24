`timescale 1ns / 1ps

module macc #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS = 8,
    parameter NUM_INPUTS = 16,
    parameter INCLUDE_BIAS = 1
)(
    o_data,
    o_valid,
    i_data,
    i_kernel,
    i_bias,
    i_valid,
    clk,
    rst_n
);

    localparam INT_BITS = DATA_WIDTH - FRAC_BITS;

    output [DATA_WIDTH*2-1:0]          o_data;
    output                             o_valid;
    input  [DATA_WIDTH*NUM_INPUTS-1:0] i_data;
    input  [DATA_WIDTH*NUM_INPUTS-1:0] i_kernel;
    input  [DATA_WIDTH-1:0]            i_bias;
    input                              i_valid;
    input                              clk;
    input                              rst_n;

    genvar i;

    // Multipliers stage
    reg [DATA_WIDTH*2*NUM_INPUTS-1:0] stage_1_data;
    reg                               stage_1_valid;

    generate
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin : gen0
            wire signed [DATA_WIDTH-1:0]   pixel = i_data[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH];
            wire signed [DATA_WIDTH-1:0]   kernel = i_kernel[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH];
            wire signed [DATA_WIDTH*2-1:0] product = pixel * kernel;

            always @ (posedge clk) begin
                if (i_valid) begin
                    stage_1_data[(i+1)*DATA_WIDTH*2-1:i*DATA_WIDTH*2] <= product;
                end
            end
        end
    endgenerate

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            stage_1_valid <= 1'b0;
        end else begin
            stage_1_valid <= i_valid;
        end
    end

    // Adder tree stages
    localparam ADDER_LAYERS = $clog2(NUM_INPUTS + (INCLUDE_BIAS ? 1 : 0));
    localparam ADDER_STAGES = (ADDER_LAYERS - 1) / 2 + 1;

    wire [DATA_WIDTH*2*(NUM_INPUTS+1)-1:0] adder_stage_out[0:ADDER_STAGES-1];
    reg  [ADDER_STAGES-2:0] adder_valid;

    generate
        for (i = 0; i < ADDER_STAGES; i = i + 1) begin : gen1
            localparam _NUM_INPUTS = num_inputs(NUM_INPUTS + (INCLUDE_BIAS ? 1 : 0), i);
            localparam _NUM_OUTPUTS = num_outputs(_NUM_INPUTS);

            wire [DATA_WIDTH*2*_NUM_INPUTS-1:0]  adder_stage_in;
            wire [DATA_WIDTH*2*_NUM_OUTPUTS-1:0] adder_stage_out_tmp;
            wire                                 valid;

            if (i == 0) begin : gen2
                wire [DATA_WIDTH*2-1:0] bias_ext = {{INT_BITS{i_bias[DATA_WIDTH-1]}}, i_bias, {FRAC_BITS{1'b0}}};
                assign adder_stage_in = INCLUDE_BIAS ? {stage_1_data, bias_ext} : stage_1_data;
                assign valid = stage_1_valid;
            end else begin : gen3
                assign adder_stage_in = adder_stage_out[i-1][DATA_WIDTH*2*_NUM_INPUTS-1:0];
                assign valid = adder_valid[i-1];
            end

            adder_stage #(
                .DATA_WIDTH (DATA_WIDTH * 2),
                .NUM_INPUTS (_NUM_INPUTS)
            ) u_adder (
                .o_data (adder_stage_out_tmp),
                .i_data (adder_stage_in)
            );

            if (i != ADDER_STAGES - 1) begin : gen4
                reg [DATA_WIDTH*2*_NUM_OUTPUTS-1:0] adder_stage_out_tmp_reg;
                assign adder_stage_out[i][DATA_WIDTH*2*_NUM_OUTPUTS-1:0] = adder_stage_out_tmp_reg;

                always @ (posedge clk) begin
                    if (valid) begin
                        adder_stage_out_tmp_reg <= adder_stage_out_tmp;
                    end
                end

                always @ (posedge clk or negedge rst_n) begin
                    if (~rst_n) begin
                        adder_valid[i] <= 1'b0;
                    end else begin
                        adder_valid[i] <= valid;
                    end
                end
            end else begin : gen5
                assign adder_stage_out[i][DATA_WIDTH*2*_NUM_OUTPUTS-1:0] = adder_stage_out_tmp;
            end
        end
    endgenerate

    assign o_data = adder_stage_out[ADDER_STAGES-1];
    assign o_valid = adder_valid[ADDER_STAGES-2];

    //////////////////////////////////////////////////////////////////////////////////////////////////
    
    function integer num_inputs;
        input integer start_num_inputs;
        input integer stage;
        integer num_layers, num_outputs_1, num_outputs;
        integer j;
        begin: num_inputs_calc
            num_inputs = start_num_inputs;
            for (j = 0; j < stage; j = j + 1) begin
                num_layers    = (num_inputs <= 2) ? 1 : 2;
                num_outputs_1 = (num_inputs - 1) / 2 + 1;
                num_outputs   = (num_layers == 2) ? (num_outputs_1 - 1) / 2 + 1 : num_outputs_1;
                num_inputs    = num_outputs;
            end
        end
    endfunction
    
    function integer num_outputs;
        input integer num_inputs;
        integer num_layers, num_outputs_1;
        begin: num_outputs_calc
            num_layers    = (num_inputs <= 2) ? 1 : 2;
            num_outputs_1 = (num_inputs - 1) / 2 + 1;
            num_outputs   = (num_layers == 2) ? (num_outputs_1 - 1) / 2 + 1 : num_outputs_1;
        end
    endfunction

endmodule
