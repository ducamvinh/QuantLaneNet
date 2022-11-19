from data_utils.data_transform import *
from evaluation.lane import LaneEval
import numpy as np
import torch
import csaps
import tqdm
import json
import glob
import cv2
import os

class TuSimpleDataset(torch.utils.data.Dataset):

    def __init__(self, input_size=(256, 512), dir_path='./dataset', train=False, evaluate=False, device='cpu', verbose=True, transform=None):
        super(TuSimpleDataset, self).__init__()

        if device not in ['cpu', 'cuda']:
            raise ValueError(f'Expected "cpu" or "cuda" device, instead got "{device}".')

        if evaluate == True and transform is not None:
            raise RuntimeError('Transformed dataset cannot return original ground truth.')

        self.input_size = input_size
        self.output_size = (self.input_size[0] // 8, self.input_size[1] // 8)
        self.num_lanes = 4
        self.device = device
        self.evaluate = evaluate
        self.transform = transform

        type_s = 'train_set' if train else 'test_set'
        label_paths = sorted(glob.glob(f'{dir_path}/tusimple/{type_s}/*.json'))
        if not label_paths:
            raise RuntimeError('Label paths not found')

        if self.evaluate:
            self.gt_list = []

        self.processed_list = []
        for path in label_paths:
            with open(path, 'r') as f:
                lines = f.readlines()

            if verbose:
                print(f'\n[INFO] Loading "{path.split(os.sep)[-1]}"...')
                lines = tqdm.tqdm(lines)
            
            for line in lines:
                data = json.loads(line)
                h_samples = data['h_samples']

                # Sort the list of lanes into theta_list
                theta_list = []
                for lane_idx, lane in enumerate(data['lanes']):
                    if sum([1 for x in lane if x >= 0]) >= 5:
                        theta_list.append((lane_idx, LaneEval.get_angle(np.array(lane[:len(h_samples)]), np.array(h_samples))))

                theta_list.sort(key=lambda x:x[1])
                try:
                    ego_left = max([idx for idx, (_, theta) in enumerate(theta_list) if theta < 0])
                except ValueError:
                    ego_left = -1   # A little expensive condition checking logic but is acceptable
                                    # because this only runs in __init__ and the entire function
                                    # runs quickly enough

                if ego_left < 1:
                    for _ in range(1 - ego_left):
                        theta_list.insert(0, (-1, 0))
                elif ego_left > 1:
                    for _ in range(ego_left - 1):
                        theta_list.pop(0)

                while len(theta_list) > self.num_lanes:
                    theta_list.pop()
                while len(theta_list) < self.num_lanes:
                    theta_list.append((-1, 0))

                if len(theta_list) != self.num_lanes:
                    raise ValueError(f'Expected {self.num_lanes} lanes, instead got {len(theta_list)}')

                # Create processed element for self.processed_list
                lanes    = []
                lanes_gt = []

                for idx, _ in theta_list:
                    if idx == -1:
                        lanes.append([-1 for _ in range(len(h_samples))])
                    else:
                        lanes.append([int(np.round(x / 1280.0 * self.input_size[1])) for x in data['lanes'][idx][:len(h_samples)]])
                        lanes_gt.append(data['lanes'][idx][:len(h_samples)])

                h_samples = [int(np.round(y / 720.0 * self.input_size[0])) for y in h_samples]
                raw_file = f'{dir_path}/tusimple/{type_s}/' + data['raw_file']

                self.processed_list.append(dict(lanes=lanes, h_samples=h_samples, raw_file=raw_file))

                if self.evaluate:
                    # lanes = [lane[:len(data['h_samples'])] for lane in data['lanes']]
                    self.gt_list.append(json.dumps(dict(lanes=lanes_gt, h_samples=data['h_samples'], raw_file=raw_file)))

        if verbose:
            print(f'\n[INFO] Load {type_s} done. Total data points: {len(self.processed_list)}.', end='\n\n')

    def __getitem__(self, index):
        sample = self.processed_list[index]

        # Load and process image
        img = cv2.imread(filename=sample['raw_file'])
        img = cv2.resize(src=img, dsize=self.input_size[::-1], interpolation=cv2.INTER_AREA)
        img = cv2.cvtColor(src=img, code=cv2.COLOR_BGR2RGB)

        # Collect lane points
        x = []
        y = []
        for i in range(self.num_lanes):
            _x = []
            _y = []
            for __x, __y in zip(sample['lanes'][i], sample['h_samples']):
                if __x >= 0:
                    _x.append(__x)
                    _y.append(__y)
            x.append(_x if len(_x) >= 7 else [])
            y.append(_y if len(_y) >= 7 else [])

        if self.transform is not None:
            img, x, y = self.transform((img, x, y))

        sampled_x = []
        sampled_y = []

        for i in range(self.num_lanes):
            if not x[i]:
                sampled_x.append([])
                sampled_y.append([])
                continue

            sp = csaps.CubicSmoothingSpline(np.array(y[i]), np.array(x[i]), smooth=0.85)
            ys = np.linspace(3.5, self.input_size[0] - 4.5, self.output_size[0])

            ys = ys[ys >= y[i][0]]
            ys = np.insert(ys, 0, ys[0] - 8)
            xs = sp(ys)

            if i == 0 or i == 1:
                xs_argmin = np.argmin(xs)
                if xs_argmin != xs.shape[0] - 1 and xs[xs_argmin] < 0:
                    xs = xs[:xs_argmin]
                    ys = ys[:xs_argmin]
            elif i == 2 or i == 3:
                xs_argmax = np.argmax(xs)
                if xs_argmax != xs.shape[0] - 1 and xs[xs_argmax] >= self.input_size[1]:
                    xs = xs[:xs_argmax]
                    ys = ys[:xs_argmax]

            ys = ys[xs < self.input_size[1]]
            xs = xs[xs < self.input_size[1]]

            ys = ys[xs >= 0]
            xs = xs[xs >= 0]

            sampled_x.append(np.round(xs).astype(np.int).tolist())
            sampled_y.append(np.round(ys).astype(np.int).tolist())

        # Create confidence and offset
        confidence = np.zeros(shape=(self.num_lanes, self.output_size[0], self.output_size[1]), dtype=np.float32)
        offset = np.zeros_like(confidence)
        vertical = np.zeros(shape=(self.num_lanes, self.output_size[0], 1), dtype=np.float32)

        for i in range(self.num_lanes):
            if not sampled_x[i]:
                continue

            xs = np.array(sampled_x[i])
            ys = np.array(sampled_y[i])

            ys_c = np.clip(ys // 8, 0, self.output_size[0] - 1)
            xs_c = np.clip(xs // 8, 0, self.output_size[1] - 1)

            confidence[i, ys_c, xs_c] = 1.
            vertical[i, ys_c, :] = 1.

            x_grid = np.arange(start=0, stop=self.input_size[1], step=8)
            x_grid = np.array([x_grid,] * self.output_size[0], dtype=np.float32)

            _offset = np.zeros(shape=self.output_size, dtype=np.float32)
            for j, (row, col) in enumerate(zip(ys_c, xs_c)):
                _offset[row, col] = xs[j]

            offset[i, ys_c, xs_c] = ((_offset - x_grid) / 8)[ys_c, xs_c]

        # Move to device
        img = torch.from_numpy(np.moveaxis(img, 2, 0)).to(self.device)
        confidence = torch.from_numpy(confidence).to(self.device)
        offset = torch.from_numpy(offset).to(self.device)
        vertical = torch.from_numpy(vertical).to(self.device)

        return_list = [img, confidence, offset, vertical]
        if self.evaluate:
            return_list.append(self.gt_list[index])
        return return_list

    def __len__(self):
        return len(self.processed_list)
