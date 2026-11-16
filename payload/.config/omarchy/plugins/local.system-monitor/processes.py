import json, subprocess
result = subprocess.run(["ps", "-eo", "pid=,pcpu=,pmem=,rss=,comm="], capture_output=True, text=True)
rows = []
for line in result.stdout.splitlines():
    parts = line.split(None, 4)
    if len(parts) != 5:
        continue
    try:
        pid, cpu, mem, rss, name = parts
        rows.append(dict(pid=int(pid), cpu=float(cpu), mem=float(mem), rss=int(rss)/1024, name=name[:64]))
    except ValueError:
        continue
print(json.dumps(rows[:8192]))
