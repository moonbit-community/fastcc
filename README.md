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

- tinycc.mbt total: 0.505s
- refs/tinycc total: 0.113s
- clang total: 1.602s
- ratio (mbt/ref): 4.49x
- ratio (mbt/clang): 0.32x
- ratio (ref/clang): 0.07x
- phases avg ms: parse=152.977 sem=95.368 codegen=217.183 total=465.528
- notes: arm64 benchmark applies `refs/vc_patches/arm64_closure_bytes.patch` to `refs/vc/v.c`; clang uses system headers (compat include skipped); numbers vary by run
