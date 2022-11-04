`timescale 1ns / 1ps

module fifo_dual_read #(
    parameter DATA_WIDTH        = 16 * 8,
    parameter DEPTH             = 512 * 5,
    parameter ALMOST_FULL_THRES = 10
)(
    output [DATA_WIDTH-1:0] rd_data_a,
    output [DATA_WIDTH-1:0] rd_data_b,
    output                  empty_a,
    output                  empty_b,
    output                  full,
    output                  almost_full,
    input  [DATA_WIDTH-1:0] wr_data,
    input                   wr_en,
    input                   rd_en_a,
    input                   rd_en_b,
    input                   rst_n,
    input                   clk
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    // Write/read counters
    wire [ADDR_WIDTH:0] wr_cnt, rd_cnt_a, rd_cnt_b;

    fifo_counter #(
        .DEPTH(DEPTH)
    ) u_cnt[2:0] (
        .cnt    ({wr_cnt, rd_cnt_a, rd_cnt_b}),
        .cnt_en ({wr_en, ~wr_en & rd_en_a, ~wr_en & rd_en_b}),
        .rst_n  (rst_n),
        .clk    (clk)
    );

    // Ram
    block_ram_dual_port #(
        .DATA_WIDTH      (DATA_WIDTH),
        .DEPTH           (DEPTH),
        .RAM_STYLE       ("auto"),
        .OUTPUT_REGISTER ("false")
    ) u_bram (
        .rd_data_a       (rd_data_a),
        .rd_data_b       (rd_data_b),
        .wr_data_a       (wr_data),
        .wr_data_b       ({DATA_WIDTH{1'b0}}),
        .addr_a          (wr_en ? wr_cnt[ADDR_WIDTH-1:0] : rd_cnt_a[ADDR_WIDTH-1:0]),
        .addr_b          (rd_cnt_b[ADDR_WIDTH-1:0]),
        .rd_en_a         (rd_en_a & ~wr_en),
        .rd_en_b         (rd_en_b),
        .wr_en_a         (wr_en),
        .wr_en_b         (1'b0),
        .clk             (clk)
    );

    // Status signals
    wire [ADDR_WIDTH-1:0] wr_addr_  = wr_cnt[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] rd_addr_a = rd_cnt_a[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] rd_addr_b = rd_cnt_b[ADDR_WIDTH-1:0];

    wire addr_eq_a = wr_addr_ == rd_addr_a;
    wire addr_eq_b = wr_addr_ == rd_addr_b;
    wire cnt_overlap_a = wr_cnt[ADDR_WIDTH] ^ rd_cnt_a[ADDR_WIDTH];
    wire cnt_overlap_b = wr_cnt[ADDR_WIDTH] ^ rd_cnt_b[ADDR_WIDTH];

    assign empty_a = addr_eq_a & ~cnt_overlap_a;
    assign empty_b = addr_eq_b & ~cnt_overlap_b;
    assign full = (addr_eq_a & cnt_overlap_a) | (addr_eq_b & cnt_overlap_b);

    wire rd_overlap = rd_cnt_a[ADDR_WIDTH] ^ rd_cnt_b[ADDR_WIDTH];
    reg [ADDR_WIDTH-1:0] closest_rd_addr_;
    reg closest_rd_addr_overlap;

    always @ (rd_overlap or rd_addr_a or rd_addr_b or cnt_overlap_a or cnt_overlap_b) begin
        case ({rd_overlap, rd_addr_a > rd_addr_b})
            2'b00: begin closest_rd_addr_ <= rd_addr_a; closest_rd_addr_overlap <= cnt_overlap_a; end
            2'b01: begin closest_rd_addr_ <= rd_addr_b; closest_rd_addr_overlap <= cnt_overlap_b; end
            2'b10: begin closest_rd_addr_ <= rd_addr_b; closest_rd_addr_overlap <= cnt_overlap_b; end
            2'b11: begin closest_rd_addr_ <= rd_addr_a; closest_rd_addr_overlap <= cnt_overlap_a; end
        endcase
    end

    wire signed [ADDR_WIDTH:0]   wr_addr         = {1'b0, wr_addr_};
    wire signed [ADDR_WIDTH:0]   closest_rd_addr = {1'b0, closest_rd_addr_};
    wire signed [ADDR_WIDTH+1:0] addr_diff_1     = closest_rd_addr - wr_addr;
    wire signed [ADDR_WIDTH+1:0] addr_diff_2     = DEPTH + addr_diff_1;
    wire signed [ADDR_WIDTH+1:0] addr_diff_3     = closest_rd_addr_overlap ? addr_diff_1 : addr_diff_2;

    assign almost_full = addr_diff_3 <= ALMOST_FULL_THRES && addr_diff_3 != 0;

endmodule
