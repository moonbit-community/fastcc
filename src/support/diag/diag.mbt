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
pub type Diag = @diag_core.Diag

///|
pub type DiagBag = @diag_core.DiagBag

///|
pub fn new_diag_bag() -> DiagBag {
  @diag_core.new_diag_bag()
}

///|
pub fn add_error(bag : DiagBag, loc : @source.SrcLoc, message : String) -> Unit {
  @diag_core.add_error(bag, loc, message)
}

///|
pub fn has_errors(bag : DiagBag) -> Bool {
  @diag_core.has_errors(bag)
}

///|
pub fn error_count(bag : DiagBag) -> Int {
  @diag_core.error_count(bag)
}

///|
pub fn format_diag(d : Diag) -> String {
  @diag_core.format_diag(d)
}
