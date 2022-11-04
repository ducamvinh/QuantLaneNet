from model.QuantLaneNet import QuantLaneNet
from evaluation.TuSimpleEval import TuSimpleEval
from data_utils.TuSimpleDataset import TuSimpleDataset
from loss.loss_dict import LossDict
from data_utils.data_transform import *

import torchvision
import torch
import argparse
import tqdm
import glob
import time
import os

def train(device='cpu', dataset_path='./dataset', checkpoint_path='./checkpoint', loader_workers=0, epochs=100, batch_size=4, lr=0.001, lr_reduce_gamma=0.7, lr_reduce_step=30, use_transform=False, use_dropout=False):

    def cuda_synchronize(device):
        if device == 'cuda':
            torch.cuda.synchronize()

    # Transformations
    if use_transform:
        composed = torchvision.transforms.Compose([
            # MyRandomRotate(max_angle=10),
            MyRandomShift(max_x=10, max_y=10),
            # MyRandomGrayScale(p=0.5),
            MyHorizontalFlip(p=0.5)
        ])
    else:
        composed = None

    # Get dataset
    train_set = TuSimpleDataset(dir_path=dataset_path, train=True,  evaluate=False, device=device, verbose=True,  transform=composed)
    val_set   = TuSimpleDataset(dir_path=dataset_path, train=True,  evaluate=True,  device=device, verbose=False, transform=None)
    test_set  = TuSimpleDataset(dir_path=dataset_path, train=False, evaluate=True,  device=device, verbose=True,  transform=None)

    # Get dataloaders
    train_loader = torch.utils.data.DataLoader(dataset=train_set, batch_size=batch_size, shuffle=True,  num_workers=loader_workers)
    val_loader   = torch.utils.data.DataLoader(dataset=val_set,   batch_size=batch_size, shuffle=False, num_workers=loader_workers)
    test_loader  = torch.utils.data.DataLoader(dataset=test_set,  batch_size=batch_size, shuffle=False, num_workers=loader_workers)

    # Initialize model
    model = QuantLaneNet(dropout=use_dropout).to(device)

    # Get optimizer and scheduler
    optimizer = torch.optim.Adam(params=model.parameters(), lr=lr)
    scheduler = torch.optim.lr_scheduler.StepLR(optimizer=optimizer, step_size=lr_reduce_step, gamma=lr_reduce_gamma, verbose=(True if epochs > lr_reduce_step else False))

    # Loss dict
    loss_dict = LossDict(device)
    loss_dict = loss_dict.loss_dict

    # Evaluation
    evaluation = TuSimpleEval()

    # Load checkpoint
    checkpoint_list = sorted(glob.glob(f'{checkpoint_path}/checkpoint_*.pth'))
    if checkpoint_list:
        loaded_checkpoint = torch.load(checkpoint_list[-1])
        start_epoch = loaded_checkpoint['epoch'] + 1

        if start_epoch >= epochs:
            raise ValueError(f'start_epoch ({start_epoch + 1}) is greater than num_epochs ({epochs}).')

        model.load_state_dict(loaded_checkpoint['model_state'])
        optimizer.load_state_dict(loaded_checkpoint['optim_state'])
        scheduler.load_state_dict(loaded_checkpoint['scheduler_state'])
    else:
        start_epoch = 0

    print('\n############ Training start ############')
    for epoch in range(start_epoch, epochs):
        print(f'\nEpoch {epoch + 1}/{epochs}:')

        running_data_dict = dict(total_loss=0)
        for name in loss_dict['name']:
            running_data_dict[name] = 0

        # TQDM progress bar
        progress_bar = tqdm.tqdm(train_loader)

        # Training loop
        for step, (img, cls_true, offset_true, vertical_true) in enumerate(progress_bar):
            model.train()

            # Forward pass
            optimizer.zero_grad()
            cls_pred, vertical_pred, offset_pred = model(img.float() / 255)

            results = dict(
                cls_pred=cls_pred, cls_true=cls_true,
                offset_pred=offset_pred, offset_true=offset_true,
                vertical_pred=vertical_pred, vertical_true=vertical_true,
            )

            # Calculate loss
            loss = 0
            for i, name in enumerate(loss_dict['name']):
                data_src = loss_dict['src'][i]
                datas = [results[src] for src in data_src]
                cur_loss = loss_dict['op'][i](*datas)

                loss += cur_loss
                running_data_dict[name] += cur_loss.detach().clone().cpu().item()
            running_data_dict['total_loss'] += loss.detach().clone().cpu().item()

            # Backward pass
            loss.backward()
            optimizer.step()

            # Verbose
            postfix = dict()
            for name in running_data_dict:
                postfix[name] = running_data_dict[name] / (step + 1)

            progress_bar.set_postfix(postfix)

            if step == len(train_loader) - 1:
                torch.save(postfix, f'{checkpoint_path}/loss_{(epoch):03d}.pth')

        scheduler.step()

        # Evaluation
        model.eval()
        eval_results = dict()

        for loader_name, loader in zip(['train', 'test'], [val_loader, test_loader]):
            acc = 0
            fp  = 0
            fn  = 0

            print(f'\n    Evaluating {loader_name} set...')

            cuda_synchronize(device)
            start_time = time.perf_counter()

            with torch.no_grad():
                for data in loader:
                    img = data[0]
                    gt = data[-1]

                    cls_pred, vertical_pred, offset_pred = model(img.float() / 255)
                    _acc, _fp, _fn = evaluation(cls_pred, vertical_pred, offset_pred, gt)

                    acc += _acc
                    fp  += _fp
                    fn  += _fn

                acc /= len(loader)
                fp  /= len(loader)
                fn  /= len(loader)

                cuda_synchronize(device)
                elapsed = time.perf_counter() - start_time

                print(f'    {loader_name} eval: acc = {acc:.04f}, fp = {fp:.04f}, fn = {fn:.04f}')
                print(f'    Elapsed time: {elapsed:.2f}s')

                eval_results[f'{loader_name}_acc'] = acc
                eval_results[f'{loader_name}_fp']  = fp
                eval_results[f'{loader_name}_fn']  = fn

        checkpoint = dict(
            epoch=epoch,
            model_state=model.state_dict(),
            scheduler_state=scheduler.state_dict(),
            optim_state=optimizer.state_dict()
        )

        torch.save(checkpoint,   f'{checkpoint_path}/checkpoint_{(epoch):03d}.pth')
        torch.save(eval_results, f'{checkpoint_path}/eval_{(epoch):03d}.pth')

