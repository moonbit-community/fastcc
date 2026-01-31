///|
fn expect_cli_error(args : Array[String]) -> Unit raise {
  match @driver.parse_cli_args(args) {
    @driver.CliParse::Error => ()
    _ => fail("expected CliParse::Error")
  }
}

///|
fn expect_cli_help(args : Array[String]) -> Unit raise {
  match @driver.parse_cli_args(args) {
    @driver.CliParse::Help => ()
    _ => fail("expected CliParse::Help")
  }
}

///|
fn must_run(args : Array[String]) -> @driver.CliConfig raise {
  match @driver.parse_cli_args(args) {
    @driver.CliParse::Run(cfg) => cfg
    @driver.CliParse::Help => fail("unexpected help")
    @driver.CliParse::Error => fail("unexpected error")
  }
}

///|
test "cli parse help" {
  expect_cli_help(["tinycc.mbt", "-h"])
  expect_cli_help(["tinycc.mbt", "--help"])
}

///|
test "cli parse listfile expansion" {
  let case_dir = make_case_dir("cli-args")
  let args_path = join_path(case_dir, "args.txt")
  let contents = (
    #| -Iinc
    #| -DNAME=1
    #| -DNOVAL
    #| -UUNDEF
    #| foo.c
    #| bar.o
    #|   
  )
  write_string(args_path, contents)
  let cfg = must_run(["tinycc.mbt", "@" + args_path])
  assert_eq(cfg.include_paths, ["inc"])
  assert_eq(cfg.inputs, ["foo.c"])
  assert_eq(cfg.link_inputs, ["bar.o"])
  assert_true(!cfg.compile_only)
  assert_true(!cfg.run)
  assert_true(!cfg.bench)
  assert_eq(cfg.macro_actions.length(), 3)
  match cfg.macro_actions[0] {
    @driver.CliMacroAction::Define(name~, value~) => {
      assert_eq(name, "NAME")
      assert_true(value is Some("1"))
    }
    _ => fail("expected define macro")
  }
  match cfg.macro_actions[1] {
    @driver.CliMacroAction::Define(name~, value~) => {
      assert_eq(name, "NOVAL")
      assert_true(value is None)
    }
    _ => fail("expected define macro")
  }
  match cfg.macro_actions[2] {
    @driver.CliMacroAction::Undef(name~) => assert_eq(name, "UNDEF")
    _ => fail("expected undef macro")
  }
}

///|
test "cli parse run args" {
  let cfg = must_run(["tinycc.mbt", "-run", "main.c", "arg1", "arg2"])
  assert_true(cfg.run)
  assert_true(!cfg.compile_only)
  assert_eq(cfg.inputs, ["main.c"])
  assert_eq(cfg.run_args, ["arg1", "arg2"])
}

///|
test "cli parse option variants" {
  let cfg = must_run([
    "tinycc.mbt",
    "-bench",
    "-fPIC",
    "-Q",
    "-O2",
    "-g",
    "-Wextra",
    "-w",
    "-isystem/usr/include",
    "-Iinclude",
    "-L/usr/lib",
    "-l",
    "m",
    "-lfoo",
    "-oout.o",
    "main.c",
  ])
  assert_true(cfg.bench)
  assert_true(!cfg.compile_only)
  assert_true(!cfg.run)
  assert_eq(cfg.output, Some("out.o"))
  assert_eq(cfg.include_paths, ["/usr/include", "include"])
  assert_eq(cfg.link_paths, ["/usr/lib"])
  assert_eq(cfg.link_libs, ["m", "foo"])
  assert_eq(cfg.inputs, ["main.c"])
}

///|
test "cli parse error branches" {
  expect_cli_error(["tinycc.mbt", "@missing.args"])
  expect_cli_error(["tinycc.mbt", "-o"])
  expect_cli_error(["tinycc.mbt", "-I"])
  expect_cli_error(["tinycc.mbt", "-D"])
  expect_cli_error(["tinycc.mbt", "-D", ""])
  expect_cli_error(["tinycc.mbt", "-D", "="])
  expect_cli_error(["tinycc.mbt", "-D="])
  expect_cli_error(["tinycc.mbt", "-U"])
  expect_cli_error(["tinycc.mbt", "-U", ""])
  expect_cli_error(["tinycc.mbt", "-isystem"])
  expect_cli_error(["tinycc.mbt", "-L"])
  expect_cli_error(["tinycc.mbt", "-l"])
  expect_cli_error(["tinycc.mbt", "-run", "-c", "main.c"])
  expect_cli_error(["tinycc.mbt", "-run", "--", "arg1"])
  expect_cli_error(["tinycc.mbt", "-c", "-run", "main.c"])
  expect_cli_error(["tinycc.mbt", "-c"])
  expect_cli_error(["tinycc.mbt", "-o", "out.o", "a.c", "b.c"])
  expect_cli_error(["tinycc.mbt", "-bogus", "a.c"])
}
