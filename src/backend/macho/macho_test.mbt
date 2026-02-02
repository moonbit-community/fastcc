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
fn read_u32_le(bytes : Bytes, offset : Int) -> UInt {
  let b0 = bytes[offset].to_uint()
  let b1 = bytes[offset + 1].to_uint() << 8
  let b2 = bytes[offset + 2].to_uint() << 16
  let b3 = bytes[offset + 3].to_uint() << 24
  b0 | b1 | b2 | b3
}

///|
test "macho encode writes magic" {
  let sec = @object.new_section(".text")
  sec.data.push((0x14000000 : UInt))
  let symbols = [
    @macho.ObjSymbol::{
      id: 1,
      name: "_main",
      section: Some(".text"),
      value: 0,
      is_external: true,
    },
  ]
  let bytes = @macho.encode_macho_object([sec], symbols)
  assert_eq(read_u32_le(bytes, 0), @macho.MH_MAGIC_64)
}
