`timescale 1ns/1ps

module activity_led_blink #(
    parameter COUNTER_WIDTH = 25
)(
    output led_out,
    input  trigger,
    input  clk,
    input  rst_n
);

    reg [COUNTER_WIDTH-1:0] delay_counter;
    reg [1:0] blink_counter;

    wire inactivity = delay_counter == 0 && blink_counter == 0 && trigger == 0;
    wire delay_counter_at_limit = delay_counter == (2**COUNTER_WIDTH - 1);

    assign led_out = delay_counter[COUNTER_WIDTH-1];

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            delay_counter <= 0;
        end else if (~inactivity) begin
            delay_counter <= delay_counter + 1;
        end else begin
            delay_counter <= delay_counter;
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            blink_counter <= 0;
        end else if (delay_counter_at_limit) begin
            blink_counter <= blink_counter + 1;
        end
    end
    
endmodule
