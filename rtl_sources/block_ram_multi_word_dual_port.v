`timescale 1ns / 1ps

module block_ram_multi_word_dual_port #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 64,
    parameter NUM_WORDS = 9 * 32,
    parameter RAM_STYLE = "auto"  
)(
    output reg [DATA_WIDTH*NUM_WORDS-1:0] rd_data_a,
    output reg [DATA_WIDTH*NUM_WORDS-1:0] rd_data_b,
    input      [DATA_WIDTH-1:0]           wr_data_a,
    input      [DATA_WIDTH-1:0]           wr_data_b,
    input      [$clog2(DEPTH)-1:0]        addr_a,
    input      [$clog2(DEPTH)-1:0]        addr_b,
    input                                 rd_en_a,
    input                                 rd_en_b,
    input      [NUM_WORDS-1:0]            wr_en_a,
    input      [NUM_WORDS-1:0]            wr_en_b,
    input                                 clk
);

    (* ram_style = RAM_STYLE *) reg [DATA_WIDTH*NUM_WORDS-1:0] ram[0:DEPTH-1];
    genvar i;

    // PORTA
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
            rd_data_a <= ram[addr_a];
        end
    end
    
    // PORTB
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
            rd_data_b <= ram[addr_b];
        end
    end

endmodule
