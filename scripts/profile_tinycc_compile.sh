#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VC_FILE="${ROOT_DIR}/refs/vc/v.c"
VC_PATCH="${ROOT_DIR}/refs/vc_patches/arm64_closure_bytes.patch"
TINYCC_DIR="${ROOT_DIR}/refs/tinycc"
TINYCC_MBT_C_DIR="${ROOT_DIR}/tests/tinycc_mbt_c"

TINYCC_MBT_BIN="${TINYCC_MBT_BIN:-${ROOT_DIR}/_build/native/release/build/tinycc.exe}"
DATASET="${DATASET:-vc}" # vc | tinycc | tinycc_mbt_c
APPLY_VC_PATCH="${APPLY_VC_PATCH:-1}"
TINYCC_SOURCES="${TINYCC_SOURCES:-}"
PROFILE_SOURCE="${PROFILE_SOURCE:-}"
PROFILE_INCLUDES="${PROFILE_INCLUDES:-}"
BUILD_MBT="${BUILD_MBT:-1}"
TRACE_DIR="${TRACE_DIR:-${ROOT_DIR}/target/trace}"
TRACE_NAME="${TRACE_NAME:-}"
XCTRACE_TEMPLATE="${XCTRACE_TEMPLATE:-Time Profiler}"

export ROOT_DIR VC_FILE VC_PATCH TINYCC_DIR TINYCC_MBT_C_DIR
export TINYCC_MBT_BIN DATASET APPLY_VC_PATCH TINYCC_SOURCES PROFILE_SOURCE PROFILE_INCLUDES

usage() {
  cat <<'EOF'
Usage:
  scripts/profile_tinycc_compile.sh

Env vars:
  DATASET=vc|tinycc|tinycc_mbt_c
  APPLY_VC_PATCH=0|1        Apply refs/vc_patches/arm64_closure_bytes.patch (default: 1)
  TINYCC_SOURCES="..."      Space-separated refs/tinycc sources (default: tcc.c)
  PROFILE_SOURCE=path       Override source file to compile (relative to repo ok)
  PROFILE_INCLUDES="..."    Override include dirs (space-separated), used with PROFILE_SOURCE
  BUILD_MBT=0|1             Build tinycc.mbt before profiling (default: 1)
  TRACE_DIR=path            Output directory for .trace and summary (default: target/trace)
  TRACE_NAME=name.trace     Trace file name (default: tinycc_${DATASET}_timeprof_YYYYmmdd_HHMMSS.trace)
  XCTRACE_TEMPLATE=name     xctrace template (default: Time Profiler)
  TINYCC_MBT_BIN=path
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if ! xcrun --find xctrace >/dev/null 2>&1; then
  echo "error: xctrace not found (install Xcode or set DEVELOPER_DIR)" >&2
  exit 1
fi

if [[ "${BUILD_MBT}" == "1" ]]; then
  echo "Building tinycc.mbt (${TINYCC_MBT_BIN})"
  moon build --release --target native src
fi

if [[ ! -x "${TINYCC_MBT_BIN}" ]]; then
  echo "error: tinycc.mbt executable missing at ${TINYCC_MBT_BIN}" >&2
  exit 1
fi

mkdir -p "${TRACE_DIR}"

if [[ -z "${TRACE_NAME}" ]]; then
  TRACE_NAME="tinycc_${DATASET}_timeprof_$(date +%Y%m%d_%H%M%S).trace"
fi
TRACE_PATH="${TRACE_DIR}/${TRACE_NAME}"
TRACE_BASENAME="${TRACE_NAME%.trace}"

eval "$(python3 - <<'PY'
import os
import shutil
import subprocess
import sys
import shlex

root = os.environ["ROOT_DIR"]
vc_file = os.environ["VC_FILE"]
vc_patch = os.environ["VC_PATCH"]
tinycc_dir = os.environ["TINYCC_DIR"]
tinycc_mbt_c_dir = os.environ["TINYCC_MBT_C_DIR"]
dataset = os.environ["DATASET"]
apply_vc_patch = os.environ.get("APPLY_VC_PATCH", "1").lower() in ("1", "true", "yes")
tinycc_sources = os.environ.get("TINYCC_SOURCES", "").split()
profile_source = os.environ.get("PROFILE_SOURCE", "").strip()
profile_includes = os.environ.get("PROFILE_INCLUDES", "").split()

def apply_vc_patch_if_needed():
    if not apply_vc_patch:
        return vc_file
    if not os.path.exists(vc_patch):
        sys.stderr.write(f"error: vc patch missing at {vc_patch}\n")
        sys.exit(1)
    if shutil.which("patch") is None:
        sys.stderr.write("error: patch command not found\n")
        sys.exit(1)
    vc_dir = os.path.join(root, "target", "trace", "vc_src")
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

def pick_source():
    if profile_source:
        src = profile_source
        if not os.path.isabs(src):
            src = os.path.join(root, src)
        includes = profile_includes
        return src, includes

    if dataset == "vc":
        src = apply_vc_patch_if_needed()
        includes = [os.path.join(root, "compat", "include")]
    elif dataset == "tinycc":
        name = tinycc_sources[0] if tinycc_sources else "tcc.c"
        src = name if os.path.isabs(name) else os.path.join(tinycc_dir, name)
        includes = [
            os.path.join(root, "compat", "include"),
            tinycc_dir,
            os.path.join(tinycc_dir, "include"),
        ]
    elif dataset == "tinycc_mbt_c":
        src = os.path.join(tinycc_mbt_c_dir, "tinycc.c")
        includes = [
            os.path.join(tinycc_mbt_c_dir, "include"),
            os.path.join(tinycc_mbt_c_dir, "lib"),
        ]
    else:
        sys.stderr.write(f"error: unknown DATASET {dataset}\n")
        sys.exit(1)
    return src, includes

src, includes = pick_source()
if not os.path.isfile(src):
    sys.stderr.write(f"error: missing source {src}\n")
    sys.exit(1)
include_args = " ".join(f"-I {path}" for path in includes if path)

out_obj = os.path.join(root, "target", "trace", f"{os.path.basename(src)}.o")
print(f"SRC={shlex.quote(src)}")
print(f"INCLUDE_ARGS={shlex.quote(include_args)}")
print(f"OUT_OBJ={shlex.quote(out_obj)}")
PY
)"

