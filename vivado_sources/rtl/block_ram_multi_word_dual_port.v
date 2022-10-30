`timescale 1ns / 1ps

module block_ram_multi_word_dual_port #(
    parameter DATA_WIDTH      = 8,
    parameter DEPTH           = 64,
    parameter NUM_WORDS       = 4,
    parameter RAM_STYLE       = "auto",
    parameter OUTPUT_REGISTER = "false"
)(
    output [DATA_WIDTH*NUM_WORDS-1:0] rd_data_a,
    output [DATA_WIDTH*NUM_WORDS-1:0] rd_data_b,
    input  [DATA_WIDTH-1:0]           wr_data_a,
    input  [DATA_WIDTH-1:0]           wr_data_b,
    input  [$clog2(DEPTH)-1:0]        addr_a,
    input  [$clog2(DEPTH)-1:0]        addr_b,
    input                             rd_en_a,
    input                             rd_en_b,
    input  [NUM_WORDS-1:0]            wr_en_a,
    input  [NUM_WORDS-1:0]            wr_en_b,
    input                             clk
);

    (* ram_style = RAM_STYLE *) reg [DATA_WIDTH*NUM_WORDS-1:0] ram[0:DEPTH-1];
    genvar i;

    // PORTA
    reg [DATA_WIDTH*NUM_WORDS-1:0] rd_data_a_reg;

    generate
        for (i = 0; i < NUM_WORDS; i = i + 1) begin : gen0
            always @ (posedge clk) begin
                if (wr_en_a[i]) begin
                    ram[addr_a][(i+1)*DATA_WIDTH-1:i*DATA_WIDTH] <= wr_data_a;
                end
            end
        end
    endgenerate

    always @ (posedge clk) begin
        if (rd_en_a) begin
            rd_data_a_reg <= ram[addr_a];
        end
    end

    // PORTB
    reg [DATA_WIDTH*NUM_WORDS-1:0] rd_data_b_reg;

    generate
        for (i = 0; i < NUM_WORDS; i = i + 1) begin : gen1
            always @ (posedge clk) begin
                if (wr_en_b[i]) begin
                    ram[addr_b][(i+1)*DATA_WIDTH-1:i*DATA_WIDTH] <= wr_data_b;
                end
            end
        end
    endgenerate

    always @ (posedge clk) begin
        if (rd_en_b) begin
            rd_data_b_reg <= ram[addr_b];
        end
    end

    // Output
    generate
        if (OUTPUT_REGISTER == "true") begin : gen2
            reg [DATA_WIDTH*NUM_WORDS-1:0] rd_data_a_reg_2;
            reg [DATA_WIDTH*NUM_WORDS-1:0] rd_data_b_reg_2;

            always @ (posedge clk) begin
                rd_data_a_reg_2 <= rd_data_a_reg;
                rd_data_b_reg_2 <= rd_data_b_reg;
            end

            assign rd_data_a = rd_data_a_reg_2;
            assign rd_data_b = rd_data_b_reg_2;
        end

        else if (OUTPUT_REGISTER == "false") begin : gen3
            assign rd_data_a = rd_data_a_reg;
            assign rd_data_b = rd_data_b_reg;
        end
    endgenerate

endmodule
