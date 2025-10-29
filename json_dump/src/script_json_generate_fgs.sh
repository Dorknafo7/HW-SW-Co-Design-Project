#!/usr/bin/env bash
set -e

# ============================================================
# 🔧 Configuration
# ============================================================
OUTDIR="${OUTDIR:-FINAL_FGS_OUT}"
RATE="${RATE:-150}"           # samples per second
DURATION="${DURATION:-25}"    # seconds
PYTHON=${PYTHON:-python3-dbg}
PAYLOAD_FILE="$OUTDIR/payloads.pkl"

mkdir -p "$OUTDIR"

# ============================================================
# 🧩 Ensure py-spy exists
# ============================================================
if ! command -v py-spy >/dev/null 2>&1; then
    echo "Installing py-spy..."
    pip install --quiet py-spy
fi

# ============================================================
# 🧩 Ensure payloads exist
# ============================================================
if [ ! -f "$PAYLOAD_FILE" ]; then
    echo "Generating payloads..."
    $PYTHON - <<'PY'
import pickle, json, random, os
os.makedirs("FINAL_FGS_OUT", exist_ok=True)
payloads = []
for i in range(256):
    obj = {"id": i, "data": [random.random() for _ in range(500)]}
    payloads.append(obj)
with open("FINAL_FGS_OUT/payloads.pkl", "wb") as f:
    pickle.dump(payloads, f)
print(f"Wrote payloads: FINAL_FGS_OUT/payloads.pkl count: {len(payloads)}")
PY
fi

echo "Wrote payloads: $PAYLOAD_FILE"

# ============================================================
# 🧠 Helper: Run py-spy safely
# ============================================================
run_flamegraph() {
    local label="$1"
    local module="$2"
    local output_svg="$OUTDIR/${label}_native.svg"

    echo
    echo "py-spy> Sampling ${label} (${module}) ..."
    py-spy record \
        -o "$output_svg" \
        --rate $RATE \
        --duration $DURATION \
        --flame "$PYTHON" - <<PYCODE
import json, pickle
with open("$PAYLOAD_FILE", "rb") as f:
    payloads = pickle.load(f)
for _ in range(50):
    [json.dumps(obj) for obj in payloads]
print("json C speedups active?", getattr(json, "_default_encoder", None) is not None)
PYCODE

    echo "py-spy> Wrote flamegraph data to '$output_svg'"
}

# ============================================================
# 🧪 Baseline: stdlib json
# ============================================================
run_flamegraph "json_stdlib" "json"

# ============================================================
# ⚡ Optimized: orjson
# ============================================================
run_flamegraph "orjson" "orjson" <<'PYCODE'
import json, pickle
import orjson
with open("$PAYLOAD_FILE", "rb") as f:
    payloads = pickle.load(f)
for _ in range(50):
    [orjson.dumps(obj) for obj in payloads]
print("orjson module:", orjson.__file__)
PYCODE

# ============================================================
# 📊 Summary
# ============================================================
echo
echo "== json vs orjson (native, C speedups ON) =="
date
echo "OUTDIR:  $OUTDIR"
echo "RATE:    $RATE Hz"
echo "DUR:     $DURATION s"
echo "Payload: $PAYLOAD_FILE"

echo
echo "Flame graphs:"
echo "  stdlib (native): $OUTDIR/json_stdlib_native.svg"
echo "  orjson (native): $OUTDIR/orjson_native.svg"
echo "[✓] Done."
