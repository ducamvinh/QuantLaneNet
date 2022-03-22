from loss.loss import *

class LossDict(object):
    def __init__(self, device):
        self.loss_dict = dict(
            name=[
                'cls_loss',
                'vertical_loss',
                'offset_loss'
            ],
            op=[
                ClassificationLoss(device=device),
                VerticalLoss(device=device),
                OffsetLoss(device=device)
            ],
            src=[
                ('cls_pred', 'vertical_pred', 'cls_true', 'vertical_true'),
                ('vertical_pred', 'vertical_true'),
                ('offset_pred', 'offset_true', 'cls_true', 'vertical_true')
            ]
        )
