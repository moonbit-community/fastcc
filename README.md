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

- tinycc.mbt total: 1.598s
- refs/tinycc total: 0.117s
- ratio (mbt/ref): 13.69x
- phases avg ms: parse=456.868 sem=137.383 codegen=959.938 total=1554.189
- notes: arm64 benchmark applies `refs/vc_patches/arm64_closure_bytes.patch` to `refs/vc/v.c`; numbers vary by run
