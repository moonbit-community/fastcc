#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SQLITE_SRC="${ROOT_DIR}/refs/sqlite"
SQLITE_BUILD_DIR="${SQLITE_BUILD_DIR:-${ROOT_DIR}/target/sqlite_build}"
TINYCC_MBT_BIN="${TINYCC_MBT_BIN:-${ROOT_DIR}/_build/native/release/build/tinycc.exe}"
BUILD_MBT="${BUILD_MBT:-1}"
SQLITE_TESTS="${SQLITE_TESTS:-1}"
SQLITE_TEST_LIST="${SQLITE_TEST_LIST:-test/veryquick.test}"
SQLITE_TEST_OPTS="${SQLITE_TEST_OPTS:---verbose=file --output=test-out.txt}"
SQLITE_OPTS="${SQLITE_OPTS:--DSQLITE_ENABLE_LOCKING_STYLE=0 -DSQLITE_WITHOUT_ZONEMALLOC -DSQLITE_ENABLE_MATH_FUNCTIONS}"
HOST_CC="${HOST_CC:-clang}"
TCLSH_CMD="${TCLSH_CMD:-tclsh}"
TCL_CONFIG_SH="${TCL_CONFIG_SH:-}"
MAKE_ASSUME_OLD="${MAKE_ASSUME_OLD:-sqlite3.o}"
SQLITE_PATCH="${SQLITE_PATCH:-${ROOT_DIR}/patches/refs-sqlite/sqlite-test-harness.patch}"
sqlite_patch_applied=0

