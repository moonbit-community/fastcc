///|
test "tokens kind text and len" {
  let plus_assign = @tokens.TokenKind::PlusAssign
  assert_eq(@tokens.token_kind_text(plus_assign), "+=")
  assert_eq(@tokens.token_kind_text_len(plus_assign), 2)

  assert_eq(@tokens.token_kind_text(@tokens.TokenKind::LBrace), "{")
  assert_eq(@tokens.token_kind_text(@tokens.TokenKind::RBrace), "}")
  assert_eq(@tokens.token_kind_text(@tokens.TokenKind::Colon), ":")
  assert_eq(@tokens.token_kind_text(@tokens.TokenKind::Question), "?")
  assert_eq(@tokens.token_kind_text(@tokens.TokenKind::Minus), "-")
  assert_eq(@tokens.token_kind_text(@tokens.TokenKind::Percent), "%")
  assert_eq(@tokens.token_kind_text(@tokens.TokenKind::PlusPlus), "++")
  assert_eq(@tokens.token_kind_text(@tokens.TokenKind::MinusAssign), "-=")
  assert_eq(@tokens.token_kind_text(@tokens.TokenKind::StarAssign), "*=")
  assert_eq(@tokens.token_kind_text(@tokens.TokenKind::ShiftLeft), "<<")
  assert_eq(@tokens.token_kind_text(@tokens.TokenKind::ShiftRight), ">>")
  assert_eq(@tokens.token_kind_text(@tokens.TokenKind::HashHash), "##")

  let ellipsis = @tokens.TokenKind::Ellipsis
  assert_eq(@tokens.token_kind_text(ellipsis), "...")
  assert_eq(@tokens.token_kind_text_len(ellipsis), 3)

  let kw_int = @tokens.TokenKind::KwInt
  assert_eq(@tokens.token_kind_text(kw_int), "")
  assert_eq(@tokens.token_kind_text_len(kw_int), 0)

  let shift_right_assign = @tokens.TokenKind::ShiftRightAssign
  assert_eq(@tokens.token_kind_text_len(shift_right_assign), 3)
}

///|
test "tokens lexeme pool helpers" {
  let pool = @tokens.new_lexeme_pool()
  let id = @tokens.lexeme_pool_intern(pool, "hello")
  assert_eq(@tokens.lexeme_pool_get(pool, id), "hello")
  assert_eq(@tokens.lexeme_pool_len(pool, id), 5)

  let slice_id = @tokens.lexeme_pool_intern_slice(pool, "abcdef", 1, 4)
  assert_eq(@tokens.lexeme_pool_len(pool, slice_id), 3)
  assert_eq(@tokens.lexeme_pool_get(pool, slice_id), "bcd")

  let empty_id = @tokens.lexeme_pool_intern(pool, "")
  assert_eq(empty_id, 0)
  assert_eq(@tokens.lexeme_pool_get(pool, 0), "")
  assert_eq(@tokens.lexeme_pool_len(pool, 0), 0)

  let full_id = @tokens.lexeme_pool_intern_slice(pool, "xyz", 0, 3)
  assert_eq(@tokens.lexeme_pool_get(pool, full_id), "xyz")
  let zero_len = @tokens.lexeme_pool_intern_slice(pool, "xyz", 2, 2)
  assert_eq(zero_len, 0)

  let tok = @preproc.make_builtin_token(@tokens.TokenKind::Ident, lexeme_id=id)
  assert_eq(@tokens.token_lexeme_id(tok), id)
  assert_eq(@tokens.token_id(tok), 0)

  let tok_id = @preproc.make_builtin_token(@tokens.TokenKind::Ident, id=7)
  assert_eq(@tokens.token_id(tok_id), 7)
  assert_eq(@tokens.token_lexeme_id(tok_id), 0)

  let interner = @intern.new_string_interner_with_capacity()
  let (_, intern_id) = interner.intern_view_with_id("world"[:])
  assert_true(@tokens.keyword_kind_from_id(0, @tokens.init_keyword_ids(interner)) is None)
  let intern_tok = @preproc.make_builtin_token(@tokens.TokenKind::Ident, id=intern_id)
  assert_eq(@tokens.token_text_with(interner, pool, intern_tok), "world")
  assert_eq(@tokens.token_text_len_with(interner, pool, intern_tok), 5)

  let lex_tok = @preproc.make_builtin_token(@tokens.TokenKind::StrLit, lexeme_id=slice_id)
  assert_eq(@tokens.token_text_with(interner, pool, lex_tok), "bcd")
  assert_eq(@tokens.token_text_len_with(interner, pool, lex_tok), 3)
}
