`timescale 1ns / 1ps

module pe_incha_dual_obuffer #(
    parameter DATA_WIDTH = 8,
    parameter OUT_CHANNEL = 17
)(
    output     [DATA_WIDTH*OUT_CHANNEL-1:0] o_data,
    output reg                              o_valid,
    input      [DATA_WIDTH-1:0]             i_data_a,
    input      [DATA_WIDTH-1:0]             i_data_b,
    input                                   i_valid,
    input                                   clk,
    input                                   rst_n
);

    localparam COUNTER_MAX = (OUT_CHANNEL + 1) / 2;
    localparam OUT_CHANNEL_ODD = COUNTER_MAX * 2 == OUT_CHANNEL ? 0 : 1;
    localparam OBUFFER_DEPTH = OUT_CHANNEL_ODD ? OUT_CHANNEL - 1 : OUT_CHANNEL;

    // Out channel counter
    reg [$clog2(COUNTER_MAX)-1:0] cha_cnt;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            cha_cnt <= 0;
        end else if (i_valid) begin
            cha_cnt <= cha_cnt == COUNTER_MAX - 1 ? 0 : cha_cnt + 1;
        end
    end

    // Output buffer
    reg [DATA_WIDTH-1:0] obuffer[0:OBUFFER_DEPTH-1];
    wire obuffer_en;

    genvar i, j;

    generate
        for (i = 0; i < OBUFFER_DEPTH; i = i + 1) begin : gen0
            assign o_data[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH] = obuffer[i];

            wire [DATA_WIDTH-1:0] buffer_in;

            if (i == OBUFFER_DEPTH - 2) begin : gen1
                assign buffer_in = i_data_a;
            end else if (i == OBUFFER_DEPTH - 1) begin : gen2
                assign buffer_in = i_data_b;
            end else begin : gen3
                assign buffer_in = obuffer[i+2];
            end

            always @ (posedge clk) begin
                if (obuffer_en) begin
                    obuffer[i] <= buffer_in;
                end
            end
        end
    endgenerate

    // If OUT_CHANNEL is odd
    generate
        if (OUT_CHANNEL_ODD) begin : gen4
            reg [DATA_WIDTH-1:0] obuffer_extra;
            
            assign obuffer_en = cha_cnt < COUNTER_MAX - 1 && i_valid;
            assign o_data[DATA_WIDTH*OUT_CHANNEL-1:DATA_WIDTH*(OUT_CHANNEL-1)] = obuffer_extra;

            always @ (posedge clk) begin
                if (cha_cnt == COUNTER_MAX - 1 && i_valid) begin
                    obuffer_extra <= i_data_a;
                end
            end
        end else begin : gen5
            assign obuffer_en = i_valid;
        end
    endgenerate

    // o_valid
    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            o_valid <= 1'b0;
        end else begin
            o_valid <= cha_cnt == COUNTER_MAX - 1 && i_valid;
        end
    end 

endmodule
