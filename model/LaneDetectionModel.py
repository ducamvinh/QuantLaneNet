from model.ConvBatchnormReLU import ConvBatchnormReLU
from model.EncoderStage import EncoderStage
import torch

# class LaneDetectionModel(torch.nn.Module):

#     def __init__(self, input_size=(256, 512), num_lanes=4, dropout=True):
        
#         super(LaneDetectionModel, self).__init__()

#         self.input_size = input_size
#         self.output_size = (self.input_size[0] // 8, self.input_size[1] // 8)

#         # Encoder stages
#         self.encoder_stage_1 = EncoderStage(in_channels=3,  mid_channels=8,  out_channels=16, dropout=dropout)
#         self.encoder_stage_2 = EncoderStage(in_channels=16, mid_channels=16, out_channels=32, dropout=dropout)
#         self.encoder_stage_3 = EncoderStage(in_channels=32, mid_channels=32, out_channels=64, dropout=dropout)

#         # Output branches
#         self.cls_out = torch.nn.Sequential(
#             ConvBatchnormReLU(in_channels=64, out_channels=32, padding=1),
#             ConvBatchnormReLU(in_channels=32, out_channels=16, padding=1),
#             ConvBatchnormReLU(in_channels=16, out_channels=8,  padding=1),
#             torch.nn.Conv2d  (in_channels=8,  out_channels=num_lanes, kernel_size=3, padding=1, bias=True),
#         )

#         self.vertical_out = torch.nn.Sequential(
#             ConvBatchnormReLU(in_channels=64, out_channels=32, kernel_size=(3, 2), stride=(1, 2), padding=(1, 0)),
#             ConvBatchnormReLU(in_channels=32, out_channels=16, kernel_size=(3, 2), stride=(1, 2), padding=(1, 0)),
#             ConvBatchnormReLU(in_channels=16, out_channels=8,  kernel_size=(3, 2), stride=(1, 2), padding=(1, 0)),
#             torch.nn.Conv2d  (in_channels=8,  out_channels=num_lanes, kernel_size=(3, self.output_size[1] // 8), padding=(1, 0), bias=True),
#             torch.nn.Sigmoid()
#         )

#         self.offset_out = torch.nn.Sequential(
#             ConvBatchnormReLU(in_channels=64, out_channels=32, padding=1),
#             ConvBatchnormReLU(in_channels=32, out_channels=16, padding=1),
#             ConvBatchnormReLU(in_channels=16, out_channels=8,  padding=1),
#             torch.nn.Conv2d  (in_channels=8,  out_channels=num_lanes, kernel_size=3, padding=1, bias=True),
#             torch.nn.Sigmoid()
#         )

#     def forward(self, x):
#         # Encoder stages
#         x1 = self.encoder_stage_1(x)
#         x2 = self.encoder_stage_2(x1)
#         x3 = self.encoder_stage_3(x2)

#         # Output branches
#         cls = self.cls_out(x3)
#         vertical = self.vertical_out(x3)
#         offset = self.offset_out(x3)

#         return cls, vertical, offset
        
