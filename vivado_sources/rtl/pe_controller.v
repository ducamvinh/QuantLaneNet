`timescale 1ns / 1ps

module pe_controller (
    output cnt_en,
    output pe_ready,
    output pe_ack,
    input  cnt_limit,
    input  i_valid,
    input  clk,
    input  rst_n
);

    // Control FSM
    localparam IDLE = 0;
    localparam BUSY = 1;

    reg [0:0] current_state;
    reg [0:0] next_state;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            current_state <= IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always @ (current_state or i_valid or cnt_limit) begin
        case (current_state)
            IDLE    : next_state <= i_valid ? BUSY : IDLE;
            BUSY    : next_state <= cnt_limit ? IDLE : BUSY;
            default : next_state <= IDLE;
        endcase
    end

    assign pe_ready = (current_state == BUSY && cnt_limit) || current_state == IDLE;
    assign pe_ack   = i_valid && current_state == IDLE;
    assign cnt_en   = pe_ack || current_state == BUSY;

endmodule
