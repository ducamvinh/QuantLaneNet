from model_fpga.LaneDetectionModelFPGA import LaneDetectionModelFPGA
import fpga_utils.fpga_address_map as fpga_address_map
from data_utils.data_utils import visualize

import numpy as np
import subprocess
import argparse
import time
import tqdm
import cv2
import os

def get_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument('--weights_bin_path', type=str, default='fpga_weights.bin')
    parser.add_argument('--video_path',       type=str, default='test_videos/video_0.mp4')
    parser.add_argument('--h2c_device',       type=str, default='/dev/xdma0_h2c_0')
    parser.add_argument('--c2h_device',       type=str, default='/dev/xdma0_c2h_0')
    parser.add_argument('--xdma_tool_dir',    type=str, default='~/xdma/tools')

    args = parser.parse_args()

    args.weights_bin_path = os.path.abspath(args.weights_bin_path)
    args.video_path = os.path.abspath(args.video_path)
    args.xdma_tool_dir = os.path.abspath(args.xdma_tool_dir)

    return args

def main():
    args = get_arguments()

    # Reset FPGA
    with open(args.h2c_device, 'wb') as f:
        f.seek(fpga_address_map.OFFSET_RESET)
        f.write(bytes([1]))

    # Write weights
    process = subprocess.run(
        args=[
            os.path.join(args.xdma_tool_dir, 'dma_to_device'),
            '--device', args.h2c_device,
            '--count', '1',
            '--address', f'0x{fpga_address_map.OFFSET_WEIGHT:x}',
            '--size', f'0x{(fpga_address_map.NUM_WEIGHTS * 2):x}',
            '--data infile', args.weights_bin_path
        ],
        stdout=subprocess.PIPE, 
        stderr=subprocess.PIPE
    )
    
    if process.stderr:
        raise Exception(process.stderr.decode('utf-8'))

    # Video stream
    cap = cv2.VideoCapture(args.video_path)
    
    # Other stuff
    offset_dummy = np.ones(shape=(32, 64, 4), dtype=np.float32) * (3.5 / 8)
    iterator = tqdm.tqdm(range(int(cap.get(cv2.CAP_PROP_FRAME_COUNT))))
    runtime = []

    for _ in iterator:
        ret, frame = cap.read()
        if not ret:
            break

        # Prepare model input
        img = cv2.cvtColor(cv2.resize(frame, (512, 256)), cv2.COLOR_BGR2RGB)

        # Write image to FPGA
        start_time = time.time()
        with open(args.h2c_device, 'wb') as f:
            f.seek(fpga_address_map.OFFSET_INPUT)
            img.tofile(file=f)

        # Wait for output to be valid
        valid = 0
        valid_ref = (1).to_bytes(length=4, byteorder='little')

        while valid != valid_ref:
            with open(args.c2h_device, 'rb') as f:
                f.seek(fpga_address_map.OFFSET_OVALID)
                valid = f.read(4)

        # Read output
        with open(args.c2h_device, 'rb') as f:
            f.seek(fpga_address_map.OFFSET_OUTPUT)
            hw_output = np.fromfile(file=f, dtype=np.ubyte, count=32*64) 

        runtime.append(time.time() - start_time)

        # Post-process output and draw dots
        cls, vertical = LaneDetectionModelFPGA.post_process(np.expand_dims(np.reshape(hw_output, (32, 64)), 0))
        vis = visualize(img, cls, vertical, offset_dummy)
        vis = cv2.cvtColor(vis, cv2.COLOR_RGB2BGR)

        # Update video window
        cv2.imshow('video', vis)
        cv2.waitKey(1)

    cap.release()
    cv2.destroyAllWindows()

    # Print info
    runtime = sum(runtime) / len(runtime)
    print(
        f'\n'
        f'\tAverage model runtime   : {(runtime * 1e3):.2f} ms\n'
        f'\tAverage model framerate : {(1 / runtime):.2f} FPS\n'
        f'\tActual video framerate  : {(iterator.format_dict["n"] / iterator.format_dict["elapsed"]):.2f} FPS\n'
    )

if __name__ == '__main__':
    main()
