import subprocess
import re

readings = subprocess.check_output(['nvidia-smi', '--query', '--display=POWER,CLOCK']).decode('utf-8')
search = re.search(r'Power Draw\s+: (\S+)[\s\S]+Power Samples((?!Avg)[\s\S])+Avg\s+: (\S+) W\s+Clocks\s+Graphics\s+: (\S+)', readings)

print(search.group(1))
print(search.group(2))
print(search.group(3))
print(search.group(4))