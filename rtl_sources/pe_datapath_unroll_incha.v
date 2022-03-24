`timescale 1ns / 1ps

module pe_datapath_unroll_incha #(
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

    genvar i;

    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Weight ram write logic
    
    // Kernel
    localparam NUM_KERNEL_WEIGHTS = KERNEL_PTS * IN_CHANNEL * OUT_CHANNEL;
    localparam QUOTIENT_WIDTH = $clog2(KERNEL_PTS * IN_CHANNEL) > $clog2(OUT_CHANNEL) ? $clog2(KERNEL_PTS * IN_CHANNEL) : $clog2(OUT_CHANNEL);

    wire [31:0] kernel_addr = weight_addr - KERNEL_BASE_ADDR;
    wire [QUOTIENT_WIDTH*2-1:0] kernel_addr_adj = kernel_addr[QUOTIENT_WIDTH*2-1:0];
    wire kernel_wr_en = weight_we && weight_addr >= KERNEL_BASE_ADDR && weight_addr < KERNEL_BASE_ADDR + NUM_KERNEL_WEIGHTS;

    wire [QUOTIENT_WIDTH-1:0]        kernel_ram_addr;
    wire [QUOTIENT_WIDTH-1:0]        kernel_word_en_num;
    wire [DATA_WIDTH-1:0]            kernel_wr_data;
    wire                             kernel_ram_wr_en_;
    wire [KERNEL_PTS*IN_CHANNEL-1:0] kernel_ram_wr_en = kernel_ram_wr_en_ ? 1 << kernel_word_en_num : 0;

    kernel_write_assist #(
        .DIVIDEND_WIDTH (QUOTIENT_WIDTH * 2),
        .DIVISOR        (KERNEL_PTS * IN_CHANNEL),
        .DATA_WIDTH     (DATA_WIDTH)
    ) u_kernel_w (
        .quotient  (kernel_ram_addr),
        .remainder (kernel_word_en_num),
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
    reg [PIXEL_WIDTH*KERNEL_PTS-1:0] i_data_reg;

    always @ (posedge clk) begin
        if (data_latch) begin
            i_data_reg <= i_data;
        end
    end

    // Kernel ram
    wire [PIXEL_WIDTH*KERNEL_PTS-1:0] kernel;
    reg  [$clog2(OUT_CHANNEL)-1:0]    kernel_cnt;
    
    assign cnt_limit = kernel_cnt == OUT_CHANNEL - 1;

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
        .DEPTH      (OUT_CHANNEL),
        .NUM_WORDS  (KERNEL_PTS * IN_CHANNEL),
        .RAM_STYLE  ("auto")
    ) u_kernel (
        .rd_data (kernel),
        .wr_data (kernel_wr_data),
        .rd_addr (kernel_cnt),
        .wr_addr (kernel_ram_addr[$clog2(OUT_CHANNEL)-1:0]),
        .wr_en   (kernel_ram_wr_en),
        .rd_en   (1'b1),
        .clk     (clk)
    );

    // Bias ram
    wire [DATA_WIDTH-1:0]          bias;
    reg  [$clog2(OUT_CHANNEL)-1:0] bias_cnt;

    always @ (posedge clk) begin
        bias_cnt <= kernel_cnt;
    end

    block_ram_single_read #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (OUT_CHANNEL),
        .RAM_STYLE  ("auto")
    ) u_bias (
        .rd_data (bias),
        .wr_data (weight_data),
        .wr_addr (bias_wr_addr),
        .rd_addr (bias_cnt),
        .wr_en   (bias_wr_en),
        .rd_en   (1'b1),
        .clk     (clk)
    );

    // MACC
    wire [DATA_WIDTH*2-1:0] macc_data_out;
    wire                    macc_valid_o;
    reg                     macc_valid_i;

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
        .NUM_INPUTS   (KERNEL_PTS * IN_CHANNEL),
        .INCLUDE_BIAS (1)
    ) u_macc (
        .o_data   (macc_data_out),
        .o_valid  (macc_valid_o),
        .i_data   (i_data_reg),
        .i_kernel (kernel),
        .i_bias   (bias),
        .i_valid  (macc_valid_i),
        .clk      (clk),
        .rst_n    (rst_n)
    );

    // MACC out reg
    reg [DATA_WIDTH-1:0] macc_data_out_reg; 
    reg                  macc_valid_o_reg;

    always @ (posedge clk) begin
        if (macc_valid_o) begin
            macc_data_out_reg <= macc_data_out[FRAC_BITS*2+INT_BITS-1:FRAC_BITS];
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            macc_valid_o_reg <= 1'b0;
        end else begin
            macc_valid_o_reg <= macc_valid_o;
        end
    end

    // Output stages
    generate
        if (OUTPUT_MODE == "batchnorm_relu") begin : gen0
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

            // Batchnorm a counter
            wire signed [DATA_WIDTH-1:0] batchnorm_a;
            reg  [$clog2(OUT_CHANNEL):0] batchnorm_a_cnt;

            always @ (posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    batchnorm_a_cnt <= 0;
                end else if (macc_valid_o) begin
                    if (batchnorm_a_cnt == OUT_CHANNEL - 1) begin
                        batchnorm_a_cnt <= 0;
                    end else begin
                        batchnorm_a_cnt <= batchnorm_a_cnt + 1;
                    end
                end
            end

            // Batchnorm b counter
            wire [DATA_WIDTH-1:0]       batchnorm_b;
            reg [$clog2(OUT_CHANNEL):0] batchnorm_b_cnt;

            always @ (posedge clk) begin
                batchnorm_b_cnt <= batchnorm_a_cnt + OUT_CHANNEL;
            end

            // Batchnorm ram
            block_ram_dual_read #(
                .DATA_WIDTH (DATA_WIDTH),
                .DEPTH      (OUT_CHANNEL * 2),
                .RAM_STYLE  ("auto")
            ) u_bn (
                .rd_data_a (batchnorm_a),
                .rd_data_b (batchnorm_b),
                .wr_data   (weight_data),
                .rd_addr_a (batchnorm_a_cnt),
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
                    batchnorm_valid[0] <= macc_valid_o_reg;
                    batchnorm_valid[1] <= batchnorm_valid[0];
                end
            end

            wire signed [DATA_WIDTH-1:0]   batchnorm_in = macc_data_out_reg;
            reg  signed [DATA_WIDTH*2-1:0] batchnorm_prod;
            reg  signed [DATA_WIDTH*2-1:0] batchnorm_res;
            wire signed [DATA_WIDTH*2-1:0] batchnorm_b_ext = {{INT_BITS{batchnorm_b[DATA_WIDTH-1]}}, batchnorm_b, {FRAC_BITS{1'b0}}};

            always @ (posedge clk) begin
                if (macc_valid_o_reg) begin
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

        else if (OUTPUT_MODE == "sigmoid") begin : gen1
            sigmoid #(
                .DATA_WIDTH (DATA_WIDTH),
                .FRAC_BITS  (FRAC_BITS)
            ) u_sigmoid (
                .o_data  (o_data),
                .o_valid (o_valid),
                .i_data  (macc_data_out_reg),
                .i_valid (macc_valid_o_reg),
                .clk     (clk),
                .rst_n   (rst_n)
            );
        end

        else if (OUTPUT_MODE == "linear") begin : gen2
            assign o_data = macc_data_out[FRAC_BITS*2+INT_BITS-1:FRAC_BITS];
            assign o_valid = macc_valid_o;
        end

        else begin : gen3
            assign o_data = 0;
            assign o_valid = 1'b0;
        end
    endgenerate

endmodule