usage() {
  cat <<'EOF'
Usage:
  scripts/run_sqlite_tests.sh

Env vars:
  SQLITE_BUILD_DIR=path   Build directory for sqlite artifacts (default: target/sqlite_build)
  SQLITE_TESTS=0|1        Run sqlite tests (default: 1)
  SQLITE_TEST_LIST="..."  Space-separated sqlite test scripts (relative to refs/sqlite)
  SQLITE_TEST_OPTS="..."  testfixture options (default: --verbose=file --output=test-out.txt)
  SQLITE_OPTS="..."       Extra sqlite compile defines (passed to make/tinycc)
  HOST_CC=clang           Host compiler for sqlite build tools/testfixture
  TCLSH_CMD=tclsh         Tcl interpreter for sqlite build
  TCL_CONFIG_SH=path      Path to tclConfig.sh (auto-detected if unset)
  MAKE_ASSUME_OLD="..."   Space-separated make targets to treat as up-to-date when building testfixture
  BUILD_MBT=0|1           Build tinycc.mbt before compiling sqlite3.c (default: 1)
  TINYCC_MBT_BIN=path     Path to tinycc.mbt executable
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

find_tcl_config() {
  "${TCLSH_CMD}" <<'TCL'
set lib [info library]
set root [file dirname [file dirname $lib]]
set cfg [file join $root tclConfig.sh]
if {[file exists $cfg]} {
  puts $cfg
  exit 0
}
set alt [file join [file dirname $root] tclConfig.sh]
if {[file exists $alt]} {
  puts $alt
  exit 0
}
puts ""
TCL
}

emit_stub_tcl_config() {
  "${TCLSH_CMD}" <<'TCL'
set ver [info tclversion]
set libdir [::tcl::pkgconfig get libdir,runtime]
set incdir [::tcl::pkgconfig get includedir,runtime]
puts "TCL_VERSION='$ver'"
puts "TCL_INCLUDE_SPEC='-I${incdir}'"
puts "TCL_LIBS=''"
if {[file exists /System/Library/Frameworks/Tcl.framework/Tcl]} {
  puts "TCL_LIB_SPEC='-framework Tcl'"
} elseif {[file exists /Library/Frameworks/Tcl.framework/Tcl]} {
  puts "TCL_LIB_SPEC='-framework Tcl'"
} else {
  puts "TCL_LIB_SPEC='-L${libdir} -ltcl${ver}'"
}
TCL
}

apply_sqlite_patch() {
  if [[ ! -f "${SQLITE_PATCH}" ]]; then
    return
  fi
  if git -C "${SQLITE_SRC}" apply --check "${SQLITE_PATCH}" >/dev/null 2>&1; then
    echo "Applying sqlite patch ${SQLITE_PATCH}"
    git -C "${SQLITE_SRC}" apply "${SQLITE_PATCH}"
    sqlite_patch_applied=1
  elif git -C "${SQLITE_SRC}" apply --reverse --check "${SQLITE_PATCH}" >/dev/null 2>&1; then
    sqlite_patch_applied=0
  else
    echo "warning: unable to apply sqlite patch ${SQLITE_PATCH}" >&2
  fi
}

cleanup_sqlite_patch() {
  if [[ "${sqlite_patch_applied}" -eq 1 ]]; then
    git -C "${SQLITE_SRC}" apply --reverse "${SQLITE_PATCH}" >/dev/null 2>&1 || true
  fi
}

if [[ -z "${TCL_CONFIG_SH}" ]]; then
  TCL_CONFIG_SH="$(find_tcl_config)"
fi

if [[ -z "${TCL_CONFIG_SH}" || ! -f "${TCL_CONFIG_SH}" ]]; then
  stub_cfg="${SQLITE_BUILD_DIR}/tclConfig.sh"
  mkdir -p "${SQLITE_BUILD_DIR}"
  emit_stub_tcl_config >"${stub_cfg}"
  TCL_CONFIG_SH="${stub_cfg}"
fi

if [[ "${BUILD_MBT}" == "1" ]]; then
  echo "Building tinycc.mbt (${TINYCC_MBT_BIN})"
  moon build --release --target native src
fi

if [[ ! -x "${TINYCC_MBT_BIN}" ]]; then
  echo "error: tinycc.mbt executable missing at ${TINYCC_MBT_BIN}" >&2
  exit 1
fi

if [[ ! -d "${SQLITE_SRC}" ]]; then
  echo "error: sqlite sources missing at ${SQLITE_SRC}" >&2
  exit 1
fi

apply_sqlite_patch
trap cleanup_sqlite_patch EXIT

SQLITE_VERSION="$(cat "${SQLITE_SRC}/VERSION")"

mkdir -p "${SQLITE_BUILD_DIR}"

echo "Generating sqlite3.c/sqlite3.h in ${SQLITE_BUILD_DIR}"
make -f "${SQLITE_SRC}/Makefile.linux-generic" -C "${SQLITE_BUILD_DIR}" \
  sqlite3.c sqlite3.h \
  TOP="${SQLITE_SRC}" \
  B.tclsh="${TCLSH_CMD}" \
  TCLSH_CMD="${TCLSH_CMD}" \
  CC="${HOST_CC}" \
  PACKAGE_VERSION="${SQLITE_VERSION}" \
  OPTS="${SQLITE_OPTS}"

SQLITE_TEST_CFLAGS_DEFAULT=(
  -DSQLITE_TEST=1
  -DSQLITE_CRASH_TEST=1
  -DTCLSH_INIT_PROC=sqlite3TestInit
  -DSQLITE_SERVER=1
  -DSQLITE_PRIVATE=
  -DSQLITE_CORE
  -DBUILD_sqlite
  -DSQLITE_SERIES_CONSTRAINT_VERIFY=1
  -DSQLITE_DEFAULT_PAGE_SIZE=1024
  -DSQLITE_ENABLE_STMTVTAB
  -DSQLITE_ENABLE_DBPAGE_VTAB
  -DSQLITE_ENABLE_BYTECODE_VTAB
  -DSQLITE_ENABLE_CARRAY
  -DSQLITE_ENABLE_PERCENTILE
  -DSQLITE_CKSUMVFS_STATIC
  -DSQLITE_STATIC_RANDOMJSON
  -DSQLITE_STRICT_SUBTYPE=1
  -DSQLITE_NO_SYNC=1
)

SQLITE_CFLAGS=("${SQLITE_TEST_CFLAGS_DEFAULT[@]}")
if [[ -n "${SQLITE_OPTS}" ]]; then
  read -r -a extra_opts <<<"${SQLITE_OPTS}"
  SQLITE_CFLAGS+=("${extra_opts[@]}")
fi

MAKE_ASSUME_OLD_ARGS=()
if [[ -n "${MAKE_ASSUME_OLD}" ]]; then
  read -r -a assume_old_targets <<<"${MAKE_ASSUME_OLD}"
  for target in "${assume_old_targets[@]}"; do
    MAKE_ASSUME_OLD_ARGS+=("-o" "${target}")
  done
fi

SQLITE_INCLUDES=(
  -I "${SQLITE_BUILD_DIR}"
  -I "${SQLITE_SRC}"
  -I "${SQLITE_SRC}/src"
  -I "${SQLITE_SRC}/ext/fts3"
  -I "${SQLITE_SRC}/ext/fts5"
  -I "${SQLITE_SRC}/ext/icu"
  -I "${SQLITE_SRC}/ext/rtree"
  -I "${SQLITE_SRC}/ext/session"
  -I "${SQLITE_SRC}/ext/rbu"
  -I "${SQLITE_SRC}/ext/misc"
)

echo "Compiling sqlite3.c with tinycc.mbt"
"${TINYCC_MBT_BIN}" \
  "${SQLITE_CFLAGS[@]}" \
  "${SQLITE_INCLUDES[@]}" \
  -c "${SQLITE_BUILD_DIR}/sqlite3.c" \
  -o "${SQLITE_BUILD_DIR}/sqlite3.o"

echo "Building testfixture (clang) with sqlite3.o"
make -f "${SQLITE_SRC}/Makefile.linux-generic" -C "${SQLITE_BUILD_DIR}" \
  "${MAKE_ASSUME_OLD_ARGS[@]}" \
  testfixture \
  TOP="${SQLITE_SRC}" \
  B.tclsh="${TCLSH_CMD}" \
  TCLSH_CMD="${TCLSH_CMD}" \
  TCL_CONFIG_SH="${TCL_CONFIG_SH}" \
  CC="${HOST_CC}" \
  PACKAGE_VERSION="${SQLITE_VERSION}" \
  OPTS="${SQLITE_OPTS}" \
  TESTFIXTURE_SRC1=sqlite3.o

if [[ "${SQLITE_TESTS}" == "1" || "${SQLITE_TESTS}" == "true" ]]; then
  echo "Running sqlite tests: ${SQLITE_TEST_LIST}"
  pushd "${SQLITE_BUILD_DIR}" >/dev/null
  for test in ${SQLITE_TEST_LIST}; do
    ./testfixture "${SQLITE_SRC}/${test}" ${SQLITE_TEST_OPTS}
  done
  popd >/dev/null
fi
