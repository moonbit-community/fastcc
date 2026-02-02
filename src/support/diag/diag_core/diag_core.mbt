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
pub(all) struct Diag {
  loc : @source.SrcLoc
  message : String
}

///|
pub(all) struct DiagBag {
  diags : Array[Diag]
}

///|
pub fn new_diag_bag() -> DiagBag {
  { diags: [] }
}

///|
pub fn add_error(bag : DiagBag, loc : @source.SrcLoc, message : String) -> Unit {
  bag.diags.push({ loc, message })
}

///|
pub fn error_count(bag : DiagBag) -> Int {
  bag.diags.length()
}

///|
pub fn has_errors(bag : DiagBag) -> Bool {
  error_count(bag) > 0
}

///|
pub fn format_diag(d : Diag) -> String {
  d.message
}
