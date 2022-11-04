`timescale 1ns / 1ps

module pe_incha_double #(
    // Layer parameters
    parameter IN_WIDTH    = 513,
    parameter IN_HEIGHT   = 257,
    parameter IN_CHANNEL  = 3,
    parameter OUT_CHANNEL = 8,
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
    input  [8*IN_CHANNEL*KERNEL_PTS-1:0]       i_data;
    input                                      i_valid;
    input  [15:0]                              weight_wr_data;
    input  [31:0]                              weight_wr_addr;
    input                                      weight_wr_en;
    input                                      clk;
    input                                      rst_n;

    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Weight ram write logic

    // Kernel
    localparam NUM_KERNEL_WEIGHTS = KERNEL_PTS * IN_CHANNEL * OUT_CHANNEL;
    localparam QUOTIENT_WIDTH     = $clog2(KERNEL_PTS * IN_CHANNEL) > $clog2(OUT_CHANNEL) ? $clog2(KERNEL_PTS * IN_CHANNEL) : $clog2(OUT_CHANNEL);

    wire [31:0]                 kernel_addr     = weight_wr_addr - KERNEL_BASE_ADDR;
    wire [QUOTIENT_WIDTH*2-1:0] kernel_addr_adj = kernel_addr[QUOTIENT_WIDTH*2-1:0];
    wire                        kernel_wr_en    = weight_wr_en && weight_wr_addr >= KERNEL_BASE_ADDR && weight_wr_addr < KERNEL_BASE_ADDR + NUM_KERNEL_WEIGHTS;

    wire [QUOTIENT_WIDTH-1:0]        kernel_ram_addr;
    wire [QUOTIENT_WIDTH-1:0]        kernel_word_en_num;
    wire [7:0]                       kernel_wr_data;
    wire                             kernel_ram_wr_en_;
    wire [KERNEL_PTS*IN_CHANNEL-1:0] kernel_ram_wr_en = kernel_ram_wr_en_ ? 1 << kernel_word_en_num : 0;

    kernel_write_assist #(
        .DIVIDEND_WIDTH (QUOTIENT_WIDTH * 2),
        .DIVISOR        (KERNEL_PTS * IN_CHANNEL),
        .DATA_WIDTH     (8)
    ) u_kernel_w (
        .quotient       (kernel_ram_addr),
        .remainder      (kernel_word_en_num),
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
    wire cnt_en;
    wire cnt_limit;

    pe_controller u_control (
        .cnt_en    (cnt_en),
        .pe_ready  (pe_ready),
        .pe_ack    (pe_ack),
        .cnt_limit (cnt_limit),
        .i_valid   (i_valid),
        .clk       (clk),
        .rst_n     (rst_n)
    );

    // Input registers
    reg [8*IN_CHANNEL*KERNEL_PTS-1:0] i_data_reg;

    always @ (posedge clk) begin
        if (pe_ack) begin
            i_data_reg <= i_data;
        end
    end

    // Kernel ram
    localparam COUNTER_MAX = (OUT_CHANNEL + 1) / 2;

    wire [8*IN_CHANNEL*KERNEL_PTS-1:0] kernel_port_a;
    wire [8*IN_CHANNEL*KERNEL_PTS-1:0] kernel_port_b;
    reg  [$clog2(COUNTER_MAX)-1:0]     kernel_cnt;

    assign cnt_limit = kernel_cnt == COUNTER_MAX - 1;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            kernel_cnt <= 0;
        end
        else if (cnt_en) begin
            kernel_cnt <= cnt_limit ? 0 : kernel_cnt + 1;
        end
    end

    block_ram_multi_word_dual_port #(
        .DATA_WIDTH      (8),
        .DEPTH           (OUT_CHANNEL),
        .NUM_WORDS       (KERNEL_PTS * IN_CHANNEL),
        .RAM_STYLE       ("auto"),
        .OUTPUT_REGISTER ("true")
    ) u_kernel (
        .rd_data_a       (kernel_port_a),
        .rd_data_b       (kernel_port_b),
        .wr_data_a       (kernel_wr_data),
        .wr_data_b       ({8{1'b0}}),
        .addr_a          (kernel_ram_wr_en_ ? kernel_ram_addr[$clog2(OUT_CHANNEL)-1:0] : {kernel_cnt, 1'b0}),
        .addr_b          ({kernel_cnt, 1'b1}),
        .rd_en_a         (1'b1),
        .rd_en_b         (1'b1),
        .wr_en_a         (kernel_ram_wr_en),
        .wr_en_b         ({KERNEL_PTS*IN_CHANNEL{1'b0}}),
        .clk             (clk)
    );


    // Bias ram
    wire signed [15:0] bias_port_a;
    wire signed [15:0] bias_port_b;

    reg  [$clog2(COUNTER_MAX)-1:0] bias_cnt;
    wire                           bias_cnt_en;
    wire                           bias_cnt_limit = bias_cnt == COUNTER_MAX - 1;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            bias_cnt <= 0;
        end
        else if (bias_cnt_en) begin
            bias_cnt <= bias_cnt_limit ? 0 : bias_cnt + 1;
        end
    end

    block_ram_dual_port #(
        .DATA_WIDTH      (16),
        .DEPTH           (OUT_CHANNEL),
        .RAM_STYLE       ("auto"),
        .OUTPUT_REGISTER ("true")
    ) u_bias (
        .rd_data_a       (bias_port_a),
        .rd_data_b       (bias_port_b),
        .wr_data_a       (weight_wr_data),
        .wr_data_b       ({16{1'b0}}),
        .addr_a          (bias_wr_en ? bias_wr_addr : {bias_cnt, 1'b0}),
        .addr_b          ({bias_cnt, 1'b1}),
        .rd_en_a         (1'b1),
        .rd_en_b         (1'b1),
        .wr_en_a         (bias_wr_en),
        .wr_en_b         (1'b0),
        .clk             (clk)
    );

    // MACC co-efficient reg
    reg signed [15:0] macc_coeff;

    always @ (posedge clk) begin
        if (weight_wr_en && weight_wr_addr == MACC_COEFF_BASE_ADDR) begin
            macc_coeff <= weight_wr_data;
        end
    end

    // Dual MACC
    localparam MACC_OUTPUT_DATA_WIDTH = 16 + $clog2(KERNEL_PTS * IN_CHANNEL);

    wire [MACC_OUTPUT_DATA_WIDTH-1:0] macc_data_out_a;
    wire [MACC_OUTPUT_DATA_WIDTH-1:0] macc_data_out_b;
    wire                              macc_valid_o;
    reg                               macc_valid_i;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            macc_valid_i <= 1'b0;
        end
        else begin
            macc_valid_i <= cnt_en;
        end
    end

    ////////////////////////////////////////////////////////////////////////////////////////////////

    // BRAM output pipeline register because Vivado won't stop screaming about it
    reg [8*IN_CHANNEL*KERNEL_PTS-1:0] i_data_reg_pipeline;
    reg                               macc_valid_i_pipeline;

    always @ (posedge clk) begin
        i_data_reg_pipeline <= i_data_reg;
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

    wire [8*IN_CHANNEL*KERNEL_PTS-1:0] macc_in_b;

    generate
        if (OUT_CHANNEL % 2) begin : gen0
            reg kernel_cnt_zero;

            always @ (posedge clk) begin
                kernel_cnt_zero <= kernel_cnt == 0;
            end

            assign macc_in_b = kernel_cnt_zero ? 0 : kernel_port_b;
        end
        else begin : gen1
            assign macc_in_b = kernel_port_b;
        end
    endgenerate

    macc_8bit_dual #(
        .NUM_INPUTS (KERNEL_PTS * IN_CHANNEL)
    ) u_macc_dual (
        .o_data_a   (macc_data_out_a),
        .o_data_b   (macc_data_out_b),
        .o_valid    (macc_valid_o),
        .i_data_a   (kernel_port_a),
        .i_data_b   (macc_in_b),
        .i_data_c   (i_data_reg_pipeline),
        .i_valid    (macc_valid_i_pipeline),
        .clk        (clk),
        .rst_n      (rst_n)
    );

    // MACC out reg
    reg signed [MACC_OUTPUT_DATA_WIDTH-1:0] macc_data_out_a_reg;
    reg signed [MACC_OUTPUT_DATA_WIDTH-1:0] macc_data_out_b_reg;
    reg                                     macc_valid_o_reg;

    always @ (posedge clk) begin
        if (macc_valid_o) begin
            macc_data_out_a_reg <= macc_data_out_a;
            macc_data_out_b_reg <= macc_data_out_b;
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            macc_valid_o_reg <= 1'b0;
        end
        else begin
            macc_valid_o_reg <= macc_valid_o;
        end
    end

    // MACC co-efficient
    reg signed [MACC_OUTPUT_DATA_WIDTH+16-1:0] coeff_prod_a;  // 16-bit co-eff (x2^-16) x {MACC_OUTPUT_DATA_WIDTH}-bit macc output (x2^0)
    reg signed [MACC_OUTPUT_DATA_WIDTH+16-1:0] coeff_prod_b;  // = {MACC_OUTPUT_DATA_WIDTH+16}-bit product (x2^-16)
    reg                                        coeff_valid;

    always @ (posedge clk) begin
        if (macc_valid_o_reg) begin
            coeff_prod_a <= macc_coeff * macc_data_out_a_reg;
            coeff_prod_b <= macc_coeff * macc_data_out_b_reg;
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            coeff_valid <= 1'b0;
        end
        else begin
            coeff_valid <= macc_valid_o_reg;
        end
    end

    // Bias
    wire signed [23:0]                          bias_adjusted_a = {bias_port_a, {8{1'b0}}};
    wire signed [23:0]                          bias_adjusted_b = {bias_port_b, {8{1'b0}}};
    reg  signed [MACC_OUTPUT_DATA_WIDTH+16-1:0] bias_sum_a;  // {MACC_OUTPUT_DATA_WIDTH+16}-bit co-eff prod (x2^-16) + 16-bit bias (x2^-8)
    reg  signed [MACC_OUTPUT_DATA_WIDTH+16-1:0] bias_sum_b;
    reg                                         bias_valid;

    assign bias_cnt_en = macc_valid_o;

    always @ (posedge clk) begin
        if (coeff_valid) begin
            bias_sum_a <= coeff_prod_a + bias_adjusted_a;
            bias_sum_b <= coeff_prod_b + bias_adjusted_b;
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            bias_valid <= 1'b0;
        end
        else begin
            bias_valid <= coeff_valid;
        end
    end

    // Output
    wire signed [OUTPUT_DATA_WIDTH-1:0] obuffer_data_a;
    wire signed [OUTPUT_DATA_WIDTH-1:0] obuffer_data_b;
    wire                                obuffer_valid;

    generate
        if (OUTPUT_MODE == "relu") begin : gen2
            assign obuffer_data_a = bias_sum_a < 0 ? 0 : ((bias_sum_a[23] || bias_sum_a[22:16] == {7{1'b1}}) ? 127 : (bias_sum_a[23:16] + (bias_sum_a[15] & |bias_sum_a[14:12])));
            assign obuffer_data_b = bias_sum_b < 0 ? 0 : ((bias_sum_b[23] || bias_sum_b[22:16] == {7{1'b1}}) ? 127 : (bias_sum_b[23:16] + (bias_sum_b[15] & |bias_sum_b[14:12])));
            assign obuffer_valid  = bias_valid;
        end

        else if (OUTPUT_MODE == "dequant" || OUTPUT_MODE == "sigmoid") begin : gen3
            // layer_scale reg
            reg signed [15:0] layer_scale;  // 16-bit layer_scale (x2^-16)

            always @ (posedge clk) begin
                if (weight_wr_en && weight_wr_addr == LAYER_SCALE_BASE_ADDR) begin
                    layer_scale <= weight_wr_data;
                end
            end

            // ######### Output dequant #########

            // bias_sum truncate
            wire signed [MACC_OUTPUT_DATA_WIDTH-1:0] bias_sum_a_int = bias_sum_a[MACC_OUTPUT_DATA_WIDTH+16-1:16];
            wire signed [MACC_OUTPUT_DATA_WIDTH-1:0] bias_sum_b_int = bias_sum_b[MACC_OUTPUT_DATA_WIDTH+16-1:16];
            reg  signed [8+16-1:0]                   bias_sum_a_trunc;  // 24-bit bias sum truncate (x2^-16)
            reg  signed [8+16-1:0]                   bias_sum_b_trunc;
            reg                                      bias_sum_trunc_valid;

            always @ (posedge clk) begin
                if (bias_valid) begin
                    bias_sum_a_trunc <= bias_sum_a_int >= 127 ? (127 << 16) : (bias_sum_a_int <= -128 ? (-128 << 16) : bias_sum_a[8+16-1:0]);
                    bias_sum_b_trunc <= bias_sum_b_int >= 127 ? (127 << 16) : (bias_sum_b_int <= -128 ? (-128 << 16) : bias_sum_b[8+16-1:0]);
                end
            end

            always @ (posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    bias_sum_trunc_valid <= 1'b0;
                end
                else begin
                    bias_sum_trunc_valid <= bias_valid;
                end
            end

            // layer_scale mult
            reg signed [39:0] dequant_a;  // 24-bit bias sum (x2^-16) x 16-bit layer_scale (x2^-16) = 40-bit product (x2^-32)
            reg signed [39:0] dequant_b;
            reg               dequant_valid;

            always @ (posedge clk) begin
                if (bias_sum_trunc_valid) begin
                    dequant_a <= bias_sum_a_trunc * layer_scale;
                    dequant_b <= bias_sum_b_trunc * layer_scale;
                end
            end

            always @ (posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    dequant_valid <= 1'b0;
                end
                else begin
                    dequant_valid <= bias_sum_trunc_valid;
                end
            end

            // Truncate for output
            wire signed [15:0] dequant_trunc_a = dequant_a[39:24] + (dequant_a[23] & |dequant_a[22:20]);
            wire signed [15:0] dequant_trunc_b = dequant_b[39:24] + (dequant_b[23] & |dequant_b[22:20]);

            if (OUTPUT_MODE == "dequant") begin : gen4
                assign obuffer_data_a = dequant_trunc_a;
                assign obuffer_data_b = dequant_trunc_b;
                assign obuffer_valid  = dequant_valid;
            end

            else if (OUTPUT_MODE == "sigmoid") begin : gen5
                wire valid_dummy;

                sigmoid #(
                    .DATA_WIDTH (16),
                    .FRAC_BITS  (8)
                ) u_sigmoid[1:0] (
                    .o_data     ({obuffer_data_b, obuffer_data_a}),
                    .o_valid    ({valid_dummy, obuffer_valid}),
                    .i_data     ({dequant_trunc_b, dequant_trunc_a}),
                    .i_valid    (dequant_valid),
                    .clk        (clk),
                    .rst_n      (rst_n)
                );
            end
        end
    endgenerate

    // obuffer
    pe_incha_obuffer #(
        .DATA_WIDTH  (OUTPUT_DATA_WIDTH),
        .NUM_INPUTS  (2),
        .OUT_CHANNEL (OUT_CHANNEL)
    ) u_obuffer (
        .o_data      (o_data),
        .o_valid     (o_valid),
        .i_data      ({obuffer_data_b, obuffer_data_a}),
        .i_valid     (obuffer_valid),
        .clk         (clk),
        .rst_n       (rst_n)
    );

endmodule
