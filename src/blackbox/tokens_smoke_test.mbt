///|
test "tokens kind text and len" {
  let plus_assign = @tokens.TokenKind::PlusAssign
  assert_eq(@tokens.token_kind_text(plus_assign), "+=")
  assert_eq(@tokens.token_kind_text_len(plus_assign), 2)

  let ellipsis = @tokens.TokenKind::Ellipsis
  assert_eq(@tokens.token_kind_text(ellipsis), "...")
  assert_eq(@tokens.token_kind_text_len(ellipsis), 3)

  let kw_int = @tokens.TokenKind::KwInt
  assert_eq(@tokens.token_kind_text(kw_int), "")
  assert_eq(@tokens.token_kind_text_len(kw_int), 0)
}

///|
test "tokens lexeme pool helpers" {
  let pool = @tokens.new_lexeme_pool()
  let id = @tokens.lexeme_pool_intern(pool, "hello")
  assert_eq(@tokens.lexeme_pool_get(pool, id), "hello")
  assert_eq(@tokens.lexeme_pool_len(pool, id), 5)

  let empty_id = @tokens.lexeme_pool_intern(pool, "")
  assert_eq(empty_id, 0)

  let tok = @preproc.make_builtin_token(@tokens.TokenKind::Ident, lexeme_id=id)
  assert_eq(@tokens.token_lexeme_id(tok), id)
  assert_eq(@tokens.token_id(tok), 0)

  let tok_id = @preproc.make_builtin_token(@tokens.TokenKind::Ident, id=7)
  assert_eq(@tokens.token_id(tok_id), 7)
  assert_eq(@tokens.token_lexeme_id(tok_id), 0)
}
