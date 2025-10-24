# HW-SW Co-Design Project

## Overview
This repository contains the code and build scripts used to run the **deepcopy** benchmark comparisons on an unmodified (baseline) CPython and on an optimized variant that uses `fastcopy.c`. The README below describes the (high-level) repository layout and how to run the benchmark workflow end-to-end inside the provided QEMU image.

> **Note:** everything needed to run the benchmark is under `src/`. You do **not** need to manually move other files from the repo to run the script — `src/` contains the build script, the CPython tarball reference, optimization source (e.g., `fastcopy.c`), and helper scripts.

## Repository structure
```
.
├── flame_graphs/                # Contains flame graphs of the baseline and optimized versions
├── src/                         # Contains all files required to reproduce the benchmark:
│   ├── build_and_benchmark_deepcopy.py   # Main automation script
│   ├── fastcopy.c                        # C-level optimization implementation
│   ├── copy.py                           # Python-level interface calling optimized methods
│   └── cpython-3.10.12.tar.xz            # Baseline CPython tarball used for building
└── report_deepcopy.pdf           # Project report and analysis
```

## Prerequisites
Run the workflow **inside the QEMU image** provided by the faculty (the environment the faculty supplied). The script assumes a typical Linux build environment inside that QEMU image with the following tools installed:

- `git`
- `tar`
- `make`, `gcc` (or toolchain required to build CPython)
- `python` (host utilities) and Python dev headers if needed for building
- `pyperformance` (or ability for the script to install/run it)
- `perf` (Linux performance counters)
- `bash` (for running the script)
- Enough disk space for extracting and building CPython

If anything is missing in the QEMU image, install it there.

## How to run (step-by-step)
1. **Clone the repo into the QEMU image**
   ```bash
   git clone https://github.com/Dorknafo7/HW-SW-Co-Design-Project.git
   cd HW-SW-Co-Design-Project
   ```

2. **Go into `src/`**
   ```bash
   cd src
   ```

3. **Make the main script executable (if needed)**
   ```bash
   chmod +x build_and_benchmark_deepcopy.py
   ```

4. **Run the script**
   ```bash
   ./build_and_benchmark_deepcopy.py
   ```

## What the `build_and_benchmark_deepcopy.py` script does (high level)
When you run the script from `src/`, it performs the following sequence automatically:

1. **Extract CPython from the provided tarball**
2. **Build the baseline CPython**
3. **Run pyperformance and `perf` on the `deepcopy` benchmark**
   - Saves results to files (e.g., baseline pyperf, perf data).
4. **Clean the baseline build**
5. **Apply optimization changes (e.g., enable `fastcopy.c`, modify `copy.py`)**
6. **Rebuild CPython with optimizations**
7. **Re-run pyperformance and `perf`**
8. **Compare baseline vs optimized results and print a summary**

## Output / results
After a successful run, the results contain:
- Baseline and optimized pyperformance output
- Baseline and optimized `perf` data
- Generated flame graphs in `flame_graphs/`
- Summary comparison printed to the console
