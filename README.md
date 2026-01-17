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

- tinycc.mbt total: 1.603s
- refs/tinycc total: 0.119s
- ratio (mbt/ref): 13.48x
- phases avg ms: parse=461.034 sem=139.913 codegen=958.466 total=1559.412
- notes: arm64 benchmark applies `refs/vc_patches/arm64_closure_bytes.patch` to `refs/vc/v.c`; numbers vary by run
