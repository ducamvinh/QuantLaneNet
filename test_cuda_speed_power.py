from multiprocessing import Process, Event, Manager
from ptflops import get_model_complexity_info
from packaging import version
import subprocess
import platform
import torch
import time
import tqdm
import re
import os

from model.QuantLaneNet import QuantLaneNet

class TestModel(QuantLaneNet):

    def __init__(self, input_size=(256, 512), num_lanes=4, dropout=True):
        super(TestModel, self).__init__(input_size=input_size, num_lanes=num_lanes, dropout=dropout)

    def forward(self, x):
        # Encoder stages
        x1 = self.encoder_stage_1(x)
        x2 = self.encoder_stage_2(x1)
        x3 = self.encoder_stage_3(x2)

        # Output branches
        cls = self.cls_out(x3)
        vertical = self.vertical_out(x3)
        # offset = self.offset_out(x3)

        return torch.cat([cls, vertical], dim=3)

def run_shell_command(cmd):
    try:
        return subprocess.check_output(cmd.split()).decode('utf-8')
    # Unknown command called
    except FileNotFoundError as e:
        raise RuntimeError(f'Unknown shell command: "{e.filename}"') from e
    # Command died or returned with error
    except subprocess.CalledProcessError as e:
        if e.returncode > 0:
            raise RuntimeError(
                f'Command "{" ".join(e.cmd)}" returned non-zero exit status "{e.returncode}" with error message:\n'
                f'--\n'
                f'{e.output.decode("utf-8")}'
            ) from e
        else:
            # Command died
            raise e

def calc_framerate(start_event, return_dict):
    print('\n[INFO] Initializing model...')
    model = TestModel(dropout=True).to('cuda')
    model.eval()

    num_test = 100000
    elapsed_time_samples = []
    x = torch.rand(size=(1, 3, 256, 512), device='cuda')

    # Start calc_power_clock process
    start_event.set()

    print(f'[INFO] Running inference {num_test:,d} times...')
    with torch.no_grad():
        for i in tqdm.tqdm(range(num_test)):
            start_time = time.perf_counter()
            y = model(x)

            if i >= 1000:
                torch.cuda.synchronize()
                elapsed_time_samples.append(time.perf_counter() - start_time)

    return_dict['framerate'] = len(elapsed_time_samples) / sum(elapsed_time_samples)
    print('\n', end='')

def calc_power(stop_event, return_dict):
    # Check if current GPU support power query
    if 'N/A' in run_shell_command('nvidia-smi --query-gpu=power.draw --format=csv,noheader'):
        # Stop if no power readings are available
        if re.match(r'[\s\S]+Avg[^\n]+Not Found', run_shell_command('nvidia-smi --query --display=POWER')):
            stop_event.wait()
            print('[INFO] Power readings are not available')
            return_dict['power'] = 'N/A'
            return
        # Define method of reading power from nvidia-smi
        def get_power():
            pattern = r'Power Samples[\s\S]+Avg\s+: (\S+) W'
            readings = re.search(pattern, run_shell_command('nvidia-smi --query --display=POWER'))
            return eval(readings.group(1))
        # Wait for GPU to warm-up
        time.sleep(3)

    else:
        # Define method of reading power from nvidia-smi
        def get_power():
            return eval(run_shell_command('nvidia-smi --query-gpu=power.draw --format=csv,noheader').split()[0])
        # Wait for GPU to warm-up
        time.sleep(1)

    # Get power readings every 1 second
    power_samples = []
    while not stop_event.is_set():
        power_samples.append(get_power())
        time.sleep(1)

    print(f'[INFO] Number of power samples: {len(power_samples)}')
    return_dict['power'] = sum(power_samples) / len(power_samples)

def calc_clock(stop_event, return_dict):
    # Check if clock readings are available
    if not re.match(r'[0-9]+(\.[0-9]+)* MHz', run_shell_command('nvidia-smi --query-gpu=clocks.gr --format=csv,noheader')):
        stop_event.wait()
        print('\n[INFO] Clock readings are not available')
        return_dict['clock'] = 'N/A'
        return

    time.sleep(1)
    clock_samples = []

    while not stop_event.is_set():
        clock_samples.append(eval(run_shell_command('nvidia-smi --query-gpu=clocks.gr --format=csv,noheader').split()[0]))
        time.sleep(1)

    print(f'[INFO] Number of clock samples: {len(clock_samples)}')
    return_dict['clock'] = sum(clock_samples) / len(clock_samples)

def get_os_name():
    if os.name == 'nt':
        # Windows
        win_version = platform.version()
        win_number = '11' if version.parse(win_version) >= version.parse('10.0.22000') else platform.release()
        return f'Windows {win_number} {platform.win32_edition()} {win_version}'
    elif os.name == 'posix':
        # Linux
        with open('/etc/os-release', 'r') as f:
            matches = re.search(r'(^|\s)NAME="([^"]+)[\s\S]+\nVERSION="([^"]+)', f.read())
            return f'{matches.group(2)} {matches.group(3)}'
    else:
        # Other
        raise NotImplementedError(f'Not implemented for "{os.name}" OS')

def main():
    # Get initial readings
    flops, params = get_model_complexity_info(model=TestModel(), input_res=(3, 256, 512), as_strings=False, print_per_layer_stat=False, verbose=False)
    gpu_name = run_shell_command('nvidia-smi --query-gpu=name --format=csv,noheader').strip()
    os_name = get_os_name()

    # Init return_dict for parallel processes
    manager = Manager()
    return_dict = manager.dict()

    # Events
    start_event = Event()
    stop_event = Event()

    # Init processes
    process_framerate = Process(target=calc_framerate, args=(start_event, return_dict))
    process_power = Process(target=calc_power, args=(stop_event, return_dict))
    process_clock = Process(target=calc_clock, args=(stop_event, return_dict))

    # Run processes
    process_framerate.start()
    start_event.wait()
    process_power.start()
    process_clock.start()

    # Wait for processes to finish
    process_framerate.join()
    stop_event.set()
    process_power.join()
    process_clock.join()

    # Calculate throughput
    throughput = flops / 1e9 * return_dict['framerate']

    print(
        f'\n'
        f'#######################################\n'
        f'\n'
        f'GPU name   : {gpu_name}\n'
        f'GPU clock  : {"%.0f MHz" % return_dict["clock"] if return_dict["clock"] != "N/A" else "N/A"}\n'
        f'OS release : {os_name}\n'
        f'Python     : {platform.python_version()}\n'
        f'PyTorch    : {torch.__version__}\n'
        f'Framerate  : {return_dict["framerate"]:.3f} FPS\n'
        f'Power      : {"%.3f W" % return_dict["power"] if return_dict["power"] != "N/A" else "N/A"}\n'
        f'Parameters : {"%.3f M" % (params / 1e6) if params >= 1e6 else "%.3f k" % (params / 1e3)}\n'
        f'Complexity : {"%.3f GFLOPs" % (flops / 1e9) if flops >= 1e9 else "%.3f MFLOPs" % (flops / 1e6)}\n'
        f'Throughput : {throughput:.3f} GOPS\n'
        f'Efficiency : {"%.3f GOPS/W" % (throughput / return_dict["power"]) if return_dict["power"] != "N/A" else "N/A"}\n'
    )

if __name__ == '__main__':
    main()
