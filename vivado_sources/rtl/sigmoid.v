`timescale 1ns / 1ps

module sigmoid #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS  = 10
)(
    output signed [DATA_WIDTH-1:0] o_data,
    output                         o_valid,
    input  signed [DATA_WIDTH-1:0] i_data,
    input                          i_valid,
    input                          clk,
    input                          rst_n
);

    localparam INT_BITS = DATA_WIDTH - FRAC_BITS;

    localparam signed [DATA_WIDTH-1:0] FOUR       = {{INT_BITS-3{1'b0}}, 3'b100, {FRAC_BITS{1'b0}}};
    localparam signed [DATA_WIDTH-1:0] MINUS_FOUR = {{INT_BITS-3{1'b1}}, 3'b100, {FRAC_BITS{1'b0}}};
    localparam signed [DATA_WIDTH+1:0] ONE        = {{INT_BITS-1{1'b0}},   1'b1, {FRAC_BITS+2{1'b0}}};
    localparam signed [DATA_WIDTH+1:0] MINUS_ONE  = {{INT_BITS-1{1'b1}},   1'b1, {FRAC_BITS+2{1'b0}}};

    // Input stage
    reg signed [DATA_WIDTH-1:0] i_data_reg;
    reg                         i_data_valid;

    always @ (posedge clk) begin
        if (i_valid) begin
            i_data_reg <= i_data;
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            i_data_valid <= 1'b0;
        end
        else begin
            i_data_valid <= i_valid;
        end
    end

    // Stage 1
    wire signed [DATA_WIDTH+1:0] x1            = {{2{i_data_reg[DATA_WIDTH-1]}}, i_data_reg}; // x1 = i_data_reg >>> 2
    wire signed [DATA_WIDTH+1:0] add_minus_one = i_data_reg < 0 ? ONE : MINUS_ONE;
    wire signed [DATA_WIDTH+1:0] x2            = x1 + add_minus_one;

    wire                         past_limit    = i_data_reg < MINUS_FOUR || i_data_reg > FOUR;
    wire signed [DATA_WIDTH+1:0] x3            = past_limit ? 0 : x2;

    reg  signed [DATA_WIDTH+1:0] stage1_reg_data;
    reg                          stage1_reg_sign;
    reg                          stage1_reg_valid;

    always @ (posedge clk) begin
        if (i_data_valid) begin
            stage1_reg_data <= x3;
            stage1_reg_sign <= i_data_reg < 0;
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            stage1_reg_valid <= 1'b0;
        end
        else begin
            stage1_reg_valid <= i_data_valid;
        end
    end

    // Stage 2
    reg signed [(DATA_WIDTH+2)*2-1:0] stage2_reg_data;
    reg                               stage2_reg_sign;
    reg                               stage2_reg_valid;

    always @ (posedge clk) begin
        if (stage1_reg_valid) begin
            stage2_reg_data <= stage1_reg_data * stage1_reg_data;
            stage2_reg_sign <= stage1_reg_sign;
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            stage2_reg_valid <= 1'b0;
        end
        else begin
            stage2_reg_valid <= stage1_reg_valid;
        end
    end

    // Stage 3
    localparam signed [(DATA_WIDTH+2)*2:0] ONE_EXT = {{INT_BITS*2-1{1'b0}}, 1'b1, {(FRAC_BITS+2)*2+1{1'b0}}};

    wire signed [(DATA_WIDTH+2)*2:0] x4 = {stage2_reg_data[(DATA_WIDTH+2)*2-1], stage2_reg_data};  // x4 = stage2_reg_data >>> 1
    wire signed [(DATA_WIDTH+2)*2:0] x5 = ONE_EXT - x4;
    wire signed [(DATA_WIDTH+2)*2:0] x6 = stage2_reg_sign ? x4 : x5;

    assign o_data  = x6[(FRAC_BITS+2)*2+INT_BITS:FRAC_BITS+5];
    assign o_valid = stage2_reg_valid;

endmodule
