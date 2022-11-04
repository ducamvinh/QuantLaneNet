`timescale 1ns / 1ps

module pe_incha_quadruple #(
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
    input [8*IN_CHANNEL*KERNEL_PTS-1:0]        i_data;
    input                                      i_valid;
    input [15:0]                               weight_wr_data;
    input [31:0]                               weight_wr_addr;
    input                                      weight_wr_en;
    input                                      clk;
    input                                      rst_n;

    genvar i;

    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Weight ram write logic

    // Kernel
    localparam NUM_KERNEL_WEIGHTS = KERNEL_PTS * IN_CHANNEL * OUT_CHANNEL;
    localparam QUOTIENT_WIDTH     = $clog2(KERNEL_PTS * IN_CHANNEL * 2) > $clog2(OUT_CHANNEL / 2) ? $clog2(KERNEL_PTS * IN_CHANNEL * 2) : $clog2(OUT_CHANNEL / 2);

    wire [31:0]                 kernel_addr     = weight_wr_addr - KERNEL_BASE_ADDR;
    wire [QUOTIENT_WIDTH*2-1:0] kernel_addr_adj = kernel_addr[QUOTIENT_WIDTH*2-1:0];
    wire                        kernel_wr_en    = weight_wr_en && weight_wr_addr >= KERNEL_BASE_ADDR && weight_wr_addr < KERNEL_BASE_ADDR + NUM_KERNEL_WEIGHTS;

    wire [QUOTIENT_WIDTH-1:0]          kernel_ram_addr;
    wire [QUOTIENT_WIDTH-1:0]          kernel_word_en_num;
    wire [7:0]                         kernel_wr_data;
    wire                               kernel_ram_wr_en_;
    wire [KERNEL_PTS*IN_CHANNEL*2-1:0] kernel_ram_wr_en = kernel_ram_wr_en_ ? 1 << kernel_word_en_num : 0;

    kernel_write_assist #(
        .DIVIDEND_WIDTH (QUOTIENT_WIDTH * 2),
        .DIVISOR        (KERNEL_PTS * IN_CHANNEL * 2),
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
    wire [$clog2(OUT_CHANNEL)-2:0] bias_wr_addr  = bias_wr_addr_[$clog2(OUT_CHANNEL)-1:1];
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
    localparam COUNTER_MAX = (OUT_CHANNEL + 3) / 4;

    wire [8*IN_CHANNEL*KERNEL_PTS*2-1:0] kernel_port_a;
    wire [8*IN_CHANNEL*KERNEL_PTS*2-1:0] kernel_port_b;
    reg  [$clog2(COUNTER_MAX)-1:0]       kernel_cnt;

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
        .DEPTH           (OUT_CHANNEL / 2),
        .NUM_WORDS       (KERNEL_PTS * IN_CHANNEL * 2),
        .RAM_STYLE       ("auto"),
        .OUTPUT_REGISTER ("true")
    ) u_kernel (
        .rd_data_a       (kernel_port_a),
        .rd_data_b       (kernel_port_b),
        .wr_data_a       (kernel_wr_data),
        .wr_data_b       ({8{1'b0}}),
        .addr_a          (kernel_ram_wr_en_ ? kernel_ram_addr[$clog2(OUT_CHANNEL)-2:0] : {kernel_cnt, 1'b0}),
        .addr_b          ({kernel_cnt, 1'b1}),
        .rd_en_a         (1'b1),
        .rd_en_b         (1'b1),
        .wr_en_a         (kernel_ram_wr_en),
        .wr_en_b         ({KERNEL_PTS*IN_CHANNEL*2{1'b0}}),
        .clk             (clk)
    );

    // Bias ram
    wire [16*2-1:0] bias_port_a;
    wire [16*2-1:0] bias_port_b;

    reg [$clog2(COUNTER_MAX)-1:0] bias_cnt;
    wire                          bias_cnt_en;
    wire                          bias_cnt_limit = bias_cnt == COUNTER_MAX - 1;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            bias_cnt <= 0;
        end
        else if (bias_cnt_en) begin
            bias_cnt <= bias_cnt_limit ? 0 : bias_cnt + 1;
        end
    end

    block_ram_multi_word_dual_port #(
        .DATA_WIDTH      (16),
        .DEPTH           (OUT_CHANNEL / 2),
        .NUM_WORDS       (2),
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
        .wr_en_a         (bias_wr_en ? (bias_wr_addr_[0] ? 2'b10 : 2'b01) : 2'b00),
        .wr_en_b         (2'b00),
        .clk             (clk)
    );

    // 4 kernel and bias buses
    wire [8*IN_CHANNEL*KERNEL_PTS-1:0] kernel[0:3];
    wire [15:0]                        bias[0:3];

    assign kernel[0] = kernel_port_a[8*IN_CHANNEL*KERNEL_PTS*1-1:8*IN_CHANNEL*KERNEL_PTS*0];
    assign kernel[1] = kernel_port_a[8*IN_CHANNEL*KERNEL_PTS*2-1:8*IN_CHANNEL*KERNEL_PTS*1];
    assign kernel[2] = kernel_port_b[8*IN_CHANNEL*KERNEL_PTS*1-1:8*IN_CHANNEL*KERNEL_PTS*0];
    assign kernel[3] = kernel_port_b[8*IN_CHANNEL*KERNEL_PTS*2-1:8*IN_CHANNEL*KERNEL_PTS*1];
    assign bias[0]   = bias_port_a[15:0];
    assign bias[1]   = bias_port_a[31:16];
    assign bias[2]   = bias_port_b[15:0];
    assign bias[3]   = bias_port_b[31:16];

    // MACC co-efficient reg
    reg signed [15:0] macc_coeff;

    always @ (posedge clk) begin
        if (weight_wr_en && weight_wr_addr == MACC_COEFF_BASE_ADDR) begin
            macc_coeff <= weight_wr_data;
        end
    end

    // MACC signals
    localparam MACC_OUTPUT_DATA_WIDTH = 16 + $clog2(KERNEL_PTS * IN_CHANNEL);

    wire [MACC_OUTPUT_DATA_WIDTH-1:0] macc_data_out[0:3];
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

    // BRAM output pipeline registers
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

    // MACCs
    wire [8*IN_CHANNEL*KERNEL_PTS-1:0] macc_kernel_in[0:2];

    generate
        if (OUT_CHANNEL % 4) begin : gen0
            reg kernel_cnt_zero;

            always @ (posedge clk) begin
                kernel_cnt_zero <= kernel_cnt == 0;
            end

            for (i = 2; i >= 0; i = i - 1) begin : gen1
                if ((OUT_CHANNEL % 4) <= (i + 1)) begin : gen2
                    assign macc_kernel_in[i] = kernel_cnt_zero ? 0 : kernel[i+1];
                end
                else begin : gen3
                    assign macc_kernel_in[i] = kernel[i+1];
                end
            end
        end
        else begin : gen4
            for (i = 0; i < 3; i = i + 1) begin : gen5
                assign macc_kernel_in[i] = kernel[i+1];
            end
        end
    endgenerate

    wire macc_valid_dummy;

    macc_8bit_dual #(
        .NUM_INPUTS (KERNEL_PTS * IN_CHANNEL)
    ) u_macc_dual[1:0] (
        .o_data_a   ({macc_data_out[1], macc_data_out[0]}),
        .o_data_b   ({macc_data_out[3], macc_data_out[2]}),
        .o_valid    ({macc_valid_dummy, macc_valid_o}),
        .i_data_a   ({macc_kernel_in[0], kernel[0]}),
        .i_data_b   ({macc_kernel_in[2], macc_kernel_in[1]}),
        .i_data_c   (i_data_reg_pipeline),
        .i_valid    (macc_valid_i_pipeline),
        .clk        (clk),
        .rst_n      (rst_n)
    );

    // MACC out reg
    reg signed [MACC_OUTPUT_DATA_WIDTH-1:0] macc_data_out_reg[0:3];
    reg                                     macc_valid_o_reg;

    always @ (posedge clk) begin
        if (macc_valid_o) begin
            macc_data_out_reg[0] <= macc_data_out[0];
            macc_data_out_reg[1] <= macc_data_out[1];
            macc_data_out_reg[2] <= macc_data_out[2];
            macc_data_out_reg[3] <= macc_data_out[3];
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
    reg signed [MACC_OUTPUT_DATA_WIDTH+16-1:0] coeff_prod[0:3];
    reg                                        coeff_valid;

    always @ (posedge clk) begin
        if (macc_valid_o_reg) begin
            coeff_prod[0] <= macc_coeff * macc_data_out_reg[0];
            coeff_prod[1] <= macc_coeff * macc_data_out_reg[1];
            coeff_prod[2] <= macc_coeff * macc_data_out_reg[2];
            coeff_prod[3] <= macc_coeff * macc_data_out_reg[3];
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
    reg signed [MACC_OUTPUT_DATA_WIDTH+16-1:0] bias_sum[0:3];
    reg                                        bias_valid;

    assign bias_cnt_en = macc_valid_o;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            bias_valid <= 1'b0;
        end
        else begin
            bias_valid <= coeff_valid;
        end
    end

    generate
        for (i = 0; i < 4; i = i + 1) begin : gen6
            wire signed [23:0] bias_adjusted = {bias[i], {8{1'b0}}};

            always @ (posedge clk) begin
                if (coeff_valid) begin
                    bias_sum[i] <= coeff_prod[i] + bias_adjusted;
                end
            end
        end
    endgenerate

    // layer_scale reg
    wire signed [15:0] layer_scale;
    wire               bias_sum_trunc_valid;
    wire               dequant_valid;

    generate
        if (OUTPUT_MODE == "dequant" || OUTPUT_MODE == "sigmoid") begin : gen7
            reg [15:0] layer_scale_reg;
            reg        dequant_valid_reg;
            reg        bias_sum_trunc_valid_reg;

            assign layer_scale = layer_scale_reg;
            assign bias_sum_trunc_valid = bias_sum_trunc_valid_reg;
            assign dequant_valid = dequant_valid_reg;

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
                    bias_sum_trunc_valid_reg <= bias_valid;
                    dequant_valid_reg <= bias_sum_trunc_valid_reg;
                end
            end
        end
    endgenerate

    // Output
    wire signed [OUTPUT_DATA_WIDTH-1:0] obuffer_data[0:3];
    wire                                obuffer_valid;

    generate
        for (i = 0; i < 4; i = i + 1) begin : gen8
            if (OUTPUT_MODE == "relu") begin : gen9
                assign obuffer_data[i] = bias_sum[i] < 0 ? 0 : ((bias_sum[i][23] || bias_sum[i][22:16] == {7{1'b1}}) ? 127 : (bias_sum[i][23:16] + (bias_sum[i][15] & |bias_sum[i][14:12])));
                assign obuffer_valid = bias_valid;
            end

            else if (OUTPUT_MODE == "dequant" || OUTPUT_MODE == "sigmoid") begin : gen10
                // bias_sum truncate
                wire signed [MACC_OUTPUT_DATA_WIDTH-1:0] bias_sum_int = bias_sum[i][MACC_OUTPUT_DATA_WIDTH+16-1:16];
                reg signed [8+16-1:0] bias_sum_trunc;

                always @ (posedge clk) begin
                    if (bias_valid) begin
                        bias_sum_trunc <= bias_sum_int >= 127 ? (127 << 16) : (bias_sum_int <= -128 ? (-128 << 16) : bias_sum[i][8+16-1:0]);
                    end
                end

                // layer_scale mult
                reg signed [39:0] dequant;

                always @ (posedge clk) begin
                    if (bias_sum_trunc_valid) begin
                        dequant <= bias_sum_trunc * layer_scale;
                    end
                end

                // Truncate for output
                wire signed [15:0] dequant_trunc = dequant[39:24] + (dequant[23] & |dequant[22:20]);

                if (OUTPUT_MODE == "dequant") begin : gen11
                    assign obuffer_data[i] = dequant_trunc;
                    assign obuffer_valid = dequant_valid;
                end

                else if (OUTPUT_MODE == "sigmoid") begin : gen12
                    wire sigmoid_valid;

                    if (i == 0) begin : gen13
                        assign obuffer_valid = sigmoid_valid;
                    end

                    sigmoid #(
                        .DATA_WIDTH (16),
                        .FRAC_BITS  (8)
                    ) u_sigmoid (
                        .o_data     (obuffer_data[i]),
                        .o_valid    (sigmoid_valid),
                        .i_data     (dequant_trunc),
                        .i_valid    (dequant_valid),
                        .clk        (clk),
                        .rst_n      (rst_n)
                    );
                end
            end
        end
    endgenerate

    // obuffer
    pe_incha_obuffer #(
        .DATA_WIDTH  (OUTPUT_DATA_WIDTH),
        .NUM_INPUTS  (4),
        .OUT_CHANNEL (OUT_CHANNEL)
    ) u_obuffer (
        .o_data      (o_data),
        .o_valid     (o_valid),
        .i_data      ({obuffer_data[3], obuffer_data[2], obuffer_data[1], obuffer_data[0]}),
        .i_valid     (obuffer_valid),
        .clk         (clk),
        .rst_n       (rst_n)
    );

endmodule
