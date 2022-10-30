import numpy as np
import cv2

def affine_translation(sample, M):
    img, x, y = sample
    height, width = img.shape[:-1] if img.shape[-1] == 3 else img.shape[1:]
    translated_img = cv2.warpAffine(src=img, M=M, dsize=(width, height))

    translated_x = []
    translated_y = []

    for lane_x, lane_y in zip(x, y):
        if lane_x:
            translated_lane_x = []
            translated_lane_y = []

            for _x, _y in zip(lane_x, lane_y):
                point = np.array([[_x], [_y], [1]])
                translated_point = np.dot(M, point).transpose().squeeze()
                translated_point = np.round(translated_point).astype(np.int)

                if 0 <= translated_point[0] < width and 0 <= translated_point[1] < height:
                    translated_lane_x.append(translated_point[0])
                    translated_lane_y.append(translated_point[1])

            translated_x.append(translated_lane_x)
            translated_y.append(translated_lane_y)
        else:
            translated_x.append([])
            translated_y.append([])

    return (translated_img, translated_x, translated_y)

class MyRandomRotate(object):

    def __init__(self, max_angle):
        self.max_angle = max_angle

    def __call__(self, sample):
        img = sample[0]

        angle = np.random.uniform(low=0, high=self.max_angle)
        angle = angle * (1 if np.random.rand() < 0.5 else -1)
        height, width = img.shape[:-1]

        M = cv2.getRotationMatrix2D(center=(width // 2, height // 2), angle=angle, scale=1.0)
        return affine_translation(sample=sample, M=M)

class MyRandomShift(object):

    def __init__(self, max_x, max_y):
        self.max_x = max_x
        self.max_y = max_y

    def __call__(self, sample):
        tx = np.random.uniform(low=-self.max_x, high=self.max_x)
        ty = np.random.uniform(low=-self.max_y, high=self.max_y)

        tx = tx * (1 if np.random.rand() < 0.5 else -1)
        ty = ty * (1 if np.random.rand() < 0.5 else -1)

        M = np.float32([[1, 0, tx], [0, 1, ty]])
        return affine_translation(sample=sample, M=M)

class MyHorizontalFlip(object):

    def __init__(self, p):
        if p > 1:
            raise ValueError('p is greater than 1.')
        elif p < 0:
            raise ValueError('p is less than 0.')
        self.p = p

    def __call__(self, sample):
        prob = 1 if np.random.rand() < self.p else 0

        if prob:
            img = sample[0]
            height, width = img.shape[:-1]

            M = np.float32([[-1, 0, width - 1], [0, 1, 0]])
            return affine_translation(sample=sample, M=M)
        else:
            return sample

class MyRandomGrayScale(object):

    def __init__(self, p):
        if p > 1:
            raise ValueError('p is greater than 1.')
        elif p < 0:
            raise ValueError('p is less than 0.')
        self.p = p

    def __call__(self, sample):
        prob = 1 if np.random.rand() < self.p else 0

        if prob:
            img, x, y = sample
            img = cv2.cvtColor(src=img, code=cv2.COLOR_RGB2GRAY)
            img = np.stack((img,) * 3, axis=-1)
            return (img, x, y)
        else:
            return sample
