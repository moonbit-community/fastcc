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

- tinycc.mbt total: 1.559s
- refs/tinycc total: 0.114s
- ratio (mbt/ref): 13.62x
- phases avg ms: parse=443.593 sem=135.485 codegen=938.442 total=1517.519
- notes: arm64 benchmark applies `refs/vc_patches/arm64_closure_bytes.patch` to `refs/vc/v.c`; numbers vary by run
