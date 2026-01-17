# tinycc.mbt

## Benchmarks

### refs/vc/v.c

File: `refs/vc/v.c` (138152 LOC)

Environment: macOS arm64, tinycc from this repo built in release mode.

### tinycc.mbt

Command:

```
./_build/native/release/build/tinycc.exe -I compat/include -c refs/vc/v.c -o /tmp/v.mbt.o
```

Results (3 runs):

- avg: 2.3598s
- throughput: 58544 LOC/s

### refs/tinycc (official)

Command:

```
refs/tinycc/tcc -I compat/include -c refs/vc/v.c -o /tmp/v.tcc.o
```

Results (3 runs):

- avg: 0.1145s
- throughput: 1206568 LOC/s
- notes: arm64 benchmark applies `refs/vc_patches/arm64_closure_bytes.patch` to `refs/vc/v.c` for the closure byte array size; tcc emits implicit declaration warnings with the compat headers

### ctest/ctest2 compile suite (scripts/bench_tinycc_compile.sh)

Command:

```
DETAIL=1 REPEAT=3 WARMUP=1 scripts/bench_tinycc_compile.sh
```

Results (latest run):

- tinycc.mbt total: 0.269s
- refs/tinycc total: 0.210s
- ratio (mbt/ref): 1.28x
- phases avg ms: parse=19.716 sem=8.596 codegen=29.092 total=57.409
- notes: 120 files (ctest + ctest2); numbers vary by run
