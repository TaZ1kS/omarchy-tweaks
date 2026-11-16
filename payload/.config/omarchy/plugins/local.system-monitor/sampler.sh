#!/bin/bash
# Sampler for the local.system-monitor bar widget.
#
# Prints one JSON line per interval with the numbers the widget and its popup
# show. CPU idle/total counters and the load average come from Omarchy's own
# `omarchy-system-stats --bar-widget`, the same source the shell uses; the
# rest is read straight from /proc and /sys so the loop does not fork for
# every sample.

export LC_ALL=C

interval="${1:-1000}"
[[ $interval =~ ^[0-9]+$ ]] || interval=1000
(( interval < 250 )) && interval=250
interval_s=$(printf '%d.%03d' $((interval / 1000)) $((interval % 1000)))

stats_bin=$(command -v omarchy-system-stats || echo /usr/share/omarchy/bin/omarchy-system-stats)

prev_idle=0
prev_total=0
prev_rx=0
prev_tx=0
prev_us=0
load=0
cpu=0
disk_total_bytes=0
disk_used_bytes=0
disk_pct=0
gpu_json="null"
top_json="[]"

# Use CPU package sensors only, never ACPI/motherboard/GPU temperature.
temp_path=""
for hw in /sys/class/hwmon/hwmon*; do
  [[ -r $hw/name ]] || continue
  read -r hw_name < "$hw/name"
  case $hw_name in coretemp|k10temp|zenpower|cpu_thermal|soc_thermal) ;; *) continue ;; esac
  for t in "$hw"/temp*_input; do
    label=""
    [[ -r ${t%_input}_label ]] && read -r label < "${t%_input}_label"
    case $label in "Package id 0"|Tdie) temp_path=$t; break ;; esac
  done
  [[ -n $temp_path ]] || { [[ -r $hw/temp1_input ]] && temp_path=$hw/temp1_input; }
  [[ -n $temp_path ]] && break
done

# AMD exposes GPU busy as a plain percentage. NVIDIA needs nvidia-smi.
gpu_busy_path=""
for f in /sys/class/drm/card*/device/gpu_busy_percent; do
  [[ -r $f ]] && { gpu_busy_path=$f; break; }
done
has_nvidia=0
command -v nvidia-smi >/dev/null 2>&1 && has_nvidia=1

tick=0
next_gpu=0
next_disk=0
next_top=0

