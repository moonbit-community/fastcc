///|
fn expect_cli_error(args : Array[String]) -> Unit raise {
  match @cli.parse_cli_args(host=@default_host.new(), args) {
    Error => ()
    _ => fail("expected CliParse::Error")
  }
}

///|
fn expect_cli_help(args : Array[String]) -> Unit raise {
  match @cli.parse_cli_args(host=@default_host.new(), args) {
    Help => ()
    _ => fail("expected CliParse::Help")
  }
}

///|
fn must_run(args : Array[String]) -> @cli.CliConfig raise {
  match @cli.parse_cli_args(host=@default_host.new(), args) {
    Run(cfg) => cfg
    Help => fail("unexpected help")
    Error => fail("unexpected error")
  }
}

///|
test "cli parse help" {
  expect_cli_help(["fastcc.mbt", "-h"])
  expect_cli_help(["fastcc.mbt", "--help"])
}

///|
test "cli parse listfile expansion" {
  let case_dir = @testutil.make_case_dir("cli-args")
  let args_path = @testutil.join_path(case_dir, "args.txt")
  let contents =
    #| -Iinc
    #| -DNAME=1
    #| -DNOVAL
    #| -UUNDEF
    #| foo.c
    #| bar.o
    #|
  @testutil.write_string(args_path, contents)
  let cfg = must_run(["fastcc.mbt", "@" + args_path])
  assert_eq(cfg.include_paths, ["inc"])
  assert_eq(cfg.inputs, ["foo.c"])
  assert_eq(cfg.link_inputs, ["bar.o"])
  assert_true(!cfg.compile_only)
  assert_true(!cfg.run)
  assert_true(!cfg.bench)
  assert_eq(cfg.macro_actions.length(), 3)
  match cfg.macro_actions[0] {
    Define(name~, value~) => {
      assert_eq(name, "NAME")
      assert_true(value is Some("1"))
    }
    _ => fail("expected define macro")
  }
  match cfg.macro_actions[1] {
    Define(name~, value~) => {
      assert_eq(name, "NOVAL")
      assert_true(value is None)
    }
    _ => fail("expected define macro")
  }
  match cfg.macro_actions[2] {
    Undef(name~) => assert_eq(name, "UNDEF")
    _ => fail("expected undef macro")
  }
}

///|
test "cli parse run args" {
  let cfg = must_run(["fastcc.mbt", "-run", "main.c", "arg1", "arg2"])
  assert_true(cfg.run)
  assert_true(!cfg.compile_only)
  assert_eq(cfg.inputs, ["main.c"])
  assert_eq(cfg.run_args, ["arg1", "arg2"])
}

///|
test "cli parse option variants" {
  let cfg = must_run([
    "fastcc.mbt", "-bench", "-fPIC", "-fwrapv", "-fno-strict-aliasing", "-Q", "-O2",
    "-g", "-Wextra", "-w", "-isystem/usr/include", "-Iinclude", "-L/usr/lib", "-l",
    "m", "-lfoo", "-oout.o", "main.c",
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
test "cli parse stdin input" {
  let cfg = must_run(["fastcc.mbt", "-"])
  assert_true(!cfg.compile_only)
  assert_true(!cfg.run)
  assert_eq(cfg.inputs, ["-"])
  assert_eq(cfg.link_inputs, [])
}

///|
test "cli parse run stdin input" {
  let cfg = must_run(["fastcc.mbt", "-run", "-", "arg1"])
  assert_true(cfg.run)
  assert_eq(cfg.inputs, ["-"])
  assert_eq(cfg.run_args, ["arg1"])
}

///|
test "cli parse link mode output with multiple inputs" {
  let cfg = must_run(["fastcc.mbt", "-o", "app.out", "a.c", "b.c"])
  assert_true(!cfg.compile_only)
  assert_true(!cfg.run)
  assert_eq(cfg.output, Some("app.out"))
  assert_eq(cfg.inputs, ["a.c", "b.c"])
}

///|
test "cli parse error branches" {
  expect_cli_error(["fastcc.mbt", "@missing.args"])
  expect_cli_error(["fastcc.mbt", "-o"])
  expect_cli_error(["fastcc.mbt", "-I"])
  expect_cli_error(["fastcc.mbt", "-D"])
  expect_cli_error(["fastcc.mbt", "-D", ""])
  expect_cli_error(["fastcc.mbt", "-D", "="])
  expect_cli_error(["fastcc.mbt", "-D="])
  expect_cli_error(["fastcc.mbt", "-U"])
  expect_cli_error(["fastcc.mbt", "-U", ""])
  expect_cli_error(["fastcc.mbt", "-isystem"])
  expect_cli_error(["fastcc.mbt", "-L"])
  expect_cli_error(["fastcc.mbt", "-l"])
  expect_cli_error(["fastcc.mbt", "-run", "-c", "main.c"])
  expect_cli_error(["fastcc.mbt", "-run", "--", "arg1"])
  expect_cli_error(["fastcc.mbt", "-c", "-run", "main.c"])
  expect_cli_error(["fastcc.mbt", "-c"])
  expect_cli_error(["fastcc.mbt", "-c", "-o", "out.o", "a.c", "b.c"])
  expect_cli_error(["fastcc.mbt", "-bogus", "a.c"])
}
