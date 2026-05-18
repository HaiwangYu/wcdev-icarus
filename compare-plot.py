#!/usr/bin/env python3
"""Overlay memory profiles across progressive fixes."""
import os, re
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

RAM_TOTAL_GB = 92.5
RUNS = [
    ("no-fix (master)",            "/exp/icarus/app/users/yuhw/wcdev-icarus/run-20260514-master-top",   "C0"),
    ("A1-A4 + A0 + C1+C2 + C5",    "/exp/icarus/app/users/yuhw/wcdev-icarus/run-20260516-c5-top",       "C3"),
    ("...+ per-TPC modules (4x)",  "/exp/icarus/app/users/yuhw/wcdev-icarus/run-20260516-per-tpc-top",  "C5"),
]

def load(run_dir):
    data = np.loadtxt(os.path.join(run_dir, "top.log"))
    if data.ndim == 1: data = data.reshape(-1, 2)
    cpu, mem_pct = data[:, 0], data[:, 1]
    mem_gb = mem_pct * RAM_TOTAL_GB / 100.0
    duration_s = None
    with open(os.path.join(run_dir, "detsim.log")) as f:
        for line in f:
            m = re.search(r"^real\s+(\d+)m([\d.]+)s", line)
            if m: duration_s = float(m.group(1)) * 60 + float(m.group(2))
    if duration_s is None: duration_s = len(cpu) * 0.1
    t = np.arange(len(cpu)) * (duration_s / len(cpu))
    return t, cpu, mem_gb, duration_s

fig, ax = plt.subplots(figsize=(13, 5))
for label, run_dir, color in RUNS:
    if not os.path.isdir(run_dir):
        print(f"skip {run_dir} (missing)")
        continue
    try:
        t, cpu, mem_gb, dur = load(run_dir)
    except Exception as e:
        print(f"skip {run_dir}: {e}")
        continue
    ax.plot(t, mem_gb, label=f"{label}  (peak {mem_gb.max():.2f} GB, {dur:.0f} s)",
            linewidth=1.0, color=color)
    ax.fill_between(t, 0, mem_gb, alpha=0.08, color=color)
ax.set_xlabel("time since lar start [sec]", fontsize=14)
ax.set_ylabel("memory (RSS) [GB]", fontsize=14)
ax.set_title("Memory vs time: progressive fixes", fontsize=14)
ax.grid(True, alpha=0.4)
ax.legend(loc="best", fontsize=11)
plt.tight_layout()
out = "/exp/icarus/app/users/yuhw/wcdev-icarus/compare_memory_vs_time.png"
plt.savefig(out, dpi=140)
print("wrote", out)
