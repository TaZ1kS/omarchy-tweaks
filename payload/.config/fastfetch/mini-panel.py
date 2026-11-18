from pathlib import Path
import shutil
import subprocess
import time


def cpu_sample():
    values = list(map(int, Path("/proc/stat").read_text().splitlines()[0].split()[1:9]))
    return sum(values), values[3] + values[4]


def cpu_temperature():
    for label in Path("/sys/class/hwmon").glob("hwmon*/temp*_label"):
        try:
            if label.read_text().startswith("Package id"):
                sensor = label.with_name(label.name.replace("_label", "_input"))
                return f"{int(sensor.read_text()) / 1000:.0f} °C"
        except (OSError, ValueError):
            continue
    return "—"


start, idle_start = cpu_sample()
stamp = time.monotonic()
output = subprocess.check_output(
    ["fastfetch", "--config", str(Path(__file__).with_name("mini.jsonc")), "--pipe", "false"],
    text=True,
)
time.sleep(max(0, 0.10 - (time.monotonic() - stamp)))
end, idle_end = cpu_sample()
cpu = 100 * (1 - (idle_end - idle_start) / max(1, end - start))
mem = {k.rstrip(":"): int(v) for k, v, *_ in
       (line.split() for line in Path("/proc/meminfo").read_text().splitlines())}
disk = shutil.disk_usage("/")
metrics = [
    ("CPU", cpu),
    ("RAM", 100 * (1 - mem["MemAvailable"] / mem["MemTotal"])),
    ("/", 100 * disk.used / disk.total),
]
for line in output.splitlines()[:4]:
    print(line)
for label, value in metrics:
    filled = round(value / 10)
    print(f"\033[38;2;104;173;255m{label:<3}  {'━' * filled}"
          f"\033[38;2;65;89;125m{'─' * (10 - filled)}"
          f"\033[38;2;179;214;255m {value:3.0f}%\033[m")
print(f"\033[38;2;104;173;255mTemp \033[38;2;179;214;255m{cpu_temperature()}\033[m")
