///|
test "driver run_args help and error" {
  assert_eq(@driver.run_args(host=@default_host.new(), ["fastcc.mbt", "-h"]), 0)
  assert_eq(
    @driver.run_args(host=@default_host.new(), ["fastcc.mbt", "--help"]),
    0,
  )
  assert_eq(
    @driver.run_args(host=@default_host.new(), ["fastcc.mbt", "-bogus"]),
    1,
  )
  assert_eq(
    @driver.run_args(host=@default_host.new(), ["fastcc.mbt", "missing-file.c"]),
    1,
  )
}

///|
test "driver link mode emits executable" {
  let stamp = @env.now().to_string()
  let src_path = "target/link-mode-\{stamp}.c"
  let exe_path = "target/link-mode-\{stamp}.exe"
  @fs.write_string_to_file(src_path, "int main(void) { return 0; }\n") catch {
    err => fail("failed to write source file: \{err.to_string()}")
  }
  let status = @driver.run_args(host=@default_host.new(), [
    "fastcc.mbt", "-o", exe_path, src_path,
  ])
  @fs.remove_file(src_path) catch {
    _ => ()
  }
  guard status == 0 else {
    @fs.remove_file(exe_path) catch {
      _ => ()
    }
    fail("expected link mode success, got status=\{status}")
  }
  assert_true(@fs.path_exists(exe_path))
  @fs.remove_file(exe_path) catch {
    _ => ()
  }
}

///|
test "driver bench now ns" {
  let now = @driver.bench_now_ns()
  assert_true(now > 0UL)
}
