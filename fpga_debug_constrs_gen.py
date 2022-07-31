import argparse

def write_constrs(constrs_path):
    # 'type' for multi-bit buses
    # 'nets' for one-bit nets (one net or multiple nets grouped together in one debug port)
    debug_ports = [
        { 'type': 'bus' , 'name':   'design_1_i/axi_smc_M00_AXI_ARADDR'                                              , 'width': 20 },
        { 'type': 'bus' , 'name':   'design_1_i/axi_smc_M00_AXI_RDATA'                                               , 'width': 64 },
        { 'type': 'bus' , 'name':   'design_1_i/axi_smc_M00_AXI_ARLEN'                                               , 'width':  8 },
        { 'type': 'bus' , 'name':   'design_1_i/axi_smc_M00_AXI_AWADDR'                                              , 'width': 20 },
        { 'type': 'bus' , 'name':   'design_1_i/axi_smc_M00_AXI_WDATA'                                               , 'width': 64 },
        { 'type': 'bus' , 'name':   'design_1_i/axi_smc_M00_AXI_WSTRB'                                               , 'width':  8 },
        { 'type': 'bus' , 'name':   'design_1_i/axi_smc_M00_AXI_AWLEN'                                               , 'width':  8 },
        { 'type': 'bus' , 'name':   'design_1_i/QuantLaneNet_AXI_0/inst/QuantLaneNet_S00_AXI_inst/S_AXI_AWADDR_LATCH', 'width': 20 },
        { 'type': 'bus' , 'name':   'design_1_i/QuantLaneNet_AXI_0/inst/QuantLaneNet_S00_AXI_inst/S_AXI_ARADDR_LATCH', 'width': 20 },
        { 'type': 'bus' , 'name':   'design_1_i/QuantLaneNet_AXI_0/inst/u_cnn/clock_cnt'                             , 'width': 32 },

        { 'type': 'nets', 'list': [ 'design_1_i/axi_smc_M00_AXI_RLAST'                                        ,
                                    'design_1_i/axi_smc_M00_AXI_ARVALID'                                      ,
                                    'design_1_i/axi_smc_M00_AXI_ARREADY'                                      ,
                                    'design_1_i/axi_smc_M00_AXI_WLAST'                                        ,
                                    'design_1_i/axi_smc_M00_AXI_AWVALID'                                      ,
                                    'design_1_i/axi_smc_M00_AXI_AWREADY'                                      ,
                                    'design_1_i/QuantLaneNet_AXI_0/inst/QuantLaneNet_S00_AXI_inst/S_AXI_WREN' ,
                                    'design_1_i/QuantLaneNet_AXI_0/inst/QuantLaneNet_S00_AXI_inst/S_AXI_RDEN' ,
                                    'design_1_i/QuantLaneNet_AXI_0/inst/u_cnn/busy'                           , 
                                    'design_1_i/QuantLaneNet_AXI_0/inst/u_cnn/u_post/o_valid'                 ]},
    ]

    # Write xdc file
    with open(constrs_path, 'w') as f:
        for i, port in enumerate(debug_ports):
            f.write(
                f'\n'
                f'#############################################################################\n'
                f'# Mark debug: Port {i}\n'
                f'#############################################################################\n'
                f'\n'
            )

            if port['type'] == 'bus':
                for i in range(port['width']):
                    f.write(f'set_property MARK_DEBUG true [get_nets {{{port["name"]}[{i}]}}]\n')
            elif port['type'] == 'nets':
                for net in port['list']:
                    f.write(f'set_property MARK_DEBUG true [get_nets {{{net}}}]\n')

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
            f'set_property   C_EN_STRG_QUAL         false         [get_debug_cores u_ila_0]\n'
            f'set_property   C_INPUT_PIPE_STAGES    0             [get_debug_cores u_ila_0]\n'
            f'set_property   C_TRIGIN_EN            false         [get_debug_cores u_ila_0]\n'
            f'set_property   C_TRIGOUT_EN           false         [get_debug_cores u_ila_0]\n'
            f'set_property   C_DATA_DEPTH           16384         [get_debug_cores u_ila_0]\n'
            f'\n'
        )

        f.write(
            f'set_property port_width 1 [get_debug_ports u_ila_0/clk]\n'
            f'connect_debug_port u_ila_0/clk [get_nets [list design_1_i/clk_wiz_0/inst/clk_out1]]\n'
        )

        for i, port in enumerate(debug_ports):
            f.write(
                f'\n'
                f'#############################################################################\n'
                f'# Connect to debug core: Port {i}\n'
                f'#############################################################################\n'
                f'\n'
            )

            if port['type'] == 'bus':
                port_width = port['width']
            elif port['type'] == 'nets':
                port_width = len(port['list'])

            if i > 0:
                f.write(f'{"create_debug_port":<19} {"u_ila_0":<13} probe\n')

            f.write(
                f'{"set_property":<19} {"PROBE_TYPE":<13} {"DATA_AND_TRIGGER":<17} [get_debug_ports u_ila_0/probe{i}]\n'
                f'{"set_property":<19} {"port_width":<13} {port_width:<17} [get_debug_ports u_ila_0/probe{i}]\n'
                f'\n'
                f'connect_debug_port u_ila_0/probe{i} [get_nets [list \\\n'
            )

            if port['type'] == 'bus':
                for i in range(port['width']):
                    f.write(f'\t{{{port["name"]}[{i}]}}  \\\n')
            elif port['type'] == 'nets':
                for net in port['list']:
                    f.write(f'\t{{{net}}}  \\\n')

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
