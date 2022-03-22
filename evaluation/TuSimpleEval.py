from data_utils.data_utils import get_og_format
from evaluation.lane import LaneEval
import json

class TuSimpleEval(object):

    def __init__(self, input_size=(256, 512)):
        self.input_size = input_size
        self.output_size = (self.input_size[0] // 8, self.input_size[1] // 8)

    def __call__(self, cls, vertical, offset, gt):
        if cls.dim() != 4 or vertical.dim() != 4:
            raise ValueError(f'Invalid shapes. cls: {cls.shape}. vertical: {vertical.shape}.')
        if len(gt) != cls.shape[0]:
            raise ValueError(f'Number of samples and gt are mismatched. Samples: {cls.shape[0]}. Gt: {len(gt)}.')

        _cls = cls.detach().clone().cpu()
        _vertical = vertical.detach().clone().cpu()
        _offset = offset.detach().clone().cpu()

        acc = 0
        fp  = 0
        fn  = 0

        for i in range(_cls.shape[0]):

            _gt = json.loads(gt[i])
            lanes = get_og_format(_cls[i, :, :, :], _vertical[i, :, :, :], _offset[i, :, :, :],
                    _gt['h_samples'], self.input_size)

            _acc, _fp, _fn = LaneEval.bench(lanes, _gt['lanes'], _gt['h_samples'], 10)

            acc += _acc
            fp  += _fp
            fn  += _fn

        return acc / _cls.shape[0], fp / _cls.shape[0], fn / _cls.shape[0]