class LaneDetectionModel(torch.nn.Module):

    def __init__(self, input_size=(256, 512), num_lanes=4, use_aux=False, size='small', dropout=True):
        if size not in ['small', 'large']:
            raise ValueError(f'Expected size "small" or "large", instead got {size}.')
        
        super(LaneDetectionModel, self).__init__()

        self.input_size = input_size
        self.output_size = (self.input_size[0] // 8, self.input_size[1] // 8)
        self.use_aux = use_aux
        channel_factor = 1 if size == 'small' else 2

        self.encoder_stage_1 = EncoderStage(in_channels=3,                     mid_channels=(8  * channel_factor), out_channels=(16 * channel_factor), dropout=dropout)
        self.encoder_stage_2 = EncoderStage(in_channels=(16 * channel_factor), mid_channels=(16 * channel_factor), out_channels=(32 * channel_factor), dropout=dropout)
        self.encoder_stage_3 = EncoderStage(in_channels=(32 * channel_factor), mid_channels=(32 * channel_factor), out_channels=(64 * channel_factor), dropout=dropout)

        if self.use_aux:
            aux_channel_factor = 1 if size == 'small' else 2

            self.aux_header_1 = torch.nn.Sequential(
                ConvBatchnormReLU(in_channels=(16 * channel_factor),      out_channels=(64 * aux_channel_factor), padding=1),
                ConvBatchnormReLU(in_channels=(64 * aux_channel_factor),  out_channels=(64 * aux_channel_factor), padding=1),
                ConvBatchnormReLU(in_channels=(64 * aux_channel_factor),  out_channels=(64 * aux_channel_factor), padding=1),
                ConvBatchnormReLU(in_channels=(64 * aux_channel_factor),  out_channels=(64 * aux_channel_factor), padding=1)
            )

            self.aux_header_2 = torch.nn.Sequential(
                ConvBatchnormReLU(in_channels=(32 * channel_factor),      out_channels=(64 * aux_channel_factor), padding=1),
                ConvBatchnormReLU(in_channels=(64 * aux_channel_factor),  out_channels=(64 * aux_channel_factor), padding=1),
                ConvBatchnormReLU(in_channels=(64 * aux_channel_factor),  out_channels=(64 * aux_channel_factor), padding=1)
            )

            self.aux_header_3 = torch.nn.Sequential(
                ConvBatchnormReLU(in_channels=(64 * channel_factor), out_channels=(64 * aux_channel_factor), padding=1),
                ConvBatchnormReLU(in_channels=(64 * aux_channel_factor),  out_channels=(64 * aux_channel_factor), padding=1)
            )

            self.aux_combine = torch.nn.Sequential(
                ConvBatchnormReLU(in_channels=(192 * aux_channel_factor), out_channels=(128 * aux_channel_factor), padding=2, dilation=2),
                ConvBatchnormReLU(in_channels=(128 * aux_channel_factor), out_channels=(64  * aux_channel_factor), padding=2, dilation=2),
                ConvBatchnormReLU(in_channels=(64  * aux_channel_factor), out_channels=(64  * aux_channel_factor), padding=2, dilation=2),
                ConvBatchnormReLU(in_channels=(64  * aux_channel_factor), out_channels=(32  * aux_channel_factor), padding=4, dilation=4),
                torch.nn.Conv2d(  in_channels=(32  * aux_channel_factor), out_channels=num_lanes + 1, kernel_size=1, bias=True)
            )

        self.cls_out = torch.nn.Sequential(
            ConvBatchnormReLU(in_channels=(64 * channel_factor), out_channels=(32 * channel_factor), padding=1),
            ConvBatchnormReLU(in_channels=(32 * channel_factor), out_channels=(16 * channel_factor), padding=1),
            ConvBatchnormReLU(in_channels=(16 * channel_factor), out_channels=(8  * channel_factor), padding=1),
            torch.nn.Conv2d(  in_channels=(8  * channel_factor), out_channels=num_lanes, kernel_size=3, padding=1, bias=True),
            # torch.nn.Sigmoid()
        )

        self.vertical_out = torch.nn.Sequential(
            ConvBatchnormReLU(in_channels=(64 * channel_factor), out_channels=(32 * channel_factor), kernel_size=(3, 2), stride=(1, 2), padding=(1, 0)),
            ConvBatchnormReLU(in_channels=(32 * channel_factor), out_channels=(16 * channel_factor), kernel_size=(3, 2), stride=(1, 2), padding=(1, 0)),
            ConvBatchnormReLU(in_channels=(16 * channel_factor), out_channels=(8  * channel_factor), kernel_size=(3, 2), stride=(1, 2), padding=(1, 0)),
            torch.nn.Conv2d(  in_channels=(8  * channel_factor), out_channels=num_lanes, kernel_size=(3, self.output_size[1] // 8), padding=(1, 0), bias=True),
            torch.nn.Sigmoid()
        )

        # self.vertical_out = torch.nn.Sequential(
        #     ConvBatchnormReLU(in_channels=64, out_channels=32,        kernel_size=(1, 2), stride=(1, 2)),
        #     ConvBatchnormReLU(in_channels=32, out_channels=16,        kernel_size=(1, 2), stride=(1, 2)),
        #     ConvBatchnormReLU(in_channels=16, out_channels=8,         kernel_size=(1, 2), stride=(1, 2)),
        #     torch.nn.Conv2d(  in_channels=8,  out_channels=num_lanes, kernel_size=(1, self.output_size[1] // 8)),
        #     torch.nn.Sigmoid()
        # )

        # self.cls_out = torch.nn.Sequential(
        #     ConvBatchnormReLU(in_channels=64, out_channels=32,        padding=1),
        #     ConvBatchnormReLU(in_channels=32, out_channels=16,        padding=1),
        #     torch.nn.Conv2d(  in_channels=16, out_channels=num_lanes, kernel_size=(3, 4), padding=(1, 2))
        # )

        self.offset_out = torch.nn.Sequential(
            ConvBatchnormReLU(in_channels=(64 * channel_factor), out_channels=(32 * channel_factor), padding=1),
            ConvBatchnormReLU(in_channels=(32 * channel_factor), out_channels=(16 * channel_factor), padding=1),
            ConvBatchnormReLU(in_channels=(16 * channel_factor), out_channels=(8  * channel_factor), padding=1),
            torch.nn.Conv2d(  in_channels=(8  * channel_factor), out_channels=num_lanes, kernel_size=3, padding=1, bias=True),
            torch.nn.Sigmoid()
        )

    def forward(self, x):
        # Encoder
        x1 = self.encoder_stage_1(x)
        x2 = self.encoder_stage_2(x1)
        x3 = self.encoder_stage_3(x2)

        # x4 = self.cls_out(x3)
        # cls = x4[:, :, :, :-1]
        # vertical = x4[:, :, :, -1].unsqueeze(3)

        cls = self.cls_out(x3)
        vertical = self.vertical_out(x3)
        offset = self.offset_out(x3)

        if self.use_aux:
            x1 = self.aux_header_1(x1)
            x2 = self.aux_header_2(x2)
            x2 = torch.nn.functional.interpolate(input=x2, scale_factor=2, mode='bilinear', align_corners=False)
            x3 = self.aux_header_3(x3)
            x3 = torch.nn.functional.interpolate(input=x3, scale_factor=4, mode='bilinear', align_corners=False)

            aux_seg = torch.cat(tensors=[x1, x2, x3], dim=1)
            aux_seg = self.aux_combine(aux_seg)

            return cls, vertical, offset, aux_seg
        else:
            return cls, vertical, offset
