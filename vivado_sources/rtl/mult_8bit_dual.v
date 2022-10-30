`timescale 1ns / 1ps

module mult_8bit_dual (
    output reg signed [15:0] prod_ac,
    output reg signed [15:0] prod_bc,
    output reg               o_valid,
    input      signed [7:0]  a,
    input      signed [7:0]  b,
    input      signed [7:0]  c,
    input                    i_valid,
    input                    clk,
    input                    rst_n
);

    // Stage 1
    wire signed [25:0] a_extend = {a, {18{1'b0}}};
    wire signed [26:0] b_extend = {{20{b[7]}}, b[6:0]};
    reg  signed [26:0] pre_add;
    reg  signed [7:0]  stage_1_c;
    reg                stage_1_valid;

    always @ (posedge clk) begin
        if (i_valid) begin
            pre_add <= a_extend + b_extend;
            stage_1_c <= c;
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            stage_1_valid <= 1'b0;
        end
        else begin
            stage_1_valid <= i_valid;
        end
    end

    // Stage 2
    reg signed [33:0] mult_packed;
    reg stage_2_valid;

    always @ (posedge clk) begin
        if (stage_1_valid) begin
            mult_packed <= pre_add * stage_1_c;
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            stage_2_valid <= 1'b0;
        end
        else begin
            stage_2_valid <= stage_1_valid;
        end
    end

    // Stage 3
    always @ (posedge clk) begin
        if (stage_2_valid) begin
            prod_ac <= mult_packed[33:18] + mult_packed[17];
            prod_bc <= mult_packed[15:0];
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            o_valid <= 1'b0;
        end
        else begin
            o_valid <= stage_2_valid;
        end
    end

endmodule
