from model.LaneDetectionModel import LaneDetectionModel
from data_utils.TuSimpleDataset import TuSimpleDataset
from evaluation.TuSimpleEval import TuSimpleEval

import matplotlib.pyplot as plt
import numpy as np
import argparse
import torch
import glob
import tqdm

def get_best_model(checkpoint_path):
    max_acc = 0
    best_model = '000'

    for path in glob.glob(f'{checkpoint_path}/eval_*.pth'):
        loaded_eval = torch.load(path)
        if loaded_eval['test_acc'] > max_acc:
            max_acc = loaded_eval['test_acc']
            best_model = path[-7:-4]

    return best_model

def evaluate_best_model(dataset_path, checkpoint_path, with_offset=True, device='cpu'):
    checkpoint = torch.load(f'{checkpoint_path}/checkpoint_{get_best_model(checkpoint_path)}.pth', map_location=device)

    model = LaneDetectionModel()
    model.load_state_dict(checkpoint['model_state'], strict=False)
    model.eval()

    test_set = TuSimpleDataset(dir_path=dataset_path, train=False, evaluate=True, device=device, verbose=True)
    evaluation = TuSimpleEval()

    acc = 0
    fp  = 0
    fn  = 0

    if not with_offset:
        offset_dummy = torch.ones(size=(1, 4, 32, 64), dtype=torch.float32) * (3.5 / 8)  

    for img, cls_true, offset_true, vertical_true, gt in tqdm.tqdm(test_set):
        cls_pred, vertical_pred, offset_pred = model(img.unsqueeze(0).float() / 255)

        if with_offset:
            _acc, _fp, _fn = evaluation(cls_pred, vertical_pred, offset_pred, [gt])
        else:
            _acc, _fp, _fn = evaluation(cls_pred, vertical_pred, offset_dummy, [gt])

        acc += _acc
        fp  += _fp
        fn  += _fn

    print(
        f'\nEvaluate best model [{"WITH" if with_offset else "WITHOUT"}] offset:\n'
        f'\tacc = {acc / len(test_set)}\n'
        f'\tfp  = {fp  / len(test_set)}\n'
        f'\tfn  = {fn  / len(test_set)}\n'
    )

def show_training_curve(checkpoint_path):
    for paths in [glob.glob(f'{checkpoint_path}/loss_*.pth'), glob.glob(f'{checkpoint_path}/eval_*.pth')]:
        val_dict = dict()
        for name in torch.load(paths[0]):
            val_dict[name] = list()

        for path in sorted(paths):
            loaded_val = torch.load(path)
            for name in loaded_val:
                val_dict[name].append(loaded_val[name])

        num_keys = len(val_dict.keys())
        num_rows = int(np.ceil(num_keys / 2))
        fig, axs = plt.subplots(nrows=num_rows, ncols=2, figsize=(10, 3 * num_rows))
        
        for i, name in enumerate(val_dict):
            # Clip the values below 10
            axs[i // 2, i % 2].plot([min(10, x) for x in val_dict[name]])
            axs[i // 2, i % 2].set_title(name)

    plt.show()

def get_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument('--device',          type=str,   default='cpu')
    parser.add_argument('--dataset_path',    type=str,   default='./dataset')
    parser.add_argument('--checkpoint_path', type=str)

    # Show training curve
    parser.add_argument('--show_train_curve', dest='train_curve', action='store_true')
    parser.set_defaults(train_curve=False)

    # Evaluate best model
    parser.add_argument('--eval_best', dest='eval', action='store_true')
    parser.set_defaults(eval=False)

    # Use offset to evaluate
    parser.add_argument('--use_offset', dest='offset', action='store_true')
    parser.add_argument('--no_offset', dest='offset', action='store_false')
    parser.set_defaults(offset=True)

    args = parser.parse_args()

    if args.dataset_path[-1] in ['/', '\\']:
        args.dataset_path = args.dataset_path[:-1]

    if args.checkpoint_path[-1] in ['/', '\\']:
        args.checkpoint_path = args.checkpoint_path[:-1]

    return args

def main():
    args = get_arguments()

    best_model = get_best_model(checkpoint_path=args.checkpoint_path)
    checkpoint_eval = torch.load(f'{args.checkpoint_path}/eval_{best_model}.pth')

    print(f'Best checkpoint: epoch {int(best_model) + 1}')
    for name in checkpoint_eval:
        print(f'\t{name}: {checkpoint_eval[name]}')

    if args.eval:
        evaluate_best_model(dataset_path=args.dataset_path, checkpoint_path=args.checkpoint_path, with_offset=args.offset, device=args.device)

    if args.train_curve:
        show_training_curve(checkpoint_path=args.checkpoint_path)

if __name__ == '__main__':
    main()
    