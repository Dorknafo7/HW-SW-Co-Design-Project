#!/usr/bin/env bash
# Generate two native flame graphs (stdlib json vs orjson) using py-spy

set -euo pipefail

RATE="${RATE:-150}"
DUR="${DUR:-25}"
OUTDIR="${OUTDIR:-FINAL_FGS_OUT}"
PREFIX="${PREFIX:-}"
SETUP_DBG="${SETUP_DBG:-1}"
PFILE="${PFILE:-$OUTDIR/payloads.pkl}"

mkdir -p "$OUTDIR"
export PFILE DUR

# ---- Setup debug symbols (noninteractive, no restarts) ----
if [[ "$SETUP_DBG" == "1" ]] && command -v apt-get >/dev/null 2>&1; then
  if command -v sysctl >/dev/null 2>&1; then
    sudo sysctl -w kernel.perf_event_paranoid=1 >/dev/null || true
    sudo sysctl -w kernel.kptr_restrict=0 >/dev/null || true
  fi
  echo "🧩 Installing debug symbol packages..."
  sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get update -y -o Dpkg::Use-Pty=0 >/dev/null || true
  sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y \
      python3-dbg libc6-dbg elfutils -o Dpkg::Use-Pty=0 >/dev/null || true
  export DEBUGINFOD_URLS="${DEBUGINFOD_URLS:-https://debuginfod.ubuntu.com}"
fi

# ---- Ensure py-spy is available ----
if ! command -v py-spy >/dev/null 2>&1; then
  echo "Installing py-spy..."
  pip install py-spy==0.3.14 --quiet
fi

# ---- Generate deterministic payload ----
python3 - <<'PY'
import os, random, string, pickle
path = os.environ.get("PFILE") or "flames_out/payloads.pkl"
os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
random.seed(0)
def rec():
    s=''.join(random.choice(string.ascii_letters+string.digits) for _ in range(64))
    return {"id":1,"name":s,
            "vals":[random.random() for _ in range(100)],
            "flags":{c:(i%3==0) for i,c in enumerate(s[:26])},
            "nested":[{"k":i,"v":s[i%len(s)]} for i in range(200)]}
payloads=[rec() for _ in range(256)]
with open(path,"wb") as f: pickle.dump(payloads,f,pickle.HIGHEST_PROTOCOL)
print("Wrote payloads:", path, "count:", len(payloads))
PY

# ---- Filenames ----
STD_SVG="$OUTDIR/${PREFIX}json_stdlib_native.svg"
ORJ_SVG="$OUTDIR/${PREFIX}orjson_native.svg"
STD_OUT="$OUTDIR/${PREFIX}stdout_json_stdlib_native.txt"
ORJ_OUT="$OUTDIR/${PREFIX}stdout_orjson_native.txt"
REPORT="$OUTDIR/${PREFIX}iterations_report.txt"

# ---- 1) stdlib json ----
py-spy record --native --rate "$RATE" --duration "$DUR" -o "$STD_SVG" -- \
python3 -u - <<'PY' | tee "$STD_OUT"
import json, time, pickle, os, sys, json.encoder as E
print("json C speedups active?", getattr(E, "c_make_encoder", None) is not None, file=sys.stderr)
PFILE=os.environ["PFILE"]; DUR=float(os.environ.get("DUR","25"))
with open(PFILE,"rb") as f: payloads=pickle.load(f)
t0=time.time(); it=0; deadline=t0+DUR+2.0
while time.time()<deadline:
    for p in payloads:
        json.dumps(p, separators=(",",":"), ensure_ascii=False)
        it+=1
print("stdlib_native_iterations:", it)
time.sleep(0.5)
PY

# ---- 2) orjson ----
py-spy record --native --rate "$RATE" --duration "$DUR" -o "$ORJ_SVG" -- \
python3 -u - <<'PY' | tee "$ORJ_OUT"
import orjson, time, pickle, os, sys
print("orjson module:", orjson.__file__, file=sys.stderr)
PFILE=os.environ["PFILE"]; DUR=float(os.environ.get("DUR","25"))
with open(PFILE,"rb") as f: payloads=pickle.load(f)
t0=time.time(); it=0; deadline=t0+DUR+2.0
while time.time()<deadline:
    for p in payloads:
        orjson.dumps(p)
        it+=1
print("orjson_native_iterations:", it)
time.sleep(0.5)
PY

# ---- report ----
{
  echo "== json vs orjson (native, C speedups ON) =="
  date
  echo "OUTDIR:  $OUTDIR"
  echo "PREFIX:  ${PREFIX:-<none>}"
  echo "RATE:    $RATE Hz"
  echo "DUR:     $DUR s"
  echo "Payload: $PFILE"
  tail -n1 "$STD_OUT" || true
  tail -n1 "$ORJ_OUT"  || true
  echo
  echo "Flame graphs:"
  echo "  stdlib (native): $STD_SVG"
  echo "  orjson (native): $ORJ_SVG"
} | tee "$REPORT"

echo "[✓] Done."
