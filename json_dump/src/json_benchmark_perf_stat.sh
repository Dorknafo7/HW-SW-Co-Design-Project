#!/usr/bin/env bash
set -e

OUTDIR="${OUTDIR:-FINAL_PERF_STAT_OUT}"
mkdir -p "$OUTDIR"

# Common event set for deeper analysis
EVENTS="cycles,instructions,branches,branch-misses,cache-references,cache-misses,\
L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses,context-switches,\
cpu-migrations,page-faults"

echo "=== BASELINE: stdlib json ==="

# 1️⃣ perf stat with extended counters
perf stat -e "$EVENTS" \
    -o "$OUTDIR/perf_stat_baseline.txt" \
    python3-dbg -m pyperformance run --bench json_dumps

# 2️⃣ perf record + report for call stacks
perf record -F 999 -g -o "$OUTDIR/perf_baseline.data" -- \
    python3-dbg -m pyperformance run --bench json_dumps
perf report --stdio -i "$OUTDIR/perf_baseline.data" > "$OUTDIR/perf_baseline_report.txt"

echo
echo "=== OPTIMIZED: orjson ==="

# Ensure orjson is available
python3-dbg -m pip install --user orjson >/dev/null 2>&1 || true

# Monkey-patch json.dumps to use orjson.dumps
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

# 3️⃣ perf stat (with extended counters) for optimized run
perf stat -e "$EVENTS" \
    -o "$OUTDIR/perf_stat_orjson.txt" \
    python3-dbg -m pyperformance run --bench json_dumps --inherit-environ=PYTHONPATH

# 4️⃣ perf record + report for optimized run
perf record -F 999 -g -o "$OUTDIR/perf_orjson.data" -- \
    python3-dbg -m pyperformance run --bench json_dumps --inherit-environ=PYTHONPATH
perf report --stdio -i "$OUTDIR/perf_orjson.data" > "$OUTDIR/perf_orjson_report.txt"

echo
echo "=== DONE ==="
echo "All outputs are in: $OUTDIR"
ls -1 "$OUTDIR"
