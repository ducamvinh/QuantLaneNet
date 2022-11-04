from model_fpga.QuantLaneNetFPGA import QuantLaneNetFPGA
from model_quantized.QuantLaneNetQuantized import QuantLaneNetQuantized
from model.QuantLaneNet import QuantLaneNet
from model_quantized.quantize_utils import convert_quantized_model
from checkpoint_info import get_best_model
from data_utils.TuSimpleDataset import TuSimpleDataset
from data_utils.data_utils import visualize
from evaluation.TuSimpleEval import TuSimpleEval

import numpy as np
import argparse
import random
import torch
import tqdm
import time
import glob
import cv2
import os

def test_image(model, img_path, use_offset, device):
    print('[INFO] Input image should be cropped to composition similar to TuSimple dataset for best accuracy')
    if device == 'cuda' and not isinstance(model, QuantLaneNetFPGA):
        print('[INFO] PyTorch model running on CUDA is lazily initialized so runtime of an image may be longer than the runtime average of thousands of images')
    print(f'[INFO] Image path: {img_path}')
    id = os.path.basename(img_path)

    # Load image
    img = cv2.imread(img_path)
    img = cv2.resize(img, (512, 256))
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # Run inference
    if isinstance(model, QuantLaneNetFPGA):
        start_time = time.perf_counter()
        fpga_output = model(img, post_process=False)
        print(f'[INFO] Process time: {((time.perf_counter() - start_time) * 1e3):.2f} ms')
        cls, vertical = model.post_process(fpga_output)
    else:
        _input = (torch.from_numpy(np.moveaxis(img, 2, 0)).unsqueeze(0).float() / 255.0).to(device)
        start_time = time.perf_counter()
        cls, vertical, offset = model(_input)

        if device == 'cuda':
            torch.cuda.synchronize()
        print(f'[INFO] Process time: {((time.perf_counter() - start_time) * 1e3):.2f} ms')

    # Display output
    if isinstance(model, QuantLaneNetFPGA) or not use_offset:
        offset = np.ones(shape=(32, 64, 4), dtype=np.float32) * (3.5 / 8)

    img = visualize(img, cls, vertical, offset)
    img = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
    cv2.imshow(id, img)
    cv2.waitKey(0)
    cv2.destroyAllWindows()

def test_random_image(model, dataset_path, use_offset, device):
    # Get random image
    img_paths = glob.glob(os.path.join(dataset_path, 'tusimple/*/clips/*/*/*.jpg'))
    if len(img_paths) == 0:
        raise FileNotFoundError(f'No images found in {dataset_path}')

    img_idx = random.randint(0, len(img_paths))
    test_image(model, img_paths[img_idx], use_offset, device)

def test_video(model, video_path, use_offset, device):
    print('[INFO] Input video should be cropped to composition similar to TuSimple dataset for best accuracy')
    print(f'[INFO] Video path: {video_path}')
    id = os.path.basename(video_path)

    # Video stream
    cap = cv2.VideoCapture(video_path)
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    width  = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))

    offset_dummy = np.ones(shape=(32, 64, 4), dtype=np.float32) * (3.5 / 8)
    iterator = tqdm.tqdm(range(int(cap.get(cv2.CAP_PROP_FRAME_COUNT))))

    runtime = []

    for _ in iterator:
        ret, frame = cap.read()
        if not ret:
            break

        # frame = frame[(height // 3):, :, :]

        # Prepare model input
        img = cv2.cvtColor(cv2.resize(frame, (512, 256)), cv2.COLOR_BGR2RGB)

        # Run inference
        if isinstance(model, QuantLaneNetFPGA):
            start_time = time.perf_counter()
            fpga_output = model(img, post_process=False)
            runtime.append(time.perf_counter() - start_time)
            cls, vertical = model.post_process(fpga_output)
        else:
            _input = (torch.from_numpy(np.moveaxis(img, 2, 0)).unsqueeze(0).float() / 255.0).to(device)
            start_time = time.perf_counter()
            cls, vertical, offset = model(_input)

            if device == 'cuda':
                torch.cuda.synchronize()
            runtime.append(time.perf_counter() - start_time)

        if isinstance(model, QuantLaneNetFPGA) or not use_offset:
            offset = offset_dummy

        # Update video
        img = visualize(img, cls, vertical, offset)
        img = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
        cv2.imshow(id, img)
        cv2.waitKey(1)

    cap.release()
    cv2.destroyAllWindows()

    runtime = sum(runtime) / len(runtime)
    print(
        f'\n'
        f'[INFO] Results:\n'
        f'    - Average model runtime   : {(runtime * 1e3):.2f} ms\n'
        f'    - Average model framerate : {(1 / runtime):.2f} FPS\n'
        f'    - Actual video framerate  : {(iterator.format_dict["n"] / iterator.format_dict["elapsed"]):.2f} FPS\n'
    )

