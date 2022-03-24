`timescale 1ns / 1ps

module block_ram_multi_word #(
    parameter DATA_WIDTH = 16,
    parameter DEPTH = 128,
    parameter NUM_WORDS = 9 * 32,
    parameter RAM_STYLE = "auto"
)(
    output reg [DATA_WIDTH*NUM_WORDS-1:0] rd_data,
    input      [DATA_WIDTH-1:0]           wr_data,
    input      [$clog2(DEPTH)-1:0]        rd_addr,
    input      [$clog2(DEPTH)-1:0]        wr_addr,
    input      [NUM_WORDS-1:0]            wr_en,
    input                                 rd_en,
    input                                 clk
);

    (* ram_style = RAM_STYLE *) reg [DATA_WIDTH*NUM_WORDS-1:0] ram[0:DEPTH-1];

    // Write port
    genvar i;

    generate
        for (i = 0; i < NUM_WORDS; i = i + 1) begin : gen0
            always @ (posedge clk) begin
                if (wr_en[i]) begin
                    ram[wr_addr][(i+1)*DATA_WIDTH-1:i*DATA_WIDTH] <= wr_data;
                end
            end
        end
    endgenerate

    // Read port
    always @ (posedge clk) begin
        if (rd_en) begin
            rd_data <= ram[rd_addr];
        end else begin
            rd_data <= rd_data;
        end
    end

endmodule
