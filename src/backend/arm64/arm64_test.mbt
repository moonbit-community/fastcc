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
test "arm64 emit32 advances code_len" {
  let emitter = @arm64.new_arm64_emitter()
  @arm64.emit32(emitter, (0x14000000 : UInt))
  assert_eq(emitter.code_len, 1)
  assert_eq(emitter.code[0], (0x14000000 : UInt))
}
