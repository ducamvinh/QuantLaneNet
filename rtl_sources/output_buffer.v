`timescale 1ns / 1ps

module output_buffer #(
    parameter DATA_WIDTH = 16,
    parameter OUT_CHANNEL = 16
)(
    output     [DATA_WIDTH*OUT_CHANNEL-1:0] o_data,
    output reg                              o_valid,
    input      [DATA_WIDTH-1:0]             i_data,
    input                                   i_valid,
    input                                   clk,
    input                                   rst_n
);

    reg [DATA_WIDTH-1:0] out_buffer[0:OUT_CHANNEL-1];
    reg [$clog2(OUT_CHANNEL)-1:0] cha_cnt;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            cha_cnt <= 0;
        end else if (i_valid) begin
            cha_cnt <= cha_cnt == OUT_CHANNEL - 1 ? 0 : cha_cnt + 1;
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            o_valid <= 1'b0;
        end else begin
            o_valid <= cha_cnt == OUT_CHANNEL - 1 && i_valid;
        end
    end

    genvar i;

    generate
        for (i = 0; i < OUT_CHANNEL; i = i + 1) begin : gen0
            assign o_data[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH] = out_buffer[i];

            always @ (posedge clk) begin
                if (i_valid) begin
                    out_buffer[i] <= i == OUT_CHANNEL - 1 ? i_data : out_buffer[i+1];
                end
            end
        end
    endgenerate

endmodule
