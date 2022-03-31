from model.LaneDetectionModel import LaneDetectionModel
import argparse

def rtl_gen(rtl_path, fifo_factor=1):
    model = LaneDetectionModel().to('cpu')
    model.eval()

    encoder_stage_1 = model.encoder_stage_1
    encoder_stage_2 = model.encoder_stage_2
    encoder_stage_3 = model.encoder_stage_3
    cls_out         = model.cls_out
    vertical_out    = model.vertical_out

    with open(rtl_path, 'w') as f:
        f.write(
            '`timescale 1ns / 1ps\n'
            '\n'
            'module model #(\n'
            '\tparameter DATA_WIDTH = 16,\n'
            '\tparameter FRAC_BITS = 8\n'
            ')(\n'
            '\toutput [DATA_WIDTH*4-1:0] o_data_cls,\n'
            '\toutput [DATA_WIDTH*4-1:0] o_data_vertical,\n'
            '\toutput                    o_valid_cls,\n'
            '\toutput                    o_valid_vertical,\n'
            '\toutput                    fifo_rd_en,\n'
            '\tinput  [DATA_WIDTH*3-1:0] i_data,\n'
            '\tinput                     i_valid,\n'
            '\tinput                     cls_almost_full,\n'
            '\tinput                     vertical_almost_full,\n'
            '\tinput  [DATA_WIDTH-1:0]   weight_data,\n'
            '\tinput  [31:0]             weight_addr,\n'
            '\tinput                     weight_we,\n'
            '\tinput                     clk,\n'
            '\tinput                     rst_n\n'
            ');\n\n'
        )

        in_size = model.input_size

        # Encoder stages
        for i, stage in enumerate([encoder_stage_1, encoder_stage_2, encoder_stage_3]):
            for j, layer in enumerate([stage.conv_same_1, stage.conv_same_2, stage.conv_down]):
                
                layer_num = i * 3 + j
                conv = layer.conv

                in_channel = conv.in_channels
                out_channel = conv.out_channels
                kernel_size = conv.kernel_size
                padding = conv.padding
                dilation = conv.dilation
                stride = conv.stride

                if layer_num == 0:
                    i_data = 'i_data'
                    i_valid = 'i_valid'
                    conv_fifo_rd_en = 'fifo_rd_en'
                else:
                    i_data = f'fifo_rd_data_enc_{layer_num-1}'
                    i_valid = f'~fifo_empty_enc_{layer_num-1}'
                    conv_fifo_rd_en = f'fifo_rd_en_enc_{layer_num-1}'

                f.write(
                    f'\t// Encoder stage {i} conv {j}\n'
                    f'\twire [DATA_WIDTH*{out_channel}-1:0] o_data_enc_{layer_num};\n'
                    f'\twire o_valid_enc_{layer_num};\n'
                    f'\twire fifo_almost_full_enc_{layer_num};\n'
                    f'\n'
                    f'\tconv #(\n'
                    f'\t\t.UNROLL_MODE           ("incha"),\n'
                    f'\t\t.DATA_WIDTH            (DATA_WIDTH),\n'
                    f'\t\t.FRAC_BITS             (FRAC_BITS),\n'
                    f'\t\t.IN_WIDTH              ({int(in_size[1])}),\n'
                    f'\t\t.IN_HEIGHT             ({int(in_size[0])}),\n'
                    f'\t\t.OUTPUT_MODE           ("batchnorm_relu"),\n'
                    f'\t\t.KERNEL_0              ({kernel_size[0]}),\n'
                    f'\t\t.KERNEL_1              ({kernel_size[1]}),\n'
                    f'\t\t.PADDING_0             ({padding[0]}),\n'
                    f'\t\t.PADDING_1             ({padding[1]}),\n'
                    f'\t\t.DILATION_0            ({dilation[0]}),\n'
                    f'\t\t.DILATION_1            ({dilation[1]}),\n'
                    f'\t\t.STRIDE_0              ({stride[0]}),\n'
                    f'\t\t.STRIDE_1              ({stride[1]}),\n'
                    f'\t\t.IN_CHANNEL            ({in_channel}),\n'
                    f'\t\t.OUT_CHANNEL           ({out_channel}),\n'
                    f'\t\t.KERNEL_BASE_ADDR      (),\n'
                    f'\t\t.BIAS_BASE_ADDR        (),\n'
                    f'\t\t.BATCHNORM_A_BASE_ADDR (),\n'
                    f'\t\t.BATCHNORM_B_BASE_ADDR ()\n'
                    f'\t) u_enc_{layer_num} (\n'
                    f'\t\t.o_data           (o_data_enc_{layer_num}),\n'
                    f'\t\t.o_valid          (o_valid_enc_{layer_num}),\n'
                    f'\t\t.fifo_rd_en       ({conv_fifo_rd_en}),\n'
                    f'\t\t.i_data           ({i_data}),\n'
                    f'\t\t.i_valid          ({i_valid}),\n'
                    f'\t\t.fifo_almost_full (fifo_almost_full_enc_{layer_num}),\n'
                    f'\t\t.weight_data      (weight_data),\n'
                    f'\t\t.weight_addr      (weight_addr),\n'
                    f'\t\t.weight_we        (weight_we),\n'
                    f'\t\t.clk              (clk),\n'
                    f'\t\t.rst_n            (rst_n)\n'
                    f'\t);\n\n'
                )

                in_size = tuple((in_size[_i] + 2 * padding[_i] - dilation[_i] * (kernel_size[_i] - 1) - 1) / stride[_i] + 1 for _i in range(2))
                buffer_factor = fifo_factor * 2 if i == 0 and j == 0 else fifo_factor
                buffer_depth = max(int(in_size[1]) * buffer_factor, 64)

                if i != 2 or j != 2:
                    f.write(
                        f'\twire [DATA_WIDTH*{out_channel}-1:0] fifo_rd_data_enc_{layer_num};\n'
                        f'\twire fifo_empty_enc_{layer_num};\n'
                        f'\twire fifo_rd_en_enc_{layer_num};\n'
                        f'\n'
                        f'\tfifo_single_read #(\n'
                        f'\t\t.DATA_WIDTH        (DATA_WIDTH * {out_channel}),\n'
                        f'\t\t.DEPTH             ({buffer_depth}),\n'
                        f'\t\t.ALMOST_FULL_THRES (10)\n'
                        f'\t) u_fifo_enc_{layer_num} (\n'
                        f'\t\t.rd_data     (fifo_rd_data_enc_{layer_num}),\n'
                        f'\t\t.empty       (fifo_empty_enc_{layer_num}),\n'
                        f'\t\t.full        (),\n'
                        f'\t\t.almost_full (fifo_almost_full_enc_{layer_num}),\n'
                        f'\t\t.wr_data     (o_data_enc_{layer_num}),\n'
                        f'\t\t.wr_en       (o_valid_enc_{layer_num}),\n'
                        f'\t\t.rd_en       (fifo_rd_en_enc_{layer_num}),\n'
                        f'\t\t.rst_n       (rst_n),\n'
                        f'\t\t.clk         (clk)\n'
                        f'\t);\n\n'
                    )
                else:
                    f.write(
                        f'\twire [DATA_WIDTH*{out_channel}-1:0] enc_rd_data_a;\n'
                        f'\twire [DATA_WIDTH*{out_channel}-1:0] enc_rd_data_b;\n'
                        f'\twire enc_empty_a;\n'
                        f'\twire enc_empty_b;\n'
                        f'\twire enc_rd_en_a;\n'
                        f'\twire enc_rd_en_b;\n'
                        f'\twire enc_wr_en = o_valid_enc_{layer_num};\n'
                        f'\n'
                        f'\tfifo_dual_read #(\n'
                        f'\t\t.DATA_WIDTH        (DATA_WIDTH * {out_channel}),\n'
                        f'\t\t.DEPTH             ({buffer_depth}),\n'
                        f'\t\t.ALMOST_FULL_THRES (10)\n'
                        f'\t) u_fifo_dual (\n'
                        f'\t\t.rd_data_a   (enc_rd_data_a),\n'
                        f'\t\t.rd_data_b   (enc_rd_data_b),\n'
                        f'\t\t.empty_a     (enc_empty_a),\n'
                        f'\t\t.empty_b     (enc_empty_b),\n'
                        f'\t\t.full        (),\n'
                        f'\t\t.almost_full (fifo_almost_full_enc_{layer_num}),\n'
                        f'\t\t.wr_data     (o_data_enc_{layer_num}),\n'
                        f'\t\t.wr_en       (enc_wr_en),\n'
                        f'\t\t.rd_en_a     (enc_rd_en_a),\n'
                        f'\t\t.rd_en_b     (enc_rd_en_b),\n'
                        f'\t\t.rst_n       (rst_n),\n'
                        f'\t\t.clk         (clk)\n'
                        f'\t);\n\n'
                    )

        # Output branches
        for i, (stage, name) in enumerate(zip([cls_out, vertical_out], ['cls', 'vertical'])):
            _in_size = in_size
            for j, layer in enumerate(stage):

                if layer._get_name() == 'ConvBatchnormReLU':
                    conv = layer.conv
                    output_mode = 'batchnorm_relu'
                    almost_full = f'fifo_almost_full_{name}_{j}'
                    almost_full_decl = f'\twire {almost_full};\n'
                elif layer._get_name() == 'Conv2d':
                    conv = layer
                    output_mode = 'sigmoid' if name == 'vertical' else 'linear'
                    almost_full = f'{name}_almost_full'
                    almost_full_decl = ''
                else:
                    continue

                if j == 0:
                    fifo_rd_en = 'enc_rd_en_a' if i == 0 else 'enc_rd_en_b'
                    i_data = 'enc_rd_data_a' if i == 0 else 'enc_rd_data_b'
                    i_valid = f'~{"enc_empty_a" if i == 0 else "enc_empty_b"} & ~enc_wr_en'
                else:
                    fifo_rd_en = f'fifo_rd_en_{name}_{j-1}'
                    i_data = f'fifo_rd_data_{name}_{j-1}'
                    i_valid = f'~fifo_empty_{name}_{j-1}'

                in_channel = conv.in_channels
                out_channel = conv.out_channels
                kernel_size = conv.kernel_size
                padding = conv.padding
                dilation = conv.dilation
                stride = conv.stride

                f.write(
                    f'\t// {name} branch conv {j}\n'
                    f'\twire [DATA_WIDTH*{out_channel}-1:0] o_data_{name}_{j};\n'
                    f'\twire o_valid_{name}_{j};\n'
                    f'{almost_full_decl}'
                    f'\n'
                    f'\tconv #(\n'
                    f'\t\t.UNROLL_MODE           ("outcha"),\n'
                    f'\t\t.DATA_WIDTH            (DATA_WIDTH),\n'
                    f'\t\t.FRAC_BITS             (FRAC_BITS),\n'
                    f'\t\t.IN_WIDTH              ({int(_in_size[1])}),\n'
                    f'\t\t.IN_HEIGHT             ({int(_in_size[0])}),\n'
                    f'\t\t.OUTPUT_MODE           ("{output_mode}"),\n'
                    f'\t\t.KERNEL_0              ({kernel_size[0]}),\n'
                    f'\t\t.KERNEL_1              ({kernel_size[1]}),\n'
                    f'\t\t.PADDING_0             ({padding[0]}),\n'
                    f'\t\t.PADDING_1             ({padding[1]}),\n'
                    f'\t\t.DILATION_0            ({dilation[0]}),\n'
                    f'\t\t.DILATION_1            ({dilation[1]}),\n'
                    f'\t\t.STRIDE_0              ({stride[0]}),\n'
                    f'\t\t.STRIDE_1              ({stride[1]}),\n'
                    f'\t\t.IN_CHANNEL            ({in_channel}),\n'
                    f'\t\t.OUT_CHANNEL           ({out_channel}),\n'
                    f'\t\t.KERNEL_BASE_ADDR      (),\n'
                    f'\t\t.BIAS_BASE_ADDR        (),\n'
                    f'\t\t.BATCHNORM_A_BASE_ADDR (),\n'
                    f'\t\t.BATCHNORM_B_BASE_ADDR ()\n'
                    f'\t) u_{name}_{j} (\n'
                    f'\t\t.o_data           (o_data_{name}_{j}),\n'
                    f'\t\t.o_valid          (o_valid_{name}_{j}),\n'
                    f'\t\t.fifo_rd_en       ({fifo_rd_en}),\n'
                    f'\t\t.i_data           ({i_data}),\n'
                    f'\t\t.i_valid          ({i_valid}),\n'
                    f'\t\t.fifo_almost_full ({almost_full}),\n'
                    f'\t\t.weight_data      (weight_data),\n'
                    f'\t\t.weight_addr      (weight_addr),\n'
                    f'\t\t.weight_we        (weight_we),\n'
                    f'\t\t.clk              (clk),\n'
                    f'\t\t.rst_n            (rst_n)\n'
                    f'\t);\n\n'
                )

                _in_size = tuple((_in_size[_i] + 2 * padding[_i] - dilation[_i] * (kernel_size[_i] - 1) - 1) / stride[_i] + 1 for _i in range(2))

                if output_mode == 'batchnorm_relu':
                    buffer_depth = max(int(in_size[1]) * fifo_factor, 64)

                    f.write(
                        f'\twire [DATA_WIDTH*{out_channel}-1:0] fifo_rd_data_{name}_{j};\n'
                        f'\twire fifo_empty_{name}_{j};\n'
                        f'\twire fifo_rd_en_{name}_{j};\n'
                        f'\n'
                        f'\tfifo_single_read #(\n'
                        f'\t\t.DATA_WIDTH        (DATA_WIDTH * {out_channel}),\n'
                        f'\t\t.DEPTH             ({buffer_depth}),\n'
                        f'\t\t.ALMOST_FULL_THRES (10)\n'
                        f'\t) u_fifo_{name}_{j} (\n'
                        f'\t\t.rd_data     (fifo_rd_data_{name}_{j}),\n'
                        f'\t\t.empty       (fifo_empty_{name}_{j}),\n'
                        f'\t\t.full        (),\n'
                        f'\t\t.almost_full ({almost_full}),\n'
                        f'\t\t.wr_data     (o_data_{name}_{j}),\n'
                        f'\t\t.wr_en       (o_valid_{name}_{j}),\n'
                        f'\t\t.rd_en       (fifo_rd_en_{name}_{j}),\n'
                        f'\t\t.rst_n       (rst_n),\n'
                        f'\t\t.clk         (clk)\n'
                        f'\t);\n\n'
                    )
                else:
                    f.write(
                        f'\tassign o_data_{name} = o_data_{name}_{j};\n'
                        f'\tassign o_valid_{name} = o_valid_{name}_{j};\n'
                        f'\n'
                    )

        f.write('endmodule\n')

