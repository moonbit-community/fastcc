///|
test "lexer core basic keyword" {
  let map = @source.new_source_map()
  let file = @source.add_file(map, "test.c", "int x;")
  let bag = @diag.new_diag_bag()
  let interner = @intern.new_string_interner_with_capacity()
  let keyword_ids = @tokens.init_keyword_ids(interner)
  let lexeme_pool = @tokens.new_lexeme_pool()
  let lex = @lexer_core.new_lexer(file, bag, interner, keyword_ids, lexeme_pool)
  let tok = @lexer_core.next_token(lex)
  inspect(tok.kind, content="KwInt")
  assert_true(!@diag.has_errors(bag))
}
