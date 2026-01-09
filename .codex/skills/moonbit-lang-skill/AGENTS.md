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
- Use `pub(all) enum` not factory functions for simple enums
- Use `pub` not `pub(all)` when the constructor should not be exported 
- Use default access control (without `pub`) for types and `pub` constructor functions if necessary
- Use `let mut` only for reassignment, not for mutable containers like Array
- Use `reinterpret_as_uint()` for unsigned ops, `to_int()` for numeric conversion
- Use `Array::length()` not `Array::size()`

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
