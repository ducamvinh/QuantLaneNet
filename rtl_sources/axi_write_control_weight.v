`timescale 1ns / 1ps

module axi_write_control_weight #(
    parameter NUM_WEIGHTS = 76976,
    parameter AXI_BASE_ADDR = (512 * 256 * 3) + (32 * 64 / 4) + 4,
    parameter AXI_ADDR_WIDTH = 32
)(
    output reg [15:0]               weight_wr_data,
    output reg [31:0]               weight_wr_addr,
    output reg                      weight_wr_en,
    input      [31:0]               axi_wr_data,
    input      [AXI_ADDR_WIDTH-1:0] axi_wr_addr,
    input      [3:0]                axi_wr_strobe,
    input                           axi_wr_en,
    input                           clk,
    input                           rst_n
);

    // Write enable
    wire within_range = axi_wr_addr >= AXI_BASE_ADDR && axi_wr_addr - AXI_BASE_ADDR < NUM_WEIGHTS * 2;
    wire wr_en_all = within_range & axi_wr_en;
    wire [1:0] wr_en;

    assign wr_en[0] = wr_en_all && axi_wr_strobe[1:0] == 2'b11;
    assign wr_en[1] = wr_en_all && axi_wr_strobe[3:2] == 2'b11;

    // Control FSM
    reg fsm_state;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            fsm_state <= 1'b0;
        end else if (~fsm_state) begin
            fsm_state <= &wr_en;
        end else begin
            fsm_state <= 1'b0;
        end
    end

    // Data buff and addr buff
    reg [AXI_ADDR_WIDTH-3:0] addr_buff_reg;
    reg [15:0] data_buff_reg;
    wire buff_en = ~fsm_state & wr_en[1];
    wire [AXI_ADDR_WIDTH-1:0] wr_addr = axi_wr_addr - AXI_BASE_ADDR;

    always @ (posedge clk) begin
        if (buff_en) begin
            addr_buff_reg <= wr_addr[AXI_ADDR_WIDTH-1:2];
            data_buff_reg <= axi_wr_data[31:16];
        end
    end

    // Output
    always @ (*) begin
        if (~fsm_state) begin
            weight_wr_data <= axi_wr_data[15:0];
            weight_wr_addr <= {wr_addr[AXI_ADDR_WIDTH-1:2], 1'b0};
            weight_wr_en   <= wr_en[0];
        end else begin
            weight_wr_data <= data_buff_reg;
            weight_wr_addr <= {addr_buff_reg, 1'b1};
            weight_wr_en   <= 1'b1;
        end
    end

endmodule
