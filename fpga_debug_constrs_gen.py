import argparse

def write_constrs(constrs_path):
    debug_list = [
        { 'name': 'design_1_i/axi_smc_M00_AXI_ARADDR'  , 'width': 20 },
        { 'name': 'design_1_i/axi_smc_M00_AXI_RDATA'   , 'width': 64 },
        # { 'name': 'design_1_i/axi_smc_M00_AXI_ARLEN'   , 'width':  8 },
        # { 'name': 'design_1_i/axi_smc_M00_AXI_RLAST'   , 'width':  1 },
        { 'name': 'design_1_i/axi_smc_M00_AXI_ARVALID' , 'width':  1 },
        { 'name': 'design_1_i/axi_smc_M00_AXI_ARREADY' , 'width':  1 },
                         
        { 'name': 'design_1_i/axi_smc_M00_AXI_AWADDR'  , 'width': 20 },
        { 'name': 'design_1_i/axi_smc_M00_AXI_WDATA'   , 'width': 64 },
        { 'name': 'design_1_i/axi_smc_M00_AXI_WSTRB'   , 'width':  8 },
        # { 'name': 'design_1_i/axi_smc_M00_AXI_AWLEN'   , 'width':  8 },
        # { 'name': 'design_1_i/axi_smc_M00_AXI_WLAST'   , 'width':  1 },
        { 'name': 'design_1_i/axi_smc_M00_AXI_AWVALID' , 'width':  1 },
        { 'name': 'design_1_i/axi_smc_M00_AXI_AWREADY' , 'width':  1 },

        { 'name': 'design_1_i/LaneDetectionCNN_AXI_0/inst/LaneDetectionCNN_S00_AXI_inst/S_AXI_AWADDR_LATCH' , 'width': 20},
        { 'name': 'design_1_i/LaneDetectionCNN_AXI_0/inst/LaneDetectionCNN_S00_AXI_inst/S_AXI_ARADDR_LATCH' , 'width': 20},
        { 'name': 'design_1_i/LaneDetectionCNN_AXI_0/inst/LaneDetectionCNN_S00_AXI_inst/S_AXI_WREN'         , 'width':  1},
        { 'name': 'design_1_i/LaneDetectionCNN_AXI_0/inst/LaneDetectionCNN_S00_AXI_inst/S_AXI_RDEN'         , 'width':  1},

        { 'name': 'design_1_i/LaneDetectionCNN_AXI_0/inst/u_cnn/clock_cnt'      , 'width': 32},
        { 'name': 'design_1_i/LaneDetectionCNN_AXI_0/inst/u_cnn/busy'           , 'width':  1},
        { 'name': 'design_1_i/LaneDetectionCNN_AXI_0/inst/u_cnn/u_post/o_valid' , 'width':  1},
    ]

    with open(constrs_path, 'w') as f:
        for net in debug_list:
            f.write(
                f'\n'
                f'#############################################################################\n'
                f'# Mark debug: {net["name"]}\n'
                f'#############################################################################\n'
                f'\n'
            )

            if net['width'] > 1:
                for i in range(net['width']):
                    f.write(f'set_property MARK_DEBUG true [get_nets {{{net["name"]}[{i}]}}]\n')
            else:
                f.write(f'set_property MARK_DEBUG true [get_nets {{{net["name"]}}}]\n')

        f.write(
            f'\n'
            f'########################################################################\n'
            f'# Create debug core\n'
            f'########################################################################\n'
            f'\n'
            f'create_debug_core                     u_ila_0 ila\n'
            f'set_property   ALL_PROBE_SAME_MU      true          [get_debug_cores u_ila_0]\n'
            f'set_property   ALL_PROBE_SAME_MU_CNT  1             [get_debug_cores u_ila_0]\n'
            f'set_property   C_ADV_TRIGGER          false         [get_debug_cores u_ila_0]\n'
            f'set_property   C_DATA_DEPTH           16384         [get_debug_cores u_ila_0]\n'
            f'set_property   C_EN_STRG_QUAL         false         [get_debug_cores u_ila_0]\n'
            f'set_property   C_INPUT_PIPE_STAGES    0             [get_debug_cores u_ila_0]\n'
            f'set_property   C_TRIGIN_EN            false         [get_debug_cores u_ila_0]\n'
            f'set_property   C_TRIGOUT_EN           false         [get_debug_cores u_ila_0]\n'
            f'\n'
        )

        f.write(
            f'set_property port_width 1 [get_debug_ports u_ila_0/clk]\n'
            f'connect_debug_port u_ila_0/clk [get_nets [list design_1_i/clk_wiz_0/inst/clk_out1]]\n'
        )

        for i, net in enumerate(debug_list):
            f.write(
                f'\n'
                f'#############################################################################\n'
                f'# Connect to debug core: {net["name"]}\n'
                f'#############################################################################\n'
                f'\n'
            )

            if i > 0:
                f.write(f'{"create_debug_port":<19} {"u_ila_0":<13} probe\n')

            f.write(
                f'{"set_property":<19} {"PROBE_TYPE":<13} {"DATA_AND_TRIGGER":<17} [get_debug_ports u_ila_0/probe{i}]\n'
                f'{"set_property":<19} {"port_width":<13} {(net["width"]):<17} [get_debug_ports u_ila_0/probe{i}]\n'
                f'\n'
                f'connect_debug_port u_ila_0/probe{i} [get_nets [list \\\n'
            )

            if net['width'] > 1:
                for i in range(net['width']):
                    f.write(f'\t{{{net["name"]}[{i}]}}  \\\n')
            else:
                f.write(f'\t{{{net["name"]}}}  \\\n')

            f.write(
                f']]\n'
            )

def get_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument('--debug_path', type=str, default='./vivado_sources/constraints/debug.xdc')
    return parser.parse_args()

def main():
    args = get_arguments()
    write_constrs(args.debug_path)    

if __name__ == '__main__':
    main()
