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

def main():
    sample = {"lanes": [[-2, -2, -2, -2, -2, -2, -2, 761, 708, 655, 600, 550, 501, 451, 409, 373, 337, 301, 264, 228, 192, 156, 120, 84, 48, 12, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2], [-2, -2, -2, -2, -2, -2, -2, -2, 780, 740, 708, 679, 652, 627, 609, 591, 573, 555, 539, 525, 511, 498, 484, 470, 456, 443, 429, 415, 401, 388, 374, 360, 347, 333, 319, 305, 292, 278, 264, 251, 237, 223, 209, 196, 182, 168, 154, 141, 127, 113, 100, 86, 72, 58, 45, -2], [-2, -2, -2, -2, -2, -2, -2, -2, 850, 802, 782, 765, 760, 754, 752, 750, 750, 754, 757, 761, 765, 769, 775, 782, 788, 794, 800, 807, 813, 819, 826, 832, 838, 845, 851, 857, 864, 870, 876, 883, 889, 895, 902, 908, 914, 921, 927, 933, 940, 946, 952, 959, 965, 971, 977, 984]], "h_samples": [160, 170, 180, 190, 200, 210, 220, 230, 240, 250, 260, 270, 280, 290, 300, 310, 320, 330, 340, 350, 360, 370, 380, 390, 400, 410, 420, 430, 440, 450, 460, 470, 480, 490, 500, 510, 520, 530, 540, 550, 560, 570, 580, 590, 600, 610, 620, 630, 640, 650, 660, 670, 680, 690, 700, 710], "raw_file": "clips/0531/1492637136370695779/20.jpg"}
    
    raw_file = 'D:/Storage/Deep Learning/PointCNN/dataset/tusimple/train_set/' + sample['raw_file']
    lanes = sample['lanes']
    h_samples = sample['h_samples']

    x = []
    y = []
    for i in range(len(lanes)):
        _x = []
        _y = []
        for __x, __y in zip(lanes[i], h_samples):
            if __x >= 0:
                _x.append(__x)
                _y.append(__y)
        x.append(_x if len(_x) >= 5 else [])
        y.append(_y if len(_y) >= 5 else [])

    img = cv2.imread(raw_file)

    transform = MyRandomRotate(max_angle=20)
    img, x, y = transform((img, x, y))

    transform = MyRandomShift(max_x=50, max_y=50)
    img, x, y = transform((img, x, y))

    transform = MyHorizontalFlip(p=0.5)
    img, x, y = transform((img, x, y))

    transform = MyRandomGrayScale(p=0.5)
    img, x, y = transform((img, x, y))
    
    for lane_x, lane_y in zip(x, y):
        for _x, _y in zip(lane_x, lane_y):
            cv2.circle(img=img, center=(_x, _y), radius=5, color=(0, 0, 255), thickness=-1)

    cv2.imshow('img', img)
    cv2.waitKey(0)
    cv2.destroyAllWindows()

if __name__ == '__main__':
    main()
    