`timescale 1ns / 1ps

module axi_write_control_fifo #(
    parameter IN_WIDTH = 512,
    parameter IN_HEIGHT = 256,
    parameter AXI_BASE_ADDR = 0,
    parameter AXI_ADDR_WIDTH = 32
)(
    output reg [8*3-1:0]            fifo_wr_data,
    output reg                      fifo_wr_en,
    output                          first_pixel,
    input      [31:0]               axi_wr_data,
    input      [AXI_ADDR_WIDTH-1:0] axi_wr_addr,
    input      [3:0]                axi_wr_strobe,
    input                           axi_wr_en,
    input                           clk,
    input                           rst_n
);

    genvar i;

    // Break wr_data word into bytes
    reg [7:0] axi_wr_data_bytes[0:3];

    generate
        for (i = 0; i < 4; i = i + 1) begin : gen0
            always @ (posedge clk) begin
                if (axi_wr_en && axi_wr_strobe[i]) begin
                    axi_wr_data_bytes[i] <= axi_wr_data[(i+1)*8-1:i*8];
                end
            end
        end
    endgenerate

    // Write enable
    // wire within_range = axi_wr_addr >= AXI_BASE_ADDR && axi_wr_addr - AXI_BASE_ADDR < IN_HEIGHT * IN_WIDTH * 3;
    // wire wr_en = within_range & axi_wr_en & |axi_wr_strobe;

    reg [0:0] dumb_optimized_nets[0:3];
    
    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            dumb_optimized_nets[0] <= 1'b0;
            dumb_optimized_nets[1] <= 1'b0;
            dumb_optimized_nets[2] <= 1'b0;
            dumb_optimized_nets[3] <= 1'b0;
        end else begin
            dumb_optimized_nets[0] <= axi_wr_addr >= AXI_BASE_ADDR;
            dumb_optimized_nets[1] <= axi_wr_addr - AXI_BASE_ADDR < IN_HEIGHT * IN_WIDTH * 3;
            dumb_optimized_nets[2] <= axi_wr_en;
            dumb_optimized_nets[3] <= |axi_wr_strobe;
        end
    end

    wire within_range = dumb_optimized_nets[0] && dumb_optimized_nets[1];
    wire wr_en = within_range && dumb_optimized_nets[2] && dumb_optimized_nets[3];

    // Pixel counter
    reg [$clog2(IN_WIDTH*IN_HEIGHT)-1:0] pixel_cnt;
    wire pixel_cnt_limit = pixel_cnt == IN_WIDTH * IN_HEIGHT - 1;
    wire pixel_cnt_en;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            pixel_cnt <= 0;
        end else if (pixel_cnt_en) begin
            pixel_cnt <= pixel_cnt_limit ? 0 : pixel_cnt + 1;
        end
    end

    // Buffer regs
    reg [7:0] buff_regs[0:2];
    reg       buff_regs_en[0:2];

    generate
        for (i = 0; i < 3; i = i + 1) begin : gen1
            always @ (posedge clk) begin
                if (buff_regs_en[i]) begin
                    buff_regs[i] <= axi_wr_data_bytes[i+1];
                end
            end
        end
    endgenerate

    // Control FSM
    localparam [1:0] STATE_0 = 2'b00;  // |x|x|x|o| ---- |x|
    localparam [1:0] STATE_1 = 2'b01;  // |x|x|o|o| ---- |x|x| 
    localparam [1:0] STATE_2 = 2'b10;  // |x|o|o|o| ---- |x|x|x|
    localparam [1:0] STATE_3 = 2'b11;  // Write all buffers

    reg [1:0] current_state;
    reg [1:0] next_state;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            current_state <= STATE_0;
        end else begin
            current_state <= next_state;
        end
    end

    always @ (*) begin
        case (current_state)
            STATE_0: next_state <= wr_en ? (pixel_cnt_limit ? STATE_0 : STATE_1) : STATE_0;
            STATE_1: next_state <= wr_en ? (pixel_cnt_limit ? STATE_0 : STATE_2) : STATE_1;
            STATE_2: next_state <= wr_en ? (pixel_cnt_limit ? STATE_0 : STATE_3) : STATE_2;
            STATE_3: next_state <= STATE_0;
        endcase
    end

    // Output
    reg [8*3-1:0] _fifo_wr_data;
    reg           _fifo_wr_en;

    assign pixel_cnt_en = _fifo_wr_en;

    always @ (*) begin
        case (current_state)
            STATE_0: begin
                _fifo_wr_data <= {axi_wr_data_bytes[2], axi_wr_data_bytes[1], axi_wr_data_bytes[0]};
                _fifo_wr_en   <= wr_en;

                buff_regs_en[0] <= 1'b0;
                buff_regs_en[1] <= 1'b0;
                buff_regs_en[2] <= wr_en;
            end

            STATE_1: begin
                _fifo_wr_data <= {axi_wr_data_bytes[1], axi_wr_data_bytes[0], buff_regs[2]};
                _fifo_wr_en   <= wr_en;

                buff_regs_en[0] <= 1'b0;
                buff_regs_en[1] <= wr_en;
                buff_regs_en[2] <= wr_en;
            end

            STATE_2: begin
                _fifo_wr_data <= {axi_wr_data_bytes[0], buff_regs[2], buff_regs[1]};
                _fifo_wr_en   <= wr_en;

                buff_regs_en[0] <= wr_en;
                buff_regs_en[1] <= wr_en;
                buff_regs_en[2] <= wr_en;
            end

            STATE_3: begin
                _fifo_wr_data <= {buff_regs[2], buff_regs[1], buff_regs[0]};
                _fifo_wr_en   <= 1'b1;

                buff_regs_en[0] <= 1'b0;
                buff_regs_en[1] <= 1'b0;
                buff_regs_en[2] <= 1'b0;
            end
        endcase
    end

    always @ (posedge clk) begin
        if (_fifo_wr_en) begin
            fifo_wr_data <= _fifo_wr_data;
        end
    end

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            fifo_wr_en <= 1'b0;
        end else begin
            fifo_wr_en <= _fifo_wr_en;
        end
    end

    // first pixel
    assign first_pixel = pixel_cnt == 0 && wr_en;

endmodule
