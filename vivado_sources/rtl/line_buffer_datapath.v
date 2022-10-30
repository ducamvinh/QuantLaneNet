`timescale 1ns / 1ps

module line_buffer_datapath #(
    // Layer parameters
    parameter DATA_WIDTH = 16,
    parameter IN_CHANNEL = 16,
    parameter IN_WIDTH   = 512,

    // Conv parameters
    parameter KERNEL_0   = 3,
    parameter KERNEL_1   = 3,
    parameter DILATION_0 = 2,
    parameter DILATION_1 = 2,
    parameter PADDING_0  = 2,
    parameter PADDING_1  = 2
)(
    o_data,
    i_data,
    is_padding,
    out_blank,
    shift,
    clk,
    rst_n
);

    localparam PIXEL_WIDTH    = DATA_WIDTH * IN_CHANNEL;
    localparam TOTAL_WIDTH    = IN_WIDTH + PADDING_1 * 2;
    localparam WINDOW_0       = DILATION_0 * (KERNEL_0 - 1) + 1;
    localparam WINDOW_1       = DILATION_1 * (KERNEL_1 - 1) + 1;
    localparam KERNEL_PTS     = KERNEL_0 * KERNEL_1;
    localparam BLANK_PTS      = num_blank_pts(0);
    localparam BLANK_PTS_SAFE = BLANK_PTS > 0 ? BLANK_PTS : 1;

    output [PIXEL_WIDTH*KERNEL_PTS-1:0] o_data;
    input  [PIXEL_WIDTH-1:0]            i_data;
    input  [BLANK_PTS_SAFE-1:0]         out_blank;
    input                               is_padding;
    input                               shift;
    input                               clk;
    input                               rst_n;

    genvar i, j;

    // Window
    reg  [PIXEL_WIDTH-1:0] window    [0:KERNEL_0-1][0:WINDOW_1-1];
    wire [PIXEL_WIDTH-1:0] window_in [0:KERNEL_0-1];

    generate
        for (i = 0; i < KERNEL_0; i = i + 1) begin : gen0
            for (j = 0; j < WINDOW_1; j = j + 1) begin : gen1
                always @ (posedge clk) begin
                    if (shift) begin
                        window[i][j] <= j == 0 ? window_in[i] : window[i][j-1];
                    end
                end
            end
        end
    endgenerate

    // FIFO buffers
    generate
        for (i = 0; i < KERNEL_0 - 1; i = i + 1) begin : gen2
            localparam FIFO_DEPTH = TOTAL_WIDTH * DILATION_0 - WINDOW_1;

            if (FIFO_DEPTH > 0) begin : gen3
                wire fifo_full;

                fifo_single_read #(
                    .DATA_WIDTH (PIXEL_WIDTH),
                    .DEPTH      (FIFO_DEPTH - 1)
                ) u_fifo (
                    .rd_data     (window_in[i+1]),
                    .empty       (),
                    .full        (fifo_full),
                    .almost_full (),
                    .wr_data     (window[i][WINDOW_1-1]),
                    .wr_en       (shift),
                    .rd_en       (shift & fifo_full),
                    .rst_n       (rst_n),
                    .clk         (clk)
                );
            end
            else begin : gen4
                assign window_in[i+1] = window[i][WINDOW_1-1];
            end
        end
    endgenerate

    // Input
    generate
        if (PADDING_0 > 0 || PADDING_1 > 0) begin : gen5
            assign window_in[0] = is_padding ? 0 : i_data;
        end
        else begin : gen6
            assign window_in[0] = i_data;
        end
    endgenerate

    // Output
    generate
        for (i = 0; i < KERNEL_0; i = i + 1) begin : gen7
            for (j = 0; j < KERNEL_1; j = j + 1) begin : gen8
                localparam REVERSED_I = KERNEL_0 - i - 1;
                localparam REVERSED_J = KERNEL_1 - j - 1;

                localparam PIXEL_IDX = i * KERNEL_1 + j;
                localparam UP_BND    = (PIXEL_IDX + 1) * PIXEL_WIDTH - 1;
                localparam LO_BND    = PIXEL_IDX * PIXEL_WIDTH;

                wire [PIXEL_WIDTH-1:0] pixel = window[REVERSED_I][REVERSED_J*DILATION_1];

                if (PIXEL_IDX < BLANK_PTS) begin : gen9
                    assign o_data[UP_BND:LO_BND] = out_blank[PIXEL_IDX] ? 0 : pixel;
                end
                else begin : gen10
                    assign o_data[UP_BND:LO_BND] = pixel;
                end
            end
        end
    endgenerate

    //////////////////////////////////////////////////////////////////////////////

    function integer num_blank_pts;
        input integer dummy;
        begin
            if (WINDOW_0 <= PADDING_0) begin
                num_blank_pts = KERNEL_PTS;
            end
            else begin
                // Top points
                if (PADDING_0 == 0) begin
                    num_blank_pts = 0;
                end
                else begin
                    num_blank_pts = KERNEL_1 * ((PADDING_0 - 1) / DILATION_0 + 1);
                end

                // Side points
                if (PADDING_1 > 0 && PADDING_0 % DILATION_0 == 0) begin
                    if (WINDOW_1 <= PADDING_1) begin
                        num_blank_pts = num_blank_pts + KERNEL_1;
                    end
                    else begin
                        num_blank_pts = num_blank_pts + (PADDING_1 - 1) / DILATION_1 + 1;
                    end
                end
            end
        end
    endfunction

endmodule
