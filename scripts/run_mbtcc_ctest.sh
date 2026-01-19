#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CTEST_DIR="${ROOT_DIR}/refs/mbtcc/ctest"
TMP_DIR="${ROOT_DIR}/target/mbtcc-ctest"
SUPPORT_C="${ROOT_DIR}/tests/mbtcc/ctest_support.c"
BOOTSTRAP_TINYCC_BIN="${TINYCC_BIN:-${ROOT_DIR}/_build/native/release/build/tinycc.exe}"
TINYCC_BUILD_TARGET="${TINYCC_BUILD_TARGET:-${ROOT_DIR}/src}"
SELFHOST="${SELFHOST:-0}"
SELFHOST_BIN="${SELFHOST_BIN:-${ROOT_DIR}/target/selfhost/tcc_selfhost}"
SELFHOST_OBJ="${SELFHOST_OBJ:-${ROOT_DIR}/target/selfhost/tcc_all.o}"
QUICKJS="${QUICKJS:-1}"
QUICKJS_DIR="${ROOT_DIR}/refs/quickjs"
QUICKJS_C="${QUICKJS_DIR}/quickjs.c"
QUICKJS_OBJ="${TMP_DIR}/quickjs_mbt.o"
QUICKJS_VERSION_DEFINE='-DCONFIG_VERSION="\"2021-03-27\""'
QUICKJS_TESTS="${QUICKJS_TESTS:-1}"
QUICKJS_TEST_LIST="${QUICKJS_TEST_LIST:-tests/test_closure.js tests/test_language.js tests/test_builtin.js tests/test_loop.js tests/test_bigint.js tests/test_cyclic_import.js tests/test_std.js}"

FILTER="${FILTER:-}"
MODE="${MODE:-strict}" # strict | allow-fail

