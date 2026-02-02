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
test "diag core collects errors" {
  let bag = @diag_core.new_diag_bag()
  assert_true(!@diag_core.has_errors(bag))
  @diag_core.add_error(bag, @source.dummy_loc(0), "err")
  assert_true(@diag_core.has_errors(bag))
  inspect(bag.diags.length(), content="1")
}
