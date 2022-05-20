import model_fpga.fpga_address_map as fpga_address_map
import numpy as np
import argparse
import time
import tqdm

def get_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument('--h2c_device', type=str, default='/dev/xdma0_h2c_0')
    parser.add_argument('--c2h_device', type=str, default='/dev/xdma0_c2h_0')
    return parser.parse_args()

def main():
    args = get_arguments()

    # Reset FPGA
    with open(args.h2c_device, 'wb') as f:
        f.seek(fpga_address_map.OFFSET_RESET)
        f.write(bytes([1]))

    runtime = []
    num_test = 100000
    x = np.random.randint(low=0, high=256, size=(256, 512, 3), dtype=np.ubyte)

    print(f'\n[INFO] Running inference {num_test:,d} times...')

    for _ in tqdm.tqdm(range(num_test)):
        # Write image to FPGA
        start_time = time.time()
        with open(args.h2c_device, 'wb') as f:
            f.seek(fpga_address_map.OFFSET_INPUT)
            x.tofile(file=f)

        # Wait for output to be valid
        valid = 0
        valid_ref = (1).to_bytes(length=8, byteorder='little')

        while valid != valid_ref:
            with open(args.c2h_device, 'rb') as f:
                f.seek(fpga_address_map.OFFSET_OVALID)
                valid = f.read(8)

        # Read output
        with open(args.c2h_device, 'rb') as f:
            f.seek(fpga_address_map.OFFSET_OUTPUT)
            hw_output = np.fromfile(file=f, dtype=np.ubyte, count=32*64) 

        runtime.append(time.time() - start_time)

    runtime = sum(runtime) / len(runtime)
    print(
        f'\n'
        f'[INFO] Results:\n'
        f'\t- Runtime   : {(runtime * 1e3):.2f} ms\n'
        f'\t- Framerate : {(1 / runtime):.2f} FPS\n'
    )

if __name__ == '__main__':
    main()
