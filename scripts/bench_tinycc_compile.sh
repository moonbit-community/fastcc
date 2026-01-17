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
DATASET="${DATASET:-vc}" # vc | tinycc | tinycc_mbt_c
APPLY_VC_PATCH="${APPLY_VC_PATCH:-1}"
TINYCC_SOURCES="${TINYCC_SOURCES:-}"
REPEAT="${REPEAT:-1}"
WARMUP="${WARMUP:-0}"
BUILD_MBT="${BUILD_MBT:-1}"
DETAIL="${DETAIL:-0}"

export ROOT_DIR VC_FILE VC_PATCH TINYCC_DIR TINYCC_MBT_C_DIR OUT_DIR
export TINYCC_MBT_BIN TINYCC_REF_BIN DATASET APPLY_VC_PATCH TINYCC_SOURCES
export REPEAT WARMUP DETAIL

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

mkdir -p "${OUT_DIR}"

python3 - <<'PY'
import os
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

tinycc_mbt = os.environ["TINYCC_MBT_BIN"]
tinycc_ref = os.environ["TINYCC_REF_BIN"]

def include_args(paths):
    args = []
    for path in paths:
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
                *include_args(item["includes"]),
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
