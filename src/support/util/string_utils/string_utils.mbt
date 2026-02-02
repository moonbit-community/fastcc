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
pub fn slice_string(text : String, start : Int, end : Int) -> String {
  text.view(start_offset=start, end_offset=end).to_string()
}

///|
pub fn hex_digit_value(code : UInt16) -> Int? {
  if code >= 48 && code <= 57 {
    return Some(code.to_int() - 48)
  }
  if code >= 65 && code <= 70 {
    return Some(code.to_int() - 65 + 10)
  }
  if code >= 97 && code <= 102 {
    return Some(code.to_int() - 97 + 10)
  }
  None
}
