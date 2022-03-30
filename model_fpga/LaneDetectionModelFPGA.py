import timeout_decorator
import numpy as np
import subprocess
import os

import fpga_utils.fpga_address_map as fpga_address_map

class LaneDetectionModelFPGA(object):

    def __init__(self, h2c_device='/dev/xdma0_h2c_0', c2h_device='/dev/xdma0_c2h_0', xdma_tool_dir='/home/ducamvinh/FPGA/dma_ip_drivers/XDMA/linux-kernel/tools'):
        self.h2c_device = h2c_device
        self.c2h_device = c2h_device
        self.xdma_tool_dir = xdma_tool_dir

    def reset(self):
        with open(self.h2c_device, 'wb') as f:
            f.seek(fpga_address_map.OFFSET_RESET)
            f.write(bytes([1]))

    def write_weights(self, weight_file_path):
        process = subprocess.run(
            args=[
                os.path.join(self.xdma_tool_dir, 'dma_to_device'),
                '--device', self.h2c_device,
                '--count', '1',
                '--address', f'0x{fpga_address_map.OFFSET_WEIGHT:x}',
                '--size', f'0x{(fpga_address_map.NUM_WEIGHTS * 2):x}',
                '--data infile', weight_file_path
            ],
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE
        )
        
        if process.stderr:
            raise Exception(process.stderr.decode('utf-8'))

    @timeout_decorator.timeout(seconds=1, timeout_exception=TimeoutError)
    def wait_valid(self):
        valid = 0
        valid_ref = (1).to_bytes(length=4, byteorder='little')

        while valid != valid_ref:
            with open(self.c2h_device, 'rb') as f:
                f.seek(fpga_address_map.OFFSET_OVALID)
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
            f.seek(fpga_address_map.OFFSET_INPUT)
            img.tofile(file=f)

        # Wait for valid signal with a timeout
        try:
            self.wait_valid()
        except TimeoutError:
            raise TimeoutError('Wait for output valid timed out')

        # Read output from FPGA
        with open(self.c2h_device, 'rb') as f:
            f.seek(fpga_address_map.OFFSET_OUTPUT)
            hw_output = np.fromfile(file=f, dtype=np.ubyte, count=32*64)

        # Post-process output and return
        hw_output = np.reshape(hw_output, (32, 64))
        if post_process:
            return self.post_process(hw_output)
        else:
            return hw_output
