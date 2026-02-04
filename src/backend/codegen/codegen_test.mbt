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
fn parse_text(text : String) -> (@ast.TranslationUnit, @diag.DiagBag) {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<test>", text)
  let pp = @preproc.new_preprocessor(map, file, bag)
  let unit = @parser.parse_translation_unit(pp)
  (unit, bag)
}

///|
test "codegen emits object bytes" {
  let (unit, bag) = parse_text("int main(){return 0;}")
  assert_true(!@diag.has_errors(bag))
  @sem.check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  match @codegen.codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(_bytes) => ()
  }
}
