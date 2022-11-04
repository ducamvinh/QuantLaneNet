`timescale 1ns / 1ps

module pe_outcha_double #(
    // Layer parameters
    parameter IN_WIDTH    = 513,
    parameter IN_HEIGHT   = 257,
    parameter IN_CHANNEL  = 3,
    parameter OUT_CHANNEL = 4,
    // parameter OUTPUT_MODE = "relu",
    parameter OUTPUT_MODE = "dequant",
    // parameter OUTPUT_MODE = "sigmoid",

    // Conv parameters
    parameter KERNEL_0   = 3,
    parameter KERNEL_1   = 3,
    parameter DILATION_0 = 2,
    parameter DILATION_1 = 2,
    parameter PADDING_0  = 2,
    parameter PADDING_1  = 2,
    parameter STRIDE_0   = 1,
    parameter STRIDE_1   = 1,

    // Weight addr map
    parameter KERNEL_BASE_ADDR      = 23,
    parameter BIAS_BASE_ADDR        = KERNEL_BASE_ADDR + KERNEL_0 * KERNEL_1 * IN_CHANNEL * OUT_CHANNEL,
    parameter MACC_COEFF_BASE_ADDR  = BIAS_BASE_ADDR + OUT_CHANNEL,
    parameter LAYER_SCALE_BASE_ADDR = MACC_COEFF_BASE_ADDR + 1
)(
    o_data,
    o_valid,
    pe_ready,
    pe_ack,
    i_data,
    i_valid,
    weight_wr_data,
    weight_wr_addr,
    weight_wr_en,
    clk,
    rst_n
);

    localparam KERNEL_PTS        = KERNEL_0 * KERNEL_1;
    localparam OUTPUT_DATA_WIDTH = OUTPUT_MODE == "relu" ? 8 : 16;

    output [OUTPUT_DATA_WIDTH*OUT_CHANNEL-1:0] o_data;
    output                                     o_valid;
    output                                     pe_ready;
    output                                     pe_ack;
    input [8*IN_CHANNEL*KERNEL_PTS-1:0]        i_data;
    input                                      i_valid;
    input [15:0]                               weight_wr_data;
    input [31:0]                               weight_wr_addr;
    input                                      weight_wr_en;
    input                                      clk;
    input                                      rst_n;

    genvar i, j;

    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Weight ram write logic

    // Kernel
    localparam NUM_KERNEL_WEIGHTS = KERNEL_PTS * IN_CHANNEL * OUT_CHANNEL;
    localparam QUOTIENT_WIDTH     = KERNEL_PTS * OUT_CHANNEL > IN_CHANNEL ? $clog2(KERNEL_PTS * OUT_CHANNEL) : $clog2(IN_CHANNEL);

    wire [31:0]                 kernel_addr     = weight_wr_addr - KERNEL_BASE_ADDR;
    wire [QUOTIENT_WIDTH*2-1:0] kernel_addr_adj = kernel_addr[QUOTIENT_WIDTH*2-1:0];
    wire                        kernel_wr_en    = weight_wr_en && weight_wr_addr >= KERNEL_BASE_ADDR && weight_wr_addr < KERNEL_BASE_ADDR + NUM_KERNEL_WEIGHTS;

    wire [QUOTIENT_WIDTH-1:0]         kernel_ram_addr;
    wire [QUOTIENT_WIDTH-1:0]         kernel_word_en_num;
    wire [7:0]                        kernel_wr_data;
    wire                              kernel_ram_wr_en_;
    wire [KERNEL_PTS*OUT_CHANNEL-1:0] kernel_ram_wr_en = kernel_ram_wr_en_ ? 1 << kernel_word_en_num : 0;

    kernel_write_assist #(
        .DIVIDEND_WIDTH (QUOTIENT_WIDTH * 2),
        .DIVISOR        (IN_CHANNEL),
        .DATA_WIDTH     (8)
    ) u_kernel_w (
        .quotient       (kernel_word_en_num),
        .remainder      (kernel_ram_addr),
        .o_data         (kernel_wr_data),
        .o_valid        (kernel_ram_wr_en_),
        .dividend       (kernel_addr_adj),
        .i_data         (weight_wr_data[7:0]),
        .i_valid        (kernel_wr_en),
        .clk            (clk),
        .rst_n          (rst_n)
    );

    // Bias
    wire [31:0]                    bias_wr_addr_ = weight_wr_addr - BIAS_BASE_ADDR;
    wire [$clog2(OUT_CHANNEL)-1:0] bias_wr_addr  = bias_wr_addr_[$clog2(OUT_CHANNEL)-1:0];
    wire                           bias_wr_en    = weight_wr_en && weight_wr_addr >= BIAS_BASE_ADDR && weight_wr_addr < BIAS_BASE_ADDR + OUT_CHANNEL;

    //////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Controller
    wire data_latch_a;
    wire data_latch_b;
    wire cnt_en;
    wire cnt_limit;

    pe_outcha_double_controller #(
        .IN_WIDTH     (IN_WIDTH),
        .IN_HEIGHT    (IN_HEIGHT),
        .KERNEL_0     (KERNEL_0),
        .KERNEL_1     (KERNEL_1),
        .DILATION_0   (DILATION_0),
        .DILATION_1   (DILATION_1),
        .PADDING_0    (PADDING_0),
        .PADDING_1    (PADDING_1),
        .STRIDE_0     (STRIDE_0),
        .STRIDE_1     (STRIDE_1)
    ) u_control (
        .data_latch_a (data_latch_a),
        .data_latch_b (data_latch_b),
        .cnt_en       (cnt_en),
        .pe_ready     (pe_ready),
        .pe_ack       (pe_ack),
        .cnt_limit    (cnt_limit),
        .i_valid      (i_valid),
        .clk          (clk),
        .rst_n        (rst_n)
    );

    // Input registers
    reg  [8*IN_CHANNEL*KERNEL_PTS-1:0] i_data_reg_a_buf;
    reg  [8*KERNEL_PTS-1:0]            i_data_reg_a     [0:IN_CHANNEL-1];
    reg  [8*KERNEL_PTS-1:0]            i_data_reg_b     [0:IN_CHANNEL-1];
    wire [8*KERNEL_PTS-1:0]            i_data_reg_a_in  [0:IN_CHANNEL-1];
    wire [8*KERNEL_PTS-1:0]            i_data_reg_b_in  [0:IN_CHANNEL-1];

    always @ (posedge clk) begin
        if (data_latch_a) begin
            i_data_reg_a_buf <= i_data;
        end
    end

    generate
        for (i = 0; i < KERNEL_PTS; i = i + 1) begin : gen0
            wire [8*IN_CHANNEL-1:0] input_pt_a = i_data_reg_a_buf[(i+1)*8*IN_CHANNEL-1:i*8*IN_CHANNEL];
            wire [8*IN_CHANNEL-1:0] input_pt_b = i_data[(i+1)*8*IN_CHANNEL-1:i*8*IN_CHANNEL];

            for (j = 0; j < IN_CHANNEL; j = j + 1) begin : gen1
                assign i_data_reg_a_in[j][(i+1)*8-1:i*8] = input_pt_a[(j+1)*8-1:j*8];
                assign i_data_reg_b_in[j][(i+1)*8-1:i*8] = input_pt_b[(j+1)*8-1:j*8];
            end
        end

        for (i = 0; i < IN_CHANNEL; i = i + 1) begin : gen2
            always @ (posedge clk) begin
                if (data_latch_b) begin
                    i_data_reg_a[i] <= i_data_reg_a_in[i];
                    i_data_reg_b[i] <= i_data_reg_b_in[i];
                end
                else if (cnt_en) begin
                    i_data_reg_a[i] <= i == IN_CHANNEL - 1 ? i_data_reg_a[i] : i_data_reg_a[i+1];
                    i_data_reg_b[i] <= i == IN_CHANNEL - 1 ? i_data_reg_b[i] : i_data_reg_b[i+1];
                end
            end
        end
    endgenerate

    // Kernel ram
    wire [8*KERNEL_PTS*OUT_CHANNEL-1:0] kernel;
    reg  [$clog2(IN_CHANNEL)-1:0]       kernel_cnt;

    assign cnt_limit = kernel_cnt == IN_CHANNEL - 1;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            kernel_cnt <= 0;
        end
        else if (cnt_en) begin
            kernel_cnt <= cnt_limit ? 0 : kernel_cnt + 1;
        end
    end

    block_ram_multi_word #(
        .DATA_WIDTH      (8),
        .DEPTH           (IN_CHANNEL),
        .NUM_WORDS       (KERNEL_PTS * OUT_CHANNEL),
        .RAM_STYLE       ("auto"),
        .OUTPUT_REGISTER ("true")
    ) u_kernel (
        .rd_data         (kernel),
        .wr_data         (kernel_wr_data),
        .rd_addr         (kernel_cnt),
        .wr_addr         (kernel_ram_addr[$clog2(IN_CHANNEL)-1:0]),
        .wr_en           (kernel_ram_wr_en),
        .rd_en           (1'b1),
        .clk             (clk)
    );

    // Bias ram
    reg [15:0] bias_ram[0:OUT_CHANNEL-1];

    always @ (posedge clk) begin
        if (bias_wr_en) begin
            bias_ram[bias_wr_addr] <= weight_wr_data;
        end
    end

    // MACC co-efficient reg
    reg signed [15:0] macc_coeff;

    always @ (posedge clk) begin
        if (weight_wr_en && weight_wr_addr == MACC_COEFF_BASE_ADDR) begin
            macc_coeff <= weight_wr_data;
        end
    end

    // MACC and later stages
    reg  macc_valid_i;
    wire macc_valid_o;
    reg  macc_valid_o_reg;
    reg  coeff_valid;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            macc_valid_i <= 1'b0;
            macc_valid_o_reg <= 1'b0;
            coeff_valid <= 1'b0;
        end
        else begin
            macc_valid_i <= cnt_en;
            macc_valid_o_reg <= macc_valid_o;
            coeff_valid <= macc_valid_o_reg;
        end
    end

    ////////////////////////////////////////////////////////////////////////////////////////////////

    // BRAM output pipeline register because Vivado won't stop screaming about it
    reg [8*KERNEL_PTS-1:0] i_data_reg_a_pipeline;
    reg [8*KERNEL_PTS-1:0] i_data_reg_b_pipeline;
    reg                    macc_valid_i_pipeline;

    always @ (posedge clk) begin
        if (macc_valid_i) begin
            i_data_reg_a_pipeline <= i_data_reg_a[0];
            i_data_reg_b_pipeline <= i_data_reg_b[0];
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            macc_valid_i_pipeline <= 1'b0;
        end
        else begin
            macc_valid_i_pipeline <= macc_valid_i;
        end
    end

    ////////////////////////////////////////////////////////////////////////////////////////////////

    // In channel counter
    reg [$clog2(IN_CHANNEL)-1:0] in_cha_cnt;
    wire                         in_cha_cnt_limit = in_cha_cnt == IN_CHANNEL - 1;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            in_cha_cnt <= 0;
        end
        else if (macc_valid_o_reg) begin
            in_cha_cnt <= in_cha_cnt_limit ? 0 : in_cha_cnt + 1;
        end
    end

    reg accum_in_sel;
    reg bias_valid_0;
    reg bias_valid_1;

    always @ (posedge clk) begin
        accum_in_sel <= macc_valid_o_reg && in_cha_cnt == 0;
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            bias_valid_0 <= 1'b0;
            bias_valid_1 <= 1'b0;
        end
        else begin
            bias_valid_0 <= macc_valid_o_reg & in_cha_cnt_limit;
            bias_valid_1 <= bias_valid_0;
        end
    end

    // Layer scale reg
    wire signed [15:0] layer_scale;
    wire               bias_sum_trunc_valid;
    wire               dequant_valid;

    generate
        if (OUTPUT_MODE == "dequant" || OUTPUT_MODE == "sigmoid") begin : gen3
            reg [15:0] layer_scale_reg;
            reg        bias_sum_trunc_valid_reg;
            reg        dequant_valid_reg;

            assign layer_scale          = layer_scale_reg;
            assign bias_sum_trunc_valid = bias_sum_trunc_valid_reg;
            assign dequant_valid        = dequant_valid_reg;

            always @ (posedge clk) begin
                if (weight_wr_en && weight_wr_addr == LAYER_SCALE_BASE_ADDR) begin
                    layer_scale_reg <= weight_wr_data;
                end
            end

            always @ (posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    bias_sum_trunc_valid_reg <= 1'b0;
                    dequant_valid_reg <= 1'b0;
                end
                else begin
                    bias_sum_trunc_valid_reg <= bias_valid_1;
                    dequant_valid_reg <= bias_sum_trunc_valid_reg;
                end
            end
        end
    endgenerate

    wire [OUTPUT_DATA_WIDTH*OUT_CHANNEL-1:0] obuffer_data_a;
    wire [OUTPUT_DATA_WIDTH*OUT_CHANNEL-1:0] obuffer_data_b;
    wire                                     obuffer_valid;

    generate
        for (i = 0; i < OUT_CHANNEL; i = i + 1) begin : gen4
            localparam MACC_OUTPUT_DATA_WIDTH = 16 + $clog2(KERNEL_PTS);

            wire [MACC_OUTPUT_DATA_WIDTH-1:0] macc_data_out_a;  // MACC_OUTPUT_DATA_WIDTH-bit (x2^0)
            wire [MACC_OUTPUT_DATA_WIDTH-1:0] macc_data_out_b;
            wire                              macc_valid_o_;

            if (i == 0) begin : gen5
                assign macc_valid_o = macc_valid_o_;
            end

            macc_8bit_dual #(
                .NUM_INPUTS (KERNEL_PTS)
            ) u_macc (
                .o_data_a   (macc_data_out_a),
                .o_data_b   (macc_data_out_b),
                .o_valid    (macc_valid_o_),
                .i_data_a   (i_data_reg_a_pipeline),
                .i_data_b   (i_data_reg_b_pipeline),
                .i_data_c   (kernel[(i+1)*8*KERNEL_PTS-1:i*8*KERNEL_PTS]),
                .i_valid    (macc_valid_i_pipeline),
                .clk        (clk),
                .rst_n      (rst_n)
            );

            // MACC output reg
            reg signed [MACC_OUTPUT_DATA_WIDTH-1:0] macc_data_out_a_reg;
            reg signed [MACC_OUTPUT_DATA_WIDTH-1:0] macc_data_out_b_reg;

            always @ (posedge clk) begin
                if (macc_valid_o) begin
                    macc_data_out_a_reg <= macc_data_out_a;
                    macc_data_out_b_reg <= macc_data_out_b;
                end
            end

            // MACC co-efficient
            reg signed [MACC_OUTPUT_DATA_WIDTH+16-1:0] coeff_prod_a;  // MACC_OUTPUT_DATA_WIDTH-bit (x2^0) x 16-bit coeff (x2^-16) = (MACC_OUTPUT_DATA_WIDTH+16)-bit coeff_prod (x2^-16)
            reg signed [MACC_OUTPUT_DATA_WIDTH+16-1:0] coeff_prod_b;

            always @ (posedge clk) begin
                if (macc_valid_o_reg) begin
                    coeff_prod_a <= macc_coeff * macc_data_out_a_reg;
                    coeff_prod_b <= macc_coeff * macc_data_out_b_reg;
                end
            end

            // In channel accum / bias
            localparam BIAS_SUM_WIDTH = MACC_OUTPUT_DATA_WIDTH + 16 + IN_CHANNEL;

            reg  signed [BIAS_SUM_WIDTH-1:0] bias_sum_a;
            reg  signed [BIAS_SUM_WIDTH-1:0] bias_sum_b;
            wire signed [BIAS_SUM_WIDTH-1:0] accum_in_a = accum_in_sel ? {{BIAS_SUM_WIDTH-8{bias_ram[i][15]}}, bias_ram[i], {8{1'b0}}} : bias_sum_a;
            wire signed [BIAS_SUM_WIDTH-1:0] accum_in_b = accum_in_sel ? {{BIAS_SUM_WIDTH-8{bias_ram[i][15]}}, bias_ram[i], {8{1'b0}}} : bias_sum_b;

            always @ (posedge clk) begin
                bias_sum_a <= coeff_prod_a + accum_in_a;
                bias_sum_b <= coeff_prod_b + accum_in_b;
            end

            if (OUTPUT_MODE == "relu") begin : gen6
                assign obuffer_data_a[(i+1)*OUTPUT_DATA_WIDTH-1:i*OUTPUT_DATA_WIDTH] = bias_sum_a < 0 ? 0 : ((bias_sum_a[23] || bias_sum_a[22:16] == {7{1'b1}}) ? 127 : (bias_sum_a[23:16] + (bias_sum_a[15] & |bias_sum_a[14:12])));
                assign obuffer_data_b[(i+1)*OUTPUT_DATA_WIDTH-1:i*OUTPUT_DATA_WIDTH] = bias_sum_b < 0 ? 0 : ((bias_sum_b[23] || bias_sum_b[22:16] == {7{1'b1}}) ? 127 : (bias_sum_b[23:16] + (bias_sum_b[15] & |bias_sum_b[14:12])));
                assign obuffer_valid = bias_valid_1;
            end

            else if (OUTPUT_MODE == "dequant" || OUTPUT_MODE == "sigmoid") begin : gen7
                // bias_sum truncate
                wire signed [BIAS_SUM_WIDTH-16-1:0] bias_sum_a_int = bias_sum_a[BIAS_SUM_WIDTH-1:16];
                wire signed [BIAS_SUM_WIDTH-16-1:0] bias_sum_b_int = bias_sum_b[BIAS_SUM_WIDTH-1:16];
                reg  signed [8+16-1:0]              bias_sum_a_trunc;   // 24-bit bias sum truncate (x2^-16)
                reg  signed [8+16-1:0]              bias_sum_b_trunc;

                always @ (posedge clk) begin
                    if (bias_valid_1) begin
                        bias_sum_a_trunc <= bias_sum_a_int >= 127 ? (127 << 16) : (bias_sum_a_int <= -128 ? (-128 << 16) : bias_sum_a[8+16-1:0]);
                        bias_sum_b_trunc <= bias_sum_b_int >= 127 ? (127 << 16) : (bias_sum_b_int <= -128 ? (-128 << 16) : bias_sum_b[8+16-1:0]);
                    end
                end

                // layer_scale mult
                reg signed [39:0] dequant_a;  // 24-bit bias_sum (x2^-16) x 16-bit layer_scale (x2^-16) = 40-bit product (x2^-32)
                reg signed [39:0] dequant_b;

                always @ (posedge clk) begin
                    if (bias_sum_trunc_valid) begin
                        dequant_a <= bias_sum_a_trunc * layer_scale;
                        dequant_b <= bias_sum_b_trunc * layer_scale;
                    end
                end

                // Truncate for ouptut
                wire signed [15:0] dequant_trunc_a = dequant_a[39:24] + (dequant_a[23] & |dequant_a[22:20]);
                wire signed [15:0] dequant_trunc_b = dequant_b[39:24] + (dequant_b[23] & |dequant_b[22:20]);

                if (OUTPUT_MODE == "dequant") begin : gen8
                    assign obuffer_data_a[(i+1)*OUTPUT_DATA_WIDTH-1:i*OUTPUT_DATA_WIDTH] = dequant_trunc_a;
                    assign obuffer_data_b[(i+1)*OUTPUT_DATA_WIDTH-1:i*OUTPUT_DATA_WIDTH] = dequant_trunc_b;
                    assign obuffer_valid = dequant_valid;
                end

                else if (OUTPUT_MODE == "sigmoid") begin : gen9
                    wire [1:0] sigmoid_valid;

                    if (i == 0) begin : gen10
                        assign obuffer_valid = sigmoid_valid[0];
                    end

                    sigmoid #(
                        .DATA_WIDTH (16),
                        .FRAC_BITS  (8)
                    ) u_sigmoid[1:0] (
                        .o_data     ({obuffer_data_b[(i+1)*OUTPUT_DATA_WIDTH-1:i*OUTPUT_DATA_WIDTH], obuffer_data_a[(i+1)*OUTPUT_DATA_WIDTH-1:i*OUTPUT_DATA_WIDTH]}),
                        .o_valid    (sigmoid_valid),
                        .i_data     ({dequant_trunc_b, dequant_trunc_a}),
                        .i_valid    (dequant_valid),
                        .clk        (clk),
                        .rst_n      (rst_n)
                    );
                end
            end
        end
    endgenerate

    // obuffer
    pe_outcha_double_obuffer #(
        .DATA_WIDTH (OUTPUT_DATA_WIDTH * OUT_CHANNEL),
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
    ) u_obuffer (
        .o_data     (o_data),
        .o_valid    (o_valid),
        .i_data_a   (obuffer_data_a),
        .i_data_b   (obuffer_data_b),
        .i_valid    (obuffer_valid),
        .clk        (clk),
        .rst_n      (rst_n)
    );

endmodule
