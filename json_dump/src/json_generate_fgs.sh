#!/usr/bin/env bash
# Two native flame graphs with C speedups ON for stdlib json (like pyperformance) and orjson.
# Usage:
#   OUTDIR=flames PREFIX=runA_ RATE=150 DUR=25 bash json_orjson_native_flames.sh
# Env knobs:
#   RATE=150, DUR=25        # sampling rate and recording duration
#   OUTDIR=flames_out       # where to write SVGs
#   PREFIX=runA_            # filename prefix
#   SETUP_DBG=1             # install python3-dbg/libc6-dbg to improve native stack depth (default 1)

set -euo pipefail

# ---- config (env) ----
RATE="${RATE:-150}"                     # 120–200 is a good sweet spot on VMs
DUR="${DUR:-25}"
OUTDIR="${OUTDIR:-FINAL_FGS_OUT}"
PREFIX="${PREFIX:-}"
SETUP_DBG="${SETUP_DBG:-1}"
PFILE="${PFILE:-$OUTDIR/payloads.pkl}"

mkdir -p "$OUTDIR"
export PFILE DUR

# ---- optional: improve native symbolization/unwinding ----
if [[ "$SETUP_DBG" == "1" ]] && command -v apt-get >/dev/null 2>&1; then
  if command -v sysctl >/dev/null 2>&1; then
    sudo sysctl -w kernel.perf_event_paranoid=1 >/dev/null || true
    sudo sysctl -w kernel.kptr_restrict=0 >/dev/null || true
  fi
  sudo apt-get update -y >/dev/null || true
  sudo apt-get install -y python3-dbg libc6-dbg elfutils >/dev/null || true
  export DEBUGINFOD_URLS="${DEBUGINFOD_URLS:-https://debuginfod.ubuntu.com}"
fi

# ---- deterministic payload shared by both runs ----
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

# ---- filenames ----
STD_SVG="$OUTDIR/${PREFIX}json_stdlib_native.svg"
ORJ_SVG="$OUTDIR/${PREFIX}orjson_native.svg"
STD_OUT="$OUTDIR/${PREFIX}stdout_json_stdlib_native.txt"
ORJ_OUT="$OUTDIR/${PREFIX}stdout_orjson_native.txt"
REPORT="$OUTDIR/${PREFIX}iterations_report.txt"

# ---- 1) stdlib json (C speedups ON; pyperformance-style). MUST use --native. ----
py-spy record --native --rate "$RATE" --duration "$DUR" -o "$STD_SVG" -- \
python3 -u - <<'PY' | tee "$STD_OUT"
import json, time, pickle, os, sys, json.encoder as E
# Self-check: confirm C speedups are active
print("json C speedups active?", getattr(E, "c_make_encoder", None) is not None, file=sys.stderr)
PFILE=os.environ["PFILE"]; DUR=float(os.environ.get("DUR","25"))
with open(PFILE,"rb") as f: payloads=pickle.load(f)
t0=time.time(); it=0; deadline=t0+DUR+2.0
while time.time()<deadline:
    for p in payloads:
        # Fair vs orjson: compact (no spaces), UTF-8
        json.dumps(p, separators=(",",":"), ensure_ascii=False)
        it+=1
print("stdlib_native_iterations:", it)
time.sleep(0.5)
PY

# ---- 2) orjson (native). Also shows native frames under the orjson .so. ----
py-spy record --native --rate "$RATE" --duration "$DUR" -o "$ORJ_SVG" -- \
python3 -u - <<'PY' | tee "$ORJ_OUT"
import orjson, time, pickle, os, sys
print("orjson module:", orjson.__file__, file=sys.stderr)  # where the .so comes from
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
