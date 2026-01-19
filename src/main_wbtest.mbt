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
  assert_eq(cfg.macro_actions, [])
}

///|
test "cli rejects unknown flags" {
  match parse_cli_args(["prog", "-Zunknown", "-c", "in.c"]) {
    CliParse::Error => ()
    _ => fail("expected parse error")
  }
}

///|
test "cli ignores common warning/debug flags" {
  let cfg = match parse_cli_args(["prog", "-Wall", "-Winvalid", "-O2", "-g", "-c", "in.c"]) {
    CliParse::Run(v) => v
    _ => fail("expected args")
  }
  assert_true(cfg.compile_only)
  assert_eq(cfg.inputs, ["in.c"])
  assert_eq(cfg.macro_actions, [])
}

///|
test "cli supports multiple input files" {
  let cfg = match parse_cli_args(["prog", "-c", "a.c", "b.c"]) {
    CliParse::Run(v) => v
    _ => fail("expected args")
  }
  assert_eq(cfg.inputs, ["a.c", "b.c"])
  assert_eq(cfg.macro_actions, [])
}

///|
test "cli parses -isystem" {
  let cfg = match parse_cli_args(["prog", "-isystem", "sysinc", "-c", "in.c"]) {
    CliParse::Run(v) => v
    _ => fail("expected args")
  }
  assert_eq(cfg.include_paths, ["sysinc"])
  assert_eq(cfg.macro_actions, [])
}

///|
test "cli parses -D and -U" {
  let cfg = match parse_cli_args([
    "prog",
    "-D",
    "FOO",
    "-DBAR=2",
    "-DBAZ=",
    "-U",
    "FOO",
    "-UQUX",
    "-c",
    "in.c",
  ]) {
    CliParse::Run(v) => v
    _ => fail("expected args")
  }
  assert_eq(cfg.macro_actions, [
    CliMacroAction::Define(name="FOO", value=None),
    CliMacroAction::Define(name="BAR", value=Some("2")),
    CliMacroAction::Define(name="BAZ", value=Some("")),
    CliMacroAction::Undef(name="FOO"),
    CliMacroAction::Undef(name="QUX"),
  ])
}

///|
test "bench timer symbol is available" {
  let now = bench_now_ns()
  assert_true(now >= 0UL)
}
