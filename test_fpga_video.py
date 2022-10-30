from model_fpga.QuantLaneNetFPGA import QuantLaneNetFPGA
import model_fpga.fpga_address_map as fpga_address_map
from data_utils.data_utils import visualize

import numpy as np
import argparse
import time
import tqdm
import cv2
import os

def get_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument('--weights_bin_path', type=str, default='./weights/fpga_weights.bin')
    parser.add_argument('--video_path',       type=str, default='./test_videos/video_0.mp4')
    parser.add_argument('--h2c_device',       type=str, default='/dev/xdma0_h2c_0')
    parser.add_argument('--c2h_device',       type=str, default='/dev/xdma0_c2h_0')

    args = parser.parse_args()

    args.weights_bin_path = os.path.abspath(args.weights_bin_path)
    args.video_path = os.path.abspath(args.video_path)

    return args

def main():
    args = get_arguments()

    # Print info
    print(
        f'[INFO] Initializing model...\n'
        f'    - Kernel modules : {args.h2c_device}\n'
        f'                       {args.c2h_device}\n'
        f'    - Weights binary : {args.weights_bin_path}\n'
        f'\n'
        f'[INFO] Input video should be cropped to composition similar to TuSimple dataset for best accuracy\n'
        f'[INFO] Video path: {args.video_path}'
    )
    id = os.path.basename(args.video_path)

    # Reset FPGA
    with open(args.h2c_device, 'wb') as f:
        f.seek(fpga_address_map.OFFSET_RESET)
        f.write(bytes([1]))

    # Write weights
    with open(args.h2c_device, 'wb') as f:
        f.seek(fpga_address_map.OFFSET_WEIGHT)
        np.fromfile(file=args.weights_bin_path, dtype=np.ubyte).tofile(file=f)

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
        start_time = time.perf_counter()
        with open(args.h2c_device, 'wb') as f:
            f.seek(fpga_address_map.OFFSET_INPUT)
            img.tofile(file=f)

        # Wait for output to be valid
        while True:
            with open(args.c2h_device, 'rb') as f:
                f.seek(fpga_address_map.OFFSET_OVALID)
                if f.read(8) == b'\x01\x00\x00\x00\x00\x00\x00\x00':  # 64-bit "00000...001" little endian
                    break

        # Read output
        with open(args.c2h_device, 'rb') as f:
            f.seek(fpga_address_map.OFFSET_OUTPUT)
            hw_output = np.fromfile(file=f, dtype=np.ubyte, count=32*64)

        runtime.append(time.perf_counter() - start_time)

        # Post-process output and draw dots
        cls, vertical = QuantLaneNetFPGA.post_process(np.expand_dims(np.reshape(hw_output, (32, 64)), 0))
        vis = visualize(img, cls, vertical, offset_dummy)
        vis = cv2.cvtColor(vis, cv2.COLOR_RGB2BGR)

        # Update video window
        cv2.imshow(id, vis)
        cv2.waitKey(1)

    cap.release()
    cv2.destroyAllWindows()

    # Print info
    runtime = sum(runtime) / len(runtime)
    print(
        f'\n'
        f'    Average model runtime   : {(runtime * 1e3):.2f} ms\n'
        f'    Average model framerate : {(1 / runtime):.2f} FPS\n'
        f'    Actual video framerate  : {(iterator.format_dict["n"] / iterator.format_dict["elapsed"]):.2f} FPS\n'
    )

if __name__ == '__main__':
    main()
