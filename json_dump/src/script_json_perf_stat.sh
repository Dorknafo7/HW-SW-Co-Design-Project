#!/usr/bin/env bash
set -e

# ============================================================
# ⚙️ General setup and memory-safe defaults
# ============================================================
OUTDIR="${OUTDIR:-FINAL_PERF_STAT_OUT}"
mkdir -p "$OUTDIR"

# Limit memory usage and pip cache to avoid OOM inside QEMU
export PIP_NO_CACHE_DIR=1
export PIP_DEFAULT_TIMEOUT=60
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_BUILD_TRACKER_DIR=/tmp/pip-build
export PIP_MAX_WORKERS=1
export MALLOC_ARENA_MAX=2

EVENTS="cycles,instructions,branches,branch-misses,cache-references,cache-misses,\
L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses,context-switches,\
cpu-migrations,page-faults"

echo "=== BASELINE: stdlib json ==="

# ============================================================
# 🧩 1. Ensure dependencies globally (once)
# ============================================================
if ! command -v pip >/dev/null 2>&1; then
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y python3-pip >/dev/null 2>&1 || true
fi

pip install --quiet pyperformance orjson || true
python3-dbg -m pip install --quiet pyperformance orjson || true

# ============================================================
# 🧪 2. Baseline run: stdlib json
# ============================================================
perf stat -e "$EVENTS" \
  -o "$OUTDIR/perf_stat_baseline.txt" \
  python3-dbg -m pyperformance run --bench json_dumps

perf record -F 999 -g -o "$OUTDIR/perf_baseline.data" -- \
  python3-dbg -m pyperformance run --bench json_dumps

perf report --stdio -i "$OUTDIR/perf_baseline.data" > "$OUTDIR/perf_baseline_report.txt"

# ============================================================
# ⚡ 3. Optimized run: orjson
# ============================================================
echo
echo "=== OPTIMIZED: orjson ==="

# Ensure orjson exists globally (avoid recompile)
python3-dbg -m pip install --quiet orjson || true

# Monkey-patch json.dumps to use orjson.dumps
PATCHDIR=$(mktemp -d)
cat > "$PATCHDIR/sitecustomize.py" <<'PY'
import json, sys
try:
    import orjson
    json.dumps = lambda obj, *a, **kw: orjson.dumps(obj).decode("utf-8")
    print("[sitecustomize] orjson patch active", file=sys.stderr)
except Exception as e:
    print("[sitecustomize] orjson patch failed:", e, file=sys.stderr)
PY

# Allow global site-packages and patch directory
export PYTHONNOUSERSITE=0
export PYTHONPATH="$PATCHDIR:/root/.local/lib/python3.10/site-packages"

# Run perf stat for optimized version
perf stat -e "$EVENTS" \
  -o "$OUTDIR/perf_stat_orjson.txt" \
  python3-dbg -m pyperformance run --bench json_dumps --inherit-environ=PYTHONPATH

# Run perf record for optimized version
perf record -F 999 -g -o "$OUTDIR/perf_orjson.data" -- \
  python3-dbg -m pyperformance run --bench json_dumps --inherit-environ=PYTHONPATH

perf report --stdio -i "$OUTDIR/perf_orjson.data" > "$OUTDIR/perf_orjson_report.txt"

# ============================================================
# 📊 4. Summary
# ============================================================
echo
echo "=== DONE ==="
echo "All outputs are in: $OUTDIR"
ls -1 "$OUTDIR"
