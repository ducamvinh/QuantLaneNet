`timescale 1ns / 1ps

module pe_outcha_double_controller #(
    parameter IN_WIDTH   = 513,
    parameter IN_HEIGHT  = 257,
    parameter KERNEL_0   = 3,
    parameter KERNEL_1   = 3,
    parameter DILATION_0 = 2,
    parameter DILATION_1 = 2,
    parameter PADDING_0  = 2,
    parameter PADDING_1  = 2,
    parameter STRIDE_0   = 1,
    parameter STRIDE_1   = 1
)(
    output reg data_latch_a,
    output reg data_latch_b,
    output reg cnt_en,
    output reg pe_ready,
    output     pe_ack,
    input      cnt_limit,
    input      i_valid,
    input      clk,
    input      rst_n
);

    // If num output pixels is odd
    localparam OUT_HEIGHT = (IN_HEIGHT + 2 * PADDING_0 - DILATION_0 * (KERNEL_0 - 1) - 1) / STRIDE_0 + 1;
    localparam OUT_WIDTH  = (IN_WIDTH  + 2 * PADDING_1 - DILATION_1 * (KERNEL_1 - 1) - 1) / STRIDE_1 + 1;
    localparam OUT_PIXELS = OUT_HEIGHT * OUT_WIDTH;

    wire last_odd;

    generate
        if (OUT_PIXELS % 2) begin : gen0
            reg [$clog2(OUT_PIXELS)-1:0] out_pixel_cnt;
            assign last_odd = out_pixel_cnt == OUT_PIXELS - 1;

            always @ (posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    out_pixel_cnt <= 0;
                end
                else if (pe_ack) begin
                    out_pixel_cnt <= last_odd ? 0 : out_pixel_cnt + 1;
                end
            end
        end
        else begin : gen1
            assign last_odd = 1'b0;
        end
    endgenerate

    // Control FSM
    localparam IDLE      = 0;
    localparam GOTA      = 1;
    localparam BUSY      = 2;
    localparam BUSY_GOTA = 3;

    reg [1:0] current_state;
    reg [1:0] next_state;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            current_state <= IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always @ (*) begin
        case (current_state)
            IDLE : next_state <= i_valid ? (last_odd ? BUSY : GOTA) : IDLE;
            GOTA : next_state <= i_valid ? BUSY : GOTA;
            BUSY : begin
                if (i_valid) begin
                    if (cnt_limit) begin
                        next_state <= last_odd ? IDLE : GOTA;
                    end
                    else begin
                        next_state <= last_odd ? BUSY : BUSY_GOTA;
                    end
                end
                else begin
                    next_state <= cnt_limit ? IDLE : BUSY;
                end
            end

            BUSY_GOTA : next_state <= cnt_limit ? GOTA : BUSY_GOTA;
            default   : next_state <= IDLE;
        endcase
    end

    // Output assignments
    always @ (*) begin
        case (current_state)
            IDLE: begin
                data_latch_a <= i_valid && !last_odd;
                data_latch_b <= i_valid &&  last_odd;
                cnt_en       <= i_valid &&  last_odd;
                pe_ready     <= 1'b1;
            end

            GOTA: begin
                data_latch_a <= 1'b0;
                data_latch_b <= i_valid;
                cnt_en       <= i_valid;
                pe_ready     <= 1'b1;
            end

            BUSY: begin
                data_latch_a <= i_valid && !last_odd;
                data_latch_b <= 1'b0;
                cnt_en       <= 1'b1;
                pe_ready     <= cnt_limit;
            end

            BUSY_GOTA: begin
                data_latch_a <= 1'b0;
                data_latch_b <= 1'b0;
                cnt_en       <= 1'b1;
                pe_ready     <= cnt_limit;
            end

            default: begin
                data_latch_a <= 1'b0;
                data_latch_b <= 1'b0;
                cnt_en       <= 1'b0;
                pe_ready     <= 1'b1;
            end
        endcase
    end

    assign pe_ack = data_latch_a | data_latch_b;

endmodule
