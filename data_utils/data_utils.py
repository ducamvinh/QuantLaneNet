import numpy as np
import torch
import csaps
import cv2

def img_convert(img):
    if type(img) == torch.Tensor:
        img = img.detach().clone().cpu().squeeze().numpy()
    if type(img) != np.ndarray:
        raise TypeError(f'Expected img type {torch.Tensor} or {np.ndarray}, instead got {type(img)}')

    if img.shape == (256, 512, 3):
        return img
    if img.shape == (3, 256, 512):
        return np.moveaxis(img, 0, 2)
    raise ValueError(f'Expected img shape (256, 512, 3) or (3, 256, 3), instead got {img.shape}')

def cls_convert(cls):
    if type(cls) == torch.Tensor:
        cls = cls.detach().clone().cpu().squeeze().numpy()
    if type(cls) != np.ndarray:
        raise TypeError(f'Expected cls type {torch.Tensor} or {np.ndarray}, instead got {type(cls)}')

    if cls.shape == (32, 64, 4):
        return cls
    if cls.shape == (4, 32, 64):
        return np.moveaxis(cls, 0, 2)
    raise ValueError(f'Expected cls shape (32, 64, 4) or (4, 32, 64), instead got {cls.shape}')

def offset_convert(offset):
    try:
        return cls_convert(offset)
    except (ValueError, TypeError) as e:
        message = str(e)
        raise type(e)(f'{message.replace("cls", "offset")}' if 'cls' in message else message)

def vertical_convert(vertical):
    if type(vertical) == torch.Tensor:
        vertical = vertical.detach().clone().cpu().numpy()
    if type(vertical) != np.ndarray:
        raise TypeError(f'Expected vertical type {torch.Tensor} or {np.ndarray}, instead got {type(vertical)}')

    if vertical.shape == (32, 1, 4):
        return vertical
    if vertical.shape == (1, 32, 1, 4):
        return vertical.squeeze()
    if vertical.shape == (4, 32, 1):
        return np.moveaxis(vertical, 0, 2)
    if vertical.shape == (1, 4, 32, 1):
        return np.moveaxis(vertical.squeeze(0), 0, 2)
    raise ValueError(f'Expected vertical shape (32, 1, 4) or (1, 32, 1, 4) or (4, 32, 1) or (1, 4, 32, 1), instead got {vertical.shape}')

def visualize(img, cls, vertical, offset, show_grid=False, num_lanes=4, input_size=(256, 512)):
    # Convert inputs into correct format and shape
    img = img_convert(img)
    cls = cls_convert(cls)
    offset = offset_convert(offset)
    vertical = vertical_convert(vertical)

    output_size = (input_size[0] // 8, input_size[1] // 8)
    colors = ((255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0), (0, 255, 255))

    for i in range(num_lanes):
        x_grid = np.arange(start=0, stop=input_size[1], step=8)
        x_grid = np.array([x_grid,] * output_size[0])
        x_grid = x_grid.astype(np.float32) + offset[:, :, i] * 8

        y_grid = np.arange(start=0, stop=input_size[0], step=8)
        y_grid = y_grid.astype(np.float32) + 3.5
        y_grid = np.array([y_grid,] * output_size[1]).transpose()

        _cls = cls[:, :, i]
        __cls = np.zeros_like(_cls)
        __cls[range(_cls.shape[0]), _cls.argmax(1)] = 1

        _vertical = vertical[:, :, i]
        __cls[_vertical.transpose().squeeze() < 0.5, :] = 0

        for x, y in zip(x_grid[__cls == 1].astype(np.int), y_grid[__cls == 1].astype(np.int)):
            cv2.circle(img=img, center=(x, y), radius=3, color=colors[i], thickness=-1)

    if show_grid:
        for i in range(7, input_size[0], 8):
            cv2.line(img=img, pt1=(0, i), pt2=(input_size[1], i), color=(0, 0, 0), thickness=1)
        for i in range(7, input_size[1], 8):
            cv2.line(img=img, pt1=(i, 0), pt2=(i, input_size[0]), color=(0, 0, 0), thickness=1)

    return img

def get_og_format(cls, vertical, offset, h_samples, input_size=(256, 512)):

    _cls = cls_convert(cls)
    _offset = offset_convert(offset)
    _vertical = vertical_convert(vertical)

    output_size = (input_size[0] // 8, input_size[1] // 8)
    lanes = []

    for j in range(_cls.shape[2]):
        x_grid = np.arange(start=0, stop=input_size[1], step=8)
        x_grid = np.array([x_grid,] * output_size[0])
        x_grid = x_grid.astype(np.float32) + _offset[:, :, j] * 8
        # x_grid = x_grid.astype(np.float32) + 3.5

        y_grid = np.arange(start=0, stop=input_size[0], step=8)
        y_grid = y_grid.astype(np.float32) + 3.5
        y_grid = np.array([y_grid,] * output_size[1]).transpose()

        __cls = _cls[:, :, j]
        ___cls = np.zeros_like(__cls)

        ___cls[range(__cls.shape[0]), __cls.argmax(1)] = 1

        __vertical = _vertical[:, :, j]
        ___cls[__vertical.transpose().squeeze() < 0.5, :] = 0

        x = x_grid[___cls == 1] / input_size[1] * 1280
        y = y_grid[___cls == 1] / input_size[0] * 720

        if y.shape[0] < 2:
            continue

        sp = csaps.CubicSmoothingSpline(y, x, smooth=0.0001)
        ys = np.array(h_samples)
        xs = np.round(sp(ys)).astype(np.int)

        xs[ys < y.min()] = -2
        xs[ys > y.max()] = -2
        lanes.append(xs.tolist())

    return lanes

def visualize_og_format(img, lanes, h_samples):
    colors = ((255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0), (0, 255, 255))
    img = np.moveaxis(img.detach().clone().cpu().squeeze().numpy(), 0, 2)
    img = cv2.resize(src=img, dsize=(1280, 720), interpolation=cv2.INTER_LINEAR)

    for i, lane in enumerate(lanes):

        for x, y in zip(lane, h_samples):
            if x >= 0:
                cv2.circle(img=img, center=(x, y), radius=5, color=colors[i], thickness=-1)

    return img
