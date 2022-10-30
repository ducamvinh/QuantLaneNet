from model.ConvBatchnormReLU import ConvBatchnormReLU
from model.EncoderStage import EncoderStage
import torch

class QuantLaneNet(torch.nn.Module):

    def __init__(self, input_size=(256, 512), num_lanes=4, dropout=True):

        super(QuantLaneNet, self).__init__()

        self.input_size = input_size
        self.output_size = (self.input_size[0] // 8, self.input_size[1] // 8)

        # Encoder stages
        self.encoder_stage_1 = EncoderStage(in_channels=3,  mid_channels=8,  out_channels=16, dropout=dropout)
        self.encoder_stage_2 = EncoderStage(in_channels=16, mid_channels=16, out_channels=32, dropout=dropout)
        self.encoder_stage_3 = EncoderStage(in_channels=32, mid_channels=32, out_channels=64, dropout=dropout)

        # Output branches
        self.cls_out = torch.nn.Sequential(
            ConvBatchnormReLU(in_channels=64, out_channels=32, padding=1),
            ConvBatchnormReLU(in_channels=32, out_channels=16, padding=1),
            ConvBatchnormReLU(in_channels=16, out_channels=8,  padding=1),
            torch.nn.Conv2d  (in_channels=8,  out_channels=num_lanes, kernel_size=3, padding=1, bias=True),
        )

        self.vertical_out = torch.nn.Sequential(
            ConvBatchnormReLU(in_channels=64, out_channels=32, kernel_size=(3, 2), stride=(1, 2), padding=(1, 0)),
            ConvBatchnormReLU(in_channels=32, out_channels=16, kernel_size=(3, 2), stride=(1, 2), padding=(1, 0)),
            ConvBatchnormReLU(in_channels=16, out_channels=8,  kernel_size=(3, 2), stride=(1, 2), padding=(1, 0)),
            torch.nn.Conv2d  (in_channels=8,  out_channels=num_lanes, kernel_size=(3, self.output_size[1] // 8), padding=(1, 0), bias=True),
            torch.nn.Sigmoid()
        )

        self.offset_out = torch.nn.Sequential(
            ConvBatchnormReLU(in_channels=64, out_channels=32, padding=1),
            ConvBatchnormReLU(in_channels=32, out_channels=16, padding=1),
            ConvBatchnormReLU(in_channels=16, out_channels=8,  padding=1),
            torch.nn.Conv2d  (in_channels=8,  out_channels=num_lanes, kernel_size=3, padding=1, bias=True),
            torch.nn.Sigmoid()
        )

    def forward(self, x):
        # Encoder stages
        x1 = self.encoder_stage_1(x)
        x2 = self.encoder_stage_2(x1)
        x3 = self.encoder_stage_3(x2)

        # Output branches
        cls = self.cls_out(x3)
        vertical = self.vertical_out(x3)
        offset = self.offset_out(x3)

        return cls, vertical, offset
