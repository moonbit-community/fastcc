///|
test "driver run_args help and error" {
  assert_eq(@driver.run_args(["tinycc.mbt", "-h"]), 0)
  assert_eq(@driver.run_args(["tinycc.mbt", "--help"]), 0)
  assert_eq(@driver.run_args(["tinycc.mbt", "-bogus"]), 1)
  assert_eq(@driver.run_args(["tinycc.mbt", "missing-file.c"]), 1)
}

///|
test "driver bench now ns" {
  let now = @driver.bench_now_ns()
  assert_true(now > 0UL)
}
