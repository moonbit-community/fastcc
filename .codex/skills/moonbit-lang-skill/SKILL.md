---
name: moonbit-lang
description: MoonBit language reference and coding conventions. Use when writing MoonBit code, asking about syntax, or encountering MoonBit-specific errors. Covers error handling, FFI, async, and common pitfalls.
---

# MoonBit Language Reference

@reference/index.md
@reference/introduction.md
@reference/fundamentals.md
@reference/methods.md
@reference/derive.md
@reference/error-handling.md
@reference/packages.md
@reference/tests.md
@reference/benchmarks.md
@reference/docs.md
@reference/attributes.md
@reference/ffi.md
@reference/async-experimental.md
@reference/error_codes/index.md
@reference/toml-parser-parser.mbt

## Official Packages

MoonBit has official packages maintained by the team:

- **moonbitlang/x**: Utilities including file I/O (`moonbitlang/x/fs`)
- **moonbitlang/async**: Asynchronous runtime with TCP, HTTP, async queues, async test, and async main

To use these packages:
1. Add the dependency: `moon add moonbitlang/x` or `moon add moonbitlang/async`
2. Import the specific subpackage in `moon.pkg.json`:
   ```json
   {"import": ["moonbitlang/x/fs"]}
   ```

## Common Pitfalls

- Use `suberror` for error types, `raise` to throw, `try! func() |> ignore` to ignore errors
- Use `func() |> ignore` not `let _ = func()`
- When using `inspect(value, content=expected_string)`, don't declare a separate `let expected = ...` variable - it causes unused variable warnings. Put the expected string directly in the `content=` parameter
- Use `!condition` not `not(condition)`
- Use `f(value)` not `f!(value)` (deprecated)
- Use `for i in 0..<n` not C-style `for i = 0; i < n; i = i + 1`
- Use `if opt is Pattern(v) { ... }` for single-branch matching, not `match opt {}`
- Use `arr.clear()` not `while arr.length() > 0 { arr.pop() }`
- Use `s.code_unit_at(i)` or `for c in s` not `s[i]` (deprecated)
- Struct/enum visibility: `priv` (hidden) < (none)/abstract (type only) < `pub` (readonly) < `pub(all)` (full)
- Default to abstract (no modifier) for internal types; use `pub struct` when external code reads fields
- Use `pub(all) enum` for enums that external code pattern-matches on
- Use `let mut` only for reassignment, not for mutable containers like Array
- Use `reinterpret_as_uint()` for unsigned ops, `to_int()` for numeric conversion
- Use `Array::length()` not `Array::size()`
- In moon.pkg.json, use "import", "test-import" and "wbtest-import" to manage package importing for ".mbt", "_test.mbt" and "_wbtest.mbt"
- Use `Option::unwrap_or` not `Option::or`

## Parser Style Reference

When writing a hand-written parser, follow the style in `reference/toml-parser-parser.mbt` (mirrored from `moonbit-community/toml-parser`).

- Prefer `Parser::parse_*` methods that advance a token view (`view`/`update_view`)
- Centralize error reporting (e.g. `Parser::error`) and include token locations
- Keep functions small (`parse_value`, `parse_array`, ...) and separate blocks with `///|`
