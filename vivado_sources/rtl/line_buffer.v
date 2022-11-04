`timescale 1ns / 1ps

module line_buffer#(
    // Layer parameters
    parameter DATA_WIDTH = 16,
    parameter IN_CHANNEL = 16,
    parameter IN_WIDTH   = 514,
    parameter IN_HEIGHT  = 256,

    // Conv parameters
    parameter KERNEL_0   = 3,
    parameter KERNEL_1   = 3,
    parameter DILATION_0 = 2,
    parameter DILATION_1 = 2,
    parameter PADDING_0  = 2,
    parameter PADDING_1  = 2,
    parameter STRIDE_0   = 3,
    parameter STRIDE_1   = 3
)(
    o_data,
    o_valid,
    fifo_rd_en,
    i_data,
    i_valid,
    fifo_almost_full,
    pe_ready,
    pe_ack,
    clk,
    rst_n
);

    localparam PIXEL_WIDTH    = DATA_WIDTH * IN_CHANNEL;
    localparam TOTAL_WIDTH    = IN_WIDTH + PADDING_1 * 2;
    localparam WINDOW_0       = DILATION_0 * (KERNEL_0 - 1) + 1;
    localparam WINDOW_1       = DILATION_1 * (KERNEL_1 - 1) + 1;
    localparam KERNEL_PTS     = KERNEL_0 * KERNEL_1;
    localparam BLANK_PTS      = num_blank_pts(0);
    localparam BLANK_PTS_SAFE = BLANK_PTS > 0 ? BLANK_PTS : 1;

    output [PIXEL_WIDTH*KERNEL_PTS-1:0] o_data;
    output                              o_valid;
    output                              fifo_rd_en;
    input  [PIXEL_WIDTH-1:0]            i_data;
    input                               i_valid;
    input                               fifo_almost_full;
    input                               pe_ready;
    input                               pe_ack;
    input                               clk;
    input                               rst_n;

    wire [BLANK_PTS_SAFE-1:0] out_blank;
    wire                      is_padding;
    wire                      shift;

    line_buffer_controller #(
        .DATA_WIDTH       (DATA_WIDTH),
        .IN_CHANNEL       (IN_CHANNEL),
        .IN_WIDTH         (IN_WIDTH),
        .IN_HEIGHT        (IN_HEIGHT),
        .KERNEL_0         (KERNEL_0),
        .KERNEL_1         (KERNEL_1),
        .DILATION_0       (DILATION_0),
        .DILATION_1       (DILATION_1),
        .PADDING_0        (PADDING_0),
        .PADDING_1        (PADDING_1),
        .STRIDE_0         (STRIDE_0),
        .STRIDE_1         (STRIDE_1)
    ) u_control (
        .fifo_rd_en       (fifo_rd_en),
        .o_valid          (o_valid),
        .is_padding       (is_padding),
        .out_blank        (out_blank),
        .shift            (shift),
        .fifo_almost_full (fifo_almost_full),
        .i_valid          (i_valid),
        .pe_ready         (pe_ready),
        .pe_ack           (pe_ack),
        .clk              (clk),
        .rst_n            (rst_n)
    );

    line_buffer_datapath #(
        .DATA_WIDTH (DATA_WIDTH),
        .IN_CHANNEL (IN_CHANNEL),
        .IN_WIDTH   (IN_WIDTH),
        .KERNEL_0   (KERNEL_0),
        .KERNEL_1   (KERNEL_1),
        .DILATION_0 (DILATION_0),
        .DILATION_1 (DILATION_1),
        .PADDING_0  (PADDING_0),
        .PADDING_1  (PADDING_1)
    ) u_datapath (
        .o_data     (o_data),
        .i_data     (i_data),
        .is_padding (is_padding),
        .out_blank  (out_blank),
        .shift      (shift),
        .clk        (clk),
        .rst_n      (rst_n)
    );

    //////////////////////////////////////////////////////////////////////////////

    function integer num_blank_pts;
        input integer dummy;
        begin
            if (WINDOW_0 <= PADDING_0) begin
                num_blank_pts = KERNEL_PTS;
            end
            else begin
                // Top points
                if (PADDING_0 == 0) begin
                    num_blank_pts = 0;
                end
                else begin
                    num_blank_pts = KERNEL_1 * ((PADDING_0 - 1) / DILATION_0 + 1);
                end

                // Side points
                if (PADDING_1 > 0 && PADDING_0 % DILATION_0 == 0) begin
                    if (WINDOW_1 <= PADDING_1) begin
                        num_blank_pts = num_blank_pts + KERNEL_1;
                    end
                    else begin
                        num_blank_pts = num_blank_pts + (PADDING_1 - 1) / DILATION_1 + 1;
                    end
                end
            end
        end
    endfunction

endmodule
