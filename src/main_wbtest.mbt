///|
test "cli parses -I/-c/-o and input" {
  let cfg = match parse_cli_args(["prog", "-Iinc1", "-I", "inc2", "-c", "-oout.o", "in.c"]) {
    CliParse::Run(v) => v
    _ => fail("expected args")
  }
  assert_eq(cfg.include_paths, ["inc1", "inc2"])
  assert_eq(cfg.inputs, ["in.c"])
  assert_eq(cfg.output, Some("out.o"))
  assert_true(cfg.compile_only)
}

///|
test "cli rejects unknown flags" {
  match parse_cli_args(["prog", "-Wall", "-Winvalid", "-c", "in.c"]) {
    CliParse::Error => ()
    _ => fail("expected parse error")
  }
}

///|
test "cli supports multiple input files" {
  let cfg = match parse_cli_args(["prog", "-c", "a.c", "b.c"]) {
    CliParse::Run(v) => v
    _ => fail("expected args")
  }
  assert_eq(cfg.inputs, ["a.c", "b.c"])
}

///|
test "cli parses -isystem" {
  let cfg = match parse_cli_args(["prog", "-isystem", "sysinc", "-c", "in.c"]) {
    CliParse::Run(v) => v
    _ => fail("expected args")
  }
  assert_eq(cfg.include_paths, ["sysinc"])
}