usage() {
  cat <<'EOF'
Usage:
  scripts/run_mbtcc_ctest.sh

Env vars:
  FILTER=regex     Run only tests whose filename matches regex (grep -E).
  MODE=strict|allow-fail
  SELFHOST=1       Build refs/tinycc with tinycc.mbt and run tests via tcc_selfhost.
  TINYCC_BIN=path  Bootstrap compiler path (used to build tcc_selfhost in SELFHOST mode).
  SELFHOST_BIN=path  Override tcc_selfhost path.
  QUICKJS=0|1      Compile refs/quickjs/quickjs.c with tinycc.mbt (default: 1).
  QUICKJS_TESTS=0|1     Run quickjs JS smoke tests using a qjs built by tinycc.mbt (default: 1).
  QUICKJS_TEST_LIST=... Space-separated test list (paths relative to refs/quickjs).

This runs mbtcc's C file tests (refs/mbtcc/ctest/*.c) against tinycc.mbt:
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
  if ! "${BOOTSTRAP_TINYCC_BIN}" -I "${ROOT_DIR}/compat/include" -I "${ROOT_DIR}/refs/tinycc" -I "${ROOT_DIR}/refs/tinycc/include" \
    -c "${ROOT_DIR}/refs/tinycc/tcc.c" -o "${SELFHOST_OBJ}" >"${TMP_DIR}/selfhost_build.log" 2>&1; then
    echo "error: failed to build refs/tinycc object"
    sed -n '1,160p' "${TMP_DIR}/selfhost_build.log" || true
    exit 1
  fi
  if ! clang "${SELFHOST_OBJ}" -o "${SELFHOST_BIN}" -lm >"${TMP_DIR}/selfhost_link.log" 2>&1; then
    echo "error: failed to link refs/tinycc binary"
    sed -n '1,160p' "${TMP_DIR}/selfhost_link.log" || true
    exit 1
  fi
  if [[ ! -x "${SELFHOST_BIN}" ]]; then
    echo "error: selfhost tinycc missing at ${SELFHOST_BIN}"
    exit 1
  fi
  TEST_TINYCC_BIN="${SELFHOST_BIN}"
fi

fail=0
total=0

quickjs_enabled=0
if [[ "${QUICKJS}" == "1" || "${QUICKJS}" == "true" ]]; then
  quickjs_enabled=1
fi
if [[ "${quickjs_enabled}" -eq 1 ]]; then
  if [[ ! -f "${QUICKJS_C}" ]]; then
    echo "error: missing quickjs source at ${QUICKJS_C}"
    exit 1
  fi
  quickjs_args=(
    -I "${ROOT_DIR}/compat/include"
    -I "${QUICKJS_DIR}"
    -D_GNU_SOURCE
    "${QUICKJS_VERSION_DEFINE}"
  )
  quickjs_host_args=(
    -I "${QUICKJS_DIR}"
    -D_GNU_SOURCE
    "${QUICKJS_VERSION_DEFINE}"
  )
  quickjs_log="${TMP_DIR}/quickjs_compile.log"
  echo "Compiling quickjs.c with ${TEST_TINYCC_BIN}"
  if ! "${TEST_TINYCC_BIN}" "${quickjs_args[@]}" -c "${QUICKJS_C}" -o "${QUICKJS_OBJ}" >"${quickjs_log}" 2>&1; then
    echo "FAILED: quickjs compile failed"
    sed -n '1,160p' "${quickjs_log}" || true
    if [[ "${MODE}" != "allow-fail" ]]; then
      exit 1
    fi
    fail=$((fail + 1))
  fi
fi

quickjs_tests_enabled=0
if [[ "${QUICKJS_TESTS}" == "1" || "${QUICKJS_TESTS}" == "true" ]]; then
  quickjs_tests_enabled=1
fi
if [[ "${quickjs_enabled}" -eq 1 && "${quickjs_tests_enabled}" -eq 1 ]]; then
  quickjs_build_dir="${TMP_DIR}/quickjs"
  quickjs_obj_dir="${quickjs_build_dir}/obj"
  quickjs_log_dir="${quickjs_build_dir}/logs"
  mkdir -p "${quickjs_obj_dir}" "${quickjs_log_dir}"

  quickjs_libs=(-lm -lpthread)
  if [[ "$(uname -s)" != "Darwin" ]]; then
    quickjs_libs+=(-ldl)
  fi

  quickjs_build_failed=0
  quickjs_lib_objs=()
  quickjs_c_obj="${QUICKJS_OBJ}"
  if [[ ! -f "${quickjs_c_obj}" ]]; then
    quickjs_c_obj="${quickjs_obj_dir}/quickjs.o"
    if ! "${TEST_TINYCC_BIN}" "${quickjs_args[@]}" -c "${QUICKJS_C}" -o "${quickjs_c_obj}" \
      >"${quickjs_log_dir}/quickjs_compile.log" 2>&1; then
      echo "FAILED: quickjs.c compile failed"
      sed -n '1,160p' "${quickjs_log_dir}/quickjs_compile.log" || true
      quickjs_build_failed=1
      if [[ "${MODE}" != "allow-fail" ]]; then
        exit 1
      fi
      fail=$((fail + 1))
    fi
  fi
  quickjs_lib_objs+=("${quickjs_c_obj}")

  quickjs_lib_sources=(
    "${QUICKJS_DIR}/dtoa.c"
    "${QUICKJS_DIR}/libregexp.c"
    "${QUICKJS_DIR}/libunicode.c"
    "${QUICKJS_DIR}/cutils.c"
    "${QUICKJS_DIR}/quickjs-libc.c"
  )
  for src in "${quickjs_lib_sources[@]}"; do
    obj="${quickjs_obj_dir}/$(basename "${src}" .c).o"
    quickjs_lib_objs+=("${obj}")
    if ! "${TEST_TINYCC_BIN}" "${quickjs_args[@]}" -c "${src}" -o "${obj}" \
      >"${quickjs_log_dir}/$(basename "${src}" .c).log" 2>&1; then
      echo "FAILED: quickjs compile failed ($(basename "${src}"))"
      sed -n '1,160p' "${quickjs_log_dir}/$(basename "${src}" .c).log" || true
      quickjs_build_failed=1
      if [[ "${MODE}" != "allow-fail" ]]; then
        exit 1
      fi
      fail=$((fail + 1))
    fi
  done

  qjsc_bin="${quickjs_build_dir}/qjsc"
  qjsc_host_obj_dir="${quickjs_build_dir}/qjsc_host"
  mkdir -p "${qjsc_host_obj_dir}"
  qjsc_host_objs=()
  quickjs_host_sources=(
    "${QUICKJS_C}"
    "${QUICKJS_DIR}/dtoa.c"
    "${QUICKJS_DIR}/libregexp.c"
    "${QUICKJS_DIR}/libunicode.c"
    "${QUICKJS_DIR}/cutils.c"
    "${QUICKJS_DIR}/quickjs-libc.c"
    "${QUICKJS_DIR}/qjsc.c"
  )
  for src in "${quickjs_host_sources[@]}"; do
    obj="${qjsc_host_obj_dir}/$(basename "${src}" .c).o"
    qjsc_host_objs+=("${obj}")
    if ! clang -c "${src}" -o "${obj}" "${quickjs_host_args[@]}" \
      >"${quickjs_log_dir}/qjsc_host_$(basename "${src}" .c).log" 2>&1; then
      echo "FAILED: qjsc host compile failed ($(basename "${src}"))"
      sed -n '1,160p' "${quickjs_log_dir}/qjsc_host_$(basename "${src}" .c).log" || true
      quickjs_build_failed=1
      if [[ "${MODE}" != "allow-fail" ]]; then
        exit 1
      fi
      fail=$((fail + 1))
    fi
  done
  if [[ "${quickjs_build_failed}" -eq 0 ]]; then
    if ! clang "${qjsc_host_objs[@]}" -o "${qjsc_bin}" "${quickjs_libs[@]}" \
      >"${quickjs_log_dir}/qjsc_link.log" 2>&1; then
      echo "FAILED: qjsc link failed"
      sed -n '1,160p' "${quickjs_log_dir}/qjsc_link.log" || true
      quickjs_build_failed=1
      if [[ "${MODE}" != "allow-fail" ]]; then
        exit 1
      fi
      fail=$((fail + 1))
    fi
  fi

  repl_c="${quickjs_build_dir}/repl.c"
  if [[ "${quickjs_build_failed}" -eq 0 ]]; then
    if ! "${qjsc_bin}" -s -c -o "${repl_c}" -m "${QUICKJS_DIR}/repl.js" \
      >"${quickjs_log_dir}/repl_gen.log" 2>&1; then
      echo "FAILED: repl.c generation failed"
      sed -n '1,160p' "${quickjs_log_dir}/repl_gen.log" || true
      quickjs_build_failed=1
      if [[ "${MODE}" != "allow-fail" ]]; then
        exit 1
      fi
      fail=$((fail + 1))
    fi
  fi

  qjs_obj="${quickjs_obj_dir}/qjs.o"
  repl_obj="${quickjs_obj_dir}/repl.o"
  qjs_bin="${quickjs_build_dir}/qjs"
  if [[ "${quickjs_build_failed}" -eq 0 ]]; then
    if ! "${TEST_TINYCC_BIN}" "${quickjs_args[@]}" -c "${QUICKJS_DIR}/qjs.c" -o "${qjs_obj}" \
      >"${quickjs_log_dir}/qjs_compile.log" 2>&1; then
      echo "FAILED: qjs compile failed"
      sed -n '1,160p' "${quickjs_log_dir}/qjs_compile.log" || true
      quickjs_build_failed=1
      if [[ "${MODE}" != "allow-fail" ]]; then
        exit 1
      fi
      fail=$((fail + 1))
    fi
    if ! "${TEST_TINYCC_BIN}" "${quickjs_args[@]}" -c "${repl_c}" -o "${repl_obj}" \
      >"${quickjs_log_dir}/repl_compile.log" 2>&1; then
      echo "FAILED: repl.c compile failed"
      sed -n '1,160p' "${quickjs_log_dir}/repl_compile.log" || true
      quickjs_build_failed=1
      if [[ "${MODE}" != "allow-fail" ]]; then
        exit 1
      fi
      fail=$((fail + 1))
    fi
  fi
  if [[ "${quickjs_build_failed}" -eq 0 ]]; then
    if ! clang "${qjs_obj}" "${repl_obj}" "${quickjs_lib_objs[@]}" -o "${qjs_bin}" "${quickjs_libs[@]}" \
      >"${quickjs_log_dir}/qjs_link.log" 2>&1; then
      echo "FAILED: qjs link failed"
      sed -n '1,160p' "${quickjs_log_dir}/qjs_link.log" || true
      quickjs_build_failed=1
      if [[ "${MODE}" != "allow-fail" ]]; then
        exit 1
      fi
      fail=$((fail + 1))
    fi
  fi

  if [[ "${quickjs_build_failed}" -eq 0 ]]; then
    echo "Running quickjs tests"
    pushd "${QUICKJS_DIR}" >/dev/null
    for test_file in ${QUICKJS_TEST_LIST}; do
      test_name="$(basename "${test_file}")"
      test_log="${quickjs_log_dir}/${test_name}.log"
      if [[ "${test_name}" == "test_builtin.js" ]]; then
        if ! "${qjs_bin}" --std "${test_file}" >"${test_log}" 2>&1; then
          echo "FAILED: quickjs test ${test_name}"
          sed -n '1,160p' "${test_log}" || true
          if [[ "${MODE}" != "allow-fail" ]]; then
            popd >/dev/null
            exit 1
          fi
          fail=$((fail + 1))
        fi
      else
        if ! "${qjs_bin}" "${test_file}" >"${test_log}" 2>&1; then
          echo "FAILED: quickjs test ${test_name}"
          sed -n '1,160p' "${test_log}" || true
          if [[ "${MODE}" != "allow-fail" ]]; then
            popd >/dev/null
            exit 1
          fi
          fail=$((fail + 1))
        fi
      fi
    done
    popd >/dev/null
  fi
fi

support_o="${TMP_DIR}/ctest_support.o"
if [[ -f "${SUPPORT_C}" ]]; then
  if ! clang -w -c "${SUPPORT_C}" -o "${support_o}" 2>"${TMP_DIR}/ctest_support.clang.log"; then
    echo "error: failed to build ctest support object"
    sed -n '1,120p' "${TMP_DIR}/ctest_support.clang.log" || true
    exit 1
  fi
else
  echo "error: missing support file ${SUPPORT_C}"
  exit 1
fi

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

echo "Running mbtcc ctest (count=${tests_count})"
while IFS= read -r c_file; do
  base="$(basename "${c_file}" .c)"
  total=$((total + 1))
  echo "-------------------------------------------"
  echo "Testing ${base}.c"

  gcc "${c_file}" "${SUPPORT_C}" -lm -o "${TMP_DIR}/${base}.gcc.out" 2>/dev/null || {
    echo "FAILED: gcc compilation failed"
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
    wrap_c="${TMP_DIR}/${base}.wrap.c"
    cat >"${wrap_c}" <<EOF
#include "${SUPPORT_C}"
#include "${c_file}"
EOF
    if ! "${TEST_TINYCC_BIN}" -B "${ROOT_DIR}/refs/tinycc" -I "${ROOT_DIR}/compat/include" -I "${CTEST_DIR}" \
      -run "${wrap_c}" -lm >"${actual_file}" 2>"${TMP_DIR}/${base}.tinycc.log"; then
      echo "FAILED: selfhost tinycc run failed"
      sed -n '1,120p' "${TMP_DIR}/${base}.tinycc.log" || true
      fail=$((fail + 1))
      continue
    fi
  else
    if ! "${TEST_TINYCC_BIN}" -I "${CTEST_DIR}" -c -o "${TMP_DIR}/${base}.o" "${c_file}" >"${TMP_DIR}/${base}.tinycc.log" 2>&1; then
      echo "FAILED: tinycc compilation failed"
      sed -n '1,120p' "${TMP_DIR}/${base}.tinycc.log" || true
      fail=$((fail + 1))
      continue
    fi
    if ! clang -w "${TMP_DIR}/${base}.o" "${support_o}" -lm -o "${TMP_DIR}/${base}.tinycc.out" 2>/dev/null; then
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
