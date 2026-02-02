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
test "lexer basic keyword" {
  let map = @source.new_source_map()
  let file = @source.add_file(map, "test.c", "int x;")
  let bag = @diag.new_diag_bag()
  let interner = @intern.new_string_interner_with_capacity()
  let keyword_ids = @tokens.init_keyword_ids(interner)
  let lexeme_pool = @tokens.new_lexeme_pool()
  let lex = @lexer.new_lexer(file, bag, interner, keyword_ids, lexeme_pool)
  let tok = @lexer.next_token(lex)
  inspect(tok.kind, content="KwInt")
  assert_true(!@diag.has_errors(bag))
}
