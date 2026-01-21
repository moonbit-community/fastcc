# tinycc.mbt

## Benchmarks

### refs/vc/v.c (bench_tinycc_compile.sh DATASET=vc)

File: `refs/vc/v.c` (138152 LOC)

Environment: macOS arm64, tinycc from this repo built in release mode.

Command:

```
DATASET=vc APPLY_VC_PATCH=1 DETAIL=1 REPEAT=3 WARMUP=1 scripts/bench_tinycc_compile.sh
```

Results (3 runs):

- tinycc.mbt total: 0.517s
- refs/tinycc total: 0.115s
- clang total: 1.634s
- ratio (mbt/ref): 4.48x
- ratio (mbt/clang): 0.32x
- ratio (ref/clang): 0.07x
- phases avg ms: parse=155.782 sem=96.063 codegen=226.162 total=478.006
- notes: arm64 benchmark applies `refs/vc_patches/arm64_closure_bytes.patch` to `refs/vc/v.c`; clang uses system headers (compat include skipped); numbers vary by run
