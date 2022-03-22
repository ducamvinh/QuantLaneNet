import timeout_decorator
import numpy as np
import subprocess
import time
import os

class LaneDetectionModelFPGA(object):

    OFFSET_INPUT  = 0x0000_0000
    OFFSET_OUTPUT = 0x0006_0000
    OFFSET_OVALID = 0x0006_0800
    OFFSET_BUSY   = 0x0006_0804
    OFFSET_RESET  = 0x0006_0808
    OFFSET_WEIGHT = 0x0006_080C
    NUM_WEIGHTS   = 76976

    def __init__(self, h2c_device='/dev/xdma0_h2c_0', c2h_device='/dev/xdma0_c2h_0', xdma_tool_dir='/home/ducamvinh/FPGA/dma_ip_drivers/XDMA/linux-kernel/tools'):
        self.h2c_device = h2c_device
        self.c2h_device = c2h_device
        self.xdma_tool_dir = xdma_tool_dir

    def reset(self):
        with open(self.h2c_device, 'wb') as f:
            f.seek(LaneDetectionModelFPGA.OFFSET_RESET)
            f.write(bytes([1]))

    def write_weights(self, weight_file_path):
        process = subprocess.run(
            args=[
                os.path.join(self.xdma_tool_dir, 'dma_to_device'),
                '--device', self.h2c_device,
                '--count', '1',
                '--address', f'0x{LaneDetectionModelFPGA.OFFSET_WEIGHT:x}',
                '--size', f'0x{(LaneDetectionModelFPGA.NUM_WEIGHTS * 2):x}',
                '--data infile', weight_file_path
            ],
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE
        )
        
        if process.stderr:
            raise Exception(process.stderr.decode('utf-8'))

    @timeout_decorator.timeout(seconds=1, timeout_exception=TimeoutError)
    def wait_valid(self):
        valid = bytes([0])
        valid_ref = (1).to_bytes(length=4, byteorder='little')

        while valid != valid_ref:
            with open(self.c2h_device, 'rb') as f:
                f.seek(LaneDetectionModelFPGA.OFFSET_OVALID)
                valid = f.read(4)

    def post_process(self, hw_output):
        cls = np.zeros(shape=(32, 64, 4), dtype=np.float32)
        vertical = np.zeros(shape=(32, 1, 4), dtype=np.float32)

        for i in range(4):
            cls[:, :, i] = np.bitwise_and(np.right_shift(hw_output, i), 1)
            vertical[:, :, i] = np.sum(cls[:, :, i], axis=1)

        return cls, vertical

    def __call__(self, img, post_process=True):  # np.array((256, 512, 3)) -> (cls: np.array(32, 64, 4), vertical: np.array(32, 1, 4))
        # Write image to FPGA
        with open(self.h2c_device, 'wb') as f:
            f.seek(LaneDetectionModelFPGA.OFFSET_INPUT)
            img.tofile(file=f)

        # Wait for valid signal with a timeout
        try:
            self.wait_valid()
        except TimeoutError:
            raise TimeoutError('Wait for output valid timed out')

        # Read output from FPGA
        with open(self.c2h_device, 'rb') as f:
            f.seek(LaneDetectionModelFPGA.OFFSET_OUTPUT)
            hw_output = np.fromfile(file=f, dtype=np.ubyte, count=32*64)

        # Post-process output and return
        hw_output = np.reshape(hw_output, (32, 64))
        if post_process:
            return self.post_process(hw_output)
        else:
            return hw_output

def main():
    import random
    import glob
    import cv2

    img_paths = glob.glob('./dataset/tusimple/*/clips/*/*/*.jpg')
    img_idx = random.randint(0, len(img_paths))
    print(f'Image index: {img_idx}')

    # Load image
    img = cv2.imread(img_paths[img_idx])
    img = cv2.resize(img, (512, 256))
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # Initialize model
    model_fpga = LaneDetectionModelFPGA()
    model_fpga.reset()
    model_fpga.write_weights('/home/ducamvinh/FPGA/Lane_Detection_CNN_PCIe/Lane_Detection_CNN_PCIe.python/weights.bin')

    # Run image
    hw_output = model_fpga(img, post_process=False)
    
    # Print image to console
    for row in range(32):
        for col in range(64):
            val = hw_output[row, col]
            print(f'{hw_output[row, col]:2x}' if val else ' -', end='')
        print('\n', end='')

    # Display input image
    cv2.imshow('img', cv2.cvtColor(img, cv2.COLOR_RGB2BGR))
    cv2.waitKey(0)
    cv2.destroyAllWindows()

if __name__ == '__main__':
    main()
