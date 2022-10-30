`timescale 1ns/1ps

module activity_led_blink #(
    parameter COUNTER_WIDTH = 25
)(
    output led_out,
    input  trigger,
    input  clk,
    input  rst_n
);

    localparam [COUNTER_WIDTH-1:0] RESET_VALUE = {1'b0, {COUNTER_WIDTH-1{1'b1}}};

    // Counter register with an extra bit to blink twice
    reg [COUNTER_WIDTH-1:0] counter;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            counter <= RESET_VALUE;
        end
        else if (counter != RESET_VALUE || trigger) begin
            counter <= counter + 1;
        end
        else begin
            counter <= counter;
        end
    end

    assign led_out = counter[COUNTER_WIDTH-1];

endmodule
