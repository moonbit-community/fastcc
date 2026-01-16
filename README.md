# tinycc.mbt

## Benchmark (refs/vc/v.c)

File: `refs/vc/v.c` (138152 LOC)

Environment: macOS arm64, tinycc from this repo built in release mode.

### tinycc.mbt

Command:

```
./_build/native/release/build/tinycc.exe -I compat/include -c refs/vc/v.c -o /tmp/v.mbt.o
```

Results (3 runs):

- avg: 2.4260s
- throughput: 56946 LOC/s

### refs/tinycc (official)

Command:

```
refs/tinycc/tcc -I compat/include -c refs/vc/v.c -o /tmp/v.tcc.o
```

Status:

- fails on arm64 with `refs/vc/v.c:137341: error: too many initializers`
- TODO: rerun benchmark on x86_64 host or patch v.c to avoid excess initializers for arm64
