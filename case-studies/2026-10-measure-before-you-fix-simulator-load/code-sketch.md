# Code Sketch: Reading a Probe That Can Fail

*A companion to [The Safety Check That Refused a Healthy Machine](README.md). This is a simplified illustration written for this write-up. It is not production code, and it leaves out the simulator handling, the locking, and the rest of the pre-flight checks around the real thing.*

## Where it fits

The case study describes a pre-flight check that decides whether it is safe to start a test run. This sketch covers the smallest piece of it: reading one number about the machine, and what to do when that read fails. It is the piece an independent review found failing open.

## The rule

A probe reads one number, such as how many pages the system is writing out to disk. The old version quietly turned a failed read into zero, which looks like "all quiet". The new version treats a failed read as unknown.

The old version, which fails open:

```bash
counter_old() {
  vm_stat 2>/dev/null | awk '/^(Pageouts|Swapouts):/{v=$NF; sub(/\./,"",v); s+=v} END{printf "%d", s}'
}
# If vm_stat is missing or broken, this prints 0 and the gate says ALLOW.
```

The new version, which fails closed:

```bash
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
```

Every probe either returns a valid number, or prints nothing and returns a failure code. A missing counter, garbage output, or a counter that goes backwards all mean refuse.

## How it connects to the case study

- **"A measurement that can't be taken got treated as good news."** This is that bug in 5 lines. `counter_old` has no way to say "I couldn't read it".
- **"Measure what's happening now."** The gate compares two readings a second apart and acts on the *rate*, not on a stored total like "swap used", which stays high long after the pressure is gone.
- **"The load average lags."** The same measurement tool that found this is in [`code/sample_machine.sh`](code/sample_machine.sh). It logs CPU idle, free memory and paging every few seconds, so I could see the CPU go idle while the load average was still high.

## The test

`./code/probes_demo.sh` runs both gates against a fake `vm_stat` in three moods, so it behaves the same on any machine:

```
machine      | OLD gate (fails open)              | NEW gate (fails closed)
-------------+------------------------------------+------------------------
healthy      | ALLOW  (paging 0 pages/s)          | ALLOW  (paging 0 pages/s)
broken       | ALLOW  (paging 0 pages/s)          | REFUSE (cannot measure paging: machine state UNKNOWN)
thrashing    | REFUSE (paging 50000 pages/s)      | REFUSE (paging 50000 pages/s)
```

The two gates agree on a healthy machine and on a thrashing one. The row that matters is `broken`.

The measurement tool prints one row per sample. These are real rows from a quiet machine:

```
seconds,load_1m,cpu_idle_pct,free_mem_pct,pageouts_delta,swapouts_delta
0,1.83,92,56,0,0
4,1.69,91,56,0,0
7,1.69,94,55,0,0
```

## A choice I made on purpose

When a probe can't be read, I refuse to run, even though a flaky probe could block a healthy machine. I chose that over guessing. There is an explicit override flag, and it prints, out loud, that it is proceeding with an unknown machine state, so overriding is a visible decision and not a silent default. A refused run costs a retry. A run started on a machine I couldn't read can leave it unusable until the run finishes.

## Run it yourself

```
./code/probes_demo.sh              # any machine with bash
./code/sample_machine.sh 30 2      # macOS: 30 seconds, one row every 2 seconds
```

The files: [`probes_demo.sh`](code/probes_demo.sh) and [`sample_machine.sh`](code/sample_machine.sh).
