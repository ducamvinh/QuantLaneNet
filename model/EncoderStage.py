from model.ConvBatchnormReLU import ConvBatchnormReLU
import torch

class EncoderStage(torch.nn.Module):

    def __init__(self, in_channels, mid_channels, out_channels, dropout=False):

        if in_channels > mid_channels:
            raise ValueError('in_channels is greater than mid_channels')

        super(EncoderStage, self).__init__()

        self.in_channels = in_channels
        self.mid_channels = mid_channels
        self.dropout = dropout

        self.conv_same_1 = ConvBatchnormReLU(in_channels=in_channels,  out_channels=mid_channels, padding=2, dilation=2)
        self.conv_same_2 = ConvBatchnormReLU(in_channels=mid_channels, out_channels=mid_channels, padding=2, dilation=2)
        self.conv_down   = ConvBatchnormReLU(in_channels=mid_channels, out_channels=out_channels, kernel_size=2, stride=2)

    def forward(self, x):
        # conv_same_1
        x = self.conv_same_1(x)
        if self.dropout:
            x = torch.nn.functional.dropout2d(x, p=0.2, training=self.training, inplace=False)

        # conv_same_2
        x = self.conv_same_2(x)
        if self.dropout:
            x = torch.nn.functional.dropout2d(x, p=0.2, training=self.training, inplace=False)

        # conv_down
        x = self.conv_down(x)
        if self.dropout:
            x = torch.nn.functional.dropout2d(x, p=0.2, training=self.training, inplace=False)

        return x
