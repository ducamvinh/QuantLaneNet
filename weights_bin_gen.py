from fixedpoint import FixedPoint
import argparse
import torch

from model.LaneDetectionModel import LaneDetectionModel
from checkpoint_info import get_best_model

def write_weights(model, weights_bin_path, qformat):
    encoder_stage_1 = model.encoder_stage_1
    encoder_stage_2 = model.encoder_stage_2
    encoder_stage_3 = model.encoder_stage_3
    cls_out         = model.cls_out
    vertical_out    = model.vertical_out

    kernel_list = []
    bias_list = []
    batchnorm_a_list = []
    batchnorm_b_list = []

    for i, stage in enumerate([encoder_stage_1, encoder_stage_2, encoder_stage_3, cls_out, vertical_out]):
        if i < 3:
            layers = [stage.conv_same_1, stage.conv_same_2, stage.conv_down]
        elif i == 3:
            layers = stage[:]
        else:
            layers = stage[:-1]

        for layer in layers:

            if layer._get_name() == 'ConvBatchnormReLU':
                conv = layer.conv
                bn = layer.bn
            elif layer._get_name() == 'Conv2d':
                conv = layer
            else:
                raise Exception(f'Unknown layer:\n{layer}')

            if layer._get_name() != 'Conv2d':
                gamma = bn.weight.detach()
                beta = bn.bias.detach()
                mean = bn.running_mean.detach()
                var = bn.running_var.detach()
                eps = bn.eps

                for fil in range(bn.num_features):
                    a = gamma[fil] / torch.sqrt(var[fil] + eps)
                    b = beta[fil] - a * mean[fil]

                    batchnorm_a_list.append(a)
                    batchnorm_b_list.append(b)

            kernel = conv.weight.detach()
            bias = conv.bias.detach()

            for fil in range(conv.out_channels):
                bias_list.append(bias[fil])

                for row in range(conv.kernel_size[0]):
                    for col in range(conv.kernel_size[1]):
                        for cha in range(conv.in_channels):
                            kernel_list.append(kernel[fil, cha, row, col])

    print(
        f'Num kernel      : {len(kernel_list)}\n'
        f'Num bias        : {len(bias_list)}\n'
        f'Num batchnorm_a : {len(batchnorm_a_list)}\n'
        f'Num batchnorm_b : {len(batchnorm_b_list)}\n'
        f'Total weights   : {len(kernel_list) + len(bias_list) + len(batchnorm_a_list) + len(batchnorm_b_list)}'
    )
    
    # Write to file
    byte_list = []
    format_str = f"%0{(qformat['m'] + qformat['n']) / 4}x"

    for val in kernel_list + bias_list + batchnorm_a_list + batchnorm_b_list:
        hex_str = format_str % FixedPoint(val, **qformat)
        val_bytes = [hex_str[i:i+2] for i in range(0, len(hex_str), 2)]
        val_bytes.reverse()
        byte_list.extend(val_bytes)

    with open(weights_bin_path, 'wb') as f:
        f.write(bytearray.fromhex(''.join(byte_list)))

def get_arguments():
    parser = argparse.ArgumentParser()
    
    parser.add_argument('--weights_bin_path', type=str, default='weights.bin')
    parser.add_argument('--checkpoint_path', type=str)

    args = parser.parse_args()

    if args.checkpoint_path[-1] in ['/', '\\']:
        args.checkpoint_path = args.checkpoint_path[:-1]

    return args

def main():
    args = get_arguments()
    qformat = {'m': 8, 'n': 8, 'signed': 1}

    # Get best checkpoint
    checkpoint = torch.load(f'{args.checkpoint_path}/checkpoint_{get_best_model(args.checkpoint_path)}.pth', map_location='cpu')

    # Initialize model
    model = LaneDetectionModel().to('cpu')
    model.load_state_dict(checkpoint['model_state'], strict=False)
    model.eval()    

    # Write weights
    print('[INFO] Writing weights...')
    write_weights(model, args.weights_bin_path, qformat)

if __name__ == '__main__':
    main()
