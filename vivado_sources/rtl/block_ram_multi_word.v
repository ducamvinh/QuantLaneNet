`timescale 1ns / 1ps

module block_ram_multi_word #(
    parameter DATA_WIDTH      = 8,
    parameter DEPTH           = 64,
    parameter NUM_WORDS       = 4,
    parameter RAM_STYLE       = "auto",
    parameter OUTPUT_REGISTER = "false"
)(
    output [DATA_WIDTH*NUM_WORDS-1:0] rd_data,
    input  [DATA_WIDTH-1:0]           wr_data,
    input  [$clog2(DEPTH)-1:0]        rd_addr,
    input  [$clog2(DEPTH)-1:0]        wr_addr,
    input  [NUM_WORDS-1:0]            wr_en,
    input                             rd_en,
    input                             clk
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
    reg [DATA_WIDTH*NUM_WORDS-1:0] rd_data_reg;

    always @ (posedge clk) begin
        if (rd_en) begin
            rd_data_reg <= ram[rd_addr];
        end
        else begin
            rd_data_reg <= rd_data_reg;
        end
    end

    // Output
    generate
        if (OUTPUT_REGISTER == "true") begin : gen1
            reg [DATA_WIDTH*NUM_WORDS-1:0] rd_data_reg_2;

            always @ (posedge clk) begin
                rd_data_reg_2 <= rd_data_reg;
            end

            assign rd_data = rd_data_reg_2;
        end

        else if (OUTPUT_REGISTER == "false") begin : gen2
            assign rd_data = rd_data_reg;
        end
    endgenerate

endmodule
