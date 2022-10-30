`timescale 1ns / 1ps

module post_process #(
    parameter OUT_WIDTH  = 64,
    parameter OUT_HEIGHT = 32,
    parameter NUM_LANES  = 4,
    parameter DATA_WIDTH = 16,
    parameter FRAC_BITS  = 8
)(
    output     [7:0]                              bram_wr_data,
    output     [$clog2(OUT_WIDTH*OUT_HEIGHT)-1:0] bram_wr_addr,
    output                                        bram_wr_en,
    output                                        fifo_rd_en_cls,
    output                                        fifo_rd_en_vertical,
    output reg                                    o_valid,
    input      [DATA_WIDTH*NUM_LANES-1:0]         i_data_cls,
    input      [DATA_WIDTH*NUM_LANES-1:0]         i_data_vertical,
    input                                         i_valid_cls,
    input                                         i_valid_vertical,
    input                                         first_pixel,
    input                                         clk,
    input                                         rst_n
);

    localparam                         INT_BITS        = DATA_WIDTH - FRAC_BITS;
    localparam signed [DATA_WIDTH-1:0] ZERO_POINT_FIVE = {{INT_BITS{1'b0}}, 1'b1, {FRAC_BITS-1{1'b0}}};

    genvar i;

    // Column counter
    reg  [$clog2(OUT_WIDTH)-1:0] col_cnt_1;
    wire                         col_cnt_1_limit = col_cnt_1 == OUT_WIDTH - 1;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            col_cnt_1 <= 0;
        end
        else if (fifo_rd_en_cls) begin
            col_cnt_1 <= col_cnt_1_limit ? 0 : col_cnt_1 + 1;
        end
    end

    // Control FSM
    localparam [1:0] IDLE                   = 2'd0;
    localparam [1:0] GOT_VERT_RECEIVING_CLS = 2'd1;
    localparam [1:0] NO_VERT_RECEIVING_CLS  = 2'd2;
    localparam [1:0] NO_VERT_FINISHED_CLS   = 2'd3;

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
            IDLE : begin
                if (i_valid_vertical) begin
                    next_state <= GOT_VERT_RECEIVING_CLS;
                end
                else if (i_valid_cls) begin
                    next_state <= NO_VERT_RECEIVING_CLS;
                end
                else begin
                    next_state <= IDLE;
                end
            end

            GOT_VERT_RECEIVING_CLS : begin
                if (i_valid_cls && col_cnt_1_limit) begin
                    next_state <= IDLE;
                end
                else begin
                    next_state <= GOT_VERT_RECEIVING_CLS;
                end
            end

            NO_VERT_RECEIVING_CLS : begin
                case ({i_valid_cls & col_cnt_1_limit, i_valid_vertical})
                    2'b00: next_state <= NO_VERT_RECEIVING_CLS;
                    2'b01: next_state <= GOT_VERT_RECEIVING_CLS;
                    2'b10: next_state <= NO_VERT_FINISHED_CLS;
                    2'b11: next_state <= IDLE;
                endcase
            end

            NO_VERT_FINISHED_CLS : begin
                if (i_valid_vertical) begin
                    next_state <= IDLE;
                end
                else begin
                    next_state <= NO_VERT_FINISHED_CLS;
                end
            end

            default : next_state <= IDLE;
        endcase
    end

    // fifo_rd_en logic
    assign fifo_rd_en_cls      = i_valid_cls      && current_state != NO_VERT_FINISHED_CLS;
    assign fifo_rd_en_vertical = i_valid_vertical && current_state != GOT_VERT_RECEIVING_CLS;

    // Previous counter and fifo_rd_en
    reg [$clog2(OUT_WIDTH)-1:0] col_cnt_1_prev;
    reg                         fifo_rd_en_cls_prev;
    reg                         fifo_rd_en_vertical_prev;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            fifo_rd_en_cls_prev <= 1'b0;
            fifo_rd_en_vertical_prev <= 1'b0;
        end
        else begin
            fifo_rd_en_cls_prev <= fifo_rd_en_cls;
            fifo_rd_en_vertical_prev <= fifo_rd_en_vertical;
        end
    end

    always @ (posedge clk) begin
        if (fifo_rd_en_cls) begin
            col_cnt_1_prev <= col_cnt_1;
        end
    end

    // Data latch
    reg  signed [DATA_WIDTH-1:0]         max_cls[0:NUM_LANES-1];
    reg         [$clog2(OUT_WIDTH)-1:0]  max_cls_idx[0:NUM_LANES-1];
    reg         [NUM_LANES-1:0]          vertical;
    wire        [NUM_LANES-1:0]          vertical_;

    generate
        for (i = 0; i < NUM_LANES; i = i + 1) begin : gen0
            wire signed [DATA_WIDTH-1:0] cls_curr      = i_data_cls      [(i+1)*DATA_WIDTH-1:i*DATA_WIDTH];
            wire signed [DATA_WIDTH-1:0] vertical_curr = i_data_vertical [(i+1)*DATA_WIDTH-1:i*DATA_WIDTH];

            assign vertical_[i] = vertical_curr >= ZERO_POINT_FIVE;

            always @ (posedge clk) begin
                if (fifo_rd_en_cls_prev && (col_cnt_1_prev == 0 || cls_curr > max_cls[i])) begin
                    max_cls[i] <= cls_curr;
                    max_cls_idx[i] <= col_cnt_1_prev;
                end

                if (fifo_rd_en_vertical_prev) begin
                    vertical[i] <= vertical_[i];
                end
            end
        end
    endgenerate

    // Write stage
    reg write_stage_start;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            write_stage_start <= 1'b0;
        end
        else begin
            case (current_state)
                GOT_VERT_RECEIVING_CLS : write_stage_start <= i_valid_cls & col_cnt_1_limit;
                NO_VERT_RECEIVING_CLS  : write_stage_start <= i_valid_cls & col_cnt_1_limit & i_valid_vertical;
                NO_VERT_FINISHED_CLS   : write_stage_start <= i_valid_vertical;
                default                : write_stage_start <= 1'b0;
            endcase
        end
    end

    // Column counter
    reg [$clog2(OUT_WIDTH)-1:0] col_cnt_2;
    wire col_cnt_2_limit = col_cnt_2 == OUT_WIDTH - 1;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            col_cnt_2 <= 0;
        end
        else begin
            if (col_cnt_2 == 0) begin
                col_cnt_2 <= {{$clog2(OUT_WIDTH)-1{1'b0}}, write_stage_start};
            end
            else begin
                col_cnt_2 <= col_cnt_2_limit ? 0 : col_cnt_2 + 1;
            end
        end
    end

    // Row counter
    reg [$clog2(OUT_HEIGHT)-1:0] row_cnt_2;
    wire row_cnt_2_limit = row_cnt_2 == OUT_HEIGHT - 1;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            row_cnt_2 <= 0;
        end
        else if (col_cnt_2_limit) begin
            row_cnt_2 <= row_cnt_2_limit ? 0 : row_cnt_2 + 1;
        end
    end

    // Fix a dumb bug I missed
    reg f_ing_bug_fix;

    always @ (posedge clk) begin
        f_ing_bug_fix <= (current_state == NO_VERT_FINISHED_CLS) && i_valid_vertical;
    end

    generate
        for (i = 0; i < NUM_LANES; i = i + 1) begin : gen1
            // Write stage data latch
            reg [$clog2(OUT_WIDTH)-1:0] write_stage_max_cls_idx;
            reg write_stage_vertical;

            always @ (posedge clk) begin
                if (write_stage_start) begin
                    write_stage_max_cls_idx <= max_cls_idx[i];
                    write_stage_vertical <= f_ing_bug_fix ? vertical_[i] : vertical[i];
                end
            end

            // One hot input select
            wire [$clog2(OUT_WIDTH)-1:0] one_hot_max_cls_idx = write_stage_start ? max_cls_idx[i] : write_stage_max_cls_idx;
            wire                         one_hot_vertical    = write_stage_start ? (f_ing_bug_fix ? vertical_[i] : vertical[i]) : write_stage_vertical;

            // bram_wr_data
            assign bram_wr_data[i] = one_hot_vertical && col_cnt_2 == one_hot_max_cls_idx;
        end
    endgenerate

    assign bram_wr_data[7:NUM_LANES] = {8-NUM_LANES{1'b0}};
    assign bram_wr_addr              = row_cnt_2 * OUT_WIDTH + col_cnt_2;
    assign bram_wr_en                = write_stage_start || col_cnt_2 != 0;

    // o_valid
    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            o_valid <= 1'b0;
        end
        else begin
            if (~o_valid) begin
                o_valid <= col_cnt_2_limit & row_cnt_2_limit;
            end
            else begin
                o_valid <= ~first_pixel;
            end
        end
    end

endmodule
