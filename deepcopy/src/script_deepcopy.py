#!/usr/bin/env python3
import os
import sys
import subprocess
import tarfile
import re
from pathlib import Path
import statistics

# === CONFIGURATION ===
ROOT = Path(__file__).resolve().parent
TARBALL = ROOT / "cpython-3.10.12.tar.gz"
FASTCOPY = ROOT / "fastcopy.c"
COPY_PY = ROOT / "copy.py"
BASELINE_JSON = ROOT / "deepcopy_baseline.json"
OPT_JSON = ROOT / "deepcopy_optimized.json"
BASELINE_PERF = ROOT / "perf_baseline.txt"
OPT_PERF = ROOT / "perf_optimized.txt"
BENCH = "deepcopy"

# === COLORS ===
GREEN = "\033[92m"; RED = "\033[91m"; YELLOW = "\033[93m"; BOLD = "\033[1m"; RESET = "\033[0m"

def run(cmd, cwd=None, silent=False, check=True):
    print(f"🔹 Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, capture_output=silent, text=True)
    if check and result.returncode != 0:
        print("❌ Command failed:", " ".join(cmd))
        print(result.stderr)
        raise SystemExit(result.returncode)
    output = (result.stdout or "") + (result.stderr or "")
    if not silent:
        print(output)
    return output.strip() or None


# === ENVIRONMENT SETUP (FULL AUTO-FIX) ===
def setup_environment():
    print("🧩 Checking and installing system dependencies...")

    # --- Ensure repositories ---
    sources = "/etc/apt/sources.list"
    with open(sources) as f:
        if "jammy-security" not in f.read():
            print("🔧 Adding jammy-security repository...")
            with open(sources, "a") as out:
                out.write("\ndeb http://security.ubuntu.com/ubuntu jammy-security main restricted universe multiverse\n")

    run(["apt-get", "update"])
    run(["apt-mark", "unhold", "libexpat1", "libsystemd0", "systemd", "udev",
         "libudev1", "libnss-systemd", "libpam-systemd", "systemd-timesyncd",
         "systemd-sysv"], check=False)

    # --- Fix libexpat chain ---
    print("🔧 Repairing libexpat1 chain...")
    run([
        "apt-get", "install", "-y",
        "--allow-downgrades", "--allow-change-held-packages", "--allow-remove-essential",
        "libexpat1=2.4.7-1ubuntu0.6", "libexpat1-dev"
    ], check=False)

    # --- Fix zlib/libffi mismatches automatically ---
    print("🔧 Checking and repairing zlib/libffi dependencies...")
    run(["apt-mark", "unhold", "zlib1g"], check=False)
    run([
        "apt-get", "install", "-y", "--allow-downgrades",
        "zlib1g=1:1.2.11.dfsg-2ubuntu9.2",
        "zlib1g-dev=1:1.2.11.dfsg-2ubuntu9.2",
        "libffi-dev",
        "--allow-change-held-packages"
    ], check=False)
    run(["apt-get", "install", "-f", "-y"], check=False)

    # --- Verify ffi/zlib headers exist ---
    ffi_ok = os.path.exists("/usr/include/ffi.h") or os.path.exists("/usr/include/x86_64-linux-gnu/ffi.h")
    zlib_ok = os.path.exists("/usr/include/zlib.h")
    if not (ffi_ok and zlib_ok):
        print("❌ Missing ffi.h or zlib.h — retrying fix...")
        run([
            "apt-get", "install", "-y", "--allow-downgrades",
            "libffi-dev", "zlib1g-dev", "zlib1g",
            "--allow-change-held-packages"
        ], check=False)
    else:
        print("✅ zlib/libffi toolchain verified OK.")

    # --- Continue dependency installation ---
    run(["apt-get", "dist-upgrade", "-y", "--allow-change-held-packages"], check=False)
    run(["apt-get", "-f", "install", "-y", "--allow-change-held-packages"], check=False)
    run(["apt-get", "install", "-y", "libfontconfig1-dev", "libxft-dev", "--allow-change-held-packages"], check=False)
    run([
        "apt-get", "install", "-y", "--allow-change-held-packages",
        "build-essential", "libssl-dev", "libbz2-dev", "liblzma-dev",
        "libreadline-dev", "libsqlite3-dev", "tk-dev", "uuid-dev",
        "wget", "ca-certificates", "python3-pip",
        "linux-tools-common", f"linux-tools-{os.uname().release}"
    ], check=False)

    # --- pyperformance ---
    try:
        subprocess.run(["python3", "-m", "pyperformance", "--version"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    except subprocess.CalledProcessError:
        print("📦 Installing pyperformance...")
        run(["python3", "-m", "pip", "install", "--upgrade", "pip"])
        run(["python3", "-m", "pip", "install", "pyperformance"])

    print("✅ Environment ready!\n")


# === CPython build and benchmark helpers ===
def extract_tarball():
    print("📦 Extracting CPython...")
    with tarfile.open(TARBALL, "r:gz") as tar:
        tar.extractall(ROOT)
        top = tar.getnames()[0].split("/")[0]
    return ROOT / top

def build_python(src):
    print(f"⚙️  Building Python in {src.name} ...")
    run(["./configure", f"--prefix={src}/install"], cwd=src, silent=True)
    run(["make", f"-j{os.cpu_count()}"], cwd=src, silent=True)
    run(["make", "install"], cwd=src, silent=True)
    return src / "install" / "bin" / "python3"

def run_pyperf(python, out):
    print(f"🚀 Running pyperformance benchmark for {python}")
    run(["python3", "-m", "pyperformance", "run", "--bench", BENCH, f"--python={python}", "-o", str(out)])
    print(f"✅ Benchmark JSON saved to {out}")

def flush_cpu_caches(): os.system("sync; echo 3 > /proc/sys/vm/drop_caches")

def run_microbenchmark_perf(python, out):
    flush_cpu_caches()
    print(f"🚀 Running perf stat (deepcopy microbenchmark)...")
    code = r"""
import copy, random
data = {'a':[random.randint(0,1000) for _ in range(1000)]}
for _ in range(50): _ = copy.deepcopy(data)
"""
    run(["perf","stat","-o",str(out),"-e","instructions,branches,branch-misses,cache-references,cache-misses",str(python),"-c",code],silent=True)
    print(f"✅ Perf results saved to {out}")

def parse_pyperf_time(json_path):
    text = json_path.read_text()
    match = re.search(r'"values":\s*\[([\d.eE+-]+)', text)
    if match:
        values = [float(x) for x in re.findall(r"[\d.]+e?-?\d*", match.group(0))]
        if values:
            return statistics.mean(values) * 1e6
    return None

def parse_perf(path):
    text = path.read_text()
    res = {}
    for k in ["instructions","branches","branch-misses","cache-references","cache-misses"]:
        m = re.search(rf"\s*([\d,]+)\s+{k}", text)
        if m: res[k]=int(m.group(1).replace(",",""))
    return res

def compare_pyperf(base, opt):
    if not base or not opt:
        print("⚠️ Could not extract benchmark times automatically.")
        return
    imp = (base - opt) / base * 100
    color = GREEN if imp > 0 else RED
    sign = "✅ Faster" if imp > 0 else "❌ Slower"
    print(f"\n📊 Comparing benchmark results...\n{color}{BOLD}{sign}: {abs(imp):.2f}% ({base:.1f} → {opt:.1f} µs){RESET}")
    print("(based on JSON benchmark results)\n")

def compare_perf(b,o):
    print("\n📊 PERF Comparison:")
    def r(a,b): return a/b if b else 0
    for name,(bv,ov) in {
        "instructions":(b.get("instructions",0),o.get("instructions",0)),
        "branch-miss rate":(r(b.get("branch-misses",0),b.get("branches",1)),r(o.get("branch-misses",0),o.get("branches",1))),
        "cache-miss rate":(r(b.get("cache-misses",0),b.get("cache-references",1)),r(o.get("cache-misses",0),o.get("cache-references",1)))
    }.items():
        imp=(bv-ov)/bv*100 if bv else 0
        col=GREEN if imp>0 else RED if imp<-1 else YELLOW
        sign="✅ IMPROVED" if imp>0 else "❌ REGRESSED" if imp<-1 else "≈ NO CHANGE"
        fmt=lambda x:f"{x*100:.2f}%" if "rate" in name else f"{x:,}"
        print(f"{col}{sign:12} {name:18}: {fmt(bv):>10} → {fmt(ov):>10} ({imp:+.2f}%){RESET}")


# === MAIN WORKFLOW ===
def main():
    setup_environment()

    print("🏗️  Building baseline version...")
    base = extract_tarball()
    base_py = build_python(base)
    run_pyperf(base_py, BASELINE_JSON)
    run_microbenchmark_perf(base_py, BASELINE_PERF)
    subprocess.run(["rm","-rf",str(base)])

    print("\n🏗️  Building optimized version...")
    subprocess.run(["rm","-rf","cpython-3.10.12"])
    opt = extract_tarball()
    (opt/"Modules"/"fastcopy.c").write_bytes(FASTCOPY.read_bytes())
    (opt/"Lib"/"copy.py").write_bytes(COPY_PY.read_bytes())
    (opt/"Modules"/"Setup.local").write_text("fastcopy fastcopy.c\n")
    opt_py = build_python(opt)
    run_pyperf(opt_py, OPT_JSON)
    run_microbenchmark_perf(opt_py, OPT_PERF)

    # === Compare benchmark results ===
    try:
        base_time = parse_pyperf_time(BASELINE_JSON)
        opt_time = parse_pyperf_time(OPT_JSON)
        compare_pyperf(base_time, opt_time)
    except Exception as e:
        print(f"⚠️ Failed to parse pyperformance results: {e}")

    # === Compare PERF results ===
    compare_perf(parse_perf(BASELINE_PERF), parse_perf(OPT_PERF))

    print(f"\n📁 Results saved to:\n  {BASELINE_JSON}\n  {OPT_JSON}\n  {BASELINE_PERF}\n  {OPT_PERF}")


if __name__ == "__main__":
    main()
