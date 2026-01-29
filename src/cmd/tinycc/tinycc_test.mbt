///|
test "cmd exposes run_main" {
  let entry : () -> Unit = @tinycc.run_main
  ignore(entry)
}
