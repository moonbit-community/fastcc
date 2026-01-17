#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CTEST_DIR="${ROOT_DIR}/refs/mbtcc/ctest"
CTEST2_DIR="${ROOT_DIR}/refs/mbtcc/ctest2"
PATCH_DIR="${ROOT_DIR}/tests/mbtcc/ctest2_patches"
EXTRA_HDR="${ROOT_DIR}/tests/mbtcc/extra.h"
OUT_DIR="${ROOT_DIR}/target/bench"

TINYCC_MBT_BIN="${TINYCC_MBT_BIN:-${ROOT_DIR}/_build/native/release/build/tinycc.exe}"
TINYCC_REF_BIN="${TINYCC_REF_BIN:-${ROOT_DIR}/refs/tinycc/tcc}"
MODE="${MODE:-both}" # ctest | ctest2 | both
REPEAT="${REPEAT:-1}"
WARMUP="${WARMUP:-0}"
BUILD_MBT="${BUILD_MBT:-1}"
DETAIL="${DETAIL:-0}"

export ROOT_DIR CTEST_DIR CTEST2_DIR PATCH_DIR EXTRA_HDR OUT_DIR
export TINYCC_MBT_BIN TINYCC_REF_BIN MODE REPEAT WARMUP DETAIL

usage() {
  cat <<'EOF'
Usage:
  scripts/bench_tinycc_compile.sh

Env vars:
  MODE=ctest|ctest2|both
  REPEAT=N          Repeat the full compile set N times (default: 1)
  WARMUP=0|1        Run a warmup compile pass (default: 0)
  BUILD_MBT=0|1     Build tinycc.mbt before benchmarking (default: 1)
  DETAIL=0|1        Collect per-phase timings from tinycc.mbt -bench (default: 0)
  TINYCC_MBT_BIN=path
  TINYCC_REF_BIN=path
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
if [[ ! -f "${EXTRA_HDR}" ]]; then
  echo "error: missing ${EXTRA_HDR}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

python3 - <<'PY'
import os
import subprocess
import sys
import time

root = os.environ["ROOT_DIR"]
ctest_dir = os.environ["CTEST_DIR"]
ctest2_dir = os.environ["CTEST2_DIR"]
patch_dir = os.environ["PATCH_DIR"]
extra_hdr = os.environ["EXTRA_HDR"]
out_dir = os.environ["OUT_DIR"]
mode = os.environ["MODE"]
repeat = int(os.environ["REPEAT"])
warmup = os.environ["WARMUP"] == "1"
detail = os.environ["DETAIL"] == "1"

tinycc_mbt = os.environ["TINYCC_MBT_BIN"]
tinycc_ref = os.environ["TINYCC_REF_BIN"]

def list_tests():
    items = []
    if mode in ("ctest", "both"):
        for name in sorted(os.listdir(ctest_dir)):
            if name.endswith(".c"):
                items.append(("ctest", os.path.join(ctest_dir, name), ctest_dir))
    if mode in ("ctest2", "both"):
        ctest2_names = set()
        for name in sorted(os.listdir(ctest2_dir)):
            if not name.endswith(".c"):
                continue
            ctest2_names.add(name)
            patch = os.path.join(patch_dir, name)
            path = patch if os.path.exists(patch) else os.path.join(ctest2_dir, name)
            items.append(("ctest2", path, ctest2_dir))
        for name in sorted(os.listdir(patch_dir)):
            if not name.endswith(".c"):
                continue
            if name in ctest2_names:
                continue
            items.append(("ctest2", os.path.join(patch_dir, name), ctest2_dir))
    return items

tests = list_tests()
if not tests:
    print("error: no tests selected", file=sys.stderr)
    sys.exit(1)

def run_compile(label, compiler, extra_args, capture_phases):
    total = 0.0
    phases = {"parse_us": 0, "sem_us": 0, "codegen_us": 0, "total_us": 0}
    for rep in range(repeat + (1 if warmup else 0)):
        rep_dir = os.path.join(out_dir, label, f"rep-{rep}")
        wrap_dir = os.path.join(out_dir, "wrap")
        os.makedirs(rep_dir, exist_ok=True)
        os.makedirs(wrap_dir, exist_ok=True)
        start = time.perf_counter()
        for group, path, include_dir in tests:
            base = os.path.basename(path)
            source = path
            if group == "ctest2":
                wrap_c = os.path.join(wrap_dir, f"{group}_{base}")
                with open(wrap_c, "w", encoding="utf-8") as f:
                    f.write(f'#include "{extra_hdr}"\n')
                    f.write(f'#include "{path}"\n')
                source = wrap_c
            out_obj = os.path.join(rep_dir, f"{group}_{base}.o")
            cmd = [
                compiler,
                "-I", os.path.join(root, "compat", "include"),
                "-I", include_dir,
                "-c",
                source,
                "-o", out_obj,
            ] + extra_args
            if capture_phases:
                proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            else:
                proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            if proc.returncode != 0:
                sys.stderr.write(f"compile failed: {label} {path}\n")
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

print(f"Benchmarking {len(tests)} files (mode={mode}, repeat={repeat}, warmup={warmup})")

mbt_args = ["-bench"] if detail else []
mbt_time, mbt_phases = run_compile("tinycc_mbt", tinycc_mbt, mbt_args, detail)
ref_time, _ = run_compile("tinycc_ref", tinycc_ref, ["-B", os.path.join(root, "refs", "tinycc")], False)

ratio = mbt_time / ref_time if ref_time > 0 else float("inf")
print(f"tinycc.mbt total: {mbt_time:.3f}s")
print(f"refs/tinycc total: {ref_time:.3f}s")
print(f"ratio (mbt/ref): {ratio:.2f}x")
if detail:
    avg_parse = mbt_phases["parse_us"] / (1000.0 * repeat)
    avg_sem = mbt_phases["sem_us"] / (1000.0 * repeat)
    avg_codegen = mbt_phases["codegen_us"] / (1000.0 * repeat)
    avg_total = mbt_phases["total_us"] / (1000.0 * repeat)
    print(f"tinycc.mbt phases (avg ms): parse={avg_parse:.3f} sem={avg_sem:.3f} codegen={avg_codegen:.3f} total={avg_total:.3f}")
PY
