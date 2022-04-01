from model_fpga.LaneDetectionModelFPGA import LaneDetectionModelFPGA
from model.LaneDetectionModel import LaneDetectionModel
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

def test_image(model, img_path, use_offset):
    print('[WARNING] Input image should be cropped to composition similar to TuSimple dataset for best accuracy')
    print(f'\tImage path: {img_path}')

    # Load image
    img = cv2.imread(img_path)
    img = cv2.resize(img, (512, 256))
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # Run inference
    if isinstance(model, LaneDetectionModel):
        start_time = time.time()
        cls, vertical, offset = model(torch.from_numpy(np.moveaxis(img, 2, 0)).unsqueeze(0).float() / 255.0)
        print(f'\tProcess time: {((time.time() - start_time) * 1e3):.2f} ms')
    else:
        start_time = time.time()
        fpga_output = model(img, post_process=False)
        print(f'\tProcess time: {((time.time() - start_time) * 1e3):.2f} ms')
        cls, vertical = model.post_process(fpga_output)

    # Display output
    if isinstance(model, LaneDetectionModelFPGA) or not use_offset:
        offset = np.ones(shape=(32, 64, 4), dtype=np.float32) * (3.5 / 8)

    img = visualize(img, cls, vertical, offset)
    img = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
    cv2.imshow(img_path, img)
    cv2.waitKey(0)
    cv2.destroyAllWindows()

def test_random_image(model, dataset_path, use_offset):
    # Get random image
    img_paths = glob.glob(os.path.join(dataset_path, 'tusimple/*/clips/*/*/*.jpg'))
    if len(img_paths) == 0:
        raise FileNotFoundError(f'No images found in {dataset_path}')

    img_idx = random.randint(0, len(img_paths))
    print(f'\tRandom index: {img_idx}')
    test_image(model, img_paths[img_idx], use_offset)

def test_video(model, video_path, use_offset, device):
    print('[WARNING] Input video should be cropped to composition similar to TuSimple dataset for best accuracy')
    print(f'Video path: {video_path}')

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
        if isinstance(model, LaneDetectionModel):
            start_time = time.time()
            cls, vertical, offset = model(torch.from_numpy(np.moveaxis(img, 2, 0)).to(device).unsqueeze(0).float() / 255.0)
            runtime.append(time.time() - start_time)
        else:
            start_time = time.time()
            fpga_output = model(img, post_process=False)
            runtime.append(time.time() - start_time)
            cls, vertical = model.post_process(fpga_output)

        if isinstance(model, LaneDetectionModelFPGA) or not use_offset:
            offset = offset_dummy

        # Update video
        img = visualize(img, cls, vertical, offset)
        img = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
        cv2.imshow(video_path, img)
        cv2.waitKey(1)
        
    cap.release()
    cv2.destroyAllWindows()

    runtime = sum(runtime) / len(runtime)
    print(
        f'\n'
        f'\tAverage model runtime   : {(runtime * 1e3):.2f} ms\n'
        f'\tAverage model framerate : {(1 / runtime):.2f} FPS\n'
        f'\tActual video framerate  : {(iterator.format_dict["n"] / iterator.format_dict["elapsed"]):.2f} FPS\n'
    )

def test_evaluate(model, dataset_path, use_offset, device):
    if isinstance(model, LaneDetectionModel):
        model_type = 'software'
    else:
        model_type = 'fpga'
        device = 'cpu'

    test_set = TuSimpleDataset(dir_path=dataset_path, train=False, evaluate=True, device=device, verbose=True)
    evaluation = TuSimpleEval()

    acc = 0
    fp  = 0
    fn  = 0

    iterator = tqdm.tqdm(test_set)
    for i, (img, cls_true, offset_true, vertical_true, gt) in enumerate(iterator):
        if model_type == 'software':
            cls_pred, vertical_pred, offset_pred = model(img.unsqueeze(0).float() / 255.0)        
        else:
            cls_pred, vertical_pred = model(img, post_process=True)

        if model_type == 'fpga' or not use_offset:
            offset_dummy = torch.ones_like(cls_pred) * (3.5 /8)
            _acc, _fp, _fn = evaluation(cls_pred, vertical_pred, offset_dummy, [gt])
        else:
            _acc, _fp, _fn = evaluation(cls_pred, vertical_pred, offset_pred, [gt])

        acc += _acc
        fp  += _fp
        fn  += _fn

        postfix = {
            'acc': acc / (i + 1) * 100,
            'fp' : fp  / (i + 1) * 100,
            'fn' : fn  / (i + 1) * 100
        }

        iterator.set_postfix(postfix)

    print(
        f'\nEvaluated {model_type} model{"" if model_type == "fpga" else (" [WITH] offset" if use_offset else " [WITHOUT] offset")}:\n'
        f'\tacc = {(acc / len(test_set) * 100):.4f}%\n'
        f'\tfp  = {(fp  / len(test_set) * 100):.4f}%\n'
        f'\tfn  = {(fn  / len(test_set) * 100):.4f}%\n'
    )

