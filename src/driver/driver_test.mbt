///|
test "cli parses -I/-c/-o and input" {
  let cfg = match @driver.parse_cli_args([
    "prog",
    "-Iinc1",
    "-I",
    "inc2",
    "-c",
    "-oout.o",
    "in.c",
  ]) {
    @driver.CliParse::Run(v) => v
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
  match @driver.parse_cli_args(["prog", "-bogus", "-c", "in.c"]) {
    @driver.CliParse::Error => ()
    _ => fail("expected parse error")
  }
}

///|
test "cli ignores -Z flags" {
  let cfg = match @driver.parse_cli_args(["prog", "-Zunknown", "-c", "in.c"]) {
    @driver.CliParse::Run(v) => v
    _ => fail("expected args")
  }
  assert_true(cfg.compile_only)
  assert_eq(cfg.inputs, ["in.c"])
}

///|
test "cli ignores common warning/debug flags" {
  let cfg = match @driver.parse_cli_args([
    "prog",
    "-Wall",
    "-Winvalid",
    "-O2",
    "-g",
    "-c",
    "in.c",
  ]) {
    @driver.CliParse::Run(v) => v
    _ => fail("expected args")
  }
  assert_true(cfg.compile_only)
  assert_eq(cfg.inputs, ["in.c"])
  assert_eq(cfg.macro_actions, [])
}

///|
test "cli supports multiple input files" {
  let cfg = match @driver.parse_cli_args(["prog", "-c", "a.c", "b.c"]) {
    @driver.CliParse::Run(v) => v
    _ => fail("expected args")
  }
  assert_eq(cfg.inputs, ["a.c", "b.c"])
  assert_eq(cfg.macro_actions, [])
}

///|
test "cli parses -isystem" {
  let cfg = match @driver.parse_cli_args(["prog", "-isystem", "sysinc", "-c", "in.c"]) {
    @driver.CliParse::Run(v) => v
    _ => fail("expected args")
  }
  assert_eq(cfg.include_paths, ["sysinc"])
  assert_eq(cfg.macro_actions, [])
}

///|
test "cli parses -D and -U" {
  let cfg = match @driver.parse_cli_args([
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
    @driver.CliParse::Run(v) => v
    _ => fail("expected args")
  }
  assert_eq(cfg.macro_actions, [
    @driver.CliMacroAction::Define(name="FOO", value=None),
    @driver.CliMacroAction::Define(name="BAR", value=Some("2")),
    @driver.CliMacroAction::Define(name="BAZ", value=Some("")),
    @driver.CliMacroAction::Undef(name="FOO"),
    @driver.CliMacroAction::Undef(name="QUX"),
  ])
}

///|
test "cli expands @listfile" {
  let dir = "target"
  if !@fs.path_exists(dir) {
    @fs.create_dir(dir) catch {
      err => fail("failed to create target dir: \{err.to_string()}")
    }
  }
  let path = dir + "/cli_args.txt"
  @fs.write_string_to_file(path, "-I inc -DTEST=1 in.c") catch {
    err => fail("failed to write listfile: \{err.to_string()}")
  }
  let cfg = match @driver.parse_cli_args(["prog", "@" + path]) {
    @driver.CliParse::Run(v) => v
    _ => fail("expected args")
  }
  assert_eq(cfg.include_paths, ["inc"])
  assert_eq(cfg.inputs, ["in.c"])
  assert_eq(cfg.macro_actions, [@driver.CliMacroAction::Define(name="TEST", value=Some("1"))])
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "cli parses -run" {
  let cfg = match @driver.parse_cli_args([
    "prog",
    "-L",
    "libdir",
    "-lfoo",
    "libbar.dylib",
    "-run",
    "main.c",
    "arg1",
  ]) {
    @driver.CliParse::Run(v) => v
    _ => fail("expected args")
  }
  assert_true(cfg.run)
  assert_eq(cfg.inputs, ["main.c"])
  assert_eq(cfg.run_args, ["arg1"])
  assert_eq(cfg.link_paths, ["libdir"])
  assert_eq(cfg.link_libs, ["foo"])
  assert_eq(cfg.link_inputs, ["libbar.dylib"])
}

///|
test "bench timer symbol is available" {
  let now = @driver.bench_now_ns()
  assert_true(now >= 0UL)
}
