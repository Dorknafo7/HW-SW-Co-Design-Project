# HW-SW Co-Design Project

## Overview
This repository contains the code and build scripts used to run the **deepcopy** benchmark comparisons on an unmodified (baseline) CPython and on an optimized variant that uses `fastcopy.c`.  
The README below describes the repository layout and explains how to reproduce the benchmark workflow end-to-end inside the provided QEMU image.

> **Note:** everything needed to run the benchmark is under `src/`.  
> You do **not** need to manually move other files — the `src/` folder already contains the build script, the CPython tarball, the optimization source (`fastcopy.c`), and helper files.

---

## Repository structure
```
.
├── flame_graphs/                 # Contains flame graphs of baseline and optimized runs
├── src/
│   ├── script_deepcopy.py        # Main automation script (full build & benchmark workflow)
│   ├── fastcopy.c                # C-level optimization implementation
│   ├── copy.py                   # Python-level interface calling the optimized method
│   └── cpython-3.10.12.tar.gz    # Baseline CPython source tarball
└── report_deepcopy.pdf           # Project report and analysis
```

---

## Prerequisites
The entire workflow must be executed **inside the QEMU image** provided by the course staff.  
The script assumes a standard Ubuntu-based environment with the following tools (installed automatically if missing):

- `gcc`, `make`, `tar`, `wget`, `ca-certificates`
- `python3` and `python3-pip`
- `perf`
- `pyperformance`
- Basic system libraries (`libffi-dev`, `zlib1g-dev`, etc.)

> The script automatically repairs broken dependencies and installs everything required, including fallback fixes for known issues with Ubuntu 22.04 (e.g., `zlib1g`, `libexpat1`, and `libffi-dev`).

---

## How to run

1. **Clone the repository inside QEMU:**
   ```bash
   git clone https://github.com/Dorknafo7/HW-SW-Co-Design-Project.git
   cd HW-SW-Co-Design-Project/deepcopy/src/
   ```

2. **Make the script executable (if needed):**
   ```bash
   chmod +x script_deepcopy.py
   ```

3. **Run it:**
   ```bash
   ./script_deepcopy.py
   ```

---

## During the run (important)

While installing dependencies, the system may briefly display an **interactive “Package configuration” screen**.

This is a standard `apt` prompt asking which services should be restarted after library updates.

> **Action required:**  
> Simply press **Enter** (or **OK**) to continue.  
> No manual selection is needed — pressing Enter proceeds safely with the installation.

After that, the script continues automatically without further interaction.

---

## What the script does

When you run `script_deepcopy.py`, it:

1. **Auto-repairs the environment** (fixes broken or outdated system libraries).
2. **Extracts and builds** a baseline CPython (unmodified).
3. **Runs `pyperformance`** on the `deepcopy` benchmark and stores baseline results.
4. **Runs `perf stat`** for low-level hardware metrics.
5. **Cleans up** the baseline build.
6. **Applies the optimization (`fastcopy.c`, `copy.py`).**
7. **Rebuilds CPython** with the new optimization.
8. **Re-runs benchmarks and `perf` measurements.**
9. **Prints a detailed comparison** of both runs.

---

## Output
After completion, the following files will be generated automatically:

- `deepcopy_baseline.json` – pyperformance results for the baseline
- `deepcopy_optimized.json` – pyperformance results for the optimized version
- `perf_baseline.txt` – raw performance counters for baseline
- `perf_optimized.txt` – raw performance counters for optimized
- Comparison summary printed directly to the console

All files are saved under `src/`.
