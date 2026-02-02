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
test "preproc core token dump" {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<test>", "int x;")
  let pp = @preproc_core.new_preprocessor(map, file, bag)
  let toks = @preproc_core.dump_tokens(pp, 8)
  assert_true(toks.length() > 0)
  assert_true(!@diag.has_errors(bag))
}
