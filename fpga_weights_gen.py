from fixedpoint import FixedPoint
import argparse
import torch
import os

from model_quantized.QuantLaneNetQuantized import QuantLaneNetQuantized
from model_quantized.quantize_utils import convert_quantized_model

def write_weights(model, weights_bin_path):
    encoder_stage_1 = model.encoder_stage_1
    encoder_stage_2 = model.encoder_stage_2
    encoder_stage_3 = model.encoder_stage_3
    cls_out         = model.cls_out
    vertical_out    = model.vertical_out

    kernel_list = []
    bias_list = []
    macc_coeff_list = []
    layer_scale_list = []

    last_layer = model.quant

    for i, stage in enumerate([encoder_stage_1, encoder_stage_2, encoder_stage_3, cls_out, vertical_out]):
        if i < 3:
            layers = [stage.conv_same_1, stage.conv_same_2, stage.conv_down]
        else:
            last_layer = model.encoder_stage_3.conv_down.conv
            if i == 3:
                layers = stage[:]
            else:
                layers = stage[:-1]

        for layer in layers:
            if layer._get_name() == 'ConvBatchnormReLU':
                conv = layer.conv
            elif layer._get_name() == 'QuantizedConv2d':
                conv = layer
            else:
                raise Exception(f'Unknown layer:\n{layer}')

            # Kernel and bias
            kernel = conv.weight().detach()
            bias = conv.bias().detach()
            y_scale = conv.scale

            for fil in range(conv.out_channels):
                bias_list.append(bias[fil] / y_scale)

                for row in range(conv.kernel_size[0]):
                    for col in range(conv.kernel_size[1]):
                        for cha in range(conv.in_channels):
                            kernel_list.append(kernel[fil, cha, row, col].int_repr())

            # MACC co-efficient
            x_scale = last_layer.scale
            w_scale = kernel.q_scale()
            macc_coeff_list.append(x_scale * w_scale / y_scale)

            # Layer scale
            if layer._get_name() == 'QuantizedConv2d':
                layer_scale_list.append(y_scale)

            last_layer = conv

    print(
        f'Num kernel      : {len(kernel_list)}\n'
        f'Num bias        : {len(bias_list)}\n'
        f'Num macc_coeff  : {len(macc_coeff_list)}\n'
        f'Num layer_scale : {len(layer_scale_list)}\n'
        f'Total weights   : {len(kernel_list) + len(bias_list) + len(macc_coeff_list) + len(layer_scale_list)}'
    )

    # Write to file
    byte_array = bytearray()
    bias_qformat = {'m': 8, 'n': 8, 'signed': 1}
    scale_qformat = {'m': 2, 'n': 16, 'signed': 0}

    for val in kernel_list:
        byte_array.extend((val.item() & 0xffff).to_bytes(length=2, byteorder='little'))

    for val in bias_list:
        byte_array.extend(int(f'{FixedPoint(val, **bias_qformat):04x}', 16).to_bytes(length=2, byteorder='little'))

    for val in macc_coeff_list + layer_scale_list:
        byte_array.extend(int(f'{FixedPoint(val, **scale_qformat):04x}', 16).to_bytes(length=2, byteorder='little'))

    # if (len(byte_array) / 2) % 2:
    #     print('byte_array is odd')
    #     byte_array.extend((0).to_bytes(length=2, byteorder='little'))

    with open(weights_bin_path, 'wb') as f:
        f.write(byte_array)

def get_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument('--weights_bin_path', type=str, default='./weights/fpga_weights.bin')
    parser.add_argument('--quantized_weights_path', type=str, default='./weights/quantized_weights_pertensor_symmetric.pth')

    args = parser.parse_args()

    args.weights_bin_path = os.path.abspath(args.weights_bin_path)
    args.quantized_weights_path = os.path.abspath(args.quantized_weights_path)

    return args

def main():
    args = get_arguments()

    # Load quantized model
    print(f'[INFO] Loading quantized model from {args.quantized_weights_path}')
    model = QuantLaneNetQuantized().to('cpu')
    model = convert_quantized_model(model)
    model.load_state_dict(torch.load(args.quantized_weights_path, map_location='cpu'))

    # Write weights
    print('[INFO] Writing weights...')
    write_weights(model, args.weights_bin_path)

if __name__ == '__main__':
    main()
