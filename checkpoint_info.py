from model.QuantLaneNet import QuantLaneNet
from data_utils.TuSimpleDataset import TuSimpleDataset
from evaluation.TuSimpleEval import TuSimpleEval

import matplotlib.pyplot as plt
import numpy as np
import argparse
import torch
import glob
import tqdm
import os

def get_best_model(checkpoint_path):
    max_acc = 0
    best_model = '000'

    for path in glob.glob(os.path.join(checkpoint_path, 'eval_*.pth')):
        loaded_eval = torch.load(path)
        if loaded_eval['test_acc'] > max_acc:
            max_acc = loaded_eval['test_acc']
            best_model = path[-7:-4]

    return best_model

def evaluate_best_model(dataset_path, checkpoint_path, with_offset=True, device='cuda'):
    best_model = get_best_model(checkpoint_path)
    checkpoint = torch.load(os.path.join(checkpoint_path, f'checkpoint_{best_model}.pth'), map_location=device)

    model = QuantLaneNet().to(device)
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
        f'\nEvaluate best model (epoch {int(best_model) + 1}) [{"WITH" if with_offset else "WITHOUT"}] offset:\n'
        f'    acc = {acc / len(test_set)}\n'
        f'    fp  = {fp  / len(test_set)}\n'
        f'    fn  = {fn  / len(test_set)}\n'
    )

def show_training_curves(checkpoint_path):
    for paths in [glob.glob(os.path.join(checkpoint_path, 'loss_*.pth')), glob.glob(os.path.join(checkpoint_path, 'eval_*.pth'))]:
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
    parser.add_argument('--show_train_curves', dest='show_train_curves', action='store_true')
    parser.set_defaults(show_train_curves=False)

    # Evaluate best model
    parser.add_argument('--eval_best', dest='eval_best', action='store_true')
    parser.set_defaults(eval_best=False)

    # Use offset to evaluate
    parser.add_argument('--use_offset', dest='offset', action='store_true')
    parser.add_argument('--no_offset', dest='offset', action='store_false')
    parser.set_defaults(offset=True)

    # Verbose
    parser.add_argument('--verbose', dest='verbose', action='store_true')
    parser.set_defaults(verbose=False)

    args = parser.parse_args()

    if args.dataset_path[-1] in ['/', '\\']:
        args.dataset_path = args.dataset_path[:-1]

    if args.checkpoint_path[-1] in ['/', '\\']:
        args.checkpoint_path = args.checkpoint_path[:-1]

    return args

def main():
    args = get_arguments()

    if args.verbose:
        best_model = get_best_model(checkpoint_path=args.checkpoint_path)
        checkpoint_eval = torch.load(f'{args.checkpoint_path}/eval_{best_model}.pth')

        print(f'Best checkpoint: epoch {int(best_model) + 1}')
        for name in checkpoint_eval:
            print(f'    {name}: {checkpoint_eval[name]}')

    if args.eval_best:
        evaluate_best_model(dataset_path=args.dataset_path, checkpoint_path=args.checkpoint_path, with_offset=args.offset, device=args.device)

    if args.show_train_curves:
        show_training_curves(checkpoint_path=args.checkpoint_path)

if __name__ == '__main__':
    main()