sanitize() {
  local value=${1//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/ }
  value=${value//$'\r'/ }
  value=${value//$'\t'/ }
  printf '%s' "$value"
}

while :; do
  # --- CPU counters and load (native Omarchy stats) --------------------
  native_cpu=0
  while IFS=$'\t' read -r key a b; do
    case $key in
      cpu)
        [[ $a =~ ^[0-9]+$ && $b =~ ^[0-9]+$ ]] || continue
        idle=$a
        total=$b
        native_cpu=1
        ;;
      load)
        [[ $a =~ ^[0-9]+([.][0-9]+)?$ ]] && load=$a
        ;;
    esac
  done < <("$stats_bin" --bar-widget 2>/dev/null)

  if (( native_cpu )); then
    if (( prev_total > 0 )); then
      dt=$((total - prev_total))
      di=$((idle - prev_idle))
      if (( dt > 0 )); then
        cpu=$(( (dt - di) * 100 / dt ))
      fi
      (( cpu < 0 )) && cpu=0
      (( cpu > 100 )) && cpu=100
    fi
    prev_total=$total
    prev_idle=$idle
  fi

  # --- Memory and swap --------------------------------------------------
  mem_total=0
  mem_avail=0
  swap_total=0
  swap_free=0
  while read -r key value _; do
    case $key in
      MemTotal:) mem_total=$value ;;
      MemAvailable:) mem_avail=$value ;;
      SwapTotal:) swap_total=$value ;;
      SwapFree:) swap_free=$value ;;
    esac
  done < /proc/meminfo

  mem_used=$((mem_total - mem_avail))
  (( mem_used < 0 )) && mem_used=0
  if (( mem_total > 0 )); then
    mem_pct=$(( mem_used * 100 / mem_total ))
  else
    mem_pct=0
  fi

  swap_used=$((swap_total - swap_free))
  (( swap_used < 0 )) && swap_used=0
  if (( swap_total > 0 )); then
    swap_pct=$(( swap_used * 100 / swap_total ))
  else
    swap_pct=0
  fi

  # --- Temperature ------------------------------------------------------
  temp=-1
  if [[ -n $temp_path && -r $temp_path ]]; then
    read -r raw_temp < "$temp_path"
    [[ $raw_temp =~ ^[0-9]+$ ]] && temp=$((raw_temp / 1000))
  fi

  # --- Network throughput ----------------------------------------------
  rx_total=0
  tx_total=0
  while IFS= read -r line; do
    [[ $line == *:* ]] || continue
    iface=${line%%:*}
    iface=${iface//[[:space:]]/}
    case $iface in
      ""|lo|docker*|veth*|br-*|virbr*|podman*|tun*|tap*|wg*|zt*|tailscale*|meta*) continue ;;
    esac
    data=${line#*:}
    set -- $data
    [[ $1 =~ ^[0-9]+$ ]] && rx_total=$((rx_total + $1))
    [[ $9 =~ ^[0-9]+$ ]] && tx_total=$((tx_total + $9))
  done < /proc/net/dev

  now_us=${EPOCHREALTIME//[.,]/}
  rx_rate=0
  tx_rate=0
  if (( prev_us > 0 && now_us > prev_us )); then
    elapsed_ms=$(( (now_us - prev_us) / 1000 ))
    if (( elapsed_ms > 0 )); then
      rx_rate=$(( (rx_total - prev_rx) * 1000 / elapsed_ms ))
      tx_rate=$(( (tx_total - prev_tx) * 1000 / elapsed_ms ))
    fi
  fi
  (( rx_rate < 0 )) && rx_rate=0
  (( tx_rate < 0 )) && tx_rate=0
  prev_us=$now_us
  prev_rx=$rx_total
  prev_tx=$tx_total

  # --- Uptime -----------------------------------------------------------
  read -r uptime_raw _ < /proc/uptime
  uptime=${uptime_raw%%.*}
  [[ $uptime =~ ^[0-9]+$ ]] || uptime=0

  # --- Disk (slow moving, refresh every 30s) ---------------------------
  if (( SECONDS >= next_disk )); then
    next_disk=$((SECONDS + 30))
    disk_line=$(df -B1 --output=size,used / 2>/dev/null | tail -n 1)
    read -r d_total d_used <<< "$disk_line"
    if [[ $d_total =~ ^[0-9]+$ && $d_used =~ ^[0-9]+$ && $d_total -gt 0 ]]; then
      disk_total_bytes=$d_total
      disk_used_bytes=$d_used
      disk_pct=$((d_used * 100 / d_total))
    fi
  fi

  # --- GPU --------------------------------------------------------------
  if (( has_nvidia )) && (( SECONDS >= next_gpu )); then
    next_gpu=$((SECONDS + 5))
    nv=$(timeout 2 nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu \
      --format=csv,noheader,nounits 2>/dev/null | head -n 1)
    if [[ -n $nv ]]; then
      IFS=',' read -r g_util g_used g_total g_temp <<< "$nv"
      g_util=${g_util// /}; g_used=${g_used// /}; g_total=${g_total// /}; g_temp=${g_temp// /}
      if [[ $g_util =~ ^[0-9]+$ && $g_used =~ ^[0-9]+$ && $g_total =~ ^[0-9]+$ ]]; then
        [[ $g_temp =~ ^[0-9]+$ ]] || g_temp=-1
        gpu_json="{\"name\":\"NVIDIA\",\"util\":$g_util,\"memUsedMb\":$g_used,\"memTotalMb\":$g_total,\"temp\":$g_temp}"
      fi
    fi
  elif [[ -n $gpu_busy_path ]]; then
    read -r g_util < "$gpu_busy_path"
    if [[ $g_util =~ ^[0-9]+$ ]]; then
      gpu_json="{\"name\":\"AMD\",\"util\":$g_util,\"memUsedMb\":0,\"memTotalMb\":0,\"temp\":-1}"
    fi
  fi

  # Process inventory is slower than the 250ms resource counters.
  if (( SECONDS >= next_top )); then
    next_top=$((SECONDS + 2))
    top_json=$(python3 "$(dirname "$0")/processes.py")
    [[ -n $top_json ]] || top_json='[]'
  fi

  # --- Emit -------------------------------------------------------------
  printf '{"cpu":%d,"mem":%d,"memUsedMb":%d,"memTotalMb":%d,"swap":%d,"swapUsedMb":%d,"swapTotalMb":%d,"temp":%d,"load":%s,"uptime":%d,"rx":%d,"tx":%d,"diskPct":%d,"diskUsedGb":%d,"diskTotalGb":%d,"gpu":%s,"top":%s}\n' \
    "$cpu" "$mem_pct" "$((mem_used / 1024))" "$((mem_total / 1024))" \
    "$swap_pct" "$((swap_used / 1024))" "$((swap_total / 1024))" \
    "$temp" "$load" "$uptime" "$rx_rate" "$tx_rate" \
    "$disk_pct" "$((disk_used_bytes / 1073741824))" "$((disk_total_bytes / 1073741824))" \
    "$gpu_json" "$top_json"

  (( tick++ ))
  sleep "$interval_s"
done
