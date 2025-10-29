#!/usr/bin/env bash
# Two runs only: baseline + optimized (orjson)
# Each run collects perf stat counters (no perf record)

set -euo pipefail
OUTDIR="${OUTDIR:-FINAL_PERF_STAT_OUT}"
mkdir -p "$OUTDIR"

echo "🧩 Ensuring dependencies..."
python3 -m pip install --quiet pyperformance==1.13.0 pyperf==2.9.0 psutil==7.1.2 || true
if ! python3 -c "import orjson" >/dev/null 2>&1; then
  echo "🧩 Installing orjson (binary build)..."
  python3 -m pip install --no-cache-dir --prefer-binary orjson==3.10.7 --quiet || true
fi

EVENTS="cycles,instructions,branches,branch-misses,cache-misses"
export PYTHONUNBUFFERED=1
export MALLOC_ARENA_MAX=2

# === 1) BASELINE (stdlib json) ===
echo "=== BASELINE: stdlib json ==="
perf stat -e "$EVENTS" -o "$OUTDIR/perf_stat_baseline.txt" -- \
  python3 -m pyperformance run -b json_dumps \
  --inherit-environ PYPERFORMANCE_RUNID \
  --output "$OUTDIR/json_baseline.json"

# === 2) OPTIMIZED (orjson patch) ===
echo "=== OPTIMIZED: orjson ==="
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
export PYTHONPATH="$PATCHDIR:${PYTHONPATH:-}"

# 🩹 detect venv path (pyperformance will reuse the same venv if it exists)
VENV_DIR=$(find ./venv -type d -name "cpython3.10-*" | head -n1 || true)
if [[ -n "$VENV_DIR" ]]; then
  echo "🧩 Ensuring orjson inside venv: $VENV_DIR"
  "$VENV_DIR/bin/python" -m pip install --no-cache-dir --prefer-binary orjson==3.10.7 --quiet || true
fi

perf stat -e "$EVENTS" -o "$OUTDIR/perf_stat_orjson.txt" -- \
  python3 -m pyperformance run -b json_dumps \
  --inherit-environ PYPERFORMANCE_RUNID,PYTHONPATH \
  --output "$OUTDIR/json_orjson.json"

echo
echo "✅ DONE"
echo "Results saved under: $OUTDIR"
ls -1 "$OUTDIR" | grep -E 'json_|perf_' | sed 's/^/  /'
