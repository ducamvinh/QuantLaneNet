`timescale 1ns / 1ps

module pe_outcha_double_obuffer #(
    parameter DATA_WIDTH = 8,
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
    output reg [DATA_WIDTH-1:0] o_data,
    output reg                  o_valid,
    input      [DATA_WIDTH-1:0] i_data_a,
    input      [DATA_WIDTH-1:0] i_data_b,
    input                       i_valid,
    input                       clk,
    input                       rst_n
);

    // If num output pixels is odd
    localparam OUT_HEIGHT = (IN_HEIGHT + 2 * PADDING_0 - DILATION_0 * (KERNEL_0 - 1) - 1) / STRIDE_0 + 1;
    localparam OUT_WIDTH  = (IN_WIDTH  + 2 * PADDING_1 - DILATION_1 * (KERNEL_1 - 1) - 1) / STRIDE_1 + 1;
    localparam OUT_PIXELS = OUT_HEIGHT * OUT_WIDTH;

    wire last_odd;

    generate
        if (OUT_PIXELS % 2) begin : gen0
            localparam COUNTER_MAX = (OUT_PIXELS + 1) / 2;

            reg [$clog2(COUNTER_MAX)-1:0] out_pixel_cnt;
            assign last_odd = out_pixel_cnt == COUNTER_MAX - 1;

            always @ (posedge clk or negedge rst_n) begin
                if (~rst_n) begin
                    out_pixel_cnt <= 0;
                end
                else if (i_valid) begin
                    out_pixel_cnt <= last_odd ? 0 : out_pixel_cnt + 1;
                end
            end
        end
        else begin : gen1
            assign last_odd = 1'b0;
        end
    endgenerate

    // Buffer
    reg [DATA_WIDTH-1:0] buffer;
    reg                  buffer_en;

    always @ (posedge clk) begin
        if (buffer_en) begin
            buffer <= i_data_b;
        end
    end

    // Control FSM
    localparam STATE_0 = 0;
    localparam STATE_1 = 1;

    reg [0:0] current_state;
    reg [0:0] next_state;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            current_state <= STATE_0;
        end
        else begin
            current_state <= next_state;
        end
    end

    always @ (*) begin
        case (current_state)
            STATE_0 : next_state <= i_valid ? (last_odd ? STATE_0 : STATE_1) : STATE_0;
            STATE_1 : next_state <= STATE_0;
            default : next_state <= STATE_0;
        endcase
    end

    // Output assignment
    always @ (*) begin
        case (current_state)
            STATE_0: begin
                o_data    <= last_odd ? i_data_b : i_data_a;
                o_valid   <= i_valid;
                buffer_en <= i_valid & ~last_odd;
            end

            STATE_1: begin
                o_data    <= buffer;
                o_valid   <= 1'b1;
                buffer_en <= 1'b0;
            end

            default: begin
                o_data    <= {DATA_WIDTH{1'bx}};
                o_valid   <= 1'b0;
                buffer_en <= 1'b0;
            end
        endcase
    end

endmodule
