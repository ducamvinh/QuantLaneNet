`timescale 1ns / 1ps

module pe_datapath_unroll_kernel #(
    // Layer parameters
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS = 8,
    parameter IN_CHANNEL = 16,
    parameter OUT_CHANNEL = 32,
    // parameter OUTPUT_MODE = "batchnorm_relu",
    // parameter OUTPUT_MODE = "sigmoid",
    parameter OUTPUT_MODE = "linear",

    // Conv parameters
    parameter KERNEL_0 = 3,
    parameter KERNEL_1 = 3,

    // Weight memory map
    parameter KERNEL_BASE_ADDR = 23,
    parameter BIAS_BASE_ADDR = KERNEL_BASE_ADDR + KERNEL_0 * KERNEL_1 * IN_CHANNEL * OUT_CHANNEL,
    parameter BATCHNORM_A_BASE_ADDR = BIAS_BASE_ADDR + OUT_CHANNEL,
    parameter BATCHNORM_B_BASE_ADDR = BATCHNORM_A_BASE_ADDR + OUT_CHANNEL
)(
    o_data,
    o_valid,
    cnt_limit,
    i_data,
    cnt_en,
    data_latch,
    weight_data,
    weight_addr,
    weight_we,
    clk,
    rst_n
);

    localparam PIXEL_WIDTH = DATA_WIDTH * IN_CHANNEL;
    localparam KERNEL_PTS = KERNEL_0 * KERNEL_1;
    localparam INT_BITS = DATA_WIDTH - FRAC_BITS;

    output [DATA_WIDTH-1:0]             o_data;
    output                              o_valid;
    output                              cnt_limit;
    input  [PIXEL_WIDTH*KERNEL_PTS-1:0] i_data;
    input                               cnt_en;
    input                               data_latch;
    input  [DATA_WIDTH-1:0]             weight_data;
    input  [31:0]                       weight_addr;
    input                               weight_we;
    input                               clk;
    input                               rst_n;

    genvar i, j;

    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Weight ram write logic
    
    localparam QUOTIENT_WIDTH_1 = $clog2((IN_CHANNEL > OUT_CHANNEL ? IN_CHANNEL : OUT_CHANNEL) * KERNEL_PTS);
    localparam NUM_KERNEL_WEIGHTS = KERNEL_PTS * IN_CHANNEL * OUT_CHANNEL;

    wire [31:0]                                 kernel_addr_ = weight_addr - KERNEL_BASE_ADDR;
    wire [QUOTIENT_WIDTH_1*2-1:0]               kernel_addr = kernel_addr_[QUOTIENT_WIDTH_1*2-1:0];
    wire                                        kernel_wr_en = weight_we && weight_addr >= KERNEL_BASE_ADDR && weight_addr < KERNEL_BASE_ADDR + NUM_KERNEL_WEIGHTS;
    wire [QUOTIENT_WIDTH_1-1:0]                 a_div_incha;
    wire [QUOTIENT_WIDTH_1-1:0]                 a_mod_incha;
    wire [QUOTIENT_WIDTH_1-1:0]                 a_div_incha_k;
    wire [$clog2(IN_CHANNEL*OUT_CHANNEL)-1:0]   kernel_word_en_num_ = a_div_incha_k[$clog2(OUT_CHANNEL)-1:0] * IN_CHANNEL + a_mod_incha;
    wire [DATA_WIDTH-1:0]                       kernel_wr_data_;
    wire                                        div_valid;

    kernel_write_assist #(
        .DIVIDEND_WIDTH (QUOTIENT_WIDTH_1 * 2),
        .DIVISOR        (IN_CHANNEL),
        .DATA_WIDTH     (DATA_WIDTH)
    ) u_kernel_w0 (
        .quotient  (a_div_incha),
        .remainder (a_mod_incha),
        .o_data    (kernel_wr_data_),
        .o_valid   (div_valid),
        .dividend  (kernel_addr),
        .i_data    (weight_data),
        .i_valid   (kernel_wr_en),
        .clk       (clk),
        .rst_n     (rst_n)
    );

    kernel_write_assist #(
        .DIVIDEND_WIDTH (QUOTIENT_WIDTH_1 * 2),
        .DIVISOR        (IN_CHANNEL * KERNEL_PTS),
        .DATA_WIDTH     (0)
    ) u_kernel_w1 (
        .quotient  (a_div_incha_k),
        .remainder (),
        .o_data    (),
        .o_valid   (),
        .dividend  (kernel_addr),
        .i_data    (1'b0),
        .i_valid   (kernel_wr_en),
        .clk       (clk),
        .rst_n     (rst_n)
    );

    localparam QUOTIENT_WIDTH_2 = OUT_CHANNEL > KERNEL_PTS ? $clog2(OUT_CHANNEL) : $clog2(KERNEL_PTS);

    wire [QUOTIENT_WIDTH_2-1:0]                          remainder;
    wire [QUOTIENT_WIDTH_2*2-1:0]                        dividend;
    wire [DATA_WIDTH-1:0]                                kernel_wr_data;
    wire [$clog2(IN_CHANNEL*OUT_CHANNEL)-1:0]            kernel_ram_addr;
    wire [$clog2(KERNEL_PTS)-1:0]                        kernel_word_en_num = remainder[$clog2(KERNEL_PTS)-1:0];
    wire                                                 kernel_ram_wr_en_;
    wire [KERNEL_PTS-1:0]                                kernel_ram_wr_en = kernel_ram_wr_en_ ? 1 << kernel_word_en_num : 0;

    generate
        if (QUOTIENT_WIDTH_2 * 2 > QUOTIENT_WIDTH_1) begin : gen0
            assign dividend = {{QUOTIENT_WIDTH_2*2-QUOTIENT_WIDTH_1{1'b0}}, a_div_incha};
        end else begin : gen1
            assign dividend = a_div_incha[QUOTIENT_WIDTH_2*2-1:0];
        end
    endgenerate

    kernel_write_assist #(
        .DIVIDEND_WIDTH (QUOTIENT_WIDTH_2 * 2),
        .DIVISOR        (KERNEL_PTS),
        .DATA_WIDTH     (DATA_WIDTH + $clog2(IN_CHANNEL * OUT_CHANNEL))
    ) u_kernel_w2 (
        .quotient  (),
        .remainder (remainder),
        .o_data    ({kernel_ram_addr, kernel_wr_data}),
        .o_valid   (kernel_ram_wr_en_),
        .dividend  (dividend),
        .i_data    ({kernel_word_en_num_, kernel_wr_data_}),
        .i_valid   (div_valid),
        .clk       (clk),
        .rst_n     (rst_n)
    );

    // Bias
    wire [31:0] bias_wr_addr_ = weight_addr - BIAS_BASE_ADDR;
    wire [$clog2(OUT_CHANNEL)-1:0] bias_wr_addr = bias_wr_addr_[$clog2(OUT_CHANNEL)-1:0];
    wire bias_wr_en = weight_we && weight_addr >= BIAS_BASE_ADDR && weight_addr < BIAS_BASE_ADDR + OUT_CHANNEL;

    //////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Input registers
    reg  [DATA_WIDTH*KERNEL_PTS-1:0] i_data_reg[0:IN_CHANNEL-1];
    wire [DATA_WIDTH*KERNEL_PTS-1:0] i_data_reg_in[0:IN_CHANNEL-1];

    generate
        for (i = 0; i < KERNEL_PTS; i = i + 1) begin : gen2
            wire [DATA_WIDTH*IN_CHANNEL-1:0] input_pt = i_data[(i+1)*DATA_WIDTH*IN_CHANNEL-1:i*DATA_WIDTH*IN_CHANNEL];
            
            for (j = 0; j < IN_CHANNEL; j = j + 1) begin : gen3
                assign i_data_reg_in[j][(i+1)*DATA_WIDTH-1:i*DATA_WIDTH] = input_pt[(j+1)*DATA_WIDTH-1:j*DATA_WIDTH];
            end
        end

        for (i = 0; i < IN_CHANNEL; i = i + 1) begin : gen4
            always @ (posedge clk) begin
                if (data_latch) begin
                    i_data_reg[i] <= i_data_reg_in[i];
                end else if (cnt_en) begin
                    i_data_reg[i] <= i == IN_CHANNEL - 1 ? i_data_reg[0] : i_data_reg[i+1];
                end
            end
        end
    endgenerate

    // Kernel ram
    wire [DATA_WIDTH*KERNEL_PTS-1:0]          kernel;
    reg  [$clog2(IN_CHANNEL*OUT_CHANNEL)-1:0] kernel_cnt;

    assign cnt_limit = kernel_cnt == IN_CHANNEL * OUT_CHANNEL - 1;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            kernel_cnt <= 0;
        end else if (cnt_en) begin
            if (cnt_limit) begin
                kernel_cnt <= 0;
            end else begin
                kernel_cnt <= kernel_cnt + 1;
            end
        end
    end

    block_ram_multi_word #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (IN_CHANNEL * OUT_CHANNEL),
        .NUM_WORDS  (KERNEL_PTS),
        .RAM_STYLE  ("auto")
    ) u_kernel (
        .rd_data (kernel),
        .wr_data (kernel_wr_data),
        .rd_addr (kernel_cnt),
        .wr_addr (kernel_ram_addr[$clog2(OUT_CHANNEL*IN_CHANNEL)-1:0]),
        .wr_en   (kernel_ram_wr_en),
        .rd_en   (1'b1),
        .clk     (clk)
    );

    // Bias ram
    wire [DATA_WIDTH-1:0]          bias;
    reg  [$clog2(IN_CHANNEL)-1:0]  bias_in_cha_cnt;
    reg  [$clog2(OUT_CHANNEL)-1:0] bias_out_cha_cnt;
    wire                           bias_in_cha_cnt_limit = bias_in_cha_cnt == IN_CHANNEL - 1;
    wire                           macc_valid_o;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            bias_in_cha_cnt <= 0;
        end else if (macc_valid_o) begin
            if (bias_in_cha_cnt_limit) begin
                bias_in_cha_cnt <= 0;
            end else begin
                bias_in_cha_cnt <= bias_in_cha_cnt + 1;
            end
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            bias_out_cha_cnt <= 0;
        end else if (macc_valid_o & bias_in_cha_cnt_limit) begin
            if (bias_out_cha_cnt == OUT_CHANNEL - 1) begin
                bias_out_cha_cnt <= 0;
            end else begin
                bias_out_cha_cnt <= bias_out_cha_cnt + 1;
            end
        end
    end

    block_ram_single_read #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (OUT_CHANNEL),
        .RAM_STYLE  ("auto")
    ) u_bias (
        .rd_data (bias),
        .wr_data (weight_data),
        .wr_addr (bias_wr_addr),
        .rd_addr (bias_out_cha_cnt),
        .wr_en   (bias_wr_en),
        .rd_en   (1'b1),
        .clk     (clk)
    );

    // MACC
    wire [DATA_WIDTH*2-1:0] macc_data_out;
    reg macc_valid_i;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            macc_valid_i <= 1'b0;
        end else begin
            macc_valid_i <= cnt_en;
        end
    end

    macc #(
        .DATA_WIDTH   (DATA_WIDTH),
        .FRAC_BITS    (FRAC_BITS),
        .NUM_INPUTS   (KERNEL_PTS),
        .INCLUDE_BIAS (0)
    ) u_macc (
        .o_data   (macc_data_out),
        .o_valid  (macc_valid_o),
        .i_data   (i_data_reg[0]),
        .i_kernel (kernel),
        .i_bias   ({DATA_WIDTH{1'b0}}),
        .i_valid  (macc_valid_i),
        .clk      (clk),
        .rst_n    (rst_n)
    );

    // In channel accum / bias
    reg  signed [DATA_WIDTH*2-1:0] bias_in;
    reg  signed [DATA_WIDTH*2-1:0] bias_out;
    reg         [1:0]              bias_valid;
    reg                            bias_add_in_sel;
    wire signed [DATA_WIDTH*2-1:0] bias_add_in = bias_add_in_sel ? {{INT_BITS{bias[DATA_WIDTH-1]}}, bias, {FRAC_BITS{1'b0}}} : bias_out;

    always @ (posedge clk) begin
        bias_out <= bias_in + bias_add_in;
        bias_add_in_sel <= macc_valid_o & bias_in_cha_cnt == 0;
        
        if (macc_valid_o) begin
            bias_in <= macc_data_out;
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            bias_valid <= 2'b00;
        end else begin
            bias_valid[0] <= macc_valid_o & bias_in_cha_cnt_limit;
            bias_valid[1] <= bias_valid[0];
        end
    end

    // Output stages
    generate
        if (OUTPUT_MODE == "batchnorm_relu") begin : gen5
            // Batchnorm write logic
            reg  [31:0] batchnorm_wr_addr_;
            wire [$clog2(OUT_CHANNEL):0] batchnorm_wr_addr = batchnorm_wr_addr_[$clog2(OUT_CHANNEL):0];
            reg  batchnorm_wr_en;

            always @ (weight_addr or weight_we) begin
                if (weight_addr >= BATCHNORM_A_BASE_ADDR && weight_addr < BATCHNORM_A_BASE_ADDR + OUT_CHANNEL) begin
                    batchnorm_wr_addr_ <= weight_addr - BATCHNORM_A_BASE_ADDR;
                    batchnorm_wr_en <= weight_we;
                end else if (weight_addr >= BATCHNORM_B_BASE_ADDR && weight_addr < BATCHNORM_B_BASE_ADDR + OUT_CHANNEL) begin
                    batchnorm_wr_addr_ <= weight_addr - BATCHNORM_B_BASE_ADDR + OUT_CHANNEL;
                    batchnorm_wr_en <= weight_we;
                end else begin
                    batchnorm_wr_addr_ <= {32{1'bx}};
                    batchnorm_wr_en <= 1'b0;
                end
            end

            // Batchnorm ram
            reg  [$clog2(OUT_CHANNEL)-1:0] batchnorm_a_cnt;
            reg  [$clog2(OUT_CHANNEL):0]   batchnorm_b_cnt;
            wire signed [DATA_WIDTH-1:0]   batchnorm_a;
            wire        [DATA_WIDTH-1:0]   batchnorm_b;

            always @ (posedge clk) begin
                batchnorm_a_cnt <= bias_out_cha_cnt;
                batchnorm_b_cnt <= batchnorm_a_cnt + OUT_CHANNEL;
            end

            block_ram_dual_read #(
                .DATA_WIDTH (DATA_WIDTH),
                .DEPTH      (OUT_CHANNEL * 2),
                .RAM_STYLE  ("auto")
            ) u_bn (
                .rd_data_a (batchnorm_a),
                .rd_data_b (batchnorm_b),
                .wr_data   (weight_data),
                .rd_addr_a ({1'b0, batchnorm_a_cnt}),
                .rd_addr_b (batchnorm_b_cnt),
                .wr_addr   (batchnorm_wr_addr),
                .rw        (batchnorm_wr_en),
                .rd_en_a   (~batchnorm_wr_en),
                .rd_en_b   (~batchnorm_wr_en),
                .clk       (clk)
            );

            reg [1:0] batchnorm_valid;
            
            always @ (posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    batchnorm_valid <= 2'b00;
                end else begin
                    batchnorm_valid[0] <= bias_valid[1];
                    batchnorm_valid[1] <= batchnorm_valid[0];
                end
            end

            wire signed [DATA_WIDTH-1:0]   batchnorm_in = bias_out[FRAC_BITS*2+INT_BITS-1:FRAC_BITS];
            reg  signed [DATA_WIDTH*2-1:0] batchnorm_prod;
            reg  signed [DATA_WIDTH*2-1:0] batchnorm_res;
            wire signed [DATA_WIDTH*2-1:0] batchnorm_b_ext = {{INT_BITS{batchnorm_b[DATA_WIDTH-1]}}, batchnorm_b, {FRAC_BITS{1'b0}}};

            always @ (posedge clk) begin
                if (bias_valid[1]) begin
                    batchnorm_prod <= batchnorm_in * batchnorm_a;
                end

                if (batchnorm_valid[0]) begin
                    batchnorm_res <= batchnorm_prod + batchnorm_b_ext;
                end
            end

            // ReLU
            assign o_data = batchnorm_res < 0 ? 0 : batchnorm_res[FRAC_BITS*2+INT_BITS-1:FRAC_BITS];
            assign o_valid = batchnorm_valid[1];
        end

        else if (OUTPUT_MODE == "sigmoid") begin : gen6
            sigmoid #(
                .DATA_WIDTH (DATA_WIDTH),
                .FRAC_BITS  (FRAC_BITS)
            ) u_sigmoid (
                .o_data  (o_data),
                .o_valid (o_valid),
                .i_data  (bias_out[FRAC_BITS*2+INT_BITS-1:FRAC_BITS]),
                .i_valid (bias_valid[1]),
                .clk     (clk),
                .rst_n   (rst_n)
            );
        end

        else if (OUTPUT_MODE == "linear") begin : gen7
            assign o_data = bias_out[FRAC_BITS*2+INT_BITS-1:FRAC_BITS];
            assign o_valid = bias_valid[1];
        end

        else begin : gen8
            assign o_data = 0;
            assign o_valid = 1'b0;
        end
    endgenerate

endmodule
 