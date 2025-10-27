# HW–SW Co-Design Project — json_dumps

🟢 Goal: profile ➜ find hotspots ➜ optimize (swap json.dumps → orjson) ➜ re-measure.
🟣 Headline: 62.3 ± 0.5 ms (stdlib) ➜ 11.9 ± 0.4 ms (orjson), ≈ 5.24× faster.

🔵 Overview

This folder reproduces the json_dumps benchmark on baseline CPython and on an optimized run that substitutes orjson for json.dumps. Everything needed to run is under src/.

🟡 Repository Structure
json_dump/
├─ flame_graphs/
│  ├─ jsondumps_flamegraph.svg           # baseline (stdlib json)
│  └─ jsondumps_flamegraph_opt.svg       # optimized (orjson)
├─ perf_stat_out/
│  ├─ perf_stat_baseline.txt             # perf stat for baseline run
│  └─ perf_stat_orjson.txt               # perf stat for patched run
├─ src/
│  ├─ json_generate_fgs.sh               # microbenchmark + record flame graphs
│  ├─ json_benchmark_perf_stat.sh        # pyperformance + perf stat (both runs)
│  └─ run_full_json_analysis.sh          # one-shot wrapper for the workflow
└─ README.md

🟣 Prerequisites

python3-dbg, pip, pyperformance

perf (Linux perf events) and permission to use it

bash, common GNU utils (awk, sed, …)

Ability to install orjson (network or local wheel)

🔧 Tip: if orjson import fails, run pip install --user orjson inside the VM.

🟢 How to Run
1) Clone
git clone https://github.com/Dorknafo7/HW-SW-Co-Design-Project.git
cd HW-SW-Co-Design-Project/json_dump/src

2) Make scripts executable
chmod +x json_generate_fgs.sh json_benchmark_perf_stat.sh run_full_json_analysis.sh

3) Generate flame graphs (baseline & optimized)
./json_generate_fgs.sh

Saves SVGs to working directory

4) Run pyperformance + perf stat (baseline & optimized)
./json_benchmark_perf_stat.sh


Executes pyperformance json_dumps benchmark with stdlib json

Then runs the same benchmark with a monkey-patch to route json.dumps → orjson.dumps

Writes hardware counters to current directory

5) One-shot full workflow
./run_full_json_analysis.sh

🟦 How the Monkey-Patch Works (calls reach orjson)

The script creates a temporary sitecustomize.py and exports PYTHONPATH so every pyperformance worker process imports it:

# inside json_benchmark_perf_stat.sh
PATCHDIR=$(mktemp -d)
cat > "$PATCHDIR/sitecustomize.py" <<'PY'
import json
try:
    import orjson
    json.dumps = lambda obj, *a, **kw: orjson.dumps(obj).decode("utf-8")
except Exception as e:
    import sys
    print("[sitecustomize] orjson patch failed:", e, file=sys.stderr)
PY
export PYTHONPATH="$PATCHDIR"

# Patched run so child processes inherit PYTHONPATH:
python3-dbg -m pyperformance run --bench json_dumps --inherit-environ=PYTHONPATH

🟩 Expected Results

Runtime: stdlib 62.2 ± 0.5 ms ➜ orjson 11.9 ± 0.1 ms (−80.9%, ≈ 5.24× speedup).

Perf counters (summary): large drops in instructions/branches/branch-misses, small IPC uptick—consistent with moving hot loops (string escaping, UTF-8 handling, number formatting) into tight native code.

📁 Outputs in working directory:

baseline & optimized flame graphs (SVG)

perf_stat_baseline.txt, perf_stat_orjson.txt

🟠 Notes & Troubleshooting

orjson install: if import fails, run pip install --user orjson

Fairness controls: orjson.dumps returns bytes, so we decode to str to match stdlib behavior.

