# Package Split Proposal

This proposal keeps code close to refs/tinycc while improving modularity and
build times by splitting the single-package `src/` layout into focused
subpackages. The aim is to introduce clear boundaries without changing
behavior.

## Goals

- Preserve compatibility with refs/tinycc semantics and codegen.
- Make the compiler pipeline easier to navigate and test.
- Reduce compile churn by limiting recompilation to touched packages.
- Allow future backends/targets without cross-file entanglement.

## Proposed package tree

```
src/
  cmd/
    tinycc/                 # CLI entrypoint (main)
  driver/                   # compile pipeline + linking
  support/                  # low-level helpers
    diag/                   # DiagBag, format helpers
    source/                 # SourceMap, SrcLoc
    intern/                 # StringInterner, LexemePool
    util/                   # fast_map, target_config, expr_utils
  frontend/
    tokens/                 # TokenKind, Token helpers
    lexer/                  # Lexer
    preproc/                # Preprocessor
    ast/                    # AST types
    parser/                 # Parser
  sem/                      # semantic analysis
  backend/
    arm64/                  # Arm64 emitter + ABI constants
    codegen/                # AST->object lowering (arm64-specific for now)
    object/                 # Section/Reloc
    macho/                  # Mach-O writer
  ffi/                      # native stubs (bench_timer, run_command)
```

Notes:
- Each directory becomes a MoonBit package via `moon.pkg.json`.
- Keep `backend/codegen` arm64-specific initially to avoid rework; separate it
  from `backend/arm64` only to isolate instruction encoding vs AST lowering.

## Suggested file mapping

Current file -> Proposed package
- `main.mbt` -> `src/cmd/tinycc/main.mbt` + `src/driver/driver.mbt`
- `diag.mbt` -> `src/support/diag/diag.mbt`
- `source.mbt` -> `src/support/source/source.mbt`
- `string_intern.mbt` + `tokens.mbt` -> `src/support/intern/`
- `fast_map.mbt` + `expr_utils.mbt` + `target_config.mbt` -> `src/support/util/`
- `lexer.mbt` -> `src/frontend/lexer/`
- `preproc.mbt` -> `src/frontend/preproc/`
- `ast.mbt` -> `src/frontend/ast/`
- `parser.mbt` -> `src/frontend/parser/`
- `sem.mbt` -> `src/sem/`
- `codegen.mbt` -> `src/backend/codegen/`
- `codegen_state.mbt` + `arm64.mbt` -> `src/backend/arm64/`
- `codegen_arm64_ast.mbt` -> `src/backend/codegen/`
- `object.mbt` -> `src/backend/object/`
- `macho.mbt` -> `src/backend/macho/`
- `bench_timer_native.mbt` + `bench_timer_stub.mbt` -> `src/ffi/`
- `run_command.c` + `bench_timer.c` -> `src/ffi/` (native-stub entries updated)
- `*_wbtest.mbt` -> package-local test files in the same directories

## Dependency rules

To avoid cycles and keep the pipeline clean, enforce this dependency ordering:

1. `support/*` has no internal dependencies (stdlib only).
2. `frontend/*` depends only on `support/*`.
3. `sem` depends on `frontend/ast` + `support/*`.
4. `backend/*` depends on `frontend/ast`, `sem`, and `support/*`.
5. `driver` depends on `frontend/*`, `sem`, `backend/*`, and `ffi`.
6. `cmd/tinycc` depends on `driver`.

## Impact on imports

- Replace implicit in-package references with explicit `@package` calls.
- `moon.pkg.json` in each package should list only its direct dependencies.
- Tests should import the package under test (black-box) or use `wbtest-import`
  only when testing private members.

## Migration plan (incremental, low-risk)

1. **Create packages without moving files**
   - Add empty directories and `moon.pkg.json` to establish the structure.
   - No code changes yet.

2. **Move pure support modules**
   - Move `diag`, `source`, `fast_map`, `string_intern`, `tokens`.
   - Update imports from affected files.

3. **Move frontend pipeline**
   - Move `lexer`, `preproc`, `parser`, `ast`.
   - Keep `Parser` + `Preprocessor` APIs identical.

4. **Move semantic analysis**
   - Move `sem.mbt` and update imports from parser/codegen.

5. **Move backend**
   - Split arm64 emitter and codegen lowering into separate packages.
   - Move Mach-O writer and object model.

6. **Move CLI/driver**
   - Extract CLI parsing and `compile_to_object_path` into `driver`.
   - Keep command-line behavior identical.

7. **Move FFI and native stubs**
   - Update `moon.pkg.json` `native-stub` paths accordingly.

8. **Update tests**
   - Relocate `*_wbtest.mbt` and adjust `test-import` / `wbtest-import`.
   - Preserve `scripts/run_mbtcc_ctest.sh` pipeline.

## Risks and mitigations

- **Risk: cyclic dependencies** (parser <-> sem <-> codegen). Mitigate by
  keeping AST types in `frontend/ast` and ensuring sem/codegen depend on it,
  not the other way around.
- **Risk: API churn** due to hidden functions. Mitigate by keeping function
  signatures stable and splitting files only after the package boundary is
  proven.
- **Risk: build/test drift**. Mitigate by keeping `scripts/run_mbtcc_ctest.sh`
  in the pipeline and running quickjs tests after each migration step.

## Optional future refinements

- Add `backend/targets` abstraction for non-arm64 outputs.
- Introduce a `driver/config` package for CLI/driver configuration parsing.
- Convert `target_config.mbt` into a `TargetInfo` struct for easier extension.
