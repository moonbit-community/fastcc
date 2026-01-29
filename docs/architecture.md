# Architecture Overview

This document summarizes the current architecture of tinycc.mbt, how data flows
through the compiler, and where each major responsibility lives today. The code
is intentionally close to refs/tinycc and is now split into focused MoonBit
packages under `src/`.

## High-level flow

```
CLI args
  -> load_input + SourceMap + DiagBag
  -> Preprocessor (includes/macros, token stream)
  -> Parser (AST + node ids)
  -> Semantic analysis (types, symbols, layouts)
  -> Arm64 codegen (text/data/rodata + relocations)
  -> Mach-O object writer
  -> clang link (optional)
  -> run (optional)
```

Key entrypoints:
- `main` lives in `src/main.mbt` and delegates to `@driver.run_main`.
- Compilation pipeline uses `compile_to_object_path` in `src/driver/driver.mbt`.
- Preprocessor entry: `@preproc.new_preprocessor` + `@parser.parse_translation_unit`.
- Semantic analysis entry: `@sem.check_translation_unit` in `src/sem/sem.mbt`.
- Codegen entry: `@codegen.codegen_arm64_object_bytes_with_sem` in `src/backend/codegen/codegen.mbt`.
- Object writer: `@macho.write_macho_object` in `src/backend/macho/macho.mbt`.

## Directory layout (current)

Top-level:
- `src/`: compiler implementation split into packages (driver, frontend/*, sem,
  backend/*, support/*, ffi).
- `compat/include/`: libc-style headers for compilation.
- `refs/`: reference projects (tinycc, quickjs, sqlite, etc.).
- `tests/`: C tests and support files.
- `scripts/`: integration scripts (ctest, quickjs, benches).
- `patches/`: patches applied to reference projects in some workflows.

## Frontend

### Source model and diagnostics
- `src/support/source/source.mbt` defines `SourceMap`, `SourceFile`, `SrcLoc`.
- `src/support/diag/diag.mbt` defines `DiagBag` and formatting helpers.
- `format_diag_for_cli` in `src/driver/driver.mbt` maps `Diag` to a CLI string.

### Tokens and interners
- `src/frontend/tokens/tokens.mbt` defines `TokenKind`, `Token`, `LexemePool`.
- `src/support/intern/string_intern.mbt` provides `StringInterner` for identifier interning.
- Token values use a packed int to reference either an interned id or a lexeme
  slice (negative values for lexeme ids).

### Lexer
- `src/frontend/lexer/lexer.mbt` consumes a `SourceFile` and produces tokens.
- Handles whitespace, comments, literals, punctuators, and line tracking.
- Emits errors into `DiagBag` directly via `add_error`.

### Preprocessor
- `src/frontend/preproc/preproc.mbt` implements macro expansion, include handling, conditional
  compilation, and builtin macros. It owns the lexer stack and include stack.
- `Preprocessor` maintains a `HiddenPool` to avoid recursive macro expansion.
- `dump_tokens` is used by the CLI when not compiling to objects.

### AST
- `src/frontend/ast/ast.mbt` defines all major syntax nodes:
  - `TranslationUnit` with `Decl` list.
  - `CType` (including qualifiers), `Expr`, `Stmt`, `Initializer`, etc.
  - Attributes and calling conventions are first-class.

### Parser
- `src/frontend/parser/parser.mbt` performs token buffering and recursive descent parsing.
- Tracks typedef scopes and overrides to resolve `typedef` vs identifier usage.
- Assigns incremental `expr_id`s to AST nodes for later caches in semantic
  analysis and codegen.

## Semantic analysis

- `src/sem/sem_core/sem_core.mbt` owns type checking, symbol tables, layout calculations, and
  builtin behaviors (re-exported by `src/sem/sem.mbt`).
- `SemContext` holds multiple maps and caches keyed by string ids:
  - globals/functions/type aliases/records/enums
  - per-function flags (e.g., compound literals, static locals)
  - computed sizes/alignments and field access details
- `src/support/util/util.mbt` provides helpers for lvalue/call detection.

## Backend

### Arm64 codegen
- `src/backend/codegen/codegen_arm64_ast.mbt` is the main backend. It walks AST + SemContext
  and emits:
  - text and data sections
  - relocation entries
  - literal pools and string tables
- `src/backend/arm64/arm64.mbt` provides the Arm64 emitter, instruction encoders, and ABI
  register metadata.
- `src/backend/arm64/codegen_state.mbt` mirrors tinycc’s internal value/type flags to keep
  parity with refs/tinycc logic.

### Object model and Mach-O writer
- `src/backend/object/object.mbt` defines `Section` + `Reloc` and adapters from the emitter.
- `src/backend/macho/macho.mbt` builds Mach-O layout (segments, sections, symbol table,
  relocations) and writes the final object bytes.

### Target config
- `src/support/util/util.mbt` houses target-specific flags (e.g. `char` signedness).

## Driver and CLI

- CLI parsing lives in `src/driver/driver.mbt` (`CliConfig`, `parse_cli_args`).
- `src/main.mbt` is a thin entrypoint that delegates to `@driver.run_main`.
- `compile_to_object_path` in `src/driver/driver.mbt` orchestrates
  preprocess -> parse -> sem -> codegen and writes an `.o` file.
- Default (no `-c`) currently dumps preprocessed tokens to stdout.
- `-run` builds a temp object, links with `clang`, and executes the result.
- `-bench` enables per-phase timing using `bench_now_ns`.

## Native interop

- `src/ffi/bench_timer.c` + `src/ffi/bench_timer_native.mbt` implement a monotonic
  timer for native builds.
- `src/ffi/bench_timer_stub.mbt` is used for non-native targets.
- `src/ffi/run_command.c` provides a tiny `system(3)` wrapper used by the driver.

## Tests and integration

- White-box tests live beside the code (`*_wbtest.mbt`).
- `scripts/run_mbtcc_ctest.sh` runs C test suites and the quickjs compile +
  JS smoke tests. It is part of the expected pipeline.
- Benchmarks are documented in `README.md`.

## Notable coupling points

- Package boundaries reduce file-level coupling, but SemContext and Parser
  still share data derived from interned ids and token pools.
- `SemContext` and `Parser` both cache ids derived from the shared interner.
- Codegen depends on both AST and `SemContext` caches for layout and symbol
  resolution.
- Object writer is currently Mach-O-specific and paired with Arm64 codegen.

## Architecture constraints

- The rewrite tracks refs/tinycc structure closely, so refactoring must avoid
  semantic drift and keep codegen behavior identical.
- The build/test pipeline expects quickjs compilation and JS tests to run
  (see `scripts/run_mbtcc_ctest.sh`).
