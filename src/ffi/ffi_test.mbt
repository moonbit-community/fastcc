// Copyright (C) 2026 International Digital Economy Academy
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License as published by the Free Software Foundation; version 2.1
// of the License.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public
// License along with this library.  If not, see <https://www.gnu.org/licenses/>.

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
