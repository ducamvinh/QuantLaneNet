`timescale 1ns / 1ps

module conv #(
    // Layer parameters
    parameter IN_WIDTH       = 512,
    parameter IN_HEIGHT      = 256,
    // parameter OUTPUT_MODE    = "relu",
    // parameter OUTPUT_MODE    = "sigmoid",
    parameter OUTPUT_MODE    = "dequant",
    parameter UNROLL_MODE    = "incha",
    // parameter UNROLL_MODE    = "outcha",
    // parameter COMPUTE_FACTOR = "single",
    // parameter COMPUTE_FACTOR = "double",
    parameter COMPUTE_FACTOR = "quadruple",

    // Conv parameters
    // Conv parameters
    parameter KERNEL_0    = 3,
    parameter KERNEL_1    = 3,
    parameter DILATION_0  = 2,
    parameter DILATION_1  = 2,
    parameter PADDING_0   = 2,
    parameter PADDING_1   = 2,
    parameter STRIDE_0    = 1,
    parameter STRIDE_1    = 1,
    parameter IN_CHANNEL  = 32,
    parameter OUT_CHANNEL = 32,

    // Weight addr map
    parameter KERNEL_BASE_ADDR      = 17176,
    parameter BIAS_BASE_ADDR        = KERNEL_BASE_ADDR + KERNEL_0 * KERNEL_1 * IN_CHANNEL * OUT_CHANNEL,
    parameter MACC_COEFF_BASE_ADDR  = BIAS_BASE_ADDR + OUT_CHANNEL,
    parameter LAYER_SCALE_BASE_ADDR = MACC_COEFF_BASE_ADDR + 1
)(
    o_data,
    o_valid,
    fifo_rd_en,
    i_data,
    i_valid,
    fifo_almost_full,
    weight_wr_data,
    weight_wr_addr,
    weight_wr_en,
    clk,
    rst_n
);

    localparam OUTPUT_DATA_WIDTH = OUTPUT_MODE == "relu" ? 8 : 16;

    output [OUTPUT_DATA_WIDTH*OUT_CHANNEL-1:0] o_data;
    output                                     o_valid;
    output                                     fifo_rd_en;
    input  [8*IN_CHANNEL-1:0]                  i_data;
    input                                      i_valid;
    input                                      fifo_almost_full;
    input  [15:0]                              weight_wr_data;
    input  [31:0]                              weight_wr_addr;
    input                                      weight_wr_en;
    input                                      clk;
    input                                      rst_n;

    // Line buffer
    wire [8*IN_CHANNEL*KERNEL_0*KERNEL_1-1:0] line_buffer_data;
    wire                                      line_buffer_valid;
    wire                                      pe_ready;
    wire                                      pe_ack;

    line_buffer#(
        .DATA_WIDTH       (8),
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
    generate
        if (UNROLL_MODE == "incha") begin : gen0
            if (COMPUTE_FACTOR == "single") begin : gen1
                pe_incha_single #(
                    .IN_WIDTH              (IN_WIDTH),
                    .IN_HEIGHT             (IN_HEIGHT),
                    .IN_CHANNEL            (IN_CHANNEL),
                    .OUT_CHANNEL           (OUT_CHANNEL),
                    .OUTPUT_MODE           (OUTPUT_MODE),
                    .KERNEL_0              (KERNEL_0),
                    .KERNEL_1              (KERNEL_1),
                    .DILATION_0            (DILATION_0),
                    .DILATION_1            (DILATION_1),
                    .PADDING_0             (PADDING_0),
                    .PADDING_1             (PADDING_1),
                    .STRIDE_0              (STRIDE_0),
                    .STRIDE_1              (STRIDE_1),
                    .KERNEL_BASE_ADDR      (KERNEL_BASE_ADDR),
                    .BIAS_BASE_ADDR        (BIAS_BASE_ADDR),
                    .MACC_COEFF_BASE_ADDR  (MACC_COEFF_BASE_ADDR),
                    .LAYER_SCALE_BASE_ADDR (LAYER_SCALE_BASE_ADDR)
                ) u_pe_incha_single (
                    .o_data                (o_data),
                    .o_valid               (o_valid),
                    .pe_ready              (pe_ready),
                    .pe_ack                (pe_ack),
                    .i_data                (line_buffer_data),
                    .i_valid               (line_buffer_valid),
                    .weight_wr_data        (weight_wr_data),
                    .weight_wr_addr        (weight_wr_addr),
                    .weight_wr_en          (weight_wr_en),
                    .clk                   (clk),
                    .rst_n                 (rst_n)
                );
            end

            else if (COMPUTE_FACTOR == "double") begin : gen2
                pe_incha_double #(
                    .IN_WIDTH              (IN_WIDTH),
                    .IN_HEIGHT             (IN_HEIGHT),
                    .IN_CHANNEL            (IN_CHANNEL),
                    .OUT_CHANNEL           (OUT_CHANNEL),
                    .OUTPUT_MODE           (OUTPUT_MODE),
                    .KERNEL_0              (KERNEL_0),
                    .KERNEL_1              (KERNEL_1),
                    .DILATION_0            (DILATION_0),
                    .DILATION_1            (DILATION_1),
                    .PADDING_0             (PADDING_0),
                    .PADDING_1             (PADDING_1),
                    .STRIDE_0              (STRIDE_0),
                    .STRIDE_1              (STRIDE_1),
                    .KERNEL_BASE_ADDR      (KERNEL_BASE_ADDR),
                    .BIAS_BASE_ADDR        (BIAS_BASE_ADDR),
                    .MACC_COEFF_BASE_ADDR  (MACC_COEFF_BASE_ADDR),
                    .LAYER_SCALE_BASE_ADDR (LAYER_SCALE_BASE_ADDR)
                ) u_pe_incha_double (
                    .o_data                (o_data),
                    .o_valid               (o_valid),
                    .pe_ready              (pe_ready),
                    .pe_ack                (pe_ack),
                    .i_data                (line_buffer_data),
                    .i_valid               (line_buffer_valid),
                    .weight_wr_data        (weight_wr_data),
                    .weight_wr_addr        (weight_wr_addr),
                    .weight_wr_en          (weight_wr_en),
                    .clk                   (clk),
                    .rst_n                 (rst_n)
                );
            end

            else if (COMPUTE_FACTOR == "quadruple") begin : gen3
                pe_incha_quadruple #(
                    .IN_WIDTH              (IN_WIDTH),
                    .IN_HEIGHT             (IN_HEIGHT),
                    .IN_CHANNEL            (IN_CHANNEL),
                    .OUT_CHANNEL           (OUT_CHANNEL),
                    .OUTPUT_MODE           (OUTPUT_MODE),
                    .KERNEL_0              (KERNEL_0),
                    .KERNEL_1              (KERNEL_1),
                    .DILATION_0            (DILATION_0),
                    .DILATION_1            (DILATION_1),
                    .PADDING_0             (PADDING_0),
                    .PADDING_1             (PADDING_1),
                    .STRIDE_0              (STRIDE_0),
                    .STRIDE_1              (STRIDE_1),
                    .KERNEL_BASE_ADDR      (KERNEL_BASE_ADDR),
                    .BIAS_BASE_ADDR        (BIAS_BASE_ADDR),
                    .MACC_COEFF_BASE_ADDR  (MACC_COEFF_BASE_ADDR),
                    .LAYER_SCALE_BASE_ADDR (LAYER_SCALE_BASE_ADDR)
                ) u_pe_incha_quadruple (
                    .o_data                (o_data),
                    .o_valid               (o_valid),
                    .pe_ready              (pe_ready),
                    .pe_ack                (pe_ack),
                    .i_data                (line_buffer_data),
                    .i_valid               (line_buffer_valid),
                    .weight_wr_data        (weight_wr_data),
                    .weight_wr_addr        (weight_wr_addr),
                    .weight_wr_en          (weight_wr_en),
                    .clk                   (clk),
                    .rst_n                 (rst_n)
                );
            end
        end

        else if (UNROLL_MODE == "outcha") begin : gen4
            if (COMPUTE_FACTOR == "single") begin : gen5
                pe_outcha_single #(
                    .IN_WIDTH              (IN_WIDTH),
                    .IN_HEIGHT             (IN_HEIGHT),
                    .IN_CHANNEL            (IN_CHANNEL),
                    .OUT_CHANNEL           (OUT_CHANNEL),
                    .OUTPUT_MODE           (OUTPUT_MODE),
                    .KERNEL_0              (KERNEL_0),
                    .KERNEL_1              (KERNEL_1),
                    .DILATION_0            (DILATION_0),
                    .DILATION_1            (DILATION_1),
                    .PADDING_0             (PADDING_0),
                    .PADDING_1             (PADDING_1),
                    .STRIDE_0              (STRIDE_0),
                    .STRIDE_1              (STRIDE_1),
                    .KERNEL_BASE_ADDR      (KERNEL_BASE_ADDR),
                    .BIAS_BASE_ADDR        (BIAS_BASE_ADDR),
                    .MACC_COEFF_BASE_ADDR  (MACC_COEFF_BASE_ADDR),
                    .LAYER_SCALE_BASE_ADDR (LAYER_SCALE_BASE_ADDR)
                ) u_pe_outcha_single (
                    .o_data                (o_data),
                    .o_valid               (o_valid),
                    .pe_ready              (pe_ready),
                    .pe_ack                (pe_ack),
                    .i_data                (line_buffer_data),
                    .i_valid               (line_buffer_valid),
                    .weight_wr_data        (weight_wr_data),
                    .weight_wr_addr        (weight_wr_addr),
                    .weight_wr_en          (weight_wr_en),
                    .clk                   (clk),
                    .rst_n                 (rst_n)
                );
            end

            else if (COMPUTE_FACTOR == "double") begin : gen6
                pe_outcha_double #(
                    .IN_WIDTH              (IN_WIDTH),
                    .IN_HEIGHT             (IN_HEIGHT),
                    .IN_CHANNEL            (IN_CHANNEL),
                    .OUT_CHANNEL           (OUT_CHANNEL),
                    .OUTPUT_MODE           (OUTPUT_MODE),
                    .KERNEL_0              (KERNEL_0),
                    .KERNEL_1              (KERNEL_1),
                    .DILATION_0            (DILATION_0),
                    .DILATION_1            (DILATION_1),
                    .PADDING_0             (PADDING_0),
                    .PADDING_1             (PADDING_1),
                    .STRIDE_0              (STRIDE_0),
                    .STRIDE_1              (STRIDE_1),
                    .KERNEL_BASE_ADDR      (KERNEL_BASE_ADDR),
                    .BIAS_BASE_ADDR        (BIAS_BASE_ADDR),
                    .MACC_COEFF_BASE_ADDR  (MACC_COEFF_BASE_ADDR),
                    .LAYER_SCALE_BASE_ADDR (LAYER_SCALE_BASE_ADDR)
                ) u_pe_outcha_double (
                    .o_data                (o_data),
                    .o_valid               (o_valid),
                    .pe_ready              (pe_ready),
                    .pe_ack                (pe_ack),
                    .i_data                (line_buffer_data),
                    .i_valid               (line_buffer_valid),
                    .weight_wr_data        (weight_wr_data),
                    .weight_wr_addr        (weight_wr_addr),
                    .weight_wr_en          (weight_wr_en),
                    .clk                   (clk),
                    .rst_n                 (rst_n)
                );
            end
        end
    endgenerate

endmodule
