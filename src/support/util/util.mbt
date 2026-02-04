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
pub type FastMap[K, V] = @fast_map.FastMap[K, V]

///|
pub let char_is_unsigned : Bool = @target_config.char_is_unsigned

///|
pub fn[K, V] fast_map_new(capacity? : Int) -> FastMap[K, V] {
  match capacity {
    None => @fast_map.fast_map_new()
    Some(value) => @fast_map.fast_map_new(capacity=value)
  }
}

///|
pub fn int_literal_end(text : String) -> Int {
  @int_literals.int_literal_end(text)
}

///|
pub fn int_literal_base(text : String) -> Int {
  @int_literals.int_literal_base(text)
}

///|
pub fn int_literal_base_from(text : String, end : Int) -> Int {
  @int_literals.int_literal_base_from(text, end)
}

///|
pub fn parse_uint64_literal(text : String, base : Int) -> UInt64 {
  @int_literals.parse_uint64_literal(text, base)
}

///|
pub fn parse_uint64_literal_prefix(
  text : String,
  base : Int,
  end : Int,
) -> UInt64 {
  @int_literals.parse_uint64_literal_prefix(text, base, end)
}

///|
pub fn parse_int_suffix(suffix : String) -> (Int, Bool) {
  @int_literals.parse_int_suffix(suffix)
}

///|
pub fn parse_int_suffix_range(text : String, start : Int) -> (Int, Bool) {
  @int_literals.parse_int_suffix_range(text, start)
}

///|
pub fn slice_string(text : String, start : Int, end : Int) -> String {
  @string_utils.slice_string(text, start, end)
}

///|
pub fn hex_digit_value(code : UInt16) -> Int? {
  @string_utils.hex_digit_value(code)
}
