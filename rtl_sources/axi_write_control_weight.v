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
    reg [4:0] dumb_optimized_nets;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            dumb_optimized_nets[0] <= 1'b0;
            dumb_optimized_nets[1] <= 1'b0;
            dumb_optimized_nets[2] <= 1'b0;
            dumb_optimized_nets[3] <= 1'b0;
            dumb_optimized_nets[4] <= 1'b0;
        end else begin
            dumb_optimized_nets[0] <= axi_wr_addr >= AXI_BASE_ADDR;
            dumb_optimized_nets[1] <= axi_wr_addr - AXI_BASE_ADDR < NUM_WEIGHTS * 2;
            dumb_optimized_nets[2] <= axi_wr_en;
            dumb_optimized_nets[3] <= axi_wr_strobe[1:0] == 2'b11;
            dumb_optimized_nets[4] <= axi_wr_strobe[3:2] == 2'b11;
        end
    end

    wire within_range = dumb_optimized_nets[0] && dumb_optimized_nets[1];
    wire wr_en_all = within_range && dumb_optimized_nets[2];
    wire [1:0] wr_en;

    assign wr_en[0] = wr_en_all && dumb_optimized_nets[3];
    assign wr_en[1] = wr_en_all && dumb_optimized_nets[4];

    // wire within_range = axi_wr_addr >= AXI_BASE_ADDR && axi_wr_addr - AXI_BASE_ADDR < NUM_WEIGHTS * 2;
    // wire wr_en_all = within_range & axi_wr_en;
    // wire [1:0] wr_en;

    // assign wr_en[0] = wr_en_all && axi_wr_strobe[1:0] == 2'b11;
    // assign wr_en[1] = wr_en_all && axi_wr_strobe[3:2] == 2'b11;

    // Control FSM
    localparam STATE_0 = 0;
    localparam STATE_1 = 1;

    reg [0:0] fsm_state;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            fsm_state <= STATE_0;
        end else if (fsm_state == STATE_0) begin
            fsm_state <= wr_en == 2'b11 ? STATE_1 : STATE_0;
        end else begin
            fsm_state <= STATE_0;
        end
    end

    // Data buff and addr buff
    reg [AXI_ADDR_WIDTH-3:0] addr_buff_reg;
    reg [15:0] data_buff_reg;
    wire buff_en = fsm_state == STATE_0 & wr_en[1];
    // wire [AXI_ADDR_WIDTH-1:0] wr_addr = axi_wr_addr - AXI_BASE_ADDR;

    reg [AXI_ADDR_WIDTH-1:0] wr_addr;
    reg [31:0]               wr_data;

    always @ (posedge clk) begin
        wr_addr <= axi_wr_addr - AXI_BASE_ADDR;
        wr_data <= axi_wr_data;
    end

    always @ (posedge clk) begin
        if (buff_en) begin
            addr_buff_reg <= wr_addr[AXI_ADDR_WIDTH-1:2];
            data_buff_reg <= wr_data[31:16];
            // data_buff_reg <= axi_wr_data[31:16];
        end
    end

    // Output
    reg [15:0] _weight_wr_data;
    reg [31:0] _weight_wr_addr;
    reg        _weight_wr_en;

    always @ (posedge clk) begin
        if (fsm_state == STATE_0 && wr_en[0]) begin
            // _weight_wr_data <= axi_wr_data[15:0];
            _weight_wr_data <= wr_data[15:0];
            _weight_wr_addr <= {wr_addr[AXI_ADDR_WIDTH-1:2], 1'b0};
        end else if (fsm_state == STATE_1) begin
            _weight_wr_data <= data_buff_reg;
            _weight_wr_addr <= {addr_buff_reg, 1'b1};
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            _weight_wr_en <= 1'b0;
        end else begin
            _weight_wr_en <= fsm_state == STATE_0 ? wr_en[0] : 1'b1;
        end
    end

    always @ (posedge clk) begin
        weight_wr_data <= _weight_wr_data;
        weight_wr_addr <= _weight_wr_addr;
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            weight_wr_en <= 1'b0;
        end else begin
            weight_wr_en <= _weight_wr_en;
        end
    end

endmodule
