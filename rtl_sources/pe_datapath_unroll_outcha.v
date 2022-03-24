`timescale 1ns / 1ps

module pe_datapath_unroll_outcha #(
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

    output [DATA_WIDTH*OUT_CHANNEL-1:0] o_data;
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
    
    // Kernel
    localparam NUM_KERNEL_WEIGHTS = KERNEL_PTS * IN_CHANNEL * OUT_CHANNEL;
    localparam QUOTIENT_WIDTH = KERNEL_PTS * OUT_CHANNEL > IN_CHANNEL ? $clog2(KERNEL_PTS * OUT_CHANNEL) : $clog2(IN_CHANNEL);

    wire [31:0] kernel_addr = weight_addr - KERNEL_BASE_ADDR;
    wire [QUOTIENT_WIDTH*2-1:0] kernel_addr_adj = kernel_addr[QUOTIENT_WIDTH*2-1:0];
    wire kernel_wr_en = weight_we && weight_addr >= KERNEL_BASE_ADDR && weight_addr < KERNEL_BASE_ADDR + NUM_KERNEL_WEIGHTS;

    wire [QUOTIENT_WIDTH-1:0]         kernel_ram_addr;
    wire [QUOTIENT_WIDTH-1:0]         kernel_word_en_num;
    wire [DATA_WIDTH-1:0]             kernel_wr_data;
    wire                              kernel_ram_wr_en_;
    wire [KERNEL_PTS*OUT_CHANNEL-1:0] kernel_ram_wr_en = kernel_ram_wr_en_ ? 1 << kernel_word_en_num : 0;

    kernel_write_assist #(
        .DIVIDEND_WIDTH (QUOTIENT_WIDTH * 2),
        .DIVISOR        (IN_CHANNEL),
        .DATA_WIDTH     (DATA_WIDTH)
    ) u_kernel_w (
        .quotient  (kernel_word_en_num),
        .remainder (kernel_ram_addr),
        .o_data    (kernel_wr_data),
        .o_valid   (kernel_ram_wr_en_),
        .dividend  (kernel_addr_adj),
        .i_data    (weight_data),
        .i_valid   (kernel_wr_en),
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
        for (i = 0; i < KERNEL_PTS; i = i + 1) begin : gen0
            wire [DATA_WIDTH*IN_CHANNEL-1:0] input_pt = i_data[(i+1)*DATA_WIDTH*IN_CHANNEL-1:i*DATA_WIDTH*IN_CHANNEL];

            for (j = 0; j < IN_CHANNEL; j = j + 1) begin : gen1
                assign i_data_reg_in[j][(i+1)*DATA_WIDTH-1:i*DATA_WIDTH] = input_pt[(j+1)*DATA_WIDTH-1:j*DATA_WIDTH];
            end
        end

        for (i = 0; i < IN_CHANNEL; i = i + 1) begin : gen2
            always @ (posedge clk) begin
                if (data_latch) begin
                    i_data_reg[i] <= i_data_reg_in[i];
                end else if (cnt_en) begin
                    i_data_reg[i] <= i == IN_CHANNEL - 1 ? i_data_reg[i] : i_data_reg[i+1];
                end
            end
        end
    endgenerate

    // Kernel ram
    wire [DATA_WIDTH*KERNEL_PTS*OUT_CHANNEL-1:0] kernel;
    reg [$clog2(IN_CHANNEL)-1:0]                 kernel_cnt;

    assign cnt_limit = kernel_cnt == IN_CHANNEL - 1;

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
        .DEPTH      (IN_CHANNEL),
        .NUM_WORDS  (KERNEL_PTS * OUT_CHANNEL),
        .RAM_STYLE  ("auto")
    ) u_kernel (
        .rd_data (kernel),
        .wr_data (kernel_wr_data),
        .rd_addr (kernel_cnt),
        .wr_addr (kernel_ram_addr[$clog2(IN_CHANNEL)-1:0]),
        .wr_en   (kernel_ram_wr_en),
        .rd_en   (1'b1),
        .clk     (clk)
    );

    // Bias ram
    reg [DATA_WIDTH-1:0] bias_ram[0:OUT_CHANNEL-1];

    always @ (posedge clk) begin
        if (bias_wr_en) begin
            bias_ram[bias_wr_addr] <= weight_data;
        end
    end

    // In channel counter
    reg  [$clog2(IN_CHANNEL)-1:0] in_cha_cnt;
    wire                          in_cha_cnt_limit = in_cha_cnt == IN_CHANNEL - 1;
    wire                          macc_valid_o;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            in_cha_cnt <= 0;
        end else if (macc_valid_o) begin
            if (in_cha_cnt_limit) begin
                in_cha_cnt <= 0;
            end else begin
                in_cha_cnt <= in_cha_cnt + 1;
            end
        end
    end

    // Bias valid
    reg [1:0] bias_valid;
    reg       bias_add_in_sel;

    always @ (posedge clk) begin
        bias_add_in_sel <= macc_valid_o && in_cha_cnt == 0;
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            bias_valid <= 2'b00;
        end else begin
            bias_valid[0] <= macc_valid_o & in_cha_cnt_limit;
            bias_valid[1] <= bias_valid[0];
        end
    end

    // Batchnorm ram
    wire [DATA_WIDTH-1:0] batchnorm_ram[0:OUT_CHANNEL*2-1];
    wire [1:0]            batchnorm_valid;
    
    generate
        if (OUTPUT_MODE == "batchnorm_relu") begin : gen3
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
            reg [DATA_WIDTH-1:0] batchnorm_ram_[0:OUT_CHANNEL*2-1];

            always @ (posedge clk) begin
                if (batchnorm_wr_en) begin
                    batchnorm_ram_[batchnorm_wr_addr] <= weight_data;
                end
            end

            for (j = 0; j < OUT_CHANNEL * 2; j = j + 1) begin : gen4
                assign batchnorm_ram[j] = batchnorm_ram_[j];
            end

            // Batchnorm valid
            reg [1:0] batchnorm_valid_;
            assign batchnorm_valid = batchnorm_valid_;

            always @ (posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    batchnorm_valid_ <= 2'b00;
                end else begin
                    batchnorm_valid_[0] <= bias_valid[1];
                    batchnorm_valid_[1] <= batchnorm_valid_[0];
                end
            end
        end
    endgenerate

    // MACC
    wire [OUT_CHANNEL-1:0] o_valid_;
    reg macc_valid_i;

    assign o_valid = o_valid_[0];

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            macc_valid_i <= 1'b0;
        end else begin
            macc_valid_i <= cnt_en;
        end
    end

    generate
        for (i = 0; i < OUT_CHANNEL; i = i + 1) begin : gen5
            wire [DATA_WIDTH*2-1:0] macc_data_out;
            wire macc_valid_o_;

            if (i == 0) begin : gen6
                assign macc_valid_o = macc_valid_o_;
            end

            macc #(
                .DATA_WIDTH   (DATA_WIDTH),
                .FRAC_BITS    (FRAC_BITS),
                .NUM_INPUTS   (KERNEL_PTS),
                .INCLUDE_BIAS (0)
            ) u_macc (
                .o_data   (macc_data_out),
                .o_valid  (macc_valid_o_),
                .i_data   (i_data_reg[0]),
                .i_kernel (kernel[(i+1)*DATA_WIDTH*KERNEL_PTS-1:i*DATA_WIDTH*KERNEL_PTS]),
                .i_bias   ({DATA_WIDTH{1'b0}}),
                .i_valid  (macc_valid_i),
                .clk      (clk),
                .rst_n    (rst_n)
            );

            // In channel accum / bias
            reg  signed [DATA_WIDTH*2-1:0] bias_in;
            reg  signed [DATA_WIDTH*2-1:0] bias_out;
            wire        [DATA_WIDTH-1:0]   bias = bias_ram[i];
            wire signed [DATA_WIDTH*2-1:0] bias_add_in = bias_add_in_sel ? {{INT_BITS{bias[DATA_WIDTH-1]}}, bias, {FRAC_BITS{1'b0}}} : bias_out;

            always @ (posedge clk) begin
                bias_out <= bias_in + bias_add_in;

                if (macc_valid_o) begin
                    bias_in <= macc_data_out;
                end
            end

            if (OUTPUT_MODE == "batchnorm_relu") begin : gen7
                wire signed [DATA_WIDTH-1:0]   batchnorm_a = batchnorm_ram[i];
                wire signed [DATA_WIDTH-1:0]   batchnorm_b = batchnorm_ram[i+OUT_CHANNEL];
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
                assign o_data[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH] = batchnorm_res < 0 ? 0 : batchnorm_res[FRAC_BITS*2+INT_BITS-1:FRAC_BITS];
                assign o_valid_[i] = batchnorm_valid[1];
            end

            else if (OUTPUT_MODE == "sigmoid") begin : gen8
                sigmoid #(
                    .DATA_WIDTH (DATA_WIDTH),
                    .FRAC_BITS  (FRAC_BITS)
                ) u_sigmoid (
                    .o_data  (o_data[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH]),
                    .o_valid (o_valid_[i]),
                    .i_data  (bias_out[FRAC_BITS*2+INT_BITS-1:FRAC_BITS]),
                    .i_valid (bias_valid[1]),
                    .clk     (clk),
                    .rst_n   (rst_n)
                );
            end

            else if (OUTPUT_MODE == "linear") begin : gen9
                assign o_data[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH] = bias_out[FRAC_BITS*2+INT_BITS-1:FRAC_BITS];
                assign o_valid_[i] = bias_valid[1];
            end

            else begin : gen10
                assign o_data[(i+1)*DATA_WIDTH-1:i*DATA_WIDTH] = 0;
                assign o_valid_[i] = 1'b0;
            end
        end
    endgenerate

endmodule
