`timescale 1ns/1ps

module activity_led_blink #(
    parameter COUNTER_WIDTH = 25
)(
    output led_out,
    input  trigger,
    input  clk,
    input  rst_n
);

    reg [COUNTER_WIDTH+1:0] counter;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            counter <= 0;
        end else if (counter != 0 || trigger) begin
            counter <= counter + 1;
        end else begin
            counter <= counter;
        end
    end

    assign led_out = counter[COUNTER_WIDTH-1];

endmodule
