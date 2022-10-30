`timescale 1ns / 1ps

module fifo_64bits_to_mem_16bits_weight #(
    parameter NUM_WEIGHTS = 76323
)(
    output reg [15:0] weight_wr_data,
    output     [31:0] weight_wr_addr,
    output            weight_wr_en,
    output            fifo_rd_en,
    input      [63:0] fifo_rd_data,
    input             fifo_empty,
    input             clk,
    input             rst_n
);

    // Control FSM
    localparam IDLE    = 0;
    localparam STATE_0 = 1;
    localparam STATE_1 = 2;
    localparam STATE_2 = 3;
    localparam STATE_3 = 4;

    reg [2:0] current_state;
    reg [2:0] next_state;

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
            IDLE    : next_state <= fifo_empty ? IDLE : STATE_0;
            STATE_0 : next_state <= STATE_1;
            STATE_1 : next_state <= STATE_2;
            STATE_2 : next_state <= STATE_3;
            STATE_3 : next_state <= fifo_empty ? IDLE : STATE_0;
            default : next_state <= IDLE;
        endcase
    end

    // Address counter
    localparam COUNTER_LIMIT = (NUM_WEIGHTS + 4) / 4 * 4;
    localparam COUNTER_WIDTH = $clog2(COUNTER_LIMIT);

    reg [COUNTER_WIDTH-1:0] addr_cnt;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            addr_cnt <= 0;
        end
        else if (current_state != IDLE) begin
            addr_cnt <= addr_cnt == COUNTER_LIMIT - 1 ? 0 : addr_cnt + 1;
        end
    end

    // Output
    always @ (*) begin
        case (current_state)
            STATE_0 : weight_wr_data <= fifo_rd_data[15:0];
            STATE_1 : weight_wr_data <= fifo_rd_data[31:16];
            STATE_2 : weight_wr_data <= fifo_rd_data[47:32];
            STATE_3 : weight_wr_data <= fifo_rd_data[63:48];
            default : weight_wr_data <= {16{1'bx}};
        endcase
    end

    assign weight_wr_addr = {{32-COUNTER_WIDTH{1'b0}}, addr_cnt};
    assign weight_wr_en = current_state != IDLE;
    assign fifo_rd_en = (current_state == IDLE || current_state == STATE_3) && ~fifo_empty;

endmodule
