`timescale 1ns / 1ps

module block_ram_dual_read #(
    parameter DATA_WIDTH = 16,
    parameter DEPTH = 64,
    parameter RAM_STYLE = "auto"
)(
    output reg [DATA_WIDTH-1:0]    rd_data_a,
    output reg [DATA_WIDTH-1:0]    rd_data_b,
    input      [DATA_WIDTH-1:0]    wr_data,
    input      [$clog2(DEPTH)-1:0] rd_addr_a,
    input      [$clog2(DEPTH)-1:0] rd_addr_b,
    input      [$clog2(DEPTH)-1:0] wr_addr,
    input                          rw,
    input                          rd_en_a,
    input                          rd_en_b,
    input                          clk
);

    (* ram_style = RAM_STYLE *) reg [DATA_WIDTH-1:0] ram[0:DEPTH-1];

    // PORTA
    wire [$clog2(DEPTH)-1:0] porta_addr = rw ? wr_addr : rd_addr_a;

    always @ (posedge clk) begin
        if (rw | rd_en_a) begin
            if (rw) begin
                ram[porta_addr] <= wr_data;
                rd_data_a <= rd_data_a;
            end else begin
                rd_data_a <= ram[porta_addr];
            end
        end else begin
            rd_data_a <= rd_data_a;
        end
    end

    // PORTB
    always @ (posedge clk) begin
        if (~rw & rd_en_b) begin
            rd_data_b <= ram[rd_addr_b];
        end else begin
            rd_data_b <= rd_data_b;
        end
    end

endmodule
