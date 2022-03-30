
`timescale 1 ns / 1 ps

	module LaneDetectionCNN_AXI_IP #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S00_AXI
		parameter integer C_S00_AXI_DATA_WIDTH	= 32,
		parameter integer C_S00_AXI_ADDR_WIDTH	= $clog2(549228)
	)
	(
		// Users to add ports here
		output wire busy,
		output wire o_valid,
		output wire wr_led,
		output wire rd_led,
		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Slave Bus Interface S00_AXI
		input wire  s00_axi_aclk,
		input wire  s00_axi_aresetn,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
		input wire [2 : 0] s00_axi_awprot,
		input wire  s00_axi_awvalid,
		output wire  s00_axi_awready,
		input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
		input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
		input wire  s00_axi_wvalid,
		output wire  s00_axi_wready,
		output wire [1 : 0] s00_axi_bresp,
		output wire  s00_axi_bvalid,
		input wire  s00_axi_bready,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
		input wire [2 : 0] s00_axi_arprot,
		input wire  s00_axi_arvalid,
		output wire  s00_axi_arready,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
		output wire [1 : 0] s00_axi_rresp,
		output wire  s00_axi_rvalid,
		input wire  s00_axi_rready
	);
// Instantiation of Axi Bus Interface S00_AXI
	wire [C_S00_AXI_ADDR_WIDTH-1:0] s00_axi_awaddr_latch;
	wire [C_S00_AXI_ADDR_WIDTH-1:0] s00_axi_araddr_latch;

	wire s00_axi_wren;
	wire s00_axi_rden;

	LaneDetectionCNN_S00_AXI # ( 
		.C_S_AXI_DATA_WIDTH (C_S00_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH (C_S00_AXI_ADDR_WIDTH)
	) LaneDetectionCNN_S00_AXI_inst (
		// User defined ports
		.S_AXI_AWADDR_LATCH (s00_axi_awaddr_latch),
		.S_AXI_ARADDR_LATCH (s00_axi_araddr_latch),
		.S_AXI_WREN         (s00_axi_wren),
		.S_AXI_RDEN         (s00_axi_rden),
		// User defined ports end

		.S_AXI_ACLK    (s00_axi_aclk),
		.S_AXI_ARESETN (s00_axi_aresetn),
		.S_AXI_AWADDR  (s00_axi_awaddr),
		.S_AXI_AWPROT  (s00_axi_awprot),
		.S_AXI_AWVALID (s00_axi_awvalid),
		.S_AXI_AWREADY (s00_axi_awready),
		.S_AXI_WDATA   (s00_axi_wdata),
		.S_AXI_WSTRB   (s00_axi_wstrb),
		.S_AXI_WVALID  (s00_axi_wvalid),
		.S_AXI_WREADY  (s00_axi_wready),
		.S_AXI_BRESP   (s00_axi_bresp),
		.S_AXI_BVALID  (s00_axi_bvalid),
		.S_AXI_BREADY  (s00_axi_bready),
		.S_AXI_ARADDR  (s00_axi_araddr),
		.S_AXI_ARPROT  (s00_axi_arprot),
		.S_AXI_ARVALID (s00_axi_arvalid),
		.S_AXI_ARREADY (s00_axi_arready),
		.S_AXI_RDATA   (),
		.S_AXI_RRESP   (s00_axi_rresp),
		.S_AXI_RVALID  (s00_axi_rvalid),
		.S_AXI_RREADY  (s00_axi_rready)
	);

	// Add user logic here
	top #(
    	.AXI_ADDR_WIDTH (C_S00_AXI_ADDR_WIDTH)
	) u_cnn (
    	.o_valid       (o_valid),
    	.busy          (busy),
    	.axi_rd_data   (s00_axi_rdata),
    	.axi_wr_data   (s00_axi_wdata),
    	.axi_wr_addr   (s00_axi_awaddr_latch),
    	.axi_rd_addr   (s00_axi_araddr_latch),
    	.axi_wr_en     (s00_axi_wren),
    	.axi_rd_en     (s00_axi_rden),
    	.axi_wr_strobe (s00_axi_wstrb),
    	.clk           (s00_axi_aclk),
    	.rst_n         (s00_axi_aresetn)
	);

	// Blink LEDs 4 times when there's a read/write request
	activity_led_blink #(
    	.COUNTER_WIDTH (24)
	) u_led [1:0] (
    	.led_out ({wr_led, rd_led}),
		.trigger ({s00_axi_wren, s00_axi_rden}),
    	.clk     (s00_axi_aclk),
		.rst_n   (s00_axi_aresetn)
	);
	// User logic ends

	endmodule
