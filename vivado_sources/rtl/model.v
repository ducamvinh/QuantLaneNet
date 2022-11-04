`timescale 1ns / 1ps

module model (
    output [16*4-1:0] o_data_cls,
    output [16*4-1:0] o_data_vertical,
    output            o_valid_cls,
    output            o_valid_vertical,
    output            fifo_rd_en,
    input  [8*3-1:0]  i_data,
    input             i_valid,
    input             cls_almost_full,
    input             vertical_almost_full,
    input  [15:0]     weight_wr_data,
    input  [31:0]     weight_wr_addr,
    input             weight_wr_en,
    input             clk,
    input             rst_n
);

    // Encoder stage 0 conv 0
    wire [8*8-1:0] o_data_enc_0;
    wire o_valid_enc_0;
    wire fifo_almost_full_enc_0;

    conv #(
        .UNROLL_MODE           ("incha"),
        .IN_WIDTH              (512),
        .IN_HEIGHT             (256),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("quadruple"),
        .KERNEL_0              (3),
        .KERNEL_1              (3),
        .PADDING_0             (2),
        .PADDING_1             (2),
        .DILATION_0            (2),
        .DILATION_1            (2),
        .STRIDE_0              (1),
        .STRIDE_1              (1),
        .IN_CHANNEL            (3),
        .OUT_CHANNEL           (8),
        .KERNEL_BASE_ADDR      (0),  // Num kernel: 216
        .BIAS_BASE_ADDR        (75960),  // Num bias: 8
        .MACC_COEFF_BASE_ADDR  (76304),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_enc_0 (
        .o_data                (o_data_enc_0),
        .o_valid               (o_valid_enc_0),
        .fifo_rd_en            (fifo_rd_en),
        .i_data                (i_data),
        .i_valid               (i_valid),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*8-1:0] fifo_rd_data_enc_0;
    wire fifo_empty_enc_0;
    wire fifo_rd_en_enc_0;

    fifo_single_read #(
        .DATA_WIDTH        (8 * 8),
        .DEPTH             (1024),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_enc_0 (
        .rd_data           (fifo_rd_data_enc_0),
        .empty             (fifo_empty_enc_0),
        .full              (),
        .almost_full       (fifo_almost_full_enc_0),
        .wr_data           (o_data_enc_0),
        .wr_en             (o_valid_enc_0),
        .rd_en             (fifo_rd_en_enc_0),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // Encoder stage 0 conv 1
    wire [8*8-1:0] o_data_enc_1;
    wire o_valid_enc_1;
    wire fifo_almost_full_enc_1;

    conv #(
        .UNROLL_MODE           ("incha"),
        .IN_WIDTH              (512),
        .IN_HEIGHT             (256),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("quadruple"),
        .KERNEL_0              (3),
        .KERNEL_1              (3),
        .PADDING_0             (2),
        .PADDING_1             (2),
        .DILATION_0            (2),
        .DILATION_1            (2),
        .STRIDE_0              (1),
        .STRIDE_1              (1),
        .IN_CHANNEL            (8),
        .OUT_CHANNEL           (8),
        .KERNEL_BASE_ADDR      (216),  // Num kernel: 576
        .BIAS_BASE_ADDR        (75968),  // Num bias: 8
        .MACC_COEFF_BASE_ADDR  (76305),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_enc_1 (
        .o_data                (o_data_enc_1),
        .o_valid               (o_valid_enc_1),
        .fifo_rd_en            (fifo_rd_en_enc_0),
        .i_data                (fifo_rd_data_enc_0),
        .i_valid               (~fifo_empty_enc_0),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*8-1:0] fifo_rd_data_enc_1;
    wire fifo_empty_enc_1;
    wire fifo_rd_en_enc_1;

    fifo_single_read #(
        .DATA_WIDTH        (8 * 8),
        .DEPTH             (512),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_enc_1 (
        .rd_data           (fifo_rd_data_enc_1),
        .empty             (fifo_empty_enc_1),
        .full              (),
        .almost_full       (fifo_almost_full_enc_1),
        .wr_data           (o_data_enc_1),
        .wr_en             (o_valid_enc_1),
        .rd_en             (fifo_rd_en_enc_1),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // Encoder stage 0 conv 2
    wire [8*16-1:0] o_data_enc_2;
    wire o_valid_enc_2;
    wire fifo_almost_full_enc_2;

    conv #(
        .UNROLL_MODE           ("incha"),
        .IN_WIDTH              (512),
        .IN_HEIGHT             (256),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("quadruple"),
        .KERNEL_0              (2),
        .KERNEL_1              (2),
        .PADDING_0             (0),
        .PADDING_1             (0),
        .DILATION_0            (1),
        .DILATION_1            (1),
        .STRIDE_0              (2),
        .STRIDE_1              (2),
        .IN_CHANNEL            (8),
        .OUT_CHANNEL           (16),
        .KERNEL_BASE_ADDR      (792),  // Num kernel: 512
        .BIAS_BASE_ADDR        (75976),  // Num bias: 16
        .MACC_COEFF_BASE_ADDR  (76306),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_enc_2 (
        .o_data                (o_data_enc_2),
        .o_valid               (o_valid_enc_2),
        .fifo_rd_en            (fifo_rd_en_enc_1),
        .i_data                (fifo_rd_data_enc_1),
        .i_valid               (~fifo_empty_enc_1),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*16-1:0] fifo_rd_data_enc_2;
    wire fifo_empty_enc_2;
    wire fifo_rd_en_enc_2;

    fifo_single_read #(
        .DATA_WIDTH        (8 * 16),
        .DEPTH             (256),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_enc_2 (
        .rd_data           (fifo_rd_data_enc_2),
        .empty             (fifo_empty_enc_2),
        .full              (),
        .almost_full       (fifo_almost_full_enc_2),
        .wr_data           (o_data_enc_2),
        .wr_en             (o_valid_enc_2),
        .rd_en             (fifo_rd_en_enc_2),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // Encoder stage 1 conv 0
    wire [8*16-1:0] o_data_enc_3;
    wire o_valid_enc_3;
    wire fifo_almost_full_enc_3;

    conv #(
        .UNROLL_MODE           ("incha"),
        .IN_WIDTH              (256),
        .IN_HEIGHT             (128),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("double"),
        .KERNEL_0              (3),
        .KERNEL_1              (3),
        .PADDING_0             (2),
        .PADDING_1             (2),
        .DILATION_0            (2),
        .DILATION_1            (2),
        .STRIDE_0              (1),
        .STRIDE_1              (1),
        .IN_CHANNEL            (16),
        .OUT_CHANNEL           (16),
        .KERNEL_BASE_ADDR      (1304),  // Num kernel: 2304
        .BIAS_BASE_ADDR        (75992),  // Num bias: 16
        .MACC_COEFF_BASE_ADDR  (76307),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_enc_3 (
        .o_data                (o_data_enc_3),
        .o_valid               (o_valid_enc_3),
        .fifo_rd_en            (fifo_rd_en_enc_2),
        .i_data                (fifo_rd_data_enc_2),
        .i_valid               (~fifo_empty_enc_2),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*16-1:0] fifo_rd_data_enc_3;
    wire fifo_empty_enc_3;
    wire fifo_rd_en_enc_3;

    fifo_single_read #(
        .DATA_WIDTH        (8 * 16),
        .DEPTH             (256),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_enc_3 (
        .rd_data           (fifo_rd_data_enc_3),
        .empty             (fifo_empty_enc_3),
        .full              (),
        .almost_full       (fifo_almost_full_enc_3),
        .wr_data           (o_data_enc_3),
        .wr_en             (o_valid_enc_3),
        .rd_en             (fifo_rd_en_enc_3),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // Encoder stage 1 conv 1
    wire [8*16-1:0] o_data_enc_4;
    wire o_valid_enc_4;
    wire fifo_almost_full_enc_4;

    conv #(
        .UNROLL_MODE           ("incha"),
        .IN_WIDTH              (256),
        .IN_HEIGHT             (128),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("double"),
        .KERNEL_0              (3),
        .KERNEL_1              (3),
        .PADDING_0             (2),
        .PADDING_1             (2),
        .DILATION_0            (2),
        .DILATION_1            (2),
        .STRIDE_0              (1),
        .STRIDE_1              (1),
        .IN_CHANNEL            (16),
        .OUT_CHANNEL           (16),
        .KERNEL_BASE_ADDR      (3608),  // Num kernel: 2304
        .BIAS_BASE_ADDR        (76008),  // Num bias: 16
        .MACC_COEFF_BASE_ADDR  (76308),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_enc_4 (
        .o_data                (o_data_enc_4),
        .o_valid               (o_valid_enc_4),
        .fifo_rd_en            (fifo_rd_en_enc_3),
        .i_data                (fifo_rd_data_enc_3),
        .i_valid               (~fifo_empty_enc_3),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*16-1:0] fifo_rd_data_enc_4;
    wire fifo_empty_enc_4;
    wire fifo_rd_en_enc_4;

    fifo_single_read #(
        .DATA_WIDTH        (8 * 16),
        .DEPTH             (256),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_enc_4 (
        .rd_data           (fifo_rd_data_enc_4),
        .empty             (fifo_empty_enc_4),
        .full              (),
        .almost_full       (fifo_almost_full_enc_4),
        .wr_data           (o_data_enc_4),
        .wr_en             (o_valid_enc_4),
        .rd_en             (fifo_rd_en_enc_4),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // Encoder stage 1 conv 2
    wire [8*32-1:0] o_data_enc_5;
    wire o_valid_enc_5;
    wire fifo_almost_full_enc_5;

    conv #(
        .UNROLL_MODE           ("incha"),
        .IN_WIDTH              (256),
        .IN_HEIGHT             (128),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("double"),
        .KERNEL_0              (2),
        .KERNEL_1              (2),
        .PADDING_0             (0),
        .PADDING_1             (0),
        .DILATION_0            (1),
        .DILATION_1            (1),
        .STRIDE_0              (2),
        .STRIDE_1              (2),
        .IN_CHANNEL            (16),
        .OUT_CHANNEL           (32),
        .KERNEL_BASE_ADDR      (5912),  // Num kernel: 2048
        .BIAS_BASE_ADDR        (76024),  // Num bias: 32
        .MACC_COEFF_BASE_ADDR  (76309),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_enc_5 (
        .o_data                (o_data_enc_5),
        .o_valid               (o_valid_enc_5),
        .fifo_rd_en            (fifo_rd_en_enc_4),
        .i_data                (fifo_rd_data_enc_4),
        .i_valid               (~fifo_empty_enc_4),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*32-1:0] fifo_rd_data_enc_5;
    wire fifo_empty_enc_5;
    wire fifo_rd_en_enc_5;

    fifo_single_read #(
        .DATA_WIDTH        (8 * 32),
        .DEPTH             (128),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_enc_5 (
        .rd_data           (fifo_rd_data_enc_5),
        .empty             (fifo_empty_enc_5),
        .full              (),
        .almost_full       (fifo_almost_full_enc_5),
        .wr_data           (o_data_enc_5),
        .wr_en             (o_valid_enc_5),
        .rd_en             (fifo_rd_en_enc_5),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // Encoder stage 2 conv 0
    wire [8*32-1:0] o_data_enc_6;
    wire o_valid_enc_6;
    wire fifo_almost_full_enc_6;

    conv #(
        .UNROLL_MODE           ("incha"),
        .IN_WIDTH              (128),
        .IN_HEIGHT             (64),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("single"),
        .KERNEL_0              (3),
        .KERNEL_1              (3),
        .PADDING_0             (2),
        .PADDING_1             (2),
        .DILATION_0            (2),
        .DILATION_1            (2),
        .STRIDE_0              (1),
        .STRIDE_1              (1),
        .IN_CHANNEL            (32),
        .OUT_CHANNEL           (32),
        .KERNEL_BASE_ADDR      (7960),  // Num kernel: 9216
        .BIAS_BASE_ADDR        (76056),  // Num bias: 32
        .MACC_COEFF_BASE_ADDR  (76310),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_enc_6 (
        .o_data                (o_data_enc_6),
        .o_valid               (o_valid_enc_6),
        .fifo_rd_en            (fifo_rd_en_enc_5),
        .i_data                (fifo_rd_data_enc_5),
        .i_valid               (~fifo_empty_enc_5),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*32-1:0] fifo_rd_data_enc_6;
    wire fifo_empty_enc_6;
    wire fifo_rd_en_enc_6;

    fifo_single_read #(
        .DATA_WIDTH        (8 * 32),
        .DEPTH             (128),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_enc_6 (
        .rd_data           (fifo_rd_data_enc_6),
        .empty             (fifo_empty_enc_6),
        .full              (),
        .almost_full       (fifo_almost_full_enc_6),
        .wr_data           (o_data_enc_6),
        .wr_en             (o_valid_enc_6),
        .rd_en             (fifo_rd_en_enc_6),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // Encoder stage 2 conv 1
    wire [8*32-1:0] o_data_enc_7;
    wire o_valid_enc_7;
    wire fifo_almost_full_enc_7;

    conv #(
        .UNROLL_MODE           ("incha"),
        .IN_WIDTH              (128),
        .IN_HEIGHT             (64),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("single"),
        .KERNEL_0              (3),
        .KERNEL_1              (3),
        .PADDING_0             (2),
        .PADDING_1             (2),
        .DILATION_0            (2),
        .DILATION_1            (2),
        .STRIDE_0              (1),
        .STRIDE_1              (1),
        .IN_CHANNEL            (32),
        .OUT_CHANNEL           (32),
        .KERNEL_BASE_ADDR      (17176),  // Num kernel: 9216
        .BIAS_BASE_ADDR        (76088),  // Num bias: 32
        .MACC_COEFF_BASE_ADDR  (76311),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_enc_7 (
        .o_data                (o_data_enc_7),
        .o_valid               (o_valid_enc_7),
        .fifo_rd_en            (fifo_rd_en_enc_6),
        .i_data                (fifo_rd_data_enc_6),
        .i_valid               (~fifo_empty_enc_6),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*32-1:0] fifo_rd_data_enc_7;
    wire fifo_empty_enc_7;
    wire fifo_rd_en_enc_7;

    fifo_single_read #(
        .DATA_WIDTH        (8 * 32),
        .DEPTH             (128),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_enc_7 (
        .rd_data           (fifo_rd_data_enc_7),
        .empty             (fifo_empty_enc_7),
        .full              (),
        .almost_full       (fifo_almost_full_enc_7),
        .wr_data           (o_data_enc_7),
        .wr_en             (o_valid_enc_7),
        .rd_en             (fifo_rd_en_enc_7),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // Encoder stage 2 conv 2
    wire [8*64-1:0] o_data_enc_8;
    wire o_valid_enc_8;
    wire fifo_almost_full_enc_8;

    conv #(
        .UNROLL_MODE           ("incha"),
        .IN_WIDTH              (128),
        .IN_HEIGHT             (64),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("single"),
        .KERNEL_0              (2),
        .KERNEL_1              (2),
        .PADDING_0             (0),
        .PADDING_1             (0),
        .DILATION_0            (1),
        .DILATION_1            (1),
        .STRIDE_0              (2),
        .STRIDE_1              (2),
        .IN_CHANNEL            (32),
        .OUT_CHANNEL           (64),
        .KERNEL_BASE_ADDR      (26392),  // Num kernel: 8192
        .BIAS_BASE_ADDR        (76120),  // Num bias: 64
        .MACC_COEFF_BASE_ADDR  (76312),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_enc_8 (
        .o_data                (o_data_enc_8),
        .o_valid               (o_valid_enc_8),
        .fifo_rd_en            (fifo_rd_en_enc_7),
        .i_data                (fifo_rd_data_enc_7),
        .i_valid               (~fifo_empty_enc_7),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*64-1:0] enc_rd_data_a;
    wire [8*64-1:0] enc_rd_data_b;
    wire enc_empty_a;
    wire enc_empty_b;
    wire enc_rd_en_a;
    wire enc_rd_en_b;
    wire enc_wr_en = o_valid_enc_8;

    fifo_dual_read #(
        .DATA_WIDTH        (8 * 64),
        .DEPTH             (64),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_dual (
        .rd_data_a         (enc_rd_data_a),
        .rd_data_b         (enc_rd_data_b),
        .empty_a           (enc_empty_a),
        .empty_b           (enc_empty_b),
        .full              (),
        .almost_full       (fifo_almost_full_enc_8),
        .wr_data           (o_data_enc_8),
        .wr_en             (enc_wr_en),
        .rd_en_a           (enc_rd_en_a),
        .rd_en_b           (enc_rd_en_b),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // cls branch conv 0
    wire [8*32-1:0] o_data_cls_0;
    wire o_valid_cls_0;
    wire fifo_almost_full_cls_0;

    conv #(
        .UNROLL_MODE           ("outcha"),
        .IN_WIDTH              (64),
        .IN_HEIGHT             (32),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("single"),
        .KERNEL_0              (3),
        .KERNEL_1              (3),
        .PADDING_0             (1),
        .PADDING_1             (1),
        .DILATION_0            (1),
        .DILATION_1            (1),
        .STRIDE_0              (1),
        .STRIDE_1              (1),
        .IN_CHANNEL            (64),
        .OUT_CHANNEL           (32),
        .KERNEL_BASE_ADDR      (34584),  // Num kernel: 18432
        .BIAS_BASE_ADDR        (76184),  // Num bias: 32
        .MACC_COEFF_BASE_ADDR  (76313),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_cls_0 (
        .o_data                (o_data_cls_0),
        .o_valid               (o_valid_cls_0),
        .fifo_rd_en            (enc_rd_en_a),
        .i_data                (enc_rd_data_a),
        .i_valid               (~enc_empty_a & ~enc_wr_en),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*32-1:0] fifo_rd_data_cls_0;
    wire fifo_empty_cls_0;
    wire fifo_rd_en_cls_0;

    fifo_single_read #(
        .DATA_WIDTH        (8 * 32),
        .DEPTH             (64),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_cls_0 (
        .rd_data           (fifo_rd_data_cls_0),
        .empty             (fifo_empty_cls_0),
        .full              (),
        .almost_full       (fifo_almost_full_cls_0),
        .wr_data           (o_data_cls_0),
        .wr_en             (o_valid_cls_0),
        .rd_en             (fifo_rd_en_cls_0),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // cls branch conv 1
    wire [8*16-1:0] o_data_cls_1;
    wire o_valid_cls_1;
    wire fifo_almost_full_cls_1;

    conv #(
        .UNROLL_MODE           ("outcha"),
        .IN_WIDTH              (64),
        .IN_HEIGHT             (32),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("single"),
        .KERNEL_0              (3),
        .KERNEL_1              (3),
        .PADDING_0             (1),
        .PADDING_1             (1),
        .DILATION_0            (1),
        .DILATION_1            (1),
        .STRIDE_0              (1),
        .STRIDE_1              (1),
        .IN_CHANNEL            (32),
        .OUT_CHANNEL           (16),
        .KERNEL_BASE_ADDR      (53016),  // Num kernel: 4608
        .BIAS_BASE_ADDR        (76216),  // Num bias: 16
        .MACC_COEFF_BASE_ADDR  (76314),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_cls_1 (
        .o_data                (o_data_cls_1),
        .o_valid               (o_valid_cls_1),
        .fifo_rd_en            (fifo_rd_en_cls_0),
        .i_data                (fifo_rd_data_cls_0),
        .i_valid               (~fifo_empty_cls_0),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*16-1:0] fifo_rd_data_cls_1;
    wire fifo_empty_cls_1;
    wire fifo_rd_en_cls_1;

    fifo_single_read #(
        .DATA_WIDTH        (8 * 16),
        .DEPTH             (64),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_cls_1 (
        .rd_data           (fifo_rd_data_cls_1),
        .empty             (fifo_empty_cls_1),
        .full              (),
        .almost_full       (fifo_almost_full_cls_1),
        .wr_data           (o_data_cls_1),
        .wr_en             (o_valid_cls_1),
        .rd_en             (fifo_rd_en_cls_1),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // cls branch conv 2
    wire [8*8-1:0] o_data_cls_2;
    wire o_valid_cls_2;
    wire fifo_almost_full_cls_2;

    conv #(
        .UNROLL_MODE           ("outcha"),
        .IN_WIDTH              (64),
        .IN_HEIGHT             (32),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("single"),
        .KERNEL_0              (3),
        .KERNEL_1              (3),
        .PADDING_0             (1),
        .PADDING_1             (1),
        .DILATION_0            (1),
        .DILATION_1            (1),
        .STRIDE_0              (1),
        .STRIDE_1              (1),
        .IN_CHANNEL            (16),
        .OUT_CHANNEL           (8),
        .KERNEL_BASE_ADDR      (57624),  // Num kernel: 1152
        .BIAS_BASE_ADDR        (76232),  // Num bias: 8
        .MACC_COEFF_BASE_ADDR  (76315),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_cls_2 (
        .o_data                (o_data_cls_2),
        .o_valid               (o_valid_cls_2),
        .fifo_rd_en            (fifo_rd_en_cls_1),
        .i_data                (fifo_rd_data_cls_1),
        .i_valid               (~fifo_empty_cls_1),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*8-1:0] fifo_rd_data_cls_2;
    wire fifo_empty_cls_2;
    wire fifo_rd_en_cls_2;

    fifo_single_read #(
        .DATA_WIDTH        (8 * 8),
        .DEPTH             (64),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_cls_2 (
        .rd_data           (fifo_rd_data_cls_2),
        .empty             (fifo_empty_cls_2),
        .full              (),
        .almost_full       (fifo_almost_full_cls_2),
        .wr_data           (o_data_cls_2),
        .wr_en             (o_valid_cls_2),
        .rd_en             (fifo_rd_en_cls_2),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // cls branch conv 3
    wire [16*4-1:0] o_data_cls_3;
    wire o_valid_cls_3;
    
    conv #(
        .UNROLL_MODE           ("outcha"),
        .IN_WIDTH              (64),
        .IN_HEIGHT             (32),
        .OUTPUT_MODE           ("dequant"),
        .COMPUTE_FACTOR        ("single"),
        .KERNEL_0              (3),
        .KERNEL_1              (3),
        .PADDING_0             (1),
        .PADDING_1             (1),
        .DILATION_0            (1),
        .DILATION_1            (1),
        .STRIDE_0              (1),
        .STRIDE_1              (1),
        .IN_CHANNEL            (8),
        .OUT_CHANNEL           (4),
        .KERNEL_BASE_ADDR      (58776),  // Num kernel: 288
        .BIAS_BASE_ADDR        (76240),  // Num bias: 4
        .MACC_COEFF_BASE_ADDR  (76316),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR (76321)   // Num layer_scale: 1
    ) u_cls_3 (
        .o_data                (o_data_cls_3),
        .o_valid               (o_valid_cls_3),
        .fifo_rd_en            (fifo_rd_en_cls_2),
        .i_data                (fifo_rd_data_cls_2),
        .i_valid               (~fifo_empty_cls_2),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    assign o_data_cls = o_data_cls_3;
    assign o_valid_cls = o_valid_cls_3;

    // vertical branch conv 0
    wire [8*32-1:0] o_data_vertical_0;
    wire o_valid_vertical_0;
    wire fifo_almost_full_vertical_0;

    conv #(
        .UNROLL_MODE           ("outcha"),
        .IN_WIDTH              (64),
        .IN_HEIGHT             (32),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("single"),
        .KERNEL_0              (3),
        .KERNEL_1              (2),
        .PADDING_0             (1),
        .PADDING_1             (0),
        .DILATION_0            (1),
        .DILATION_1            (1),
        .STRIDE_0              (1),
        .STRIDE_1              (2),
        .IN_CHANNEL            (64),
        .OUT_CHANNEL           (32),
        .KERNEL_BASE_ADDR      (59064),  // Num kernel: 12288
        .BIAS_BASE_ADDR        (76244),  // Num bias: 32
        .MACC_COEFF_BASE_ADDR  (76317),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_vertical_0 (
        .o_data                (o_data_vertical_0),
        .o_valid               (o_valid_vertical_0),
        .fifo_rd_en            (enc_rd_en_b),
        .i_data                (enc_rd_data_b),
        .i_valid               (~enc_empty_b & ~enc_wr_en),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*32-1:0] fifo_rd_data_vertical_0;
    wire fifo_empty_vertical_0;
    wire fifo_rd_en_vertical_0;

    fifo_single_read #(
        .DATA_WIDTH        (8 * 32),
        .DEPTH             (64),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_vertical_0 (
        .rd_data           (fifo_rd_data_vertical_0),
        .empty             (fifo_empty_vertical_0),
        .full              (),
        .almost_full       (fifo_almost_full_vertical_0),
        .wr_data           (o_data_vertical_0),
        .wr_en             (o_valid_vertical_0),
        .rd_en             (fifo_rd_en_vertical_0),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // vertical branch conv 1
    wire [8*16-1:0] o_data_vertical_1;
    wire o_valid_vertical_1;
    wire fifo_almost_full_vertical_1;

    conv #(
        .UNROLL_MODE           ("outcha"),
        .IN_WIDTH              (32),
        .IN_HEIGHT             (32),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("single"),
        .KERNEL_0              (3),
        .KERNEL_1              (2),
        .PADDING_0             (1),
        .PADDING_1             (0),
        .DILATION_0            (1),
        .DILATION_1            (1),
        .STRIDE_0              (1),
        .STRIDE_1              (2),
        .IN_CHANNEL            (32),
        .OUT_CHANNEL           (16),
        .KERNEL_BASE_ADDR      (71352),  // Num kernel: 3072
        .BIAS_BASE_ADDR        (76276),  // Num bias: 16
        .MACC_COEFF_BASE_ADDR  (76318),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_vertical_1 (
        .o_data                (o_data_vertical_1),
        .o_valid               (o_valid_vertical_1),
        .fifo_rd_en            (fifo_rd_en_vertical_0),
        .i_data                (fifo_rd_data_vertical_0),
        .i_valid               (~fifo_empty_vertical_0),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*16-1:0] fifo_rd_data_vertical_1;
    wire fifo_empty_vertical_1;
    wire fifo_rd_en_vertical_1;

    fifo_single_read #(
        .DATA_WIDTH        (8 * 16),
        .DEPTH             (64),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_vertical_1 (
        .rd_data           (fifo_rd_data_vertical_1),
        .empty             (fifo_empty_vertical_1),
        .full              (),
        .almost_full       (fifo_almost_full_vertical_1),
        .wr_data           (o_data_vertical_1),
        .wr_en             (o_valid_vertical_1),
        .rd_en             (fifo_rd_en_vertical_1),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // vertical branch conv 2
    wire [8*8-1:0] o_data_vertical_2;
    wire o_valid_vertical_2;
    wire fifo_almost_full_vertical_2;

    conv #(
        .UNROLL_MODE           ("outcha"),
        .IN_WIDTH              (16),
        .IN_HEIGHT             (32),
        .OUTPUT_MODE           ("relu"),
        .COMPUTE_FACTOR        ("single"),
        .KERNEL_0              (3),
        .KERNEL_1              (2),
        .PADDING_0             (1),
        .PADDING_1             (0),
        .DILATION_0            (1),
        .DILATION_1            (1),
        .STRIDE_0              (1),
        .STRIDE_1              (2),
        .IN_CHANNEL            (16),
        .OUT_CHANNEL           (8),
        .KERNEL_BASE_ADDR      (74424),  // Num kernel: 768
        .BIAS_BASE_ADDR        (76292),  // Num bias: 8
        .MACC_COEFF_BASE_ADDR  (76319),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR ()
    ) u_vertical_2 (
        .o_data                (o_data_vertical_2),
        .o_valid               (o_valid_vertical_2),
        .fifo_rd_en            (fifo_rd_en_vertical_1),
        .i_data                (fifo_rd_data_vertical_1),
        .i_valid               (~fifo_empty_vertical_1),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    wire [8*8-1:0] fifo_rd_data_vertical_2;
    wire fifo_empty_vertical_2;
    wire fifo_rd_en_vertical_2;

    fifo_single_read #(
        .DATA_WIDTH        (8 * 8),
        .DEPTH             (64),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_vertical_2 (
        .rd_data           (fifo_rd_data_vertical_2),
        .empty             (fifo_empty_vertical_2),
        .full              (),
        .almost_full       (fifo_almost_full_vertical_2),
        .wr_data           (o_data_vertical_2),
        .wr_en             (o_valid_vertical_2),
        .rd_en             (fifo_rd_en_vertical_2),
        .rst_n             (rst_n),
        .clk               (clk)
    );

    // vertical branch conv 3
    wire [16*4-1:0] o_data_vertical_3;
    wire o_valid_vertical_3;
    
    conv #(
        .UNROLL_MODE           ("outcha"),
        .IN_WIDTH              (8),
        .IN_HEIGHT             (32),
        .OUTPUT_MODE           ("sigmoid"),
        .COMPUTE_FACTOR        ("single"),
        .KERNEL_0              (3),
        .KERNEL_1              (8),
        .PADDING_0             (1),
        .PADDING_1             (0),
        .DILATION_0            (1),
        .DILATION_1            (1),
        .STRIDE_0              (1),
        .STRIDE_1              (1),
        .IN_CHANNEL            (8),
        .OUT_CHANNEL           (4),
        .KERNEL_BASE_ADDR      (75192),  // Num kernel: 768
        .BIAS_BASE_ADDR        (76300),  // Num bias: 4
        .MACC_COEFF_BASE_ADDR  (76320),  // Num macc_coeff: 1
        .LAYER_SCALE_BASE_ADDR (76322)   // Num layer_scale: 1
    ) u_vertical_3 (
        .o_data                (o_data_vertical_3),
        .o_valid               (o_valid_vertical_3),
        .fifo_rd_en            (fifo_rd_en_vertical_2),
        .i_data                (fifo_rd_data_vertical_2),
        .i_valid               (~fifo_empty_vertical_2),
        .fifo_almost_full      (1'b0),
        .weight_wr_data        (weight_wr_data),
        .weight_wr_addr        (weight_wr_addr),
        .weight_wr_en          (weight_wr_en),
        .clk                   (clk),
        .rst_n                 (rst_n)
    );

    assign o_data_vertical = o_data_vertical_3;
    assign o_valid_vertical = o_valid_vertical_3;

endmodule