def get_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument('--model',            type=str, default='software',     choices=('software', 'fpga'))
    parser.add_argument('--test_mode',        type=str, default='random_image', choices=('image', 'random_image', 'video', 'evaluate'))
    parser.add_argument('--dataset_path',     type=str, default='dataset')
    parser.add_argument('--checkpoint_path',  type=str, default='checkpoint')
    parser.add_argument('--device',           type=str, default='cpu',          choices=('cuda', 'cpu'))
    parser.add_argument('--weights_bin_path', type=str, default='weights.bin')
    parser.add_argument('--image_path',       type=str, default='dataset/tusimple/train_set/clips/0313-1/37920/20.jpg')
    parser.add_argument('--video_path',       type=str, default='test_videos/video_0.mp4')
    parser.add_argument('--h2c_device',       type=str, default='/dev/xdma0_h2c_0')
    parser.add_argument('--c2h_device',       type=str, default='/dev/xdma0_c2h_0')
    parser.add_argument('--xdma_tool_dir',    type=str, default='~/xdma/tools')

    # Use offset to evaluate software model
    parser.add_argument('--use_offset', dest='offset', action='store_true', help='Use offset output to evaluate software model')
    parser.add_argument('--no_offset', dest='offset', action='store_false', help="Don't offset output to evaluate software model")
    parser.set_defaults(offset=False)

    args = parser.parse_args()
    args.dataset_path = os.path.abspath(args.dataset_path)
    args.checkpoint_path = os.path.abspath(args.checkpoint_path)
    args.weights_bin_path = os.path.abspath(args.weights_bin_path)
    args.video_path = os.path.abspath(args.video_path)
    args.xdma_tool_dir = os.path.abspath(args.xdma_tool_dir)

    if args.model == 'fpga' and args.offset:
        raise ValueError("FPGA model doesn't use offset, please use --no_offset option or leave offset options empty")

    return args

def main():
    args = get_arguments()

    # Initialize model
    print('[INFO] Initializing model...')
    if args.model == 'software':
        checkpoint_path = os.path.join(args.checkpoint_path, f'checkpoint_{get_best_model(args.checkpoint_path)}.pth')
        print(
            f'\t- Type       : Software\n'
            f'\t- Platform   : {args.device.upper()}\n'
            f'\t- Checkpoint : {checkpoint_path}\n'
        )

        checkpoint = torch.load(checkpoint_path, map_location=args.device)
        model = LaneDetectionModel().to(args.device)
        model.load_state_dict(checkpoint['model_state'], strict=False)
        model.eval()
    else:
        print(
            f'\t- Type           : FPGA\n'
            f'\t- XDMA tools     : {args.xdma_tool_dir}\n'
            f'\t- Kernel modules : {args.h2c_device}, {args.c2h_device}\n'
            f'\t- Weights binary : {args.weights_bin_path}\n'
        )

        model = LaneDetectionModelFPGA(h2c_device=args.h2c_device, c2h_device=args.c2h_device, xdma_tool_dir=args.xdma_tool_dir)
        model.reset()
        model.write_weights(args.weights_bin_path)

    print(f'\n[INFO] Running test: {args.test_mode}...')
    if args.test_mode == 'random_image':
        test_random_image(model, args.dataset_path, args.offset)
    elif args.test_mode == 'image':
        test_image(model, args.image_path, args.offset)
    elif args.test_mode == 'video':
        test_video(model, args.video_path, args.offset, args.device)
    elif args.test_mode == 'evaluate':
        test_evaluate(model, args.dataset_path, args.offset, args.device)

if __name__ == '__main__':
    main()
