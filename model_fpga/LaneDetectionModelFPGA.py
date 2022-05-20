import timeout_decorator
import numpy as np
import subprocess
import torch
import os

import model_fpga.fpga_address_map as fpga_address_map

class LaneDetectionModelFPGA(object):

    def __init__(self, h2c_device='/dev/xdma0_h2c_0', c2h_device='/dev/xdma0_c2h_0', xdma_tool_dir='~/xdma/tools'):
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
        valid_ref = (1).to_bytes(length=8, byteorder='little')

        while valid != valid_ref:
            with open(self.c2h_device, 'rb') as f:
                f.seek(fpga_address_map.OFFSET_OVALID)
                valid = f.read(8)

    def _inference(self, img):
        # Check image shape
        if img.shape == (3, 256, 512):
            img = np.moveaxis(img, 0, 2)
        elif img.shape != (256, 512, 3):
            raise ValueError(f'Unknown image shape: {img.shape}. Expected (3, 256, 512) or (256, 512, 3)')

        # Write image to FPGA
        with open(self.h2c_device, 'wb') as f:
            f.seek(fpga_address_map.OFFSET_INPUT)
            img.tofile(file=f)

        # Wait for valid signal with a timeout
        try:
            self.wait_valid()
        except TimeoutError:
            raise TimeoutError('Valid polling timed out')

        # Read output from FPGA
        with open(self.c2h_device, 'rb') as f:
            f.seek(fpga_address_map.OFFSET_OUTPUT)
            hw_output = np.fromfile(file=f, dtype=np.ubyte, count=32*64)

        return np.reshape(hw_output, (32, 64))

    @staticmethod
    def post_process(hw_output):
        if type(hw_output) == np.ndarray:
            hw_output = torch.from_numpy(hw_output)
        
        num_frame = hw_output.size(0)
        cls = torch.zeros(size=(num_frame, 4, 32, 64), dtype=torch.float32)
        vertical = torch.zeros(size=(num_frame, 4, 32, 1), dtype=torch.float32)

        for i in range(4):
            cls[:, i, :, :] = torch.bitwise_and(torch.bitwise_right_shift(hw_output, i), 1)
            vertical[:, i, :, 0] = torch.sum(cls[:, i, :, :], dim=2)

        return cls, vertical

    def __call__(self, img, post_process=True):
        # Convert to numpy if img is torch
        if type(img) == torch.Tensor:
            img = img.numpy()

        # Check image dtype
        if img.dtype not in (np.ubyte, np.uint8):
            raise TypeError(f'Expected np.ubyte or np.uint8, instead got {img.dtype}')

        # Run inference
        if img.ndim == 3:
            if img.shape not in ((256, 512, 3), (3, 256, 512)):
                raise ValueError(f'Unknown image shape: {img.shape}. Expected (3, 256, 512) or (256, 512, 3)')
            
            hw_output = np.expand_dims(self._inference(img), axis=0)
        else:
            if img.shape[1:] not in ((256, 512, 3), (3, 256, 512)):
                raise ValueError(f'Unknown image shape: {img.shape}. Expected (3, 256, 512) or (256, 512, 3)')
            
            num_frame = img.shape[0]
            hw_output = np.zeros(shape=(num_frame, 32, 64), dtype=np.ubyte)

            for i in range(num_frame):
                hw_output[i, :, :] = self._inference(img[i, :, :, :])

        # Convert output to torch
        hw_output = torch.from_numpy(hw_output)

        # Post-process and return
        if post_process:
            return self.post_process(hw_output)
        else:
            return hw_output
