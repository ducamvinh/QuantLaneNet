from multiprocessing import Process, Event, Manager
from ptflops import get_model_complexity_info
import subprocess
import torch
import time
import tqdm
import re

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

def calc_power_clock(stop_event, return_dict):
    # Check if current GPU support power query
    if 'N/A' in subprocess.check_output(['nvidia-smi', '--query-gpu=power.draw', '--format=csv,noheader']).decode('utf-8'):
        pattern = r'Power Samples[\s\S]+Avg\s+: (\S+) W\s+Clocks\s+Graphics\s+: (\S+)'
        time.sleep(3)
    else:
        pattern = r'Power Draw\s+: (\S+)[\s\S]+\n\s+Clocks\s+Graphics\s+: (\S+)'
        time.sleep(1)

    # Start sampling every 1 second
    power_samples = []
    clock_samples = []

    while not stop_event.is_set():
        readings = subprocess.check_output(['nvidia-smi', '--query', '--display=POWER,CLOCK']).decode('utf-8')
        search = re.search(pattern, readings)

        power_samples.append(eval(search.group(1)))
        clock_samples.append(eval(search.group(2)))

        time.sleep(1)

    print('\n[INFO] Number of power/clock samples:', len(power_samples))
    return_dict['power'] = sum(power_samples) / len(power_samples)
    return_dict['clock'] = sum(clock_samples) / len(clock_samples)

def get_os_name(os_release_path):
    with open(os_release_path, 'r') as f:
        for line in f:
            if 'NAME=' in line:
                dist_name = line.split('"')[1]
            elif 'VERSION=' in line:
                return dist_name + ' ' + line.split('"')[1]

def main():
    # Init return_dict for parallel processes
    manager = Manager()
    return_dict = manager.dict()

    # Events
    start_event = Event()
    stop_event = Event()

    # Init processes
    process_framerate = Process(target=calc_framerate, args=(start_event, return_dict))
    process_power_clock = Process(target=calc_power_clock, args=(stop_event, return_dict))

    # Run processes
    process_framerate.start()
    start_event.wait()
    process_power_clock.start()

    process_framerate.join()
    stop_event.set()
    process_power_clock.join()

    # Get values
    flops, params = get_model_complexity_info(model=TestModel(), input_res=(3, 256, 512), as_strings=False, print_per_layer_stat=False, verbose=False)
    throughput = flops / 1e9 * return_dict['framerate']
    linux_dist = get_os_name('/etc/os-release')
    gpu_name = subprocess.check_output(['nvidia-smi', '--query-gpu=name', '--format=csv,noheader']).decode('utf-8').strip()

    print(
        f'\n'
        f'#######################################\n'
        f'\n'
        f'GPU name   : {gpu_name}\n'
        f'GPU clock  : {return_dict["clock"]:,.0f} MHz\n'
        f'Linux dist : {linux_dist}\n'
        f'Frame rate : {return_dict["framerate"]:.3f} FPS\n'
        f'Power      : {return_dict["power"]:.3f} W\n'
        f'Parameters : {"%.3f M" % (params / 1e6) if params >= 1e6 else "%.3f k" % (params / 1e3)}\n'
        f'Complexity : {"%.3f GFLOPs" % (flops / 1e9) if flops >= 1e9 else "%.3f MFLOPs" % (flops / 1e6)}\n'
        f'Throughput : {throughput:.3f} GOPS\n'
        f'Efficiency : {(throughput / return_dict["power"]):.3f} GOPS/W\n'
    )

if __name__ == '__main__':
    main()
