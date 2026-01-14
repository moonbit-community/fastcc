#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CTEST_DIR="${ROOT_DIR}/refs/mbtcc/ctest2"
TMP_DIR="${ROOT_DIR}/target/mbtcc-ctest2"
EXTRA_HDR="${ROOT_DIR}/tests/mbtcc/extra.h"
PATCH_DIR="${ROOT_DIR}/tests/mbtcc/ctest2_patches"

FILTER="${FILTER:-}"
MODE="${MODE:-strict}" # strict | allow-fail

usage() {
  cat <<'EOF'
Usage:
  scripts/run_mbtcc_ctest2.sh

Env vars:
  FILTER=regex     Run only tests whose filename matches regex (grep -E).
  MODE=strict|allow-fail

This runs mbtcc's second C test suite (refs/mbtcc/ctest2/*.c) against tinycc.mbt:
  - expected output: gcc
  - actual output: tinycc.mbt (-c -> .o) + clang link -> run
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

command -v moon >/dev/null || { echo "error: moon not found"; exit 1; }
command -v gcc >/dev/null || { echo "error: gcc not found"; exit 1; }
command -v clang >/dev/null || { echo "error: clang not found"; exit 1; }
[[ -f "${EXTRA_HDR}" ]] || { echo "error: missing ${EXTRA_HDR}"; exit 1; }

rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

tests_file="${TMP_DIR}/tests.txt"
find "${CTEST_DIR}" -maxdepth 1 -type f -name '*.c' -print | sort >"${tests_file}"
if [[ -n "${FILTER}" ]]; then
  grep -E "${FILTER}" "${tests_file}" >"${tests_file}.filtered" || true
  mv "${tests_file}.filtered" "${tests_file}"
fi

tests_count="$(wc -l <"${tests_file}" | tr -d ' ')"
if [[ "${tests_count}" -eq 0 ]]; then
  echo "error: no tests selected"
  exit 1
fi

fail=0
total=0

echo "Running mbtcc ctest2 (count=${tests_count})"
while IFS= read -r c_file; do
  base="$(basename "${c_file}" .c)"
  total=$((total + 1))
  echo "-------------------------------------------"
  echo "Testing ${base}.c"

  source_c="${c_file}"
  patch_c="${PATCH_DIR}/${base}.c"
  if [[ -f "${patch_c}" ]]; then
    echo "PATCHED: using ${patch_c}"
    source_c="${patch_c}"
  fi

  wrap_c="${TMP_DIR}/${base}.wrap.c"
  cat >"${wrap_c}" <<EOF
#include "${EXTRA_HDR}"
#include "${source_c}"
EOF

  gcc -I "${CTEST_DIR}" "${wrap_c}" -lm -o "${TMP_DIR}/${base}.gcc.out" >"${TMP_DIR}/${base}.gcc.log" 2>&1 || {
    echo "FAILED: gcc compilation failed"
    sed -n '1,120p' "${TMP_DIR}/${base}.gcc.log" || true
    fail=$((fail + 1))
    continue
  }
  expected_file="${TMP_DIR}/${base}.expected.txt"
  if ! "${TMP_DIR}/${base}.gcc.out" >"${expected_file}"; then
    echo "FAILED: gcc run failed"
    fail=$((fail + 1))
    continue
  fi

  rm -f "${TMP_DIR}/${base}.o" "${TMP_DIR}/${base}.tinycc.out" "${TMP_DIR}/${base}.actual.txt"
  if ! moon run --release "${ROOT_DIR}/src" -- -I "${CTEST_DIR}" -c -o "${TMP_DIR}/${base}.o" "${wrap_c}" >"${TMP_DIR}/${base}.tinycc.log" 2>&1; then
    echo "FAILED: tinycc.mbt compilation failed"
    sed -n '1,120p' "${TMP_DIR}/${base}.tinycc.log" || true
    fail=$((fail + 1))
    continue
  fi
  if ! clang -w "${TMP_DIR}/${base}.o" -lm -o "${TMP_DIR}/${base}.tinycc.out" 2>/dev/null; then
    echo "FAILED: clang link failed"
    fail=$((fail + 1))
    continue
  fi
  actual_file="${TMP_DIR}/${base}.actual.txt"
  if ! "${TMP_DIR}/${base}.tinycc.out" >"${actual_file}"; then
    echo "FAILED: tinycc.mbt run failed"
    fail=$((fail + 1))
    continue
  fi

  if cmp -s "${expected_file}" "${actual_file}"; then
    echo "PASSED"
  else
    echo "FAILED: output mismatch"
    echo "Expected:"
    sed -n '1,120p' "${expected_file}" || true
    echo "Got:"
    sed -n '1,120p' "${actual_file}" || true
    fail=$((fail + 1))
  fi
done <"${tests_file}"

echo "-------------------------------------------"
echo "Summary: total=${total} failed=${fail}"
if [[ "${fail}" -ne 0 && "${MODE}" != "allow-fail" ]]; then
  exit 1
fi
