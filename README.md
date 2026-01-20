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

- tinycc.mbt total: 0.494s
- refs/tinycc total: 0.114s
- clang total: 1.593s
- ratio (mbt/ref): 4.35x
- ratio (mbt/clang): 0.31x
- ratio (ref/clang): 0.07x
- phases avg ms: parse=153.536 sem=92.947 codegen=205.947 total=452.431
- notes: arm64 benchmark applies `refs/vc_patches/arm64_closure_bytes.patch` to `refs/vc/v.c`; clang uses system headers (compat include skipped); numbers vary by run
