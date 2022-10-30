import torch

class ClassificationLoss(torch.nn.Module):

    def __init__(self, device):
        super(ClassificationLoss, self).__init__()
        self.device = device
        self.bce_loss = torch.nn.BCELoss()

    def forward(self, cls_pred, vertical_pred, cls_true, vertical_true):

        _cls_true = cls_true.clone()
        _cls_pred = torch.sigmoid(cls_pred.clone())
        _vertical_true = vertical_true.clone()
        _vertical_pred = vertical_pred.clone()

        loss = torch.tensor(0., device=self.device)
        for sam_idx in range(_cls_true.shape[0]):
            for cha_idx in range(_cls_true.shape[1]):
                __cls_pred = _cls_pred[sam_idx, cha_idx, :, :]
                __vertical_pred = _vertical_pred[sam_idx, cha_idx, :, :]
                confidence_pred = __cls_pred

                __cls_true = _cls_true[sam_idx, cha_idx, :, :]
                __vertical_true = _vertical_true[sam_idx, cha_idx, :, :]
                confidence_true = __cls_true

                for row_idx in range(confidence_true.shape[0]):
                    loss += self.bce_loss(confidence_pred[row_idx, :], confidence_true[row_idx, :])

        return loss / _cls_true.shape[0]

class VerticalLoss(torch.nn.Module):

    def __init__(self, device):
        super(VerticalLoss, self).__init__()
        self.device = device
        self.bce_loss = torch.nn.BCELoss()

    def forward(self, vertical_pred, vertical_true):
        loss = torch.tensor(0., device=self.device)

        for sam_idx in range(vertical_pred.shape[0]):
            for cha_idx in range(vertical_pred.shape[1]):
                loss += self.bce_loss(vertical_pred[sam_idx, cha_idx, :, 0], vertical_true[sam_idx, cha_idx, :, 0])

        return loss / vertical_pred.shape[0]

class OffsetLoss(torch.nn.Module):

    def __init__(self, device):
        super(OffsetLoss, self).__init__()
        self.device = device
        self.l1_loss = torch.nn.L1Loss()

    def forward(self, offset_pred, offset_true, cls_true, vertical_true):
        loss = torch.tensor(0., device=self.device)

        _offset_pred = offset_pred.clone()
        _offset_true = offset_true.clone()
        _cls_true = cls_true.clone()
        _vertical_true = vertical_true.clone()

        for sam_idx in range(_offset_pred.shape[0]):
            for cha_idx in range(_offset_pred.shape[1]):
                _confidence = _cls_true[sam_idx, cha_idx, :, :]
                confidence = torch.zeros_like(_confidence)
                confidence[range(_confidence.shape[0]), _confidence.argmax(1)] = 1

                vertical = _vertical_true[sam_idx, cha_idx, :, :]
                confidence[vertical.transpose(0, 1).squeeze() < 0.5] = 0

                __offset_true = _offset_true[sam_idx, cha_idx, :, :]
                __offset_pred = _offset_pred[sam_idx, cha_idx, :, :]

                __offset_true = __offset_true[confidence == 1]
                __offset_pred = __offset_pred[confidence == 1]

                if __offset_true.shape[0] > 0:
                    loss += self.l1_loss(__offset_pred, __offset_true)

        return loss / _offset_pred.shape[0]

def main():
    loss_funct = ClassificationLoss(device='cpu')

    cls_true = torch.ones(size=(4, 4, 32, 64), dtype=torch.float32)
    cls_pred = torch.zeros(size=(4, 4, 32, 64), dtype=torch.float32)
    vertical_true = torch.ones(size=(4, 4, 32, 1), dtype=torch.float32)
    vertical_pred = torch.zeros(size=(4, 4, 32, 1), dtype=torch.float32)

    loss = loss_funct(cls_true, vertical_true, cls_pred, vertical_pred)
    print(loss)

if __name__ == '__main__':
    main()
