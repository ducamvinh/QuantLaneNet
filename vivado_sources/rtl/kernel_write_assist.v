`timescale 1ns / 1ps

module kernel_write_assist #(
    parameter DIVIDEND_WIDTH = 20,
    parameter DIVISOR        = 288,
    parameter DATA_WIDTH     = 16
)(
    output [DIVIDEND_WIDTH/2-1:0]            quotient,
    output [DIVIDEND_WIDTH/2-1:0]            remainder,
    output [DATA_WIDTH-1:0]                  o_data,
    output                                   o_valid,
    input  [DIVIDEND_WIDTH-1:0]              dividend,
    input  [(DATA_WIDTH>0?DATA_WIDTH:1)-1:0] i_data,
    input                                    i_valid,
    input                                    clk,
    input                                    rst_n
);

    reg [DIVIDEND_WIDTH-1:0]   dividend_reg[0:DIVIDEND_WIDTH/2];
    reg [DIVIDEND_WIDTH/2-1:0] quotient_reg[0:DIVIDEND_WIDTH/2];
    reg [DIVIDEND_WIDTH/2:0]   valid_reg;

    genvar i;

    generate
        for (i = 0; i < DIVIDEND_WIDTH / 2 + 1; i = i + 1) begin : gen0
            wire signed [DIVIDEND_WIDTH:0]     dividend_cur;
            wire signed [DIVIDEND_WIDTH:0]     divisor_cur = DIVISOR << (DIVIDEND_WIDTH / 2 - i);
            wire signed [DIVIDEND_WIDTH:0]     sub = dividend_cur - divisor_cur;
            wire        [DIVIDEND_WIDTH/2-1:0] quotient_cur;
            wire                               valid_cur;

            if (i == 0) begin : gen1
                assign dividend_cur = {1'b0, dividend};
                assign quotient_cur = 0;
                assign valid_cur = i_valid;
            end
            else begin : gen2
                assign dividend_cur = {1'b0, dividend_reg[i-1]};
                assign quotient_cur = quotient_reg[i-1];
                assign valid_cur = valid_reg[i-1];
            end

            always @ (posedge clk) begin
                if (valid_cur) begin
                    if (sub < 0) begin
                        dividend_reg[i] <= dividend_cur[DIVIDEND_WIDTH-1:0];
                        quotient_reg[i] <= quotient_cur << 1;
                    end
                    else begin
                        dividend_reg[i] <= sub[DIVIDEND_WIDTH-1:0];
                        quotient_reg[i] <= (quotient_cur << 1) | 1'b1;
                    end
                end
            end

            always @ (posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    valid_reg[i] <= 1'b0;
                end
                else begin
                    valid_reg[i] <= valid_cur;
                end
            end
        end
    endgenerate

    generate
        if (DATA_WIDTH > 0) begin : gen3
            reg [DATA_WIDTH-1:0] data_reg[0:DIVIDEND_WIDTH/2];
            assign o_data = data_reg[DIVIDEND_WIDTH/2];

            for (i = 0; i < DIVIDEND_WIDTH / 2 + 1; i = i + 1) begin : gen4
                always @ (posedge clk) begin
                    data_reg[i] <= i == 0 ? i_data : data_reg[i-1];
                end
            end
        end
        else begin : gen5
            assign o_data = 0;
        end
    endgenerate

    assign quotient = quotient_reg[DIVIDEND_WIDTH/2];
    assign remainder = dividend_reg[DIVIDEND_WIDTH/2][DIVIDEND_WIDTH/2-1:0];
    assign o_valid = valid_reg[DIVIDEND_WIDTH/2];

endmodule
