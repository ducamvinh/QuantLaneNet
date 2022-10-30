`timescale 1ns / 1ps

module fifo_counter #(
    parameter DEPTH = 2**16
)(
    cnt,
    cnt_en,
    rst_n,
    clk
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    output [ADDR_WIDTH:0] cnt;
    input cnt_en, rst_n, clk;

    reg [ADDR_WIDTH-1:0] cnt_low;
    reg cnt_msb;

    assign cnt = {cnt_msb, cnt_low};
    wire at_limit = cnt_low == DEPTH - 1;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            {cnt_msb, cnt_low} <= 0;
        end
        else if (cnt_en) begin
            cnt_msb <= at_limit ^ cnt_msb;
            cnt_low <= at_limit ? 0 : cnt_low + 1;
        end
    end

endmodule
