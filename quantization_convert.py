from model_quantized.QuantLaneNetQuantized import QuantLaneNetQuantized
from data_utils.TuSimpleDataset import TuSimpleDataset
from checkpoint_info import get_best_model

from torch.quantization.observer import MovingAverageMinMaxObserver
import torch
import argparse
import tqdm
import os
import re

def convert(dataset_path, checkpoint_path, quantized_weights_path):
    # Get dataset
    test_set  = TuSimpleDataset(dir_path=dataset_path, train=False, evaluate=False, device='cpu', verbose=True, transform=None)
    test_loader = torch.utils.data.DataLoader(dataset=test_set, batch_size=16, shuffle=True)

    # Load model
    checkpoint = torch.load(os.path.join(checkpoint_path, f'checkpoint_{get_best_model(checkpoint_path)}.pth'), map_location='cpu')
    model = QuantLaneNetQuantized()
    model.load_state_dict(checkpoint['model_state'], strict=False)
    model.eval()

    # Get modules to fuse
    r = re.compile('(encoder_stage_[1-3].conv_[^.]+)|(.+_out\.[0-2])')
    conv_bn_relu_layers = set([m.group(0) for m in map(r.match, checkpoint['model_state']) if m])
    fuse_modules = [[f'{block}.{layer}' for layer in ('conv', 'bn', 'relu')] for block in conv_bn_relu_layers]

    # Prepare model for quantization
    model.qconfig = torch.quantization.QConfig(
        activation=MovingAverageMinMaxObserver.with_args(qscheme=torch.per_tensor_symmetric, dtype=torch.quint8),
        weight=MovingAverageMinMaxObserver.with_args(qscheme=torch.per_tensor_symmetric, dtype=torch.qint8)
    )
    model_fused = torch.quantization.fuse_modules(model, fuse_modules)
    model_prepared = torch.quantization.prepare(model_fused)

    # Calibrate model
    print('[INFO] Calibrating model...')
    for img, cls_true, offset_true, vertical_true in tqdm.tqdm(test_loader):
        model_prepared(img.float() / 255.0)

    # Convert final quantized model
    model_quantized = torch.quantization.convert(model_prepared)
    torch.save(model_quantized.state_dict(), quantized_weights_path)
    print(f'\n[INFO] Converted and saved quantized weights to {quantized_weights_path}')

def get_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument('--checkpoint_path',        type=str, default='./checkpoint')
    parser.add_argument('--dataset_path',           type=str, default='./dataset')
    parser.add_argument('--quantized_weights_path', type=str, default='./weights/quantized_weights_pertensor_symmetric.pth')

    args = parser.parse_args()

    args.checkpoint_path = os.path.abspath(args.checkpoint_path)
    args.dataset_path = os.path.abspath(args.dataset_path)
    args.quantized_weights_path = os.path.abspath(args.quantized_weights_path)

    return args

def main():
    args = get_arguments()

    convert(
        dataset_path=args.dataset_path,
        checkpoint_path=args.checkpoint_path,
        quantized_weights_path=args.quantized_weights_path
    )

if __name__ == '__main__':
    main()
