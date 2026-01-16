#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/tests/tinycc_mbt_c"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/target/tinycc-mbt-c}"
OUT_BIN="${OUT_BIN:-${BUILD_DIR}/tinycc_mbt_c}"
CC="${CC:-clang}"
CFLAGS="${CFLAGS:--O2 -std=c11}"
LDFLAGS="${LDFLAGS:-}"
LDLIBS="${LDLIBS:--lm}"
RUN="${RUN:-0}"

usage() {
  cat <<USAGE
Usage:
  scripts/run_tinycc_mbt_c.sh

Env vars:
  CC=clang|gcc      C compiler to use (default: clang)
  CFLAGS="..."      Extra compile flags (default: -O2 -std=c11)
  LDFLAGS="..."     Extra link flags
  LDLIBS="..."      Extra libraries (default: -lm)
  BUILD_DIR=path    Output directory for object files
  OUT_BIN=path      Output binary path
  RUN=1             Run a quick smoke test after build

This compiles tests/tinycc_mbt_c into a native tinycc executable.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

command -v "${CC}" >/dev/null || { echo "error: ${CC} not found"; exit 1; }

TINYCC_C="${SRC_DIR}/tinycc.c"
RUNTIME_C="${SRC_DIR}/lib/runtime.c"
RUNTIME_CORE_C="${SRC_DIR}/lib/runtime_core.c"
FS_NATIVE_C="${SRC_DIR}/lib/fs_native.c"

[[ -f "${TINYCC_C}" ]] || { echo "error: missing ${TINYCC_C}"; exit 1; }
[[ -f "${RUNTIME_C}" ]] || { echo "error: missing ${RUNTIME_C}"; exit 1; }
[[ -f "${RUNTIME_CORE_C}" ]] || { echo "error: missing ${RUNTIME_CORE_C}"; exit 1; }
[[ -f "${FS_NATIVE_C}" ]] || { echo "error: missing ${FS_NATIVE_C}"; exit 1; }

mkdir -p "${BUILD_DIR}"

includes=("-I" "${SRC_DIR}/include")

objs=()
for src in "${TINYCC_C}" "${RUNTIME_C}" "${RUNTIME_CORE_C}" "${FS_NATIVE_C}"; do
  obj="${BUILD_DIR}/$(basename "${src}" .c).o"
  # shellcheck disable=SC2086
  "${CC}" ${CFLAGS} "${includes[@]}" -c "${src}" -o "${obj}"
  objs+=("${obj}")
done

# shellcheck disable=SC2086
"${CC}" ${LDFLAGS} "${objs[@]}" ${LDLIBS} -o "${OUT_BIN}"

echo "Built ${OUT_BIN}"

if [[ "${RUN}" == "1" || "${RUN}" == "true" ]]; then
  echo "Running smoke test (\"${OUT_BIN} -v\")"
  TCC_LIB_PATH="${SRC_DIR}/lib" "${OUT_BIN}" -v
fi
