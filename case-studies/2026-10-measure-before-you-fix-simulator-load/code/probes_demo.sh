#!/usr/bin/env bash
# Shows the bug my own safety check had, and the fix, on any machine.
#
#   ./probes_demo.sh
#
# A "probe" reads one number about the machine. The question is what happens
# when the probe itself FAILS. The old gate turned a failed read into "0",
# which looks like "all quiet". The fixed gate treats it as "unknown: refuse".
set -u
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# A fake `vm_stat` in three moods, so this runs the same everywhere.
mkdir -p "$WORK/healthy" "$WORK/broken" "$WORK/thrashing"
cat > "$WORK/healthy/vm_stat" <<'X'
#!/bin/bash
echo "Pageouts: 1000."; echo "Swapouts: 0."
X
cat > "$WORK/broken/vm_stat" <<'X'
#!/bin/bash
exit 1
X
cat > "$WORK/thrashing/vm_stat" <<'X'
#!/bin/bash
f=/tmp/.probe_demo_n; n=$(cat $f 2>/dev/null || echo 0); echo $((n+1)) > $f
echo "Pageouts: $((1000 + n * 50000))."; echo "Swapouts: 0."
X
chmod +x "$WORK"/*/vm_stat; rm -f /tmp/.probe_demo_n

# --- OLD: a failed read silently becomes 0 ("healthy") ---------------------
counter_old() { vm_stat 2>/dev/null | awk '/^(Pageouts|Swapouts):/{v=$NF; sub(/\./,"",v); s+=v} END{printf "%d", s}'; }
gate_old() {
  a=$(counter_old); sleep 1; b=$(counter_old)
  rate=$((b - a))
  if [ "$rate" -gt 1000 ]; then echo "REFUSE (paging $rate pages/s)"; else echo "ALLOW  (paging $rate pages/s)"; fi
}

# --- NEW: a failed or invalid read is UNKNOWN, and unknown means refuse -----
counter_new() {
  out=$(vm_stat 2>/dev/null | awk '/^Pageouts:/{p=$NF; sub(/\./,"",p); hp=1} /^Swapouts:/{s=$NF; sub(/\./,"",s); hs=1} END{ if (hp && hs && p ~ /^[0-9]+$/ && s ~ /^[0-9]+$/) printf "%d", p+s }')
  [ -n "$out" ] || return 1
  echo "$out"
}
gate_new() {
  a=$(counter_new) || { echo "REFUSE (cannot measure paging: machine state UNKNOWN)"; return; }
  sleep 1
  b=$(counter_new) || { echo "REFUSE (cannot measure paging: machine state UNKNOWN)"; return; }
  [ "$b" -ge "$a" ] || { echo "REFUSE (counter went backwards: UNKNOWN)"; return; }
  rate=$((b - a))
  if [ "$rate" -gt 1000 ]; then echo "REFUSE (paging $rate pages/s)"; else echo "ALLOW  (paging $rate pages/s)"; fi
}

printf '%-12s | %-34s | %s\n' "machine" "OLD gate (fails open)" "NEW gate (fails closed)"
printf '%-12s-+-%-34s-+-%s\n' "------------" "----------------------------------" "-----------------------"
for mood in healthy broken thrashing; do
  rm -f /tmp/.probe_demo_n
  o=$(PATH="$WORK/$mood:$PATH" gate_old); rm -f /tmp/.probe_demo_n
  n=$(PATH="$WORK/$mood:$PATH" gate_new)
  printf '%-12s | %-34s | %s\n' "$mood" "$o" "$n"
done
echo
echo "The row that matters is 'broken': the old gate says ALLOW because it could not"
echo "read the probe and treated that as zero. The new gate says REFUSE."
