import numpy as np
import csaps
import cv2

def visualize(img, cls, vertical, offset, show_grid=False, num_lanes=4, input_size=(256, 512)):
    output_size = (input_size[0] // 8, input_size[1] // 8)
    colors = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0), (0, 255, 255)]

    img = np.moveaxis(img.detach().clone().cpu().squeeze().numpy(), 0, 2)
    cls = cls.detach().clone().cpu().numpy().squeeze()
    vertical = vertical.detach().clone().cpu().numpy()
    offset = offset.detach().clone().cpu().numpy().squeeze()

    if vertical.ndim == 4:
        vertical = vertical.squeeze(0)

    for i in range(num_lanes):
        x_grid = np.arange(start=0, stop=input_size[1], step=8)
        x_grid = np.array([x_grid,] * output_size[0])
        x_grid = x_grid.astype(np.float32) + offset[i, :, :] * 8

        y_grid = np.arange(start=0, stop=input_size[0], step=8)
        y_grid = y_grid.astype(np.float32) + 3.5
        y_grid = np.array([y_grid,] * output_size[1]).transpose()

        _cls = cls[i, :, :]
        __cls = np.zeros_like(_cls)
        __cls[range(_cls.shape[0]), _cls.argmax(1)] = 1

        _vertical = vertical[i, :, :]
        __cls[_vertical.transpose().squeeze() < 0.5, :] = 0

        for x, y in zip(x_grid[__cls == 1], y_grid[__cls == 1]):
            cv2.circle(img=img, center=(x, y), radius=3, color=colors[i], thickness=-1)

    if show_grid:
        for i in range(7, input_size[0], 8):
            cv2.line(img=img, pt1=(0, i), pt2=(input_size[1], i), color=(0, 0, 0), thickness=1)
        for i in range(7, input_size[1], 8):
            cv2.line(img=img, pt1=(i, 0), pt2=(i, input_size[0]), color=(0, 0, 0), thickness=1)

    return img

def get_og_format(cls, vertical, offset, h_samples, input_size=(256, 512)):

    output_size = (input_size[0] // 8, input_size[1] // 8)
    
    _cls = cls.detach().clone().squeeze().cpu().numpy()
    _vertical = vertical.detach().clone().cpu().numpy()
    _offset = offset.detach().clone().cpu().squeeze().numpy()

    if _vertical.ndim == 4:
        _vertical = _vertical.squeeze(0)

    lanes = []

    for j in range(_cls.shape[0]):
        x_grid = np.arange(start=0, stop=input_size[1], step=8)
        x_grid = np.array([x_grid,] * output_size[0])
        x_grid = x_grid.astype(np.float32) + _offset[j, :, :] * 8
        # x_grid = x_grid.astype(np.float32) + 3.5

        y_grid = np.arange(start=0, stop=input_size[0], step=8)
        y_grid = y_grid.astype(np.float32) + 3.5
        y_grid = np.array([y_grid,] * output_size[1]).transpose()

        __cls = _cls[j, :, :]
        ___cls = np.zeros_like(__cls)

        ___cls[range(__cls.shape[0]), __cls.argmax(1)] = 1

        __vertical = _vertical[j, :, :]
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
    colors = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0), (0, 255, 255)]
    img = np.moveaxis(img.detach().clone().cpu().squeeze().numpy(), 0, 2)
    img = cv2.resize(src=img, dsize=(1280, 720), interpolation=cv2.INTER_LINEAR)

    for i, lane in enumerate(lanes):

        for x, y in zip(lane, h_samples):
            if x >= 0:
                cv2.circle(img=img, center=(x, y), radius=5, color=colors[i], thickness=-1)

    return img
    