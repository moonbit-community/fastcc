# Architecture Overview

This document summarizes the current architecture of tinycc.mbt, how data flows
through the compiler, and where each major responsibility lives today. The code
is intentionally close to refs/tinycc and currently lives in a single MoonBit
package (`src/`).

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
- `main` and CLI parsing live in `src/main.mbt`.
- Compilation pipeline uses `compile_to_object_path` in `src/main.mbt`.
- Preprocessor entry: `new_preprocessor` + `parse_translation_unit`.
- Semantic analysis entry: `check_translation_unit` in `src/sem.mbt`.
- Codegen entry: `codegen_arm64_object_bytes_with_sem` in `src/codegen_arm64_ast.mbt`.
- Object writer: `write_macho_object` in `src/macho.mbt`.

## Directory layout (current)

Top-level:
- `src/`: compiler implementation in one MoonBit package.
- `compat/include/`: libc-style headers for compilation.
- `refs/`: reference projects (tinycc, quickjs, sqlite, etc.).
- `tests/`: C tests and support files.
- `scripts/`: integration scripts (ctest, quickjs, benches).
- `patches/`: patches applied to reference projects in some workflows.

## Frontend

### Source model and diagnostics
- `src/source.mbt` defines `SourceMap`, `SourceFile`, `SrcLoc`.
- `src/diag.mbt` defines `DiagBag` and formatting helpers.
- `format_diag_for_cli` in `src/main.mbt` maps `Diag` to a CLI string.

### Tokens and interners
- `src/tokens.mbt` defines `TokenKind`, `Token`, `LexemePool`.
- `src/string_intern.mbt` provides `StringInterner` for identifier interning.
- Token values use a packed int to reference either an interned id or a lexeme
  slice (negative values for lexeme ids).

### Lexer
- `src/lexer.mbt` consumes a `SourceFile` and produces tokens.
- Handles whitespace, comments, literals, punctuators, and line tracking.
- Emits errors into `DiagBag` directly via `add_error`.

### Preprocessor
- `src/preproc.mbt` implements macro expansion, include handling, conditional
  compilation, and builtin macros. It owns the lexer stack and include stack.
- `Preprocessor` maintains a `HiddenPool` to avoid recursive macro expansion.
- `dump_tokens` is used by the CLI when not compiling to objects.

### AST
- `src/ast.mbt` defines all major syntax nodes:
  - `TranslationUnit` with `Decl` list.
  - `CType` (including qualifiers), `Expr`, `Stmt`, `Initializer`, etc.
  - Attributes and calling conventions are first-class.

### Parser
- `src/parser.mbt` performs token buffering and recursive descent parsing.
- Tracks typedef scopes and overrides to resolve `typedef` vs identifier usage.
- Assigns incremental `expr_id`s to AST nodes for later caches in semantic
  analysis and codegen.

## Semantic analysis

- `src/sem.mbt` owns type checking, symbol tables, layout calculations, and
  builtin behaviors.
- `SemContext` holds multiple maps and caches keyed by string ids:
  - globals/functions/type aliases/records/enums
  - per-function flags (e.g., compound literals, static locals)
  - computed sizes/alignments and field access details
- `expr_utils.mbt` provides helpers for lvalue/call detection.

## Backend

### Arm64 codegen
- `src/codegen_arm64_ast.mbt` is the main backend. It walks AST + SemContext
  and emits:
  - text and data sections
  - relocation entries
  - literal pools and string tables
- `src/arm64.mbt` provides the Arm64 emitter, instruction encoders, and ABI
  register metadata.
- `src/codegen_state.mbt` mirrors tinycc’s internal value/type flags to keep
  parity with refs/tinycc logic.

### Object model and Mach-O writer
- `src/object.mbt` defines `Section` + `Reloc` and adapters from the emitter.
- `src/macho.mbt` builds Mach-O layout (segments, sections, symbol table,
  relocations) and writes the final object bytes.

### Target config
- `src/target_config.mbt` houses target-specific flags (e.g. `char` signedness).

## Driver and CLI

- CLI parsing lives in `src/main.mbt` (`CliConfig`, `parse_cli_args`).
- `compile_to_object_path` orchestrates preprocess -> parse -> sem -> codegen
  and writes an `.o` file.
- Default (no `-c`) currently dumps preprocessed tokens to stdout.
- `-run` builds a temp object, links with `clang`, and executes the result.
- `-bench` enables per-phase timing using `bench_now_ns`.

## Native interop

- `src/bench_timer.c` + `src/bench_timer_native.mbt` implement a monotonic
  timer for native builds.
- `src/bench_timer_stub.mbt` is used for non-native targets.
- `src/run_command.c` provides a tiny `system(3)` wrapper used by the driver.

## Tests and integration

- White-box tests live beside the code (`*_wbtest.mbt`).
- `scripts/run_mbtcc_ctest.sh` runs C test suites and the quickjs compile +
  JS smoke tests. It is part of the expected pipeline.
- Benchmarks are documented in `README.md`.

## Notable coupling points

- Many files share global helper functions without explicit module boundaries
  (single-package design).
- `SemContext` and `Parser` both cache ids derived from the shared interner.
- Codegen depends on both AST and `SemContext` caches for layout and symbol
  resolution.
- Object writer is currently Mach-O-specific and paired with Arm64 codegen.

## Architecture constraints

- The rewrite tracks refs/tinycc structure closely, so refactoring must avoid
  semantic drift and keep codegen behavior identical.
- The build/test pipeline expects quickjs compilation and JS tests to run
  (see `scripts/run_mbtcc_ctest.sh`).
