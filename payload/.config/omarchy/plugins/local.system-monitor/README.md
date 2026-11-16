# System monitor

Бар-віджет для Omarchy shell: живе значення в топ-барі та поп-ап з повною
картиною машини. Використовує штатні речі Omarchy — `BarIconButton`,
`KeyboardPanel`, `PanelHero`, кольори й шрифти теми, `qs.Commons` та
`omarchy-system-stats`.

## Що показує

- У барі — обраний показник (типово CPU) з іконкою та відсотком. Наведення
  показує підказку з CPU, RAM і температурою.
- Клік відкриває поп-ап: CPU з графіком за останню хвилину, пам'ять, своп,
  диск, GPU (якщо є), температура, швидкість мережі, uptime, середнє
  навантаження і п'ять найактивніших процесів.
- Середній клік по іконці або кнопка внизу відкриває `btop`.

## Налаштування

У `~/.config/omarchy/shell.json` в записі віджета:

```json
{ "id": "local.system-monitor", "settings": { "metric": "memory", "interval": 1000 } }
```

`metric`: `cpu`, `memory`, `temperature`, `gpu`, `disk`, `network`.
`interval`: період оновлення в мілісекундах, мінімум 500.

Можна додати кілька екземплярів, щоб бачити, наприклад, CPU і пам'ять
одночасно:

```json
{ "id": "local.system-monitor" },
{ "id": "local.system-monitor", "settings": { "metric": "memory" } }
```

## Керування

```bash
omarchy plugin list | grep system-monitor
omarchy bar move local.system-monitor --before omarchy.power
omarchy plugin disable local.system-monitor
```

## Звідки дані

- CPU (idle/total) і load average — з `omarchy-system-stats --bar-widget`,
  того самого джерела, яке використовує shell.
- Пам'ять, своп, uptime, мережа — з `/proc`.
- Температура — з `coretemp`/`k10temp` (або іншого) `hwmon`.
- Диск — з `df` раз на 30 секунд.
- GPU — `nvidia-smi` або `gpu_busy_percent` у `amdgpu`; без GPU секція
  просто не показується.
- Найактивніші процеси — з `ps` раз на 5 секунд.

`sampler.sh` друкує один рядок JSON за інтервал. Віджет перевіряє числа перед
показом, а текст назв процесів екранує й обрізає.


## Version 1.1

CPU package temperature now uses coretemp Package id 0 (or an available CPU-specific sensor); unrelated motherboard/ACPI sensors are excluded. Resource sampling supports 250 ms. Disk, GPU and process scans use separate slower schedules.

Settings include graph duration (10–300 seconds), height (30–150), panel width (320–700), and process rows (3–15). The panel scrolls when necessary. The CPU graph has a fixed 0–100% scale and timestamp-based history. Process rows show PID, CPU lifetime average, and resident memory (MiB), sortable by CPU or memory. Pause freezes displayed samples; resume continues collection.
