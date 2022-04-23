from torch.quantization.observer import MovingAverageMinMaxObserver
import torch
import re

def convert_quantized_model(model):
    model.eval()

    # Get modules to fuse
    r = re.compile('(encoder_stage_[1-3].conv_[^.]+)|(.+_out\.[0-2])')
    conv_bn_relu_layers = set([m.group(0) for m in map(r.match, [name for name, _ in model.named_modules()]) if m])
    fuse_modules = [[f'{block}.{layer}' for layer in ('conv', 'bn', 'relu')] for block in conv_bn_relu_layers]

    # Prepare model for quantization
    model.qconfig = torch.quantization.QConfig(
        activation=MovingAverageMinMaxObserver.with_args(qscheme=torch.per_tensor_symmetric, dtype=torch.quint8),
        weight=MovingAverageMinMaxObserver.with_args(qscheme=torch.per_tensor_symmetric, dtype=torch.qint8)
    )
    model_fused = torch.quantization.fuse_modules(model, fuse_modules)
    model_prepared = torch.quantization.prepare(model_fused)
    model_prepared(torch.rand(size=(1, 3, 256, 512), device=('cuda' if next(model.parameters()).is_cuda else 'cpu')))

    return torch.quantization.convert(model_prepared)
