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
test "parser tracks typedef struct name" {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(
    map, "<test>", "typedef struct { int x; } T; int main(){ T r; return r.x; }",
  )
  let pp = @preproc.new_preprocessor(map, file, bag, host=@default_host.new())
  let parser = new_parser(pp)
  ignore(parse_translation_unit_with(parser))
  let (_, type_id) = parser.pp.interner.intern_view_with_id("T"[:])
  assert_true(get_typedef_count(parser, type_id) > 0)
}