def weight_addr_map(rtl_path):
    with open(rtl_path, 'r') as f:
        lines = f.readlines()

    total_weights = 0
    kernel_0 = 0
    kernel_1 = 0
    in_channel = 0
    out_channel = 0
    output_mode = ''

    # Kernel
    for i, line in enumerate(lines):
        if 'KERNEL_0' in line:
            kernel_0 = int(line.split('(')[1].split(')')[0])
        if 'KERNEL_1' in line:
            kernel_1 = int(line.split('(')[1].split(')')[0])
        if 'IN_CHANNEL' in line:
            in_channel = int(line.split('(')[1].split(')')[0])
        if 'OUT_CHANNEL' in line:
            out_channel = int(line.split('(')[1].split(')')[0])
        if 'KERNEL_BASE_ADDR' in line:
            num_weights = kernel_0 * kernel_1 * in_channel * out_channel
            lines[i] = line.split('(')[0] + f'({total_weights}),  // Num kernel: {num_weights}\n'
            total_weights += num_weights

    # Bias
    for i, line in enumerate(lines):
        if 'OUT_CHANNEL' in line:
            out_channel = int(line.split('(')[1].split(')')[0])
        if 'BIAS_BASE_ADDR' in line:
            lines[i] = line.split('(')[0] + f'({total_weights}),  // Num bias: {out_channel}\n'
            total_weights += out_channel

    # Batchnorm a
    for i, line in enumerate(lines):
        if 'OUTPUT_MODE' in line:
            output_mode = line.split('"')[1]
        if 'OUT_CHANNEL' in line:
            out_channel = int(line.split('(')[1].split(')')[0])
        if 'BATCHNORM_A_BASE_ADDR' in line and output_mode == 'batchnorm_relu':
            lines[i] = line.split('(')[0] + f'({total_weights}),  // Num bn_a: {out_channel}\n'
            total_weights += out_channel

    # Batchnorm b
    for i, line in enumerate(lines):
        if 'OUTPUT_MODE' in line:
            output_mode = line.split('"')[1]
        if 'OUT_CHANNEL' in line:
            out_channel = int(line.split('(')[1].split(')')[0])
        if 'BATCHNORM_B_BASE_ADDR' in line and output_mode == 'batchnorm_relu':
            lines[i] = line.split('(')[0] + f'({total_weights})   // Num bn_b: {out_channel}\n'
            total_weights += out_channel

    with open(rtl_path, 'w') as f:
        for line in lines:
            f.write(line)

def get_arguments():
    parser = argparse.ArgumentParser()
    
    parser.add_argument('--rtl_path', type=str, default='rtl_sources/model.v')
    parser.add_argument('--fifo_factor', type=int, default=1)

    return parser.parse_args()

def main():
    args = get_arguments()

    rtl_gen(rtl_path=args.rtl_path, fifo_factor=args.fifo_factor)
    weight_addr_map(rtl_path=args.rtl_path)
    
if __name__ == '__main__':
    main()