def test_evaluate(model, dataset_path, use_offset, device):
    if isinstance(model, QuantLaneNetFPGA):
        model_type = 'fpga'
        device = 'cpu'
    elif isinstance(model, QuantLaneNetQuantized):
        model_type = 'quantized'
    else:
        model_type = 'software'

    test_set = TuSimpleDataset(dir_path=dataset_path, train=False, evaluate=True, device=device, verbose=True)
    evaluation = TuSimpleEval()

    acc = 0
    fp  = 0
    fn  = 0

    print('[INFO] Evaluating model...')

    iterator = tqdm.tqdm(test_set)
    stop_idx = len(test_set) - 1

    for i, (img, cls_true, offset_true, vertical_true, gt) in enumerate(iterator):
        if model_type == 'fpga':
            cls_pred, vertical_pred = model(img, post_process=True)
        else:
            cls_pred, vertical_pred, offset_pred = model(img.unsqueeze(0).float() / 255.0)

        if model_type == 'fpga' or not use_offset:
            offset_dummy = torch.ones_like(cls_pred) * (3.5 /8)
            _acc, _fp, _fn = evaluation(cls_pred, vertical_pred, offset_dummy, [gt])
        else:
            _acc, _fp, _fn = evaluation(cls_pred, vertical_pred, offset_pred, [gt])

        acc += _acc
        fp  += _fp
        fn  += _fn

        if i % 10 == 0 or i == stop_idx:
            iterator.set_postfix({
                'acc': acc / (i + 1) * 100,
                'fp' : fp  / (i + 1) * 100,
                'fn' : fn  / (i + 1) * 100
            })

    print(
        f'\n[INFO] Evaluated {model_type} model{"" if model_type == "fpga" else (" [WITH] offset" if use_offset else " [WITHOUT] offset")}:\n'
        f'    - acc = {(acc / len(test_set) * 100):.4f}%\n'
        f'    - fp  = {(fp  / len(test_set) * 100):.4f}%\n'
        f'    - fn  = {(fn  / len(test_set) * 100):.4f}%\n'
    )

def get_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument('--model',                  type=str, default='software',     choices=('software', 'quantized', 'fpga'))
    parser.add_argument('--test_mode',              type=str, default='random_image', choices=('image', 'random_image', 'video', 'evaluate'))
    parser.add_argument('--device',                 type=str, default='cpu',          choices=('cuda', 'cpu'))
    parser.add_argument('--dataset_path',           type=str, default='./dataset')
    parser.add_argument('--checkpoint_path',        type=str, default='./checkpoint')
    parser.add_argument('--quantized_weights_path', type=str, default='./weights/quantized_weights_pertensor_symmetric.pth')
    parser.add_argument('--weights_bin_path',       type=str, default='./weights/fpga_weights.bin')
    parser.add_argument('--image_path',             type=str, default='./dataset/tusimple/train_set/clips/0313-1/37920/20.jpg')
    parser.add_argument('--video_path',             type=str, default='./test_videos/video_0.mp4')
    parser.add_argument('--h2c_device',             type=str, default='/dev/xdma0_h2c_0')
    parser.add_argument('--c2h_device',             type=str, default='/dev/xdma0_c2h_0')

    # Use offset to evaluate software model
    parser.add_argument('--use_offset', dest='offset', action='store_true', help='Use offset output to evaluate software model')
    parser.add_argument('--no_offset', dest='offset', action='store_false', help="Don't offset output to evaluate software model")
    parser.set_defaults(offset=False)

    args = parser.parse_args()

    args.dataset_path           = os.path.abspath(args.dataset_path)
    args.checkpoint_path        = os.path.abspath(args.checkpoint_path)
    args.weights_bin_path       = os.path.abspath(args.weights_bin_path)
    args.video_path             = os.path.abspath(args.video_path)
    args.quantized_weights_path = os.path.abspath(args.quantized_weights_path)

    if args.model == 'fpga' and args.offset:
        raise ValueError("FPGA model doesn't use offset, please use --no_offset option or leave offset options empty")
    elif args.model == 'quantized' and args.device == 'cuda':
        raise NotImplementedError("PyTorch quantization doesn't support CUDA inference as of the making of this project (PyTorch 1.11.0)")

    return args

def main():
    args = get_arguments()

    # Initialize model
    print('[INFO] Initializing model...')
    if args.model == 'software':
        checkpoint_path = os.path.join(args.checkpoint_path, f'checkpoint_{get_best_model(args.checkpoint_path)}.pth')
        print(
            f'    - Type       : Software\n'
            f'    - Platform   : {args.device.upper()}\n'
            f'    - Checkpoint : {checkpoint_path}\n'
        )

        checkpoint = torch.load(checkpoint_path, map_location=args.device)
        model = QuantLaneNet().to(args.device)
        model.load_state_dict(checkpoint['model_state'], strict=False)
        model.eval()
    elif args.model == 'quantized':
        print(
            f'    - Type     : Quantized\n'
            f'    - Platform : {args.device.upper()}\n'
            f'    - Weights  : {args.quantized_weights_path}\n'
        )

        model = QuantLaneNetQuantized().to(args.device)
        model = convert_quantized_model(model)
        model.load_state_dict(torch.load(args.quantized_weights_path, map_location=args.device))
    else:
        print(
            f'    - Type           : FPGA\n'
            f'    - Kernel modules : {args.h2c_device}\n'
            f'                       {args.c2h_device}\n'
            f'    - Weights binary : {args.weights_bin_path}\n'
        )

        model = QuantLaneNetFPGA(h2c_device=args.h2c_device, c2h_device=args.c2h_device)
        model.reset()
        model.write_weights(args.weights_bin_path)

    print(f'[INFO] Running test: {args.test_mode}')
    if args.test_mode == 'random_image':
        test_random_image(model, args.dataset_path, args.offset, args.device)
    elif args.test_mode == 'image':
        test_image(model, args.image_path, args.offset, args.device)
    elif args.test_mode == 'video':
        test_video(model, args.video_path, args.offset, args.device)
    elif args.test_mode == 'evaluate':
        test_evaluate(model, args.dataset_path, args.offset, args.device)

if __name__ == '__main__':
    main()
