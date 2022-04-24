from threading import Thread, Event
from pthflops import count_ops
from queue import Queue
import subprocess
import torch
import time
import tqdm

from model.LaneDetectionModel import LaneDetectionModel

class TestModel(LaneDetectionModel):

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

def calc_framerate(thread_start_event):
    model = TestModel(dropout=True).to('cuda')
    model.eval()

    elapsed_time_samples = []
    thread_start_event.set()

    print('[INFO] Running inference on 20000 random inputs...')
    with torch.no_grad():
        for i in tqdm.tqdm(range(20000)):
            x = torch.rand(size=(1, 3, 256, 512), device='cuda')

            torch.cuda.synchronize()
            start_time = time.time()

            y = model(x)

            if i >= 10000:
                torch.cuda.synchronize()
                elapsed_time_samples.append(time.time() - start_time)

    return len(elapsed_time_samples) / sum(elapsed_time_samples)

def calc_power(thread_stop_event):
    time.sleep(1)
    power_samples = []

    while not thread_stop_event.isSet():
        power = subprocess.check_output(['nvidia-smi', '--query-gpu=power.draw', '--format=csv,noheader']).decode('utf-8')
        power_samples.append(eval(power.split()[0]))
        time.sleep(1)

    print('Number of power samples:', len(power_samples))
    return sum(power_samples) / len(power_samples)

def get_os_name(os_release_path):
    with open(os_release_path, 'r') as f:
        for line in f:
            if 'NAME=' in line:
                dist_name = line.split('"')[1]
            elif 'VERSION=' in line:
                return dist_name + ' ' + line.split('"')[1]

def main():
    que = Queue()

    thread_start_event = Event()
    thread_stop_event = Event()

    thread_framerate = Thread(target=lambda q, arg: q.put(calc_framerate(arg)), args=(que, thread_start_event))
    thread_power = Thread(target=lambda q, arg: q.put(calc_power(arg)), args=(que, thread_stop_event))

    thread_framerate.start()
    thread_start_event.wait()
    thread_power.start()

    thread_framerate.join()
    thread_stop_event.set()
    thread_power.join()

    framerate = que.get()
    power = que.get()
    gflops = count_ops(TestModel(), torch.rand(size=(1, 3, 256, 512)), verbose=False)[0] / 1e9
    linux_dist = get_os_name('/etc/os-release')
    gpu_name = subprocess.check_output(['nvidia-smi', '--query-gpu=name', '--format=csv,noheader']).decode('utf-8').strip()
    clocks = subprocess.Popen(['nvidia-smi', '--query', '--display=CLOCK'], stdout=subprocess.PIPE)
    gpu_clock_mhz = eval(subprocess.check_output(['grep', '--after-context=1', 'Max Clocks'], stdin=clocks.stdout).decode('utf-8').split()[-2])

    print(
        f'\n'
        f'#######################################\n'
        f'\n'
        f'GPU name   : {gpu_name}\n'
        f'GPU clock  : {gpu_clock_mhz:,d} MHz\n'
        f'Linux dist : {linux_dist}\n'
        f'Frame rate : {framerate:.3f} FPS\n'
        f'Power      : {power:.3f} W\n'
        f'Complexity : {gflops:.3f} GFLOPs\n'
        f'Throughput : {(gflops * framerate):.3f} GOPS\n'
        f'Efficiency : {(gflops * framerate / power):.3f} GOPS/W\n'
    )

if __name__ == '__main__':
    main()
