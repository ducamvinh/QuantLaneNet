`timescale 1ns / 1ps

module pe #(
    // Layer parameters
    // parameter UNROLL_MODE = "kernel",
    // parameter UNROLL_MODE = "incha",
    parameter UNROLL_MODE = "outcha",
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS = 8,

    // Conv parameters
    parameter KERNEL_0 = 3,
    parameter KERNEL_1 = 3,
    parameter IN_CHANNEL = 16,
    parameter OUT_CHANNEL = 32,
    parameter OUTPUT_MODE = "batchnorm_relu",
    // parameter OUTPUT_MODE = "sigmoid",
    // parameter OUTPUT_MODE = "linear",

    // Weight memory map
    parameter KERNEL_BASE_ADDR = 23,
    parameter BIAS_BASE_ADDR = KERNEL_BASE_ADDR + KERNEL_0 * KERNEL_1 * IN_CHANNEL * OUT_CHANNEL,
    parameter BATCHNORM_A_BASE_ADDR = BIAS_BASE_ADDR + OUT_CHANNEL,
    parameter BATCHNORM_B_BASE_ADDR = BATCHNORM_A_BASE_ADDR + OUT_CHANNEL
)(
    o_data,
    o_valid,
    pe_ready,
    pe_ack,
    i_data,
    i_valid,
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
    output                              pe_ready;
    output                              pe_ack;
    input  [PIXEL_WIDTH*KERNEL_PTS-1:0] i_data;
    input                               i_valid;
    input  [DATA_WIDTH-1:0]             weight_data;
    input  [31:0]                       weight_addr;
    input                               weight_we;
    input                               clk;
    input                               rst_n;

    // Controller
    wire cnt_limit;
    wire cnt_en;

    pe_controller u_control (
        .cnt_en    (cnt_en),
        .pe_ready  (pe_ready),
        .pe_ack    (pe_ack),
        .cnt_limit (cnt_limit),
        .i_valid   (i_valid),
        .clk       (clk),
        .rst_n     (rst_n)
    );

    // Datapath
    generate
        if (UNROLL_MODE == "kernel" || UNROLL_MODE == "incha") begin : gen0
            wire [DATA_WIDTH-1:0] datapath_o_data;
            wire                  datapath_o_valid;

            if (UNROLL_MODE == "kernel") begin : gen1
                pe_datapath_unroll_kernel #(
                    .DATA_WIDTH            (DATA_WIDTH),
                    .FRAC_BITS             (FRAC_BITS),
                    .IN_CHANNEL            (IN_CHANNEL),
                    .OUT_CHANNEL           (OUT_CHANNEL),
                    .OUTPUT_MODE           (OUTPUT_MODE),
                    .KERNEL_0              (KERNEL_0),
                    .KERNEL_1              (KERNEL_1),
                    .KERNEL_BASE_ADDR      (KERNEL_BASE_ADDR),
                    .BIAS_BASE_ADDR        (BIAS_BASE_ADDR),
                    .BATCHNORM_A_BASE_ADDR (BATCHNORM_A_BASE_ADDR),
                    .BATCHNORM_B_BASE_ADDR (BATCHNORM_B_BASE_ADDR)
                ) u_datapath (
                    .o_data      (datapath_o_data),
                    .o_valid     (datapath_o_valid),
                    .cnt_limit   (cnt_limit),
                    .i_data      (i_data),
                    .cnt_en      (cnt_en),
                    .data_latch  (pe_ack),
                    .weight_data (weight_data),
                    .weight_addr (weight_addr),
                    .weight_we   (weight_we),
                    .clk         (clk),
                    .rst_n       (rst_n)
                );
            end else if (UNROLL_MODE == "incha") begin : gen2
                pe_datapath_unroll_incha #(
                    .DATA_WIDTH            (DATA_WIDTH),
                    .FRAC_BITS             (FRAC_BITS),
                    .IN_CHANNEL            (IN_CHANNEL),
                    .OUT_CHANNEL           (OUT_CHANNEL),
                    .OUTPUT_MODE           (OUTPUT_MODE),
                    .KERNEL_0              (KERNEL_0),
                    .KERNEL_1              (KERNEL_1),
                    .KERNEL_BASE_ADDR      (KERNEL_BASE_ADDR),
                    .BIAS_BASE_ADDR        (BIAS_BASE_ADDR),
                    .BATCHNORM_A_BASE_ADDR (BATCHNORM_A_BASE_ADDR),
                    .BATCHNORM_B_BASE_ADDR (BATCHNORM_B_BASE_ADDR)
                ) u_datapath (
                    .o_data      (datapath_o_data),
                    .o_valid     (datapath_o_valid),
                    .cnt_limit   (cnt_limit),
                    .i_data      (i_data),
                    .cnt_en      (cnt_en),
                    .data_latch  (pe_ack),
                    .weight_data (weight_data),
                    .weight_addr (weight_addr),
                    .weight_we   (weight_we),
                    .clk         (clk),
                    .rst_n       (rst_n)
                );
            end

            // Output buffer
            output_buffer #(
                .DATA_WIDTH  (DATA_WIDTH),
                .OUT_CHANNEL (OUT_CHANNEL)
            ) u_obuffer (
                .o_data  (o_data),
                .o_valid (o_valid),
                .i_data  (datapath_o_data),
                .i_valid (datapath_o_valid),
                .clk     (clk),
                .rst_n   (rst_n)
            );
        end

        else if (UNROLL_MODE == "outcha") begin : gen3
            pe_datapath_unroll_outcha #(
                .DATA_WIDTH            (DATA_WIDTH),
                .FRAC_BITS             (FRAC_BITS),
                .IN_CHANNEL            (IN_CHANNEL),
                .OUT_CHANNEL           (OUT_CHANNEL),
                .OUTPUT_MODE           (OUTPUT_MODE),
                .KERNEL_0              (KERNEL_0),
                .KERNEL_1              (KERNEL_1),
                .KERNEL_BASE_ADDR      (KERNEL_BASE_ADDR),
                .BIAS_BASE_ADDR        (BIAS_BASE_ADDR),
                .BATCHNORM_A_BASE_ADDR (BATCHNORM_A_BASE_ADDR),
                .BATCHNORM_B_BASE_ADDR (BATCHNORM_B_BASE_ADDR)
            ) u_datapath (
                .o_data      (o_data),
                .o_valid     (o_valid),
                .cnt_limit   (cnt_limit),
                .i_data      (i_data),
                .cnt_en      (cnt_en),
                .data_latch  (pe_ack),
                .weight_data (weight_data),
                .weight_addr (weight_addr),
                .weight_we   (weight_we),
                .clk         (clk),
                .rst_n       (rst_n)
            );
        end else begin : gen4
            assign o_data = 0;
            assign o_valid = 1'b0;
        end
    endgenerate

endmodule