def get_arguments():
    parser = argparse.ArgumentParser()

    parser.add_argument('--device',          type=str,   default='cpu', choices=('cuda', 'cpu'))
    parser.add_argument('--dataset_path',    type=str)
    parser.add_argument('--checkpoint_path', type=str)
    parser.add_argument('--loader_workers',  type=int,   default=0)
    parser.add_argument('--epochs',          type=int,   default=100)
    parser.add_argument('--batch_size',      type=int,   default=4)
    parser.add_argument('--lr',              type=float, default=0.001)
    parser.add_argument('--lr_reduce_gamma', type=float, default=0.7)
    parser.add_argument('--lr_reduce_step',  type=int,   default=200)

    # Transform
    parser.add_argument('--use_transform', dest='transform', action='store_true')
    parser.add_argument('--no_transform',  dest='transform', action='store_false')
    parser.set_defaults(transform=False)

    # Dropout
    parser.add_argument('--use_dropout', dest='dropout', action='store_true')
    parser.add_argument('--no_dropout',  dest='dropout', action='store_false')
    parser.set_defaults(dropout=True)

    args = parser.parse_args()

    if args.device == 'cuda' and args.loader_workers != 0:
        torch.multiprocessing.set_start_method('spawn')

    if args.dataset_path[-1] in ['/', '\\']:
        args.dataset_path = args.dataset_path[:-1]

    if args.checkpoint_path[-1] in ['/', '\\']:
        args.checkpoint_path = args.checkpoint_path[:-1]

    return args

def main():
    args = get_arguments()

    if not os.path.isdir(args.checkpoint_path):
        os.makedirs(args.checkpoint_path)

    train(
        device=args.device,
        dataset_path=args.dataset_path,
        checkpoint_path=args.checkpoint_path,
        loader_workers=args.loader_workers,
        epochs=args.epochs,
        batch_size=args.batch_size,
        lr=args.lr,
        lr_reduce_gamma=args.lr_reduce_gamma,
        lr_reduce_step=args.lr_reduce_step,
        use_transform=args.transform,
        use_dropout=args.dropout
    )

if __name__ == '__main__':
    main()
