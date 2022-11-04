from model.QuantLaneNet import QuantLaneNet
import torch
import os

if os.name == 'nt':
    # Windows
    torch.backends.quantized.engine = 'fbgemm'
else:
    # Linux
    torch.backends.quantized.engine = 'qnnpack'

class QuantLaneNetQuantized(QuantLaneNet):

    def __init__(self, input_size=(256, 512), num_lanes=4, dropout=True):
        super(QuantLaneNetQuantized, self).__init__(input_size=input_size, num_lanes=num_lanes, dropout=dropout)
        self.quant    = torch.quantization.QuantStub()
        self.dequant1 = torch.quantization.DeQuantStub()
        self.dequant2 = torch.quantization.DeQuantStub()
        self.dequant3 = torch.quantization.DeQuantStub()

    def forward(self, x):
        # Quant
        x = self.quant(x)

        # Encoder stages
        x1 = self.encoder_stage_1(x)
        x2 = self.encoder_stage_2(x1)
        x3 = self.encoder_stage_3(x2)

        # Output branches
        cls = self.cls_out(x3)
        vertical = self.vertical_out(x3)
        offset = self.offset_out(x3)

        # Dequant
        return self.dequant1(cls), self.dequant2(vertical), self.dequant3(offset)
