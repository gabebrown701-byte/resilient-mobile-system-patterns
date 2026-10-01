#!/usr/bin/env bash
# Samples what a machine is ACTUALLY doing, once every few seconds, and prints
# one CSV row per sample. macOS only (uses top, vm_stat, memory_pressure).
#
#   ./sample_machine.sh [seconds=60] [interval=2]  > run.csv
#
# Columns: seconds, load_1m, cpu_idle_pct, free_mem_pct, pageouts_delta,
#          swapouts_delta, busiest_process
#
# Why these columns: the 1-minute load average LAGS (it keeps reading high
# after the CPU is already idle), "swap used" is a stale high-water mark, and
# neither says what is happening NOW. CPU idle and paging deltas do.
DURATION="${1:-60}"; INTERVAL="${2:-2}"
counter() { vm_stat | awk -v k="$1" '$0 ~ k":" {v=$NF; sub(/\./,"",v); print v}'; }
prev_po=$(counter Pageouts); prev_so=$(counter Swapouts)
echo "seconds,load_1m,cpu_idle_pct,free_mem_pct,pageouts_delta,swapouts_delta,busiest_process"
start=$(date +%s)
while :; do
  now=$(( $(date +%s) - start )); [ "$now" -gt "$DURATION" ] && break
  frame=$(top -l 2 -s 1 -n 1 -o cpu -stats command,cpu 2>/dev/null | awk '/^Processes:/{n++} n==2')
  idle=$(echo "$frame" | awk '/^CPU usage:/{for(i=1;i<=NF;i++) if($i=="idle"){gsub("%","",$(i-1)); printf "%d",$(i-1)}}')
  busiest=$(echo "$frame" | awk '/^COMMAND/{getline; print $1}')
  load=$(sysctl -n vm.loadavg | awk '{print $2}')
  free=$(memory_pressure 2>/dev/null | tail -1 | grep -o '[0-9]*%' | tr -d '%')
  po=$(counter Pageouts); so=$(counter Swapouts)
  echo "$now,$load,$idle,$free,$((po-prev_po)),$((so-prev_so)),$busiest"
  prev_po=$po; prev_so=$so
  sleep "$INTERVAL"
done
