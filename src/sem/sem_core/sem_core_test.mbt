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
test "sem core accepts empty translation unit" {
  let bag = @diag.new_diag_bag()
  let unit = @ast.TranslationUnit::{ decls: [], expr_id_max: 0 }
  let _ctx = @sem_core.check_translation_unit(unit, bag)
  assert_true(!@diag.has_errors(bag))
}
