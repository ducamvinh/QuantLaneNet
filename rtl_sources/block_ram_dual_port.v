`timescale 1ns / 1ps

module block_ram_dual_port #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 2**16,
    parameter RAM_STYLE = "auto"
)(
    output reg [DATA_WIDTH-1:0]    rd_data_a,
    output reg [DATA_WIDTH-1:0]    rd_data_b,
    input      [DATA_WIDTH-1:0]    wr_data_a,
    input      [DATA_WIDTH-1:0]    wr_data_b,
    input      [$clog2(DEPTH)-1:0] addr_a,
    input      [$clog2(DEPTH)-1:0] addr_b,
    input                          rd_en_a,
    input                          rd_en_b,
    input                          wr_en_a,
    input                          wr_en_b,
    input                          clk
);

    (* ram_style = RAM_STYLE *) reg [DATA_WIDTH-1:0] ram[0:DEPTH-1];

    // PORTA
    always @ (posedge clk) begin
        if (wr_en_a) begin
            ram[addr_a] <= wr_data_a;
        end
    end

    always @ (posedge clk) begin
        if (rd_en_a) begin
            rd_data_a <= ram[addr_a];
        end
    end

    // PORTB
    always @ (posedge clk) begin
        if (wr_en_b) begin
            ram[addr_b] <= wr_data_b;
        end
    end

    always @ (posedge clk) begin
        if (rd_en_b) begin
            rd_data_b <= ram[addr_b];
        end
    end

endmodule
