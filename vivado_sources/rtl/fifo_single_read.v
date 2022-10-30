`timescale 1ns / 1ps

module fifo_single_read #(
    parameter DATA_WIDTH        = 32,
    parameter DEPTH             = 2**16,
    parameter ALMOST_FULL_THRES = 10
)(
    output [DATA_WIDTH-1:0] rd_data,
    output                  empty,
    output                  full,
    output                  almost_full,
    input  [DATA_WIDTH-1:0] wr_data,
    input                   wr_en,
    input                   rd_en,
    input                   rst_n,
    input                   clk
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    // Write/read counters
    wire [ADDR_WIDTH:0] wr_cnt, rd_cnt;

    fifo_counter #(
        .DEPTH (DEPTH)
    ) u_cnt[1:0] (
        .cnt    ({wr_cnt, rd_cnt}),
        .cnt_en ({wr_en, rd_en}),
        .rst_n  (rst_n),
        .clk    (clk)
    );

    // Ram
    block_ram_single_port #(
        .DATA_WIDTH      (DATA_WIDTH),
        .DEPTH           (DEPTH),
        .OUTPUT_REGISTER ("false")
    ) u_bram (
        .rd_data (rd_data),
        .wr_data (wr_data),
        .wr_addr (wr_cnt[ADDR_WIDTH-1:0]),
        .rd_addr (rd_cnt[ADDR_WIDTH-1:0]),
        .wr_en   (wr_en),
        .rd_en   (rd_en),
        .clk     (clk)
    );

    // Status signals
    wire signed [ADDR_WIDTH:0] wr_addr = {1'b0, wr_cnt[ADDR_WIDTH-1:0]};
    wire signed [ADDR_WIDTH:0] rd_addr = {1'b0, rd_cnt[ADDR_WIDTH-1:0]};

    wire                         addr_eq     = wr_addr == rd_addr;
    wire                         cnt_overlap = wr_cnt[ADDR_WIDTH] ^ rd_cnt[ADDR_WIDTH];
    wire signed [ADDR_WIDTH+1:0] addr_diff_1 = rd_addr - wr_addr;
    wire signed [ADDR_WIDTH+1:0] addr_diff_2 = DEPTH + addr_diff_1;
    wire signed [ADDR_WIDTH+1:0] addr_diff_3 = cnt_overlap ? addr_diff_1 : addr_diff_2;

    assign full        = addr_eq & cnt_overlap;
    assign empty       = addr_eq & ~cnt_overlap;
    assign almost_full = addr_diff_3 <= ALMOST_FULL_THRES && addr_diff_3 != 0;

endmodule
