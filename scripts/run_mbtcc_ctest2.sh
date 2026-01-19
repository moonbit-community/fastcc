#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CTEST_DIR="${ROOT_DIR}/refs/mbtcc/ctest2"
TMP_DIR="${ROOT_DIR}/target/mbtcc-ctest2"
EXTRA_HDR="${ROOT_DIR}/tests/mbtcc/extra.h"
PATCH_DIR="${ROOT_DIR}/tests/mbtcc/ctest2_patches"
BOOTSTRAP_TINYCC_BIN="${TINYCC_BIN:-${ROOT_DIR}/_build/native/release/build/tinycc.exe}"
TINYCC_BUILD_TARGET="${TINYCC_BUILD_TARGET:-${ROOT_DIR}/src}"
SELFHOST="${SELFHOST:-0}"
SELFHOST_BIN="${SELFHOST_BIN:-${ROOT_DIR}/target/selfhost/tcc_selfhost}"
SELFHOST_OBJ="${SELFHOST_OBJ:-${ROOT_DIR}/target/selfhost/tcc_all.o}"
TINYCC_ARM64_ASM_PATCH="${ROOT_DIR}/patches/refs-tinycc/arm64-asm-hints.patch"
tinycc_patch_backup=""

FILTER="${FILTER:-}"
MODE="${MODE:-strict}" # strict | allow-fail

usage() {
  cat <<'EOF'
Usage:
  scripts/run_mbtcc_ctest2.sh

Env vars:
  FILTER=regex     Run only tests whose filename matches regex (grep -E).
  MODE=strict|allow-fail
  SELFHOST=1       Build refs/tinycc with tinycc.mbt and run tests via tcc_selfhost.
  TINYCC_BIN=path  Bootstrap compiler path (used to build tcc_selfhost in SELFHOST mode).
  SELFHOST_BIN=path  Override tcc_selfhost path.

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

apply_tinycc_patch() {
  if [[ ! -f "${TINYCC_ARM64_ASM_PATCH}" ]]; then
    return
  fi
  if git -C "${ROOT_DIR}/refs/tinycc" apply --check "${TINYCC_ARM64_ASM_PATCH}" >/dev/null 2>&1; then
    tinycc_patch_backup="${TMP_DIR}/arm64-asm.c.bak"
    cp "${ROOT_DIR}/refs/tinycc/arm64-asm.c" "${tinycc_patch_backup}"
    git -C "${ROOT_DIR}/refs/tinycc" apply "${TINYCC_ARM64_ASM_PATCH}"
  elif git -C "${ROOT_DIR}/refs/tinycc" apply --reverse --check "${TINYCC_ARM64_ASM_PATCH}" >/dev/null 2>&1; then
    : # already applied
  else
    echo "warning: unable to apply tinycc arm64 asm patch"
  fi
}

cleanup_tinycc_patch() {
  if [[ -n "${tinycc_patch_backup}" && -f "${tinycc_patch_backup}" ]]; then
    mv "${tinycc_patch_backup}" "${ROOT_DIR}/refs/tinycc/arm64-asm.c"
  fi
}

# Build tinycc native executable once up front (bootstrap compiler).
echo "Building tinycc executable (${BOOTSTRAP_TINYCC_BIN})"
moon build --release --target native "${TINYCC_BUILD_TARGET}"
if [[ ! -x "${BOOTSTRAP_TINYCC_BIN}" ]]; then
  echo "error: tinycc executable missing at ${BOOTSTRAP_TINYCC_BIN}"
  exit 1
fi

rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

use_selfhost=0
if [[ "${SELFHOST}" == "1" || "${SELFHOST}" == "true" ]]; then
  use_selfhost=1
fi

TEST_TINYCC_BIN="${BOOTSTRAP_TINYCC_BIN}"
if [[ "${use_selfhost}" -eq 1 ]]; then
  echo "Building selfhost tinycc (${SELFHOST_BIN})"
  mkdir -p "$(dirname "${SELFHOST_BIN}")"
  apply_tinycc_patch
  if ! "${BOOTSTRAP_TINYCC_BIN}" -I "${ROOT_DIR}/compat/include" -I "${ROOT_DIR}/refs/tinycc" -I "${ROOT_DIR}/refs/tinycc/include" \
    -c "${ROOT_DIR}/refs/tinycc/tcc.c" -o "${SELFHOST_OBJ}" >"${TMP_DIR}/selfhost_build.log" 2>&1; then
    echo "error: failed to build refs/tinycc object"
    sed -n '1,160p' "${TMP_DIR}/selfhost_build.log" || true
    cleanup_tinycc_patch
    exit 1
  fi
  if ! clang "${SELFHOST_OBJ}" -o "${SELFHOST_BIN}" -lm >"${TMP_DIR}/selfhost_link.log" 2>&1; then
    echo "error: failed to link refs/tinycc binary"
    sed -n '1,160p' "${TMP_DIR}/selfhost_link.log" || true
    cleanup_tinycc_patch
    exit 1
  fi
  cleanup_tinycc_patch
  if [[ ! -x "${SELFHOST_BIN}" ]]; then
    echo "error: selfhost tinycc missing at ${SELFHOST_BIN}"
    exit 1
  fi
  TEST_TINYCC_BIN="${SELFHOST_BIN}"
fi

tests_file="${TMP_DIR}/tests.txt"
find "${CTEST_DIR}" -maxdepth 1 -type f -name '*.c' -print | sort >"${tests_file}"
if [[ -d "${PATCH_DIR}" ]]; then
  while IFS= read -r patch; do
    base="$(basename "${patch}")"
    if ! grep -q "/${base}$" "${tests_file}"; then
      echo "${patch}" >>"${tests_file}"
    fi
  done < <(find "${PATCH_DIR}" -maxdepth 1 -type f -name '*.c' -print)
fi
sort -o "${tests_file}" "${tests_file}"
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
  actual_file="${TMP_DIR}/${base}.actual.txt"
  if [[ "${use_selfhost}" -eq 1 ]]; then
    if ! "${TEST_TINYCC_BIN}" -B "${ROOT_DIR}/refs/tinycc" -I "${ROOT_DIR}/compat/include" -I "${CTEST_DIR}" \
      -run "${wrap_c}" -lm >"${actual_file}" 2>"${TMP_DIR}/${base}.tinycc.log"; then
      echo "FAILED: selfhost tinycc run failed"
      sed -n '1,120p' "${TMP_DIR}/${base}.tinycc.log" || true
      fail=$((fail + 1))
      continue
    fi
  else
    if ! "${TEST_TINYCC_BIN}" -I "${CTEST_DIR}" -c -o "${TMP_DIR}/${base}.o" "${wrap_c}" >"${TMP_DIR}/${base}.tinycc.log" 2>&1; then
      echo "FAILED: tinycc compilation failed"
      sed -n '1,120p' "${TMP_DIR}/${base}.tinycc.log" || true
      fail=$((fail + 1))
      continue
    fi
    if ! clang -w "${TMP_DIR}/${base}.o" -lm -o "${TMP_DIR}/${base}.tinycc.out" 2>/dev/null; then
      echo "FAILED: clang link failed"
      fail=$((fail + 1))
      continue
    fi
    if ! "${TMP_DIR}/${base}.tinycc.out" >"${actual_file}"; then
      echo "FAILED: tinycc.mbt run failed"
      fail=$((fail + 1))
      continue
    fi
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
