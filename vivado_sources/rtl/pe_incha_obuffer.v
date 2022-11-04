`timescale 1ns / 1ps

module pe_incha_obuffer #(
    parameter DATA_WIDTH  = 8,
    parameter NUM_INPUTS  = 2,
    parameter OUT_CHANNEL = 8
)(
    output     [DATA_WIDTH*OUT_CHANNEL-1:0] o_data,
    output reg                              o_valid,
    input      [DATA_WIDTH*NUM_INPUTS-1:0]  i_data,
    input                                   i_valid,
    input                                   clk,
    input                                   rst_n
);

    localparam COUNTER_MAX   = (OUT_CHANNEL + NUM_INPUTS - 1) / NUM_INPUTS;
    localparam OBUFFER_DEPTH = OUT_CHANNEL - OUT_CHANNEL % NUM_INPUTS;

    genvar i;

    // Out channel counter
    reg [$clog2(COUNTER_MAX)-1:0] cha_cnt;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            cha_cnt <= 0;
        end
        else if (i_valid) begin
            cha_cnt <= cha_cnt == COUNTER_MAX - 1 ? 0 : cha_cnt + 1;
        end
    end

    // Output buffer
    reg  [DATA_WIDTH-1:0] obuffer    [0:OBUFFER_DEPTH-1];
    wire                  obuffer_en;

    generate
        for (i = 0; i < OBUFFER_DEPTH; i = i + 1) begin : gen0
            assign o_data[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH] = obuffer[i];

            wire [DATA_WIDTH-1:0] buffer_in;

            if (OBUFFER_DEPTH - i <= NUM_INPUTS) begin : gen1
                localparam J = i % NUM_INPUTS;
                assign buffer_in = i_data[(J+1)*DATA_WIDTH-1:J*DATA_WIDTH];
            end
            else begin : gen2
                assign buffer_in = obuffer[i+NUM_INPUTS];
            end

            always @ (posedge clk) begin
                if (obuffer_en) begin
                    obuffer[i] <= buffer_in;
                end
            end
        end
    endgenerate

    // obuffer_valid
    generate
        if (OUT_CHANNEL % NUM_INPUTS) begin : gen3
            assign obuffer_en = cha_cnt < COUNTER_MAX - 1 && i_valid;

            for (i = 0; i < OUT_CHANNEL % NUM_INPUTS; i = i + 1) begin : gen4
                localparam J = OBUFFER_DEPTH + i;

                reg [DATA_WIDTH-1:0] obuffer_extra;
                assign o_data[(J+1)*DATA_WIDTH-1:J*DATA_WIDTH] = obuffer_extra;

                always @ (posedge clk) begin
                    if (cha_cnt == COUNTER_MAX - 1 && i_valid) begin
                        obuffer_extra <= i_data[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH];
                    end
                end
            end
        end
        else begin : gen5
            assign obuffer_en = i_valid;
        end
    endgenerate

    // o_valid
    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            o_valid <= 1'b0;
        end
        else begin
            o_valid <= cha_cnt == COUNTER_MAX - 1 && i_valid;
        end
    end

endmodule
