`timescale 1ns / 1ps

module conv #(
    // Layer parameters
    // parameter UNROLL_MODE = "kernel",
    // parameter UNROLL_MODE = "incha",
    parameter UNROLL_MODE = "outcha",
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS = 8,
    parameter IN_WIDTH = 512,
    parameter IN_HEIGHT = 257,
    // parameter OUTPUT_MODE = "batchnorm_relu",
    // parameter OUTPUT_MODE = "sigmoid",
    parameter OUTPUT_MODE = "linear",

    // Conv parameters
    parameter KERNEL_0 = 3,
    parameter KERNEL_1 = 3,
    parameter DILATION_0 = 2,
    parameter DILATION_1 = 2,
    parameter PADDING_0 = 2,
    parameter PADDING_1 = 2,
    parameter STRIDE_0 = 3,
    parameter STRIDE_1 = 3,
    parameter IN_CHANNEL = 3,
    parameter OUT_CHANNEL = 8,

    // Weight memory map
    parameter KERNEL_BASE_ADDR = 23,
    parameter BIAS_BASE_ADDR = KERNEL_BASE_ADDR + KERNEL_0 * KERNEL_1 * IN_CHANNEL * OUT_CHANNEL,
    parameter BATCHNORM_A_BASE_ADDR = BIAS_BASE_ADDR + OUT_CHANNEL,
    parameter BATCHNORM_B_BASE_ADDR = BATCHNORM_A_BASE_ADDR + OUT_CHANNEL
)(
    o_data,
    o_valid,
    fifo_rd_en,
    i_data,
    i_valid,
    fifo_almost_full,
    weight_data,
    weight_addr,
    weight_we,
    clk,
    rst_n
);

    localparam PIXEL_WIDTH = DATA_WIDTH * IN_CHANNEL;
    localparam KERNEL_PTS = KERNEL_0 * KERNEL_1;

    output [DATA_WIDTH*OUT_CHANNEL-1:0] o_data;
    output                              o_valid;
    output                              fifo_rd_en;
    input  [DATA_WIDTH*IN_CHANNEL-1:0]  i_data;
    input                               i_valid;
    input                               fifo_almost_full;
    input  [DATA_WIDTH-1:0]             weight_data;
    input  [31:0]                       weight_addr;
    input                               weight_we;
    input                               clk;
    input                               rst_n;

    // Line buffer
    wire [PIXEL_WIDTH*KERNEL_PTS-1:0] line_buffer_data;
    wire                              line_buffer_valid;
    wire                              pe_ready;
    wire                              pe_ack;

    line_buffer#(
        .DATA_WIDTH (DATA_WIDTH),
        .IN_CHANNEL (IN_CHANNEL),
        .IN_WIDTH   (IN_WIDTH),
        .IN_HEIGHT  (IN_HEIGHT),
        .KERNEL_0   (KERNEL_0),
        .KERNEL_1   (KERNEL_1),
        .DILATION_0 (DILATION_0),
        .DILATION_1 (DILATION_1),
        .PADDING_0  (PADDING_0),
        .PADDING_1  (PADDING_1),
        .STRIDE_0   (STRIDE_0),
        .STRIDE_1   (STRIDE_1)
    ) u_line_buffer (
        .o_data           (line_buffer_data),
        .o_valid          (line_buffer_valid),
        .fifo_rd_en       (fifo_rd_en), 
        .i_data           (i_data),
        .i_valid          (i_valid),
        .fifo_almost_full (fifo_almost_full),
        .pe_ready         (pe_ready),
        .pe_ack           (pe_ack),
        .clk              (clk),
        .rst_n            (rst_n)
    );

    // PE
    pe #(
        .UNROLL_MODE           (UNROLL_MODE),
        .DATA_WIDTH            (DATA_WIDTH),
        .FRAC_BITS             (FRAC_BITS),
        .KERNEL_0              (KERNEL_0),
        .KERNEL_1              (KERNEL_1),
        .IN_CHANNEL            (IN_CHANNEL),
        .OUT_CHANNEL           (OUT_CHANNEL),
        .OUTPUT_MODE           (OUTPUT_MODE),
        .KERNEL_BASE_ADDR      (KERNEL_BASE_ADDR),
        .BIAS_BASE_ADDR        (BIAS_BASE_ADDR),
        .BATCHNORM_A_BASE_ADDR (BATCHNORM_A_BASE_ADDR),
        .BATCHNORM_B_BASE_ADDR (BATCHNORM_B_BASE_ADDR)
    ) u_pe (
        .o_data      (o_data), 
        .o_valid     (o_valid),
        .pe_ready    (pe_ready),
        .pe_ack      (pe_ack),
        .i_data      (line_buffer_data),
        .i_valid     (line_buffer_valid), 
        .weight_data (weight_data),
        .weight_addr (weight_addr),
        .weight_we   (weight_we), 
        .clk         (clk),
        .rst_n       (rst_n)
    );

endmodule
