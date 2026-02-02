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
pub type StringInterner = @intern_core.StringInterner

///|
pub let tok_hash_init : UInt = @intern_core.tok_hash_init

///|
pub fn tok_hash_step(h : UInt, code : UInt16) -> UInt {
  @intern_core.tok_hash_step(h, code)
}

///|
pub fn new_string_interner_with_capacity(capacity? : Int) -> StringInterner {
  match capacity {
    None => @intern_core.new_string_interner_with_capacity()
    Some(value) =>
      @intern_core.new_string_interner_with_capacity(capacity=value)
  }
}
