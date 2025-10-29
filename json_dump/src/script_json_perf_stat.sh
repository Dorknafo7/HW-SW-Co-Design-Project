#!/usr/bin/env bash
# Run perf stat + pyperformance benchmarks for stdlib json vs orjson
# Generates perf stat + perf record data under FINAL_PERF_STAT_OUT/

set -euo pipefail

OUTDIR="${OUTDIR:-FINAL_PERF_STAT_OUT}"
mkdir -p "$OUTDIR"

# === Perf + Benchmark Config ===
DUR="${DUR:-15}"
EVENTS="cycles,instructions,branches,branch-misses,cache-misses,L1-dcache-loads,L1-dcache-load-misses"
CPU_FREQ_GOVERNOR_PATH="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
PYVER="3.10"

# === System preparation ===
echo "=== BASELINE: stdlib json ==="

# Reduce memory footprint and stabilize environment
export MALLOC_ARENA_MAX=2
export PIP_NO_CACHE_DIR=1
export PIP_MAX_WORKERS=1
export PYTHONUNBUFFERED=1

# === Allow pyperformance venvs to access global orjson ===
# Avoid rebuilding orjson (Rust compile) inside each venv -> prevents OOM
export PYTHONPATH="/usr/local/lib/python${PYVER}/dist-packages:${PYTHONPATH:-}"
export PYTHONNOUSERSITE=1

# === Ensure pyperformance + pyperf are installed globally ===
if ! python3 -m pip show pyperformance >/dev/null 2>&1; then
    python3 -m pip install --quiet pyperformance==1.13.0 pyperf==2.9.0
fi

# === 1. Baseline stdlib json ===
python3 -m pyperformance run -b json_dumps --inherit-environ PYPERFORMANCE_RUNID \
    --output "$OUTDIR/json_baseline.json" | tee "$OUTDIR/json_baseline.log"

# Record perf stat and perf record
perf stat -e "$EVENTS" -o "$OUTDIR/perf_stat_baseline.txt" -- \
    python3 -m pyperformance run -b json_dumps --inherit-environ PYPERFORMANCE_RUNID \
    --output "$OUTDIR/json_baseline_perf.json" | tee -a "$OUTDIR/json_baseline.log"

perf record -e "$EVENTS" -a -g -o "$OUTDIR/perf_baseline.data" -- \
    python3 -m pyperformance run -b json_dumps --inherit-environ PYPERFORMANCE_RUNID \
    --output "$OUTDIR/json_baseline_perfrec.json" | tee -a "$OUTDIR/json_baseline.log"

# === 2. Optimized run: orjson patch active ===
echo "=== OPTIMIZED: orjson ==="

# Inject sitecustomize for orjson patch
PATCHDIR=$(mktemp -d)
cat > "$PATCHDIR/sitecustomize.py" <<'PY'
import json, sys
try:
    import orjson
    json.dumps = lambda obj, *a, **kw: orjson.dumps(obj).decode("utf-8")
    print("[sitecustomize] orjson patch active", file=sys.stderr)
except Exception as e:
    print(f"[sitecustomize] orjson patch failed: {e}", file=sys.stderr)
PY
export PYTHONPATH="$PATCHDIR:$PYTHONPATH"

# Run pyperformance with orjson monkey-patch visible in all venvs
python3 -m pyperformance run -b json_dumps \
    --inherit-environ PYPERFORMANCE_RUNID,PYTHONPATH \
    --output "$OUTDIR/json_orjson.json" | tee "$OUTDIR/json_orjson.log"

# Record perf for patched version
perf stat -e "$EVENTS" -o "$OUTDIR/perf_stat_orjson.txt" -- \
    python3 -m pyperformance run -b json_dumps \
    --inherit-environ PYPERFORMANCE_RUNID,PYTHONPATH \
    --output "$OUTDIR/json_orjson_perf.json" | tee -a "$OUTDIR/json_orjson.log"

perf record -e "$EVENTS" -a -g -o "$OUTDIR/perf_orjson.data" -- \
    python3 -m pyperformance run -b json_dumps \
    --inherit-environ PYPERFORMANCE_RUNID,PYTHONPATH \
    --output "$OUTDIR/json_orjson_perfrec.json" | tee -a "$OUTDIR/json_orjson.log"

# === Summarize Results ===
echo
echo "=== DONE ==="
echo "All outputs are in: $OUTDIR"
ls -1 "$OUTDIR" | grep perf | sed 's/^/  /'