echo "Profiling compile: ${SRC}"
echo "Trace output: ${TRACE_PATH}"

DEVELOPER_DIR="${DEVELOPER_DIR:-}" \
xcrun xctrace record --template "${XCTRACE_TEMPLATE}" \
  --output "${TRACE_PATH}" \
  --launch -- "${TINYCC_MBT_BIN}" ${INCLUDE_ARGS} -c "${SRC}" -o "${OUT_OBJ}"

TIME_PROFILE_XML="${TRACE_DIR}/${TRACE_BASENAME}_time-profile.xml"
SUMMARY_TXT="${TRACE_DIR}/${TRACE_BASENAME}_summary.txt"

xcrun xctrace export --input "${TRACE_PATH}" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  --output "${TIME_PROFILE_XML}"

python3 - <<PY
import xml.etree.ElementTree as ET
from collections import Counter
import pathlib

xml_path = pathlib.Path("${TIME_PROFILE_XML}")
summary_path = pathlib.Path("${SUMMARY_TXT}")

root = ET.parse(xml_path).getroot()

frame_by_id = {}
for frame in root.iter("frame"):
    fid = frame.get("id")
    if fid and fid not in frame_by_id:
        frame_by_id[fid] = frame

binary_by_id = {}
for binary in root.iter("binary"):
    bid = binary.get("id")
    if bid and bid not in binary_by_id:
        binary_by_id[bid] = binary

frame_binary_name = {}
for fid, frame in frame_by_id.items():
    b = frame.find("binary")
    if b is not None:
        bref = b.get("ref")
        if bref and bref in binary_by_id:
            b = binary_by_id[bref]
        name = b.get("name") if b is not None else None
        if name:
            frame_binary_name[fid] = name

def resolve_frame(elem):
    ref = elem.get("ref")
    if ref:
        return frame_by_id.get(ref)
    return elem

def collect_counts(leaf_only):
    counts = Counter()
    for row in root.iter("row"):
        backtrace = row.find("backtrace")
        if backtrace is None:
            continue
        frames = backtrace.findall("frame")
        if not frames:
            continue
        frames = frames[:1] if leaf_only else frames
        for frame in frames:
            f = resolve_frame(frame)
            if f is None:
                continue
            fid = f.get("id") or f.get("ref")
            if frame_binary_name.get(fid) != "tinycc.exe":
                continue
            name = f.get("name") or "<unknown>"
            counts[name] += 1
    return counts

inclusive = collect_counts(leaf_only=False)
leaf = collect_counts(leaf_only=True)

lines = []
lines.append("Top inclusive frames (tinycc.exe):")
for name, count in inclusive.most_common(20):
    lines.append(f"{count:4d} {name}")
lines.append("")
lines.append("Top leaf frames (tinycc.exe):")
for name, count in leaf.most_common(20):
    lines.append(f"{count:4d} {name}")

summary = "\\n".join(lines)
summary_path.write_text(summary + "\\n", encoding="utf-8")
print(summary)
PY

echo "Summary written to ${SUMMARY_TXT}"
