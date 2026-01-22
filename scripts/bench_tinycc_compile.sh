#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VC_FILE="${ROOT_DIR}/refs/vc/v.c"
VC_PATCH="${ROOT_DIR}/refs/vc_patches/arm64_closure_bytes.patch"
TINYCC_DIR="${ROOT_DIR}/refs/tinycc"
TINYCC_MBT_C_DIR="${ROOT_DIR}/tests/tinycc_mbt_c"
OUT_DIR="${ROOT_DIR}/target/bench"

TINYCC_MBT_BIN="${TINYCC_MBT_BIN:-${ROOT_DIR}/_build/native/release/build/tinycc.exe}"
TINYCC_REF_BIN="${TINYCC_REF_BIN:-${TINYCC_DIR}/tcc}"
CLANG_BIN="${CLANG_BIN:-clang}"
CLANG_FLAGS="${CLANG_FLAGS:-}"
DATASET="${DATASET:-vc}" # vc | tinycc | tinycc_mbt_c
APPLY_VC_PATCH="${APPLY_VC_PATCH:-1}"
TINYCC_SOURCES="${TINYCC_SOURCES:-}"
REPEAT="${REPEAT:-1}"
WARMUP="${WARMUP:-0}"
BUILD_MBT="${BUILD_MBT:-1}"
DETAIL="${DETAIL:-0}"
BASELINE_FILE="${BASELINE_FILE:-${ROOT_DIR}/README.md}"
REGRESSION_PCT="${REGRESSION_PCT:-0}"

export ROOT_DIR VC_FILE VC_PATCH TINYCC_DIR TINYCC_MBT_C_DIR OUT_DIR
export TINYCC_MBT_BIN TINYCC_REF_BIN CLANG_BIN CLANG_FLAGS DATASET APPLY_VC_PATCH TINYCC_SOURCES
export REPEAT WARMUP DETAIL BASELINE_FILE REGRESSION_PCT

