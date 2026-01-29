///|
test "cli parses -c" {
  let cfg = match @cli.parse_cli_args(["prog", "-c", "main.c"]) {
    @cli.CliParse::Run(v) => v
    _ => fail("expected run")
  }
  assert_true(cfg.compile_only)
  assert_eq(cfg.inputs, ["main.c"])
}
