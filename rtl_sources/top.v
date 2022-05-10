`timescale 1ns / 1ps

module top #(
    parameter AXI_ADDR_WIDTH = $clog2(547922)
)(
    output                          o_valid,
    output                          busy,
    output reg [31:0]               axi_rd_data,
    input      [31:0]               axi_wr_data,
    input      [AXI_ADDR_WIDTH-1:0] axi_wr_addr,
    input      [AXI_ADDR_WIDTH-1:0] axi_rd_addr,
    input                           axi_wr_en,
    input                           axi_rd_en,
    input      [3:0]                axi_wr_strobe,
    input                           clk,
    input                           rst_n
);

    // IP params
    localparam IN_WIDTH = 512;
    localparam IN_HEIGHT = 256;
    localparam NUM_LANES = 4;
    localparam NUM_WEIGHTS = 76323;
    localparam OUT_WIDTH = IN_WIDTH / 8;
    localparam OUT_HEIGHT = IN_HEIGHT / 8;

    // AXI addr map
    localparam OFFSET_INPUT = 0;                                        // 0x0000_0000 ### 0
    localparam OFFSET_OUTPUT = IN_WIDTH * IN_HEIGHT * 3;                // 0x0006_0000 ### 393216
    localparam OFFSET_OVALID = OFFSET_OUTPUT + OUT_WIDTH * OUT_HEIGHT;  // 0x0006_0800 ### 395264
    localparam OFFSET_BUSY = OFFSET_OVALID + 4;                         // 0x0006_0804 ### 395268
    localparam OFFSET_RESET = OFFSET_BUSY + 4;                          // 0x0006_0808 ### 395272
    localparam OFFSET_WEIGHT = OFFSET_RESET + 4;                        // 0x0006_080C ### 395276
                                                             // HIGH_ADDR: 0x0008_5C52 ### 547922
                                                             // RANGE:     535.08K
    localparam OFFSET_CLOCK_CNT = 'h0009_0000;

    // Soft reset
    reg [3:0] soft_reset_count;
    wire internal_reset_n = soft_reset_count == 0 && rst_n;

    always @ (posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            soft_reset_count <= 0;
        end else if (soft_reset_count == 0) begin
            if (axi_wr_en && axi_wr_strobe[0] && axi_wr_data[0] && axi_wr_addr == OFFSET_RESET) begin
                soft_reset_count <= soft_reset_count + 1;
            end else begin
                soft_reset_count <= soft_reset_count;
            end
        end else begin
            soft_reset_count <= soft_reset_count + 1;
        end
    end

    // Weight write control
    wire [15:0] weight_wr_data;
    wire [31:0] weight_wr_addr;
    wire        weight_wr_en;

    axi_write_control_weight #(
        .NUM_WEIGHTS    (NUM_WEIGHTS),
        .AXI_BASE_ADDR  (OFFSET_WEIGHT),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH)
    ) u_weight_wr (
        .weight_wr_data (weight_wr_data),
        .weight_wr_addr (weight_wr_addr), 
        .weight_wr_en   (weight_wr_en),
        .axi_wr_data    (axi_wr_data),
        .axi_wr_addr    (axi_wr_addr),
        .axi_wr_strobe  (axi_wr_strobe),
        .axi_wr_en      (axi_wr_en),
        .clk            (clk), 
        .rst_n          (internal_reset_n)
    ); 

    // Input fifo write control
    wire [8*3-1:0] fifo_wr_data_;
    wire           fifo_wr_en;
    wire           first_pixel;

    axi_write_control_fifo #(
        .IN_WIDTH       (IN_WIDTH),
        .IN_HEIGHT      (IN_HEIGHT),
        .AXI_BASE_ADDR  (OFFSET_INPUT),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH)
    ) u_fifo_wr (
        .fifo_wr_data  (fifo_wr_data_),
        .fifo_wr_en    (fifo_wr_en),
        .first_pixel   (first_pixel),
        .axi_wr_data   (axi_wr_data),
        .axi_wr_addr   (axi_wr_addr),
        .axi_wr_strobe (axi_wr_strobe),
        .axi_wr_en     (axi_wr_en),
        .clk           (clk),
        .rst_n         (internal_reset_n)
    );

    // Input FIFO
    wire [7*3-1:0] fifo_wr_data;
    wire [7*3-1:0] fifo_rd_data;
    wire           fifo_empty;
    wire           fifo_rd_en;

    assign fifo_wr_data = {
        fifo_wr_data_[3*8-1:2*8+1],
        fifo_wr_data_[2*8-1:1*8+1],
        fifo_wr_data_[1*8-1:0*8+1]
    };

    fifo_single_read #(
        .DATA_WIDTH        (7 * 3),
        .DEPTH             (128),
        .ALMOST_FULL_THRES (10)
    ) u_fifo (
        .rd_data     (fifo_rd_data),
        .empty       (fifo_empty),
        .full        (),
        .almost_full (),
        .wr_data     (fifo_wr_data),
        .wr_en       (fifo_wr_en), 
        .rd_en       (fifo_rd_en),
        .rst_n       (internal_reset_n), 
        .clk         (clk)
    );

    // Model
    wire [16*NUM_LANES-1:0] model_o_data_cls;
    wire [16*NUM_LANES-1:0] model_o_data_vertical;
    wire [23:0]             model_i_data;
    wire                    model_o_valid_cls;
    wire                    model_o_valid_vertical;
    wire                    cls_fifo_almost_full;
    wire                    vertical_fifo_almost_full;
    
    assign model_i_data = {
        {1'b0, fifo_rd_data[3*7-1:2*7]},
        {1'b0, fifo_rd_data[2*7-1:1*7]},
        {1'b0, fifo_rd_data[1*7-1:0*7]}
    };

    model u_model (
        .o_data_cls           (model_o_data_cls),
	    .o_data_vertical      (model_o_data_vertical),
	    .o_valid_cls          (model_o_valid_cls),
	    .o_valid_vertical     (model_o_valid_vertical), 
	    .fifo_rd_en           (fifo_rd_en),
	    .i_data               (model_i_data),
	    .i_valid              (~fifo_empty),
	    .cls_almost_full      (cls_fifo_almost_full),
	    .vertical_almost_full (vertical_fifo_almost_full),
	    .weight_wr_data       (weight_wr_data),
	    .weight_wr_addr       (weight_wr_addr),
	    .weight_wr_en         (weight_wr_en),
	    .clk                  (clk),
	    .rst_n                (internal_reset_n)
    );

    // Output FIFOs
    wire [16*NUM_LANES-1:0] cls_fifo_rd_data;
    wire                    cls_fifo_empty;
    wire                    cls_fifo_rd_en;

    fifo_single_read #(
        .DATA_WIDTH        (16 * NUM_LANES),
        .DEPTH             (OUT_WIDTH * 1),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_cls (
        .rd_data     (cls_fifo_rd_data),
        .empty       (cls_fifo_empty),
        .full        (),
        .almost_full (cls_fifo_almost_full),
        .wr_data     (model_o_data_cls),
        .wr_en       (model_o_valid_cls),
        .rd_en       (cls_fifo_rd_en),
        .rst_n       (internal_reset_n),
        .clk         (clk)
    );

    wire [16*NUM_LANES-1:0] vertical_fifo_rd_data;
    wire                    vertical_fifo_empty;
    wire                    vertical_fifo_rd_en;

    fifo_single_read #(
        .DATA_WIDTH        (16 * NUM_LANES),
        .DEPTH             (OUT_HEIGHT),
        .ALMOST_FULL_THRES (10)
    ) u_fifo_vertical (
        .rd_data     (vertical_fifo_rd_data),
        .empty       (vertical_fifo_empty),
        .full        (),
        .almost_full (vertical_fifo_almost_full),
        .wr_data     (model_o_data_vertical),
        .wr_en       (model_o_valid_vertical),
        .rd_en       (vertical_fifo_rd_en),
        .rst_n       (internal_reset_n),
        .clk         (clk)
    );

    // Post process
    wire [7:0]                              bram_wr_data;
    wire [$clog2(OUT_WIDTH*OUT_HEIGHT)-1:0] bram_wr_addr;
    wire                                    bram_wr_en;

    post_process #(
        .OUT_WIDTH  (OUT_WIDTH),
        .OUT_HEIGHT (OUT_HEIGHT),
        .NUM_LANES  (NUM_LANES),
        .DATA_WIDTH (16),
        .FRAC_BITS  (8)
    ) u_post (
        .bram_wr_data        (bram_wr_data), 
        .bram_wr_addr        (bram_wr_addr),
        .bram_wr_en          (bram_wr_en),
        .fifo_rd_en_cls      (cls_fifo_rd_en),
        .fifo_rd_en_vertical (vertical_fifo_rd_en),
        .o_valid             (o_valid),
        .i_data_cls          (cls_fifo_rd_data),
        .i_data_vertical     (vertical_fifo_rd_data),
        .i_valid_cls         (~cls_fifo_empty),
        .i_valid_vertical    (~vertical_fifo_empty),
        .first_pixel         (first_pixel), 
        .clk                 (clk),
        .rst_n               (internal_reset_n)
    );

    // Post process BRAM
    wire [8*4-1:0] bram_rd_data;
    wire [AXI_ADDR_WIDTH-1:0] bram_rd_addr_ = axi_rd_addr - OFFSET_OUTPUT;
    wire [$clog2(OUT_WIDTH*OUT_HEIGHT)-1:0] bram_rd_addr = bram_rd_addr_[$clog2(OUT_WIDTH*OUT_HEIGHT)+1:2];
    wire bram_within_range = axi_rd_addr >= OFFSET_OUTPUT && axi_rd_addr - OFFSET_OUTPUT < OUT_WIDTH * OUT_HEIGHT;

    reg [3:0] bram_byte_en;

    always @ (*) begin
        case (bram_wr_addr[1:0])
            2'b00: bram_byte_en <= {1'b0, 1'b0, 1'b0, bram_wr_en};
            2'b01: bram_byte_en <= {1'b0, 1'b0, bram_wr_en, 1'b0};
            2'b10: bram_byte_en <= {1'b0, bram_wr_en, 1'b0, 1'b0};
            2'b11: bram_byte_en <= {bram_wr_en, 1'b0, 1'b0, 1'b0};
        endcase
    end

    block_ram_multi_word #(
        .DATA_WIDTH      (8),
        .DEPTH           (OUT_WIDTH * OUT_HEIGHT / 4),
        .NUM_WORDS       (4),
        .RAM_STYLE       ("auto"),
        .OUTPUT_REGISTER ("false")
    ) u_bram (
        .rd_data (bram_rd_data),
        .wr_data (bram_wr_data),
        .rd_addr (bram_rd_addr),
        .wr_addr (bram_wr_addr[$clog2(OUT_WIDTH*OUT_HEIGHT)-1:2]),
        .wr_en   (bram_byte_en),
        .rd_en   (axi_rd_en & bram_within_range),
        .clk     (clk)
    );

    // Clock counter
    localparam CLOCK_CNT_IDLE = 0;
    localparam CLOCK_CNT_BUSY = 1;

    reg [0:0] clock_cnt_fsm;

    always @ (posedge clk or negedge internal_reset_n) begin
        if (~internal_reset_n) begin
            clock_cnt_fsm <= CLOCK_CNT_IDLE;
        end else begin
            case (clock_cnt_fsm)
                CLOCK_CNT_IDLE : clock_cnt_fsm <= first_pixel ? CLOCK_CNT_BUSY : CLOCK_CNT_IDLE;
                CLOCK_CNT_BUSY : clock_cnt_fsm <= o_valid ? CLOCK_CNT_IDLE : CLOCK_CNT_BUSY;
            endcase
        end
    end

    reg [31:0] clock_cnt;

    always @ (posedge clk) begin
        if (clock_cnt_fsm == CLOCK_CNT_IDLE) begin
            clock_cnt <= first_pixel ? 0 : clock_cnt;
        end else if (clock_cnt_fsm == CLOCK_CNT_BUSY) begin
            clock_cnt <= o_valid ? clock_cnt : clock_cnt + 1;
        end
    end

    // axi_rd_data
    always @ (*) begin
        case (axi_rd_addr)
            OFFSET_OVALID    : axi_rd_data <= {{31{1'b0}}, o_valid};
            OFFSET_BUSY      : axi_rd_data <= {{31{1'b0}}, busy};
            OFFSET_CLOCK_CNT : axi_rd_data <= clock_cnt;
            default          : axi_rd_data <= bram_within_range ? bram_rd_data : {32{1'b0}};
        endcase
    end

    // busy
    reg internal_busy;
    assign busy = internal_busy & ~o_valid;

    always @ (posedge clk or negedge internal_reset_n) begin
        if (~internal_reset_n) begin
            internal_busy <= 1'b0;
        end else if (internal_busy == 1'b0 && first_pixel == 1'b1) begin
            internal_busy <= 1'b1;
        end else if (internal_busy == 1'b1 && o_valid == 1'b1) begin
            internal_busy <= 1'b0;
        end
    end

endmodule
