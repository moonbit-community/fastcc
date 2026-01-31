# Tests

This repo has two kinds of tests:

- **Package-level unit/edge tests** live next to the code they validate (e.g. `src/frontend/preproc/*_test.mbt`).
  They were added to lock in behavior while rewriting `refs/tinycc` in MoonBit and to prevent regressions when refactoring packages.
- **Integration/blackbox tests** live in `src/blackbox/` and exercise the end-to-end pipeline (preprocess → parse → sem → codegen, plus driver behavior).

## Why these tests exist

The bigger test files are intentionally “edge-case heavy”:

- **Preprocessor (`src/frontend/preproc/*`)**: macro registry/hidden-set behavior, directive parsing, include resolution, and `#if` expression evaluation.
- **Lexer / Tokens / Parser (`src/frontend/*`)**: tokenization and parser error-recovery paths that are easy to accidentally break while refactoring.
- **Semantics (`src/sem/*`)**: helper/wrapper utilities that many later passes rely on.
- **Backends (`src/backend/*`)**: ARM64 encoding/emitter correctness and Mach-O object encoding/relocations.
- **Support utilities (`src/support/*`)**: literal parsing, string helpers, interning, and map wrappers used pervasively across the compiler.

## Parallelization note

Tests were originally introduced under a single `src/blackbox` package, which made it hard for `moon test` to parallelize work.
They are now distributed into their owning packages, and shared filesystem helpers were extracted into `hackwaly/tinycc/testutil`.
