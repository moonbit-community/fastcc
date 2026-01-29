///|
fn cstring_bytes(s : String) -> Bytes {
  let buf = @buffer.new(size_hint=s.length() + 1)
  buf.write_bytes(@encoding/utf8.encode(s))
  buf.write_byte((0 : Byte))
  buf.to_bytes()
}

///|
test "bench_now_ns is callable" {
  let now = @ffi.bench_now_ns()
  assert_true(now >= 0UL)
}

///|
test "run_command shell builtin" {
  let status = @ffi.run_command(cstring_bytes(":"))
  assert_eq(status, 0)
}
