from model_quantized.QuantLaneNetQuantized import QuantLaneNetQuantized
from model_quantized.quantize_utils import convert_quantized_model
import argparse

def rtl_gen(model, rtl_path, fifo_factor=1):

    encoder_stage_1 = model.encoder_stage_1
    encoder_stage_2 = model.encoder_stage_2
    encoder_stage_3 = model.encoder_stage_3
    cls_out         = model.cls_out
    vertical_out    = model.vertical_out

    with open(rtl_path, 'w') as f:
        f.write(
            '`timescale 1ns / 1ps\n'
            '\n'
            'module model (\n'
            '    output [16*4-1:0] o_data_cls,\n'
            '    output [16*4-1:0] o_data_vertical,\n'
            '    output            o_valid_cls,\n'
            '    output            o_valid_vertical,\n'
            '    output            fifo_rd_en,\n'
            '    input  [8*3-1:0]  i_data,\n'
            '    input             i_valid,\n'
            '    input             cls_almost_full,\n'
            '    input             vertical_almost_full,\n'
            '    input  [15:0]     weight_wr_data,\n'
            '    input  [31:0]     weight_wr_addr,\n'
            '    input             weight_wr_en,\n'
            '    input             clk,\n'
            '    input             rst_n\n'
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

                if i == 0:
                    compute_factor = 'quadruple'
                elif i == 1:
                    compute_factor = 'double'
                else:
                    compute_factor = 'single'

                f.write(
                    f'    // Encoder stage {i} conv {j}\n'
                    f'    wire [8*{out_channel}-1:0] o_data_enc_{layer_num};\n'
                    f'    wire o_valid_enc_{layer_num};\n'
                    f'    wire fifo_almost_full_enc_{layer_num};\n'
                    f'\n'
                    f'    conv #(\n'
                    f'        .UNROLL_MODE           ("incha"),\n'
                    f'        .IN_WIDTH              ({int(in_size[1])}),\n'
                    f'        .IN_HEIGHT             ({int(in_size[0])}),\n'
                    f'        .OUTPUT_MODE           ("relu"),\n'
                    f'        .COMPUTE_FACTOR        ("{compute_factor}"),\n'
                    f'        .KERNEL_0              ({kernel_size[0]}),\n'
                    f'        .KERNEL_1              ({kernel_size[1]}),\n'
                    f'        .PADDING_0             ({padding[0]}),\n'
                    f'        .PADDING_1             ({padding[1]}),\n'
                    f'        .DILATION_0            ({dilation[0]}),\n'
                    f'        .DILATION_1            ({dilation[1]}),\n'
                    f'        .STRIDE_0              ({stride[0]}),\n'
                    f'        .STRIDE_1              ({stride[1]}),\n'
                    f'        .IN_CHANNEL            ({in_channel}),\n'
                    f'        .OUT_CHANNEL           ({out_channel}),\n'
                    f'        .KERNEL_BASE_ADDR      (),\n'
                    f'        .BIAS_BASE_ADDR        (),\n'
                    f'        .MACC_COEFF_BASE_ADDR  (),\n'
                    f'        .LAYER_SCALE_BASE_ADDR ()\n'
                    f'    ) u_enc_{layer_num} (\n'
                    f'        .o_data                (o_data_enc_{layer_num}),\n'
                    f'        .o_valid               (o_valid_enc_{layer_num}),\n'
                    f'        .fifo_rd_en            ({conv_fifo_rd_en}),\n'
                    f'        .i_data                ({i_data}),\n'
                    f'        .i_valid               ({i_valid}),\n'
                    # f'        .fifo_almost_full      (fifo_almost_full_enc_{layer_num}),\n'
                    f'        .fifo_almost_full      (1\'b0),\n'
                    f'        .weight_wr_data        (weight_wr_data),\n'
                    f'        .weight_wr_addr        (weight_wr_addr),\n'
                    f'        .weight_wr_en          (weight_wr_en),\n'
                    f'        .clk                   (clk),\n'
                    f'        .rst_n                 (rst_n)\n'
                    f'    );\n\n'
                )

                in_size = tuple((in_size[_i] + 2 * padding[_i] - dilation[_i] * (kernel_size[_i] - 1) - 1) / stride[_i] + 1 for _i in range(2))
                buffer_factor = fifo_factor * 2 if i == 0 and j == 0 else fifo_factor
                buffer_depth = max(int(in_size[1]) * buffer_factor, 64)

                if i != 2 or j != 2:
                    f.write(
                        f'    wire [8*{out_channel}-1:0] fifo_rd_data_enc_{layer_num};\n'
                        f'    wire fifo_empty_enc_{layer_num};\n'
                        f'    wire fifo_rd_en_enc_{layer_num};\n'
                        f'\n'
                        f'    fifo_single_read #(\n'
                        f'        .DATA_WIDTH        (8 * {out_channel}),\n'
                        f'        .DEPTH             ({buffer_depth}),\n'
                        f'        .ALMOST_FULL_THRES (10)\n'
                        f'    ) u_fifo_enc_{layer_num} (\n'
                        f'        .rd_data           (fifo_rd_data_enc_{layer_num}),\n'
                        f'        .empty             (fifo_empty_enc_{layer_num}),\n'
                        f'        .full              (),\n'
                        f'        .almost_full       (fifo_almost_full_enc_{layer_num}),\n'
                        f'        .wr_data           (o_data_enc_{layer_num}),\n'
                        f'        .wr_en             (o_valid_enc_{layer_num}),\n'
                        f'        .rd_en             (fifo_rd_en_enc_{layer_num}),\n'
                        f'        .rst_n             (rst_n),\n'
                        f'        .clk               (clk)\n'
                        f'    );\n\n'
                    )
                else:
                    f.write(
                        f'    wire [8*{out_channel}-1:0] enc_rd_data_a;\n'
                        f'    wire [8*{out_channel}-1:0] enc_rd_data_b;\n'
                        f'    wire enc_empty_a;\n'
                        f'    wire enc_empty_b;\n'
                        f'    wire enc_rd_en_a;\n'
                        f'    wire enc_rd_en_b;\n'
                        f'    wire enc_wr_en = o_valid_enc_{layer_num};\n'
                        f'\n'
                        f'    fifo_dual_read #(\n'
                        f'        .DATA_WIDTH        (8 * {out_channel}),\n'
                        f'        .DEPTH             ({buffer_depth}),\n'
                        f'        .ALMOST_FULL_THRES (10)\n'
                        f'    ) u_fifo_dual (\n'
                        f'        .rd_data_a         (enc_rd_data_a),\n'
                        f'        .rd_data_b         (enc_rd_data_b),\n'
                        f'        .empty_a           (enc_empty_a),\n'
                        f'        .empty_b           (enc_empty_b),\n'
                        f'        .full              (),\n'
                        f'        .almost_full       (fifo_almost_full_enc_{layer_num}),\n'
                        f'        .wr_data           (o_data_enc_{layer_num}),\n'
                        f'        .wr_en             (enc_wr_en),\n'
                        f'        .rd_en_a           (enc_rd_en_a),\n'
                        f'        .rd_en_b           (enc_rd_en_b),\n'
                        f'        .rst_n             (rst_n),\n'
                        f'        .clk               (clk)\n'
                        f'    );\n\n'
                    )

        # Output branches
        for i, (stage, name) in enumerate(zip([cls_out, vertical_out], ['cls', 'vertical'])):
            _in_size = in_size
            for j, layer in enumerate(stage):

                if layer._get_name() == 'ConvBatchnormReLU':
                    conv = layer.conv
                    output_mode = 'relu'
                    almost_full = f'fifo_almost_full_{name}_{j}'
                    almost_full_decl = f'wire {almost_full};\n'
                    data_width = 8
                elif layer._get_name() == 'QuantizedConv2d':
                    conv = layer
                    output_mode = 'sigmoid' if name == 'vertical' else 'dequant'
                    almost_full = f'{name}_almost_full'
                    almost_full_decl = ''
                    data_width = 16
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
                    f'    // {name} branch conv {j}\n'
                    f'    wire [{data_width}*{out_channel}-1:0] o_data_{name}_{j};\n'
                    f'    wire o_valid_{name}_{j};\n'
                    f'    {almost_full_decl}'
                    f'\n'
                    f'    conv #(\n'
                    f'        .UNROLL_MODE           ("outcha"),\n'
                    f'        .IN_WIDTH              ({int(_in_size[1])}),\n'
                    f'        .IN_HEIGHT             ({int(_in_size[0])}),\n'
                    f'        .OUTPUT_MODE           ("{output_mode}"),\n'
                    f'        .COMPUTE_FACTOR        ("single"),\n'
                    f'        .KERNEL_0              ({kernel_size[0]}),\n'
                    f'        .KERNEL_1              ({kernel_size[1]}),\n'
                    f'        .PADDING_0             ({padding[0]}),\n'
                    f'        .PADDING_1             ({padding[1]}),\n'
                    f'        .DILATION_0            ({dilation[0]}),\n'
                    f'        .DILATION_1            ({dilation[1]}),\n'
                    f'        .STRIDE_0              ({stride[0]}),\n'
                    f'        .STRIDE_1              ({stride[1]}),\n'
                    f'        .IN_CHANNEL            ({in_channel}),\n'
                    f'        .OUT_CHANNEL           ({out_channel}),\n'
                    f'        .KERNEL_BASE_ADDR      (),\n'
                    f'        .BIAS_BASE_ADDR        (),\n'
                    f'        .MACC_COEFF_BASE_ADDR  (),\n'
                    f'        .LAYER_SCALE_BASE_ADDR ()\n'
                    f'    ) u_{name}_{j} (\n'
                    f'        .o_data                (o_data_{name}_{j}),\n'
                    f'        .o_valid               (o_valid_{name}_{j}),\n'
                    f'        .fifo_rd_en            ({fifo_rd_en}),\n'
                    f'        .i_data                ({i_data}),\n'
                    f'        .i_valid               ({i_valid}),\n'
                    # f'        .fifo_almost_full      ({almost_full}),\n'
                    f'        .fifo_almost_full      (1\'b0),\n'
                    f'        .weight_wr_data        (weight_wr_data),\n'
                    f'        .weight_wr_addr        (weight_wr_addr),\n'
                    f'        .weight_wr_en          (weight_wr_en),\n'
                    f'        .clk                   (clk),\n'
                    f'        .rst_n                 (rst_n)\n'
                    f'    );\n\n'
                )

                _in_size = tuple((_in_size[_i] + 2 * padding[_i] - dilation[_i] * (kernel_size[_i] - 1) - 1) / stride[_i] + 1 for _i in range(2))

                if output_mode == 'relu':
                    buffer_depth = max(int(in_size[1]) * fifo_factor, 64)

                    f.write(
                        f'    wire [8*{out_channel}-1:0] fifo_rd_data_{name}_{j};\n'
                        f'    wire fifo_empty_{name}_{j};\n'
                        f'    wire fifo_rd_en_{name}_{j};\n'
                        f'\n'
                        f'    fifo_single_read #(\n'
                        f'        .DATA_WIDTH        (8 * {out_channel}),\n'
                        f'        .DEPTH             ({buffer_depth}),\n'
                        f'        .ALMOST_FULL_THRES (10)\n'
                        f'    ) u_fifo_{name}_{j} (\n'
                        f'        .rd_data           (fifo_rd_data_{name}_{j}),\n'
                        f'        .empty             (fifo_empty_{name}_{j}),\n'
                        f'        .full              (),\n'
                        f'        .almost_full       ({almost_full}),\n'
                        f'        .wr_data           (o_data_{name}_{j}),\n'
                        f'        .wr_en             (o_valid_{name}_{j}),\n'
                        f'        .rd_en             (fifo_rd_en_{name}_{j}),\n'
                        f'        .rst_n             (rst_n),\n'
                        f'        .clk               (clk)\n'
                        f'    );\n\n'
                    )
                else:
                    f.write(
                        f'    assign o_data_{name} = o_data_{name}_{j};\n'
                        f'    assign o_valid_{name} = o_valid_{name}_{j};\n'
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

    # MACC co-efficient
    for i, line in enumerate(lines):
        if 'MACC_COEFF_BASE_ADDR' in line:
            lines[i] = line.split('(')[0] + f'({total_weights}),  // Num macc_coeff: 1\n'
            total_weights += 1

    # Layer scale
    for i, line in enumerate(lines):
        if 'OUTPUT_MODE' in line:
            output_mode = line.split('"')[1]
        if 'LAYER_SCALE_BASE_ADDR' in line and output_mode in ['dequant', 'sigmoid']:
            lines[i] = line.split('(')[0] + f'({total_weights})   // Num layer_scale: 1\n'
            total_weights += 1

    print(f'Total weights: {total_weights:,}')
    with open(rtl_path, 'w') as f:
        for line in lines:
            f.write(line)

def get_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument('--rtl_path', type=str, default='./vivado_sources/rtl/model.v')
    parser.add_argument('--fifo_factor', type=int, default=1)

    return parser.parse_args()

def main():
    args = get_arguments()

    # Initialize model
    model = QuantLaneNetQuantized().to('cpu')
    model = convert_quantized_model(model)

    # Write RTL file
    rtl_gen(model=model, rtl_path=args.rtl_path, fifo_factor=args.fifo_factor)
    weight_addr_map(rtl_path=args.rtl_path)

if __name__ == '__main__':
    main()
