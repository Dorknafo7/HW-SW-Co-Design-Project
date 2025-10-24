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
GREEN = "\033[92m"
RED = "\033[91m"
BOLD = "\033[1m"
RESET = "\033[0m"


def run(cmd, cwd=None, silent=False):
    """Run a shell command and handle errors gracefully."""
    print(f"🔹 Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, capture_output=silent, text=True)
    if result.returncode != 0:
        print("❌ Command failed:", " ".join(cmd))
        print(result.stderr)
        raise SystemExit(result.returncode)
    output = (result.stdout or "") + (result.stderr or "")
    if not silent:
        print(output)
    return output.strip() or None


def extract_tarball():
    """Extract CPython tarball and return the extracted directory path."""
    print("📦 Extracting CPython...")
    with tarfile.open(TARBALL, "r:gz") as tar:
        tar.extractall(ROOT)
        top_level = tar.getnames()[0].split("/")[0]
    return ROOT / top_level


def build_python(src_dir):
    """Configure, build, and install Python (silent build)."""
    print(f"⚙️  Building Python in {src_dir.name} ...")
    run(["./configure", f"--prefix={src_dir}/install"], cwd=src_dir, silent=True)
    run(["make", f"-j{os.cpu_count()}"], cwd=src_dir, silent=True)
    run(["make", "install"], cwd=src_dir, silent=True)
    return src_dir / "install" / "bin" / "python3"


def run_pyperf(python_path: Path, output_json: Path):
    """Run pyperformance deepcopy benchmark."""
    print(f"🚀 Running pyperformance benchmark for {python_path}")
    run([
        "python3", "-m", "pyperformance", "run",
        "--bench", BENCH,
        f"--python={python_path}",
        "-o", str(output_json)
    ])
    print(f"✅ Benchmark JSON saved to {output_json}")


def flush_cpu_caches():
    """Flush CPU caches between runs."""
    print("🧹 Flushing CPU caches...")
    os.system("sync; echo 3 > /proc/sys/vm/drop_caches")


def run_microbenchmark_perf(python_path: Path, output_txt: Path):
    """Run perf stat on deepcopy microbenchmark."""
    flush_cpu_caches()
    print(f"🚀 Running perf stat (deepcopy microbenchmark) for {python_path}")
    print("   Running perf to collect performance statistics...")

    perf_code = r"""
import copy, random

data = {
    'list_int': [random.randint(0, 1000) for _ in range(1000)],
    'nested_list': [[i for i in range(100)] for _ in range(50)],
    'dict_obj': {str(i): {'val': i, 'list': list(range(50))} for i in range(100)},
    'mix': [{'a': [1, 2, 3], 'b': (4, 5, 6)} for _ in range(200)]
}

for _ in range(50):
    _ = copy.deepcopy(data)
"""

    run([
        "perf", "stat",
        "-o", str(output_txt),
        "-e", "instructions,branches,branch-misses,cache-references,cache-misses",
        str(python_path), "-c", perf_code
    ], silent=True)

    print(f"✅ Perf results saved to {output_txt}")


def parse_pyperf_time(json_path: Path):
    """Extract mean time (µs) from pyperformance JSON output."""
    text = json_path.read_text()
    match = re.search(r'"values":\s*\[([\d.eE+-]+)', text)
    if match:
        values = [float(x) for x in re.findall(r"[\d.]+e?-?\d*", match.group(0))]
        if values:
            return statistics.mean(values) * 1e6
    return None


def parse_perf_stat(path: Path):
    """Parse key perf stat counters."""
    text = path.read_text()
    results = {}
    for key in ["instructions", "branches", "branch-misses", "cache-references", "cache-misses"]:
        match = re.search(rf"\s*([\d,]+)\s+{key}", text)
        if match:
            results[key] = int(match.group(1).replace(",", ""))
    return results


def compare_pyperf(base, opt):
    if not base or not opt:
        print("⚠️ Could not extract benchmark times automatically.")
        return
    diff = opt - base
    improvement = (base - opt) / base * 100
    color = GREEN if improvement > 0 else RED
    sign = "✅ Faster" if improvement > 0 else "❌ Slower"
    print(f"\n📊 Comparing benchmark results...\n{color}{BOLD}{sign}: {abs(improvement):.2f}% ({base:.1f} → {opt:.1f} µs){RESET}")
    print("(based on JSON benchmark results)\n")


def compare_perf(base_perf, opt_perf):
    print("\n📊 PERF Comparison (deepcopy microbenchmark):")
    all_keys = sorted(set(base_perf.keys()) | set(opt_perf.keys()))
    for key in all_keys:
        b = base_perf.get(key, 0)
        o = opt_perf.get(key, 0)
        if b == 0:
            continue
        improvement = (b - o) / b * 100
        better = improvement > 0
        color = GREEN if better else RED
        sign = "✅ Improved" if better else "❌ Worse"
        print(f"{color}{sign:12} {key:15}: {b:,} → {o:,} ({improvement:+.2f}%){RESET}")


def test_deepcopy_correctness(python_path: Path):
    """Run comprehensive correctness tests to ensure deepcopy behavior is preserved."""
    print("\n🧪 Running deepcopy correctness tests...")

    test_code = r"""
import copy

# --- Define diverse and composite test data ---
data = {
    "simple_list": [1, 2, [3, 4]],
    "nested_dict": {"a": 10, "b": {"c": 20, "d": [1, 2, 3]}},
    "tuple_mix": (1, [2, 3], {"x": 5}),
    "composite": [
        {"nums": [1, 2, 3], "inner": {"k": (1, 2)}},
        [ {"nested": [ {"v": 9} ]} ],
        ({"deep": {"copy": [42]}},)
    ],
    "empty_structs": {"list": [], "tuple": (), "dict": {}}
}

# Add self-reference to test memoization correctness
data["self"] = data

# Perform deepcopy using the optimized implementation
clone = copy.deepcopy(data)

# --- 1) Ensure distinct identity ---
assert id(clone) != id(data)

# --- 2) Ensure structural equality (excluding self-reference) ---
data_no_self = {k: v for k, v in data.items() if k != "self"}
clone_no_self = {k: v for k, v in clone.items() if k != "self"}
assert clone_no_self == data_no_self

# --- 3) Ensure independence of mutable elements ---
clone["simple_list"][2][0] = 999
clone["nested_dict"]["b"]["d"][1] = 777
clone["tuple_mix"][1][0] = 555
clone["composite"][0]["inner"]["k"] = (8, 8)
clone["empty_structs"]["list"].append("x")

# Verify original remains unchanged
assert data["simple_list"][2][0] == 3
assert data["nested_dict"]["b"]["d"][1] == 2
assert data["tuple_mix"][1][0] == 2
assert data["composite"][0]["inner"]["k"] == (1, 2)
assert data["empty_structs"]["list"] == []

# --- 4) Ensure self-reference preserved correctly ---
assert clone["self"] is clone
assert data["self"] is data

print("✅ deepcopy correctness verified successfully across all test cases!")
"""

    result = subprocess.run(
        [str(python_path), "-c", test_code],
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        print(result.stdout.strip())
    else:
        print("❌ deepcopy correctness test failed!")
        print(result.stderr)
        raise SystemExit(result.returncode)


def main():
    # === Handle test-only mode ===
    if len(sys.argv) >= 3 and sys.argv[1] == "--test-only":
        python_path = Path(sys.argv[2])
        if not python_path.exists():
            print(f"❌ Python path not found: {python_path}")
            sys.exit(1)
        test_deepcopy_correctness(python_path)
        sys.exit(0)

    # === BASELINE BUILD ===
    print("🏗️  Building baseline version...")
    base_dir = extract_tarball()
    base_python = build_python(base_dir)

    print("\n🚀 Running baseline benchmarks...")
    run_pyperf(base_python, BASELINE_JSON)
    base_time = parse_pyperf_time(BASELINE_JSON)
    run_microbenchmark_perf(base_python, BASELINE_PERF)

    print("🧹 Cleaning up baseline build...")
    subprocess.run(["rm", "-rf", str(base_dir)])

    # === OPTIMIZED BUILD ===
    print("\n🏗️  Building optimized version...")
    subprocess.run(["rm", "-rf", "cpython-3.10.12"])
    opt_dir = extract_tarball()
    print("📥 Copying optimization files...")
    (opt_dir / "Modules" / "fastcopy.c").write_bytes(FASTCOPY.read_bytes())
    (opt_dir / "Lib" / "copy.py").write_bytes(COPY_PY.read_bytes())
    (opt_dir / "Modules" / "Setup.local").write_text("fastcopy fastcopy.c\n")

    opt_python = build_python(opt_dir)

    print("\n🚀 Running optimized benchmarks...")
    run_pyperf(opt_python, OPT_JSON)
    opt_time = parse_pyperf_time(OPT_JSON)
    run_microbenchmark_perf(opt_python, OPT_PERF)

    # ✅ Verify correctness before comparing results
    test_deepcopy_correctness(opt_python)

    # === COMPARISON ===
    compare_pyperf(base_time, opt_time)
    compare_perf(parse_perf_stat(BASELINE_PERF), parse_perf_stat(OPT_PERF))

    print(f"\n📁 Results saved to:\n  {BASELINE_JSON}\n  {OPT_JSON}\n  {BASELINE_PERF}\n  {OPT_PERF}")


if __name__ == "__main__":
    main()
