`timescale 1ns / 1ps

module fifo_64bits_to_fifo_24bits_input (
    output reg [23:0] o_data,
    output reg        o_empty,
    output reg        o_fifo_rd_en,
    input      [63:0] i_data,
    input             i_empty,
    input             i_fifo_rd_en,
    input             clk,
    input             rst_n
);

    genvar i;

    // Input bytes
    wire [7:0] i_data_bytes[0:7];

    generate
        for (i = 0; i < 8; i = i + 1) begin : gen0
            assign i_data_bytes[i] = i_data[(i+1)*8-1:i*8];
        end
    endgenerate

    // Control FSM
    localparam STATE_0 = 0;
    localparam STATE_1 = 1;
    localparam STATE_2 = 2;
    localparam STATE_3 = 3;
    localparam STATE_4 = 4;
    localparam STATE_5 = 5;
    localparam STATE_6 = 6;
    localparam STATE_7 = 7;

    reg [2:0] current_state;
    reg [2:0] next_state;

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
            STATE_0 : next_state <= i_fifo_rd_en ? STATE_1 : STATE_0;
            STATE_1 : next_state <= i_fifo_rd_en ? STATE_2 : STATE_1;
            STATE_2 : next_state <= i_fifo_rd_en ? STATE_3 : STATE_2;
            STATE_3 : next_state <= i_fifo_rd_en ? STATE_4 : STATE_3;
            STATE_4 : next_state <= i_fifo_rd_en ? STATE_5 : STATE_4;
            STATE_5 : next_state <= i_fifo_rd_en ? STATE_6 : STATE_5;
            STATE_6 : next_state <= i_fifo_rd_en ? STATE_7 : STATE_6;
            STATE_7 : next_state <= i_fifo_rd_en ? STATE_0 : STATE_7;
            default : next_state <= STATE_0;
        endcase
    end

    // Buffer regs
    reg [7:0] buff_regs[0:1];

    always @ (posedge clk) begin
        if (i_fifo_rd_en && (current_state == STATE_2 || current_state == STATE_5)) begin
            buff_regs[1] <= i_data_bytes[7];
        end
    end

    always @ (posedge clk) begin
        if (i_fifo_rd_en && current_state == STATE_2) begin
            buff_regs[0] <= i_data_bytes[6];
        end
    end

    // Output
    always @ (*) begin
        case (current_state)
            STATE_0 : begin
                o_data       <= {i_data_bytes[7], i_data_bytes[6], i_data_bytes[5]};
                o_empty      <= i_empty;
                o_fifo_rd_en <= i_fifo_rd_en;
            end

            STATE_1 : begin
                o_data       <= {i_data_bytes[2], i_data_bytes[1], i_data_bytes[0]};
                o_empty      <= 1'b0;
                o_fifo_rd_en <= 1'b0;
            end

            STATE_2 : begin
                o_data       <= {i_data_bytes[5], i_data_bytes[4], i_data_bytes[3]};
                o_empty      <= i_empty;
                o_fifo_rd_en <= i_fifo_rd_en;
            end

            STATE_3 : begin
                o_data       <= {i_data_bytes[0], buff_regs[1], buff_regs[0]};
                o_empty      <= 1'b0;
                o_fifo_rd_en <= 1'b0;
            end

            STATE_4 : begin
                o_data       <= {i_data_bytes[3], i_data_bytes[2], i_data_bytes[1]};
                o_empty      <= 1'b0;
                o_fifo_rd_en <= 1'b0;
            end

            STATE_5 : begin
                o_data       <= {i_data_bytes[6], i_data_bytes[5], i_data_bytes[4]};
                o_empty      <= i_empty;
                o_fifo_rd_en <= i_fifo_rd_en;
            end

            STATE_6 : begin
                o_data       <= {i_data_bytes[1], i_data_bytes[0], buff_regs[1]};
                o_empty      <= 1'b0;
                o_fifo_rd_en <= 1'b0;
            end

            STATE_7 : begin
                o_data       <= {i_data_bytes[4], i_data_bytes[3], i_data_bytes[2]};
                o_empty      <= 1'b0;
                o_fifo_rd_en <= 1'b0;
            end

            default : begin
                o_data       <= {24{1'bx}};
                o_empty      <= 1'b1;
                o_fifo_rd_en <= 1'b0;
            end
        endcase
    end

endmodule