usage() {
  cat <<'EOF'
Usage:
  scripts/bench_tinycc_compile.sh

Env vars:
  DATASET=vc|tinycc|tinycc_mbt_c
  APPLY_VC_PATCH=0|1    Apply refs/vc_patches/arm64_closure_bytes.patch (default: 1)
  TINYCC_SOURCES="..."  Space-separated refs/tinycc sources (default: tcc.c)
  REPEAT=N          Repeat the full compile set N times (default: 1)
  WARMUP=0|1        Run a warmup compile pass (default: 0)
  BUILD_MBT=0|1     Build tinycc.mbt before benchmarking (default: 1)
  DETAIL=0|1        Collect per-phase timings from tinycc.mbt -bench (default: 0)
  BASELINE_FILE=path  Baseline README to compare (default: README.md)
  REGRESSION_PCT=N    Flag regression if slower by N percent (default: 0)
  TINYCC_MBT_BIN=path
  TINYCC_REF_BIN=path
  CLANG_BIN=path
  CLANG_FLAGS="..." Extra flags for clang (default: none)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${BUILD_MBT}" == "1" ]]; then
  echo "Building tinycc.mbt (${TINYCC_MBT_BIN})"
  moon build --release --target native src
fi

if [[ ! -x "${TINYCC_MBT_BIN}" ]]; then
  echo "error: tinycc.mbt executable missing at ${TINYCC_MBT_BIN}" >&2
  exit 1
fi
if [[ ! -x "${TINYCC_REF_BIN}" ]]; then
  echo "error: refs/tinycc executable missing at ${TINYCC_REF_BIN}" >&2
  exit 1
fi
if ! command -v "${CLANG_BIN}" >/dev/null 2>&1; then
  echo "error: clang missing at ${CLANG_BIN}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

python3 - <<'PY'
import os
import re
import shutil
import subprocess
import sys
import time

root = os.environ["ROOT_DIR"]
vc_file = os.environ["VC_FILE"]
vc_patch = os.environ["VC_PATCH"]
tinycc_dir = os.environ["TINYCC_DIR"]
tinycc_mbt_c_dir = os.environ["TINYCC_MBT_C_DIR"]
out_dir = os.environ["OUT_DIR"]
dataset = os.environ["DATASET"]
apply_vc_patch = os.environ.get("APPLY_VC_PATCH", "1").lower() in ("1", "true", "yes")
tinycc_sources = os.environ.get("TINYCC_SOURCES", "").split()
repeat = int(os.environ["REPEAT"])
warmup = os.environ["WARMUP"] == "1"
detail = os.environ["DETAIL"] == "1"
baseline_file = os.environ.get("BASELINE_FILE")
regression_pct = float(os.environ.get("REGRESSION_PCT", "0"))

tinycc_mbt = os.environ["TINYCC_MBT_BIN"]
tinycc_ref = os.environ["TINYCC_REF_BIN"]
clang_bin = os.environ["CLANG_BIN"]
clang_flags = os.environ.get("CLANG_FLAGS", "").split()

compat_include = os.path.join(root, "compat", "include")

def include_args(paths, compat_after):
    args = []
    for path in paths:
        if compat_after and path == compat_include:
            continue
        args.extend(["-I", path])
    return args

def apply_vc_patch_if_needed():
    if not apply_vc_patch:
        return vc_file
    if not os.path.exists(vc_patch):
        sys.stderr.write(f"error: vc patch missing at {vc_patch}\n")
        sys.exit(1)
    if shutil.which("patch") is None:
        sys.stderr.write("error: patch command not found\n")
        sys.exit(1)
    vc_dir = os.path.join(out_dir, "vc_src")
    os.makedirs(vc_dir, exist_ok=True)
    patched = os.path.join(vc_dir, "v.c")
    shutil.copy2(vc_file, patched)
    proc = subprocess.run(
        ["patch", "-p1", "-i", vc_patch],
        cwd=vc_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        sys.stderr.write("error: failed to apply vc patch\n")
        sys.stderr.write(proc.stderr.decode("utf-8", "replace")[:400])
        sys.stderr.write("\n")
        sys.exit(1)
    return patched

def build_sources():
    sources = []
    if dataset == "vc":
        src = apply_vc_patch_if_needed()
        sources.append({
            "group": "vc",
            "path": src,
            "includes": [os.path.join(root, "compat", "include")],
        })
    elif dataset == "tinycc":
        names = tinycc_sources if tinycc_sources else ["tcc.c"]
        includes = [
            os.path.join(root, "compat", "include"),
            tinycc_dir,
            os.path.join(tinycc_dir, "include"),
        ]
        for name in names:
            path = name
            if not os.path.isabs(path):
                path = os.path.join(tinycc_dir, name)
            sources.append({
                "group": "tinycc",
                "path": path,
                "includes": includes,
            })
    elif dataset == "tinycc_mbt_c":
        include_dir = os.path.join(tinycc_mbt_c_dir, "include")
        lib_dir = os.path.join(tinycc_mbt_c_dir, "lib")
        includes = [include_dir, lib_dir]
        sources.append({
            "group": "tinycc_mbt_c",
            "path": os.path.join(tinycc_mbt_c_dir, "tinycc.c"),
            "includes": includes,
        })
        if os.path.isdir(lib_dir):
            for name in sorted(os.listdir(lib_dir)):
                if name.endswith(".c"):
                    sources.append({
                        "group": "tinycc_mbt_c",
                        "path": os.path.join(lib_dir, name),
                        "includes": includes,
                    })
    else:
        sys.stderr.write(f"error: unknown DATASET {dataset}\n")
        sys.exit(1)
    return sources

sources = build_sources()
if not sources:
    print("error: no sources selected", file=sys.stderr)
    sys.exit(1)
for item in sources:
    if not os.path.isfile(item["path"]):
        print(f"error: missing source {item['path']}", file=sys.stderr)
        sys.exit(1)

def run_compile(label, compiler, extra_args, capture_phases):
    total = 0.0
    phases = {"parse_us": 0, "sem_us": 0, "codegen_us": 0, "total_us": 0}
    for rep in range(repeat + (1 if warmup else 0)):
        rep_dir = os.path.join(out_dir, label, f"rep-{rep}")
        os.makedirs(rep_dir, exist_ok=True)
        start = time.perf_counter()
        for item in sources:
            group = item["group"]
            source = item["path"]
            base = os.path.basename(source)
            out_obj = os.path.join(rep_dir, f"{group}_{base}.o")
            cmd = [
                compiler,
                *include_args(item["includes"], label == "clang"),
                "-c",
                source,
                "-o", out_obj,
            ] + extra_args
            if capture_phases:
                proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            else:
                proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            if proc.returncode != 0:
                sys.stderr.write(f"compile failed: {label} {source}\n")
                sys.stderr.write(proc.stderr.decode("utf-8", "replace")[:400])
                sys.stderr.write("\n")
                sys.exit(1)
            if capture_phases and not (warmup and rep == 0):
                def get_us(parts, key):
                    us_key = f"{key}_us"
                    ms_key = f"{key}_ms"
                    if us_key in parts:
                        return int(parts[us_key])
                    if ms_key in parts:
                        return int(parts[ms_key]) * 1000
                    return 0
                for line in proc.stdout.decode("utf-8", "replace").splitlines():
                    if not line.startswith("bench: file="):
                        continue
                    parts = dict(item.split("=", 1) for item in line.split()[1:])
                    phases["parse_us"] += get_us(parts, "parse")
                    phases["sem_us"] += get_us(parts, "sem")
                    phases["codegen_us"] += get_us(parts, "codegen")
                    phases["total_us"] += get_us(parts, "total")
        end = time.perf_counter()
        if warmup and rep == 0:
            continue
        total += (end - start)
    return total / repeat, phases

print(f"Benchmarking {len(sources)} files (dataset={dataset}, repeat={repeat}, warmup={warmup})")

mbt_args = ["-bench"] if detail else []
mbt_time, mbt_phases = run_compile("tinycc_mbt", tinycc_mbt, mbt_args, detail)
ref_time, _ = run_compile("tinycc_ref", tinycc_ref, ["-B", tinycc_dir], False)
clang_time, _ = run_compile("clang", clang_bin, clang_flags, False)

ratio_mbt_ref = mbt_time / ref_time if ref_time > 0 else float("inf")
ratio_mbt_clang = mbt_time / clang_time if clang_time > 0 else float("inf")
ratio_ref_clang = ref_time / clang_time if clang_time > 0 else float("inf")
print(f"tinycc.mbt total: {mbt_time:.3f}s")
print(f"refs/tinycc total: {ref_time:.3f}s")
print(f"clang total: {clang_time:.3f}s")
print(f"ratio (mbt/ref): {ratio_mbt_ref:.2f}x")
print(f"ratio (mbt/clang): {ratio_mbt_clang:.2f}x")
print(f"ratio (ref/clang): {ratio_ref_clang:.2f}x")
if detail:
    avg_parse = mbt_phases["parse_us"] / (1000.0 * repeat)
    avg_sem = mbt_phases["sem_us"] / (1000.0 * repeat)
    avg_codegen = mbt_phases["codegen_us"] / (1000.0 * repeat)
    avg_total = mbt_phases["total_us"] / (1000.0 * repeat)
    print(f"tinycc.mbt phases (avg ms): parse={avg_parse:.3f} sem={avg_sem:.3f} codegen={avg_codegen:.3f} total={avg_total:.3f}")

def load_baseline(path, dataset_name):
    if not path or not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    marker = f"bench_tinycc_compile.sh DATASET={dataset_name}"
    start = None
    for idx, line in enumerate(lines):
        if marker in line:
            start = idx
            break
    if start is None:
        return None
    end = len(lines)
    for idx in range(start + 1, len(lines)):
        if lines[idx].startswith("### "):
            end = idx
            break
    block = "\n".join(lines[start:end])
    def grab(pattern):
        match = re.search(pattern, block)
        return float(match.group(1)) if match else None
    baseline = {
        "mbt_total_s": grab(r"tinycc\.mbt total:\s*([0-9.]+)s"),
        "ref_total_s": grab(r"refs/tinycc total:\s*([0-9.]+)s"),
        "clang_total_s": grab(r"clang total:\s*([0-9.]+)s"),
        "ratio_mbt_ref": grab(r"ratio \(mbt/ref\):\s*([0-9.]+)x"),
        "ratio_mbt_clang": grab(r"ratio \(mbt/clang\):\s*([0-9.]+)x"),
        "ratio_ref_clang": grab(r"ratio \(ref/clang\):\s*([0-9.]+)x"),
    }
    phase_match = re.search(
        r"phases avg ms:\s*parse=([0-9.]+)\s+sem=([0-9.]+)\s+codegen=([0-9.]+)\s+total=([0-9.]+)",
        block,
    )
    if phase_match:
        baseline["phase_parse_ms"] = float(phase_match.group(1))
        baseline["phase_sem_ms"] = float(phase_match.group(2))
        baseline["phase_codegen_ms"] = float(phase_match.group(3))
        baseline["phase_total_ms"] = float(phase_match.group(4))
    if all(value is None for value in baseline.values()):
        return None
    return baseline

def fmt(value, unit):
    if unit == "s":
        return f"{value:.3f}s"
    if unit == "x":
        return f"{value:.2f}x"
    if unit == "ms":
        return f"{value:.3f}ms"
    return f"{value:.3f}{unit}"

def report_delta(label, current, baseline, unit):
    delta = current - baseline
    delta_pct = (delta / baseline * 100.0) if baseline else 0.0
    is_regression = delta_pct > regression_pct
    sign = "+" if delta >= 0 else ""
    status = "REGRESSION" if is_regression else "ok"
    print(
        f"baseline {label}: {fmt(baseline, unit)} "
        f"(current {fmt(current, unit)}, delta {sign}{fmt(delta, unit)}, {sign}{delta_pct:.1f}%) {status}"
    )
    return is_regression

baseline = load_baseline(baseline_file, dataset)
if baseline:
    print(f"Baseline ({baseline_file})")
    regressions = []
    if baseline.get("mbt_total_s") is not None:
        regressions.append(report_delta("tinycc.mbt total", mbt_time, baseline["mbt_total_s"], "s"))
    if baseline.get("ratio_mbt_ref") is not None:
        regressions.append(report_delta("ratio (mbt/ref)", ratio_mbt_ref, baseline["ratio_mbt_ref"], "x"))
    if detail and baseline.get("phase_total_ms") is not None:
        regressions.append(report_delta("phases total", avg_total, baseline["phase_total_ms"], "ms"))
    if any(regressions):
        print("Regression detected.")
    else:
        print("No regression detected.")
else:
    print(f"Baseline not found for DATASET={dataset} in {baseline_file}")
PY
