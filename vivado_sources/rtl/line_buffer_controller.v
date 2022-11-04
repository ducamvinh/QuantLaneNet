`timescale 1ns / 1ps

module line_buffer_controller #(
    // Layer parameters
    parameter DATA_WIDTH = 16,
    parameter IN_CHANNEL = 16,
    parameter IN_WIDTH   = 512,
    parameter IN_HEIGHT  = 256,

    // Conv parameters
    parameter KERNEL_0   = 4,
    parameter KERNEL_1   = 4,
    parameter DILATION_0 = 2,
    parameter DILATION_1 = 2,
    parameter PADDING_0  = 2,
    parameter PADDING_1  = 2,
    parameter STRIDE_0   = 5,
    parameter STRIDE_1   = 5
)(
    fifo_rd_en,
    o_valid,
    is_padding,
    out_blank,
    shift,
    fifo_almost_full,
    i_valid,
    pe_ready,
    pe_ack,
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

    output                          fifo_rd_en;
    output reg                      o_valid;
    output reg                      is_padding;
    output reg [BLANK_PTS_SAFE-1:0] out_blank;
    output reg                      shift;
    input                           fifo_almost_full;
    input                           i_valid;
    input                           pe_ready;
    input                           pe_ack;
    input                           clk;
    input                           rst_n;

    genvar i;
    reg get_pixel;

    // Column and row counters
    localparam COL_CNT_WIDTH = $clog2(IN_WIDTH)  + (PADDING_1 > 0 ? 2 : 1);
    localparam ROW_CNT_WIDTH = $clog2(IN_HEIGHT) + (PADDING_0 > 0 ? 2 : 1);

    reg  signed [COL_CNT_WIDTH-1:0] col_cnt;
    wire                            col_cnt_limit = col_cnt == IN_WIDTH + PADDING_1 - 1;
    wire                            col_cnt_en    = get_pixel;

    reg  signed [ROW_CNT_WIDTH-1:0] row_cnt;
    wire                            row_cnt_limit = row_cnt == IN_HEIGHT + PADDING_0 - 1;
    wire                            row_cnt_en    = col_cnt_limit & get_pixel;

    wire                            end_of_frame  = col_cnt_limit & row_cnt_limit;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            col_cnt <= 0;
        end
        else if (col_cnt_en) begin
            if (end_of_frame) begin
                col_cnt <= 0;
            end
            else if (col_cnt_limit) begin
                col_cnt <= -PADDING_1;
            end
            else begin
                col_cnt <= col_cnt + 1;
            end
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            row_cnt <= 0;
        end
        else if (row_cnt_en) begin
            if (row_cnt_limit) begin
                row_cnt <= 0;
            end
            else begin
                row_cnt <= row_cnt + 1;
            end
        end
    end

    // Stride valid
    wire [1:0] stride_valid;

    generate
        for (i = 0; i < 2; i = i + 1) begin : gen0
            localparam STRIDE = i == 0 ? STRIDE_0 : STRIDE_1;

            if (STRIDE > 1) begin : gen1
                localparam PADDING      =  i == 0 ? PADDING_0 : PADDING_1;
                localparam START_IDX    = (i == 0 ? WINDOW_0 : WINDOW_1) - PADDING - 1;
                localparam FRAME_LENGTH =  i == 0 ? IN_HEIGHT : IN_WIDTH;
                localparam RESET_VAL    = (-START_IDX + FRAME_LENGTH * STRIDE) % STRIDE;

                reg  [$clog2(STRIDE)-1:0] stride_cnt;
                wire [$clog2(STRIDE)-1:0] soft_reset;

                wire stride_cnt_en          = i == 0 ? row_cnt_en : col_cnt_en;
                wire stride_cnt_limit_big   = i == 0 ? row_cnt_limit : col_cnt_limit;
                wire stride_cnt_limit_small = stride_cnt == STRIDE - 1;

                if (i == 0) begin : gen2
                    assign soft_reset = RESET_VAL;
                end
                else begin : gen3
                    localparam SOFT_RESET_VAL = (-PADDING - START_IDX + FRAME_LENGTH * STRIDE) % STRIDE;
                    assign soft_reset = row_cnt_limit ? RESET_VAL : SOFT_RESET_VAL;
                end

                always @ (posedge clk or negedge rst_n) begin
                    if (~rst_n) begin
                        stride_cnt <= RESET_VAL;
                    end
                    else if (stride_cnt_en) begin
                        if (stride_cnt_limit_big) begin
                            stride_cnt <= soft_reset;
                        end
                        else if (stride_cnt_limit_small) begin
                            stride_cnt <= 0;
                        end
                        else begin
                            stride_cnt <= stride_cnt + 1;
                        end
                    end
                end

                assign stride_valid[i] = stride_cnt == 0;
            end
            else begin : gen4
                assign stride_valid[i] = 1'b1;
            end
        end
    endgenerate

    // Index valid
    wire idx_valid = row_cnt >= WINDOW_0 - PADDING_0 - 1 && col_cnt >= WINDOW_1 - PADDING_1 - 1 && stride_valid == 2'b11;

    // Index valid previous
    reg idx_valid_prev;

    always @ (posedge clk) begin
        if (get_pixel) begin
            idx_valid_prev <= idx_valid;
        end
    end

    // Index padding
    wire idx_padding;

    generate
        if (PADDING_0 == 0 && PADDING_1 == 0) begin : gen5
            assign idx_padding = 1'b0;
        end
        else if (PADDING_0 == 0 && PADDING_1 > 0) begin : gen6
            assign idx_padding = col_cnt < 0 || col_cnt >= IN_WIDTH;
        end
        else if (PADDING_0 > 0 && PADDING_1 == 0) begin : gen7
            assign idx_padding = row_cnt >= IN_HEIGHT;
        end
        else begin : gen8
            assign idx_padding = row_cnt >= IN_HEIGHT || col_cnt < 0 || col_cnt >= IN_WIDTH;
        end
    endgenerate

    // is_padding
    generate
        if (PADDING_0 > 0 || PADDING_1 > 0) begin : gen9
            always @ (posedge clk) begin
                if (get_pixel) begin
                    is_padding <= idx_padding;
                end
            end
        end
        else begin : gen10
            always @ (*) is_padding <= 1'b0;
        end
    endgenerate

    // out_blank
    generate
        // If there are blanking points
        if (BLANK_PTS > 0) begin : gen11
            reg [BLANK_PTS-1:0] blank;

            for (i = 0; i < BLANK_PTS; i = i + 1) begin : gen12
                localparam ROW_IDX = i / KERNEL_1 * DILATION_0;
                localparam COL_IDX = i % KERNEL_1 * DILATION_1;
                localparam ROW_TARGET = WINDOW_0 - ROW_IDX - 1;
                localparam COL_TARGET = WINDOW_1 - COL_IDX - 1;

                always @ (posedge clk) begin
                    if (get_pixel) begin
                        if (row_cnt > ROW_TARGET) begin
                            blank[i] <= 1'b0;
                        end
                        else if (row_cnt < ROW_TARGET) begin
                            blank[i] <= 1'b1;
                        end
                        else begin
                            blank[i] <= col_cnt < COL_TARGET;
                        end
                    end
                end
            end

            always @ (posedge clk) begin
                if (shift) begin
                    out_blank <= blank;
                end
            end
        end

        // If there's no blanking points
        else begin : gen13
            always @ (*) out_blank <= 0;
        end
    endgenerate

    // shift
    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            shift <= 1'b0;
        end
        else begin
            shift <= get_pixel;
        end
    end

    // o_valid
    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            o_valid <= 1'b0;
        end
        else if (shift | pe_ack) begin
            o_valid <= shift ? idx_valid_prev : 1'b0;
        end
    end

    // fifo_rd_en
    assign fifo_rd_en = get_pixel & ~idx_padding;

    // get_pixel
    wire ready = ~fifo_almost_full & (i_valid | idx_padding);

    always @ (ready or pe_ready or pe_ack or shift or idx_valid_prev or o_valid) begin
        casex ({ready, pe_ready, pe_ack, shift, idx_valid_prev, o_valid})
            6'b0xxxxx : get_pixel <= 1'b0;
            6'b110xxx : get_pixel <= 1'b1;
            6'b1x111x : get_pixel <= 1'b0;
            6'b1x110x : get_pixel <= 1'b1;
            6'b1110xx : get_pixel <= 1'b1;
            6'b10010x : get_pixel <= 1'b1;
            6'b10011x : get_pixel <= 1'b0;
            6'b1000x0 : get_pixel <= 1'b1;
            6'b1000x1 : get_pixel <= 1'b0;
            default   : get_pixel <= 1'b0;
        endcase
    end

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
