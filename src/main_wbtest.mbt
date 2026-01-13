///|
test "cli parses -I/-c/-o and input" {
  let (includes, input, output, compile_only) = match
    parse_cli_args(["prog", "-Iinc1", "-I", "inc2", "-c", "-oout.o", "in.c"]) {
    None => fail("expected args")
    Some(v) => v
  }
  assert_eq(includes, ["inc1", "inc2"])
  assert_eq(input, Some("in.c"))
  assert_eq(output, Some("out.o"))
  assert_true(compile_only)
}

///|
test "cli ignores unknown flags" {
  let (includes, input, output, compile_only) = match
    parse_cli_args(["prog", "-Wall", "-Winvalid", "-c", "in.c"]) {
    None => fail("expected args")
    Some(v) => v
  }
  assert_eq(includes, [])
  assert_eq(input, Some("in.c"))
  assert_eq(output, None)
  assert_true(compile_only)
}
