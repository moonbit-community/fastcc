///|
test "tokens kind text and len" {
  let plus_assign = @tokens.TokenKind::PlusAssign
  assert_eq(@tokens.token_kind_text(plus_assign), "+=")
  assert_eq(@tokens.token_kind_text_len(plus_assign), 2)
  assert_eq(@tokens.token_kind_text(LBrace), "{")
  assert_eq(@tokens.token_kind_text(RBrace), "}")
  assert_eq(@tokens.token_kind_text(LBracket), "[")
  assert_eq(@tokens.token_kind_text(RBracket), "]")
  assert_eq(@tokens.token_kind_text(Comma), ",")
  assert_eq(@tokens.token_kind_text(Colon), ":")
  assert_eq(@tokens.token_kind_text(Question), "?")
  assert_eq(@tokens.token_kind_text(Minus), "-")
  assert_eq(@tokens.token_kind_text(Percent), "%")
  assert_eq(@tokens.token_kind_text(PlusPlus), "++")
  assert_eq(@tokens.token_kind_text(MinusMinus), "--")
  assert_eq(@tokens.token_kind_text(MinusAssign), "-=")
  assert_eq(@tokens.token_kind_text(StarAssign), "*=")
  assert_eq(@tokens.token_kind_text(SlashAssign), "/=")
  assert_eq(@tokens.token_kind_text(PercentAssign), "%=")
  assert_eq(@tokens.token_kind_text(ShiftLeft), "<<")
  assert_eq(@tokens.token_kind_text(ShiftRight), ">>")
  assert_eq(@tokens.token_kind_text(ShiftLeftAssign), "<<=")
  assert_eq(@tokens.token_kind_text(ShiftRightAssign), ">>=")
  assert_eq(@tokens.token_kind_text(Eq), "==")
  assert_eq(@tokens.token_kind_text(Ne), "!=")
  assert_eq(@tokens.token_kind_text(Lt), "<")
  assert_eq(@tokens.token_kind_text(Le), "<=")
  assert_eq(@tokens.token_kind_text(Amp), "&")
  assert_eq(@tokens.token_kind_text(Pipe), "|")
  assert_eq(@tokens.token_kind_text(Caret), "^")
  assert_eq(@tokens.token_kind_text(Tilde), "~")
  assert_eq(@tokens.token_kind_text(Bang), "!")
  assert_eq(@tokens.token_kind_text(HashHash), "##")
  let ellipsis = @tokens.TokenKind::Ellipsis
  assert_eq(@tokens.token_kind_text(ellipsis), "...")
  assert_eq(@tokens.token_kind_text_len(ellipsis), 3)
  let kw_int = @tokens.TokenKind::KwInt
  assert_eq(@tokens.token_kind_text(kw_int), "")
  assert_eq(@tokens.token_kind_text_len(kw_int), 0)
  let shift_right_assign = @tokens.TokenKind::ShiftRightAssign
  assert_eq(@tokens.token_kind_text_len(shift_right_assign), 3)
  let shift_left_assign = @tokens.TokenKind::ShiftLeftAssign
  assert_eq(@tokens.token_kind_text_len(shift_left_assign), 3)
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
  let tok = @preproc.make_builtin_token(Ident, lexeme_id=id)
  assert_eq(@tokens.token_lexeme_id(tok), id)
  assert_eq(@tokens.token_id(tok), 0)
  let tok_id = @preproc.make_builtin_token(Ident, id=7)
  assert_eq(@tokens.token_id(tok_id), 7)
  assert_eq(@tokens.token_lexeme_id(tok_id), 0)
  let interner = @intern.new_string_interner_with_capacity()
  let (_, intern_id) = interner.intern_view_with_id("world"[:])
  assert_true(
    @tokens.keyword_kind_from_id(0, @tokens.init_keyword_ids(interner)) is None,
  )
  let intern_tok = @preproc.make_builtin_token(Ident, id=intern_id)
  assert_eq(@tokens.token_text_with(interner, pool, intern_tok), "world")
  assert_eq(@tokens.token_text_len_with(interner, pool, intern_tok), 5)
  let lex_tok = @preproc.make_builtin_token(StrLit, lexeme_id=slice_id)
  assert_eq(@tokens.token_text_with(interner, pool, lex_tok), "bcd")
  assert_eq(@tokens.token_text_len_with(interner, pool, lex_tok), 3)
  let plain_tok : @tokens.Token = {
    kind: Plus,
    value: 0,
    loc: @source.dummy_loc(0),
    line_start: false,
    hidden: @tokens.empty_hidden,
  }
  assert_eq(@tokens.token_text_with(interner, pool, plain_tok), "+")
  assert_eq(@tokens.token_text_len_with(interner, pool, plain_tok), 1)
  let kw_tok : @tokens.Token = {
    kind: KwInt,
    value: 0,
    loc: @source.dummy_loc(0),
    line_start: false,
    hidden: @tokens.empty_hidden,
  }
  assert_eq(@tokens.token_text_with(interner, pool, kw_tok), "")
  assert_eq(@tokens.token_text_len_with(interner, pool, kw_tok), 0)
  let tilde_tok : @tokens.Token = {
    kind: Tilde,
    value: 0,
    loc: @source.dummy_loc(0),
    line_start: false,
    hidden: @tokens.empty_hidden,
  }
  assert_eq(@tokens.token_text_with(interner, pool, tilde_tok), "~")
  let bang_tok : @tokens.Token = {
    kind: Bang,
    value: 0,
    loc: @source.dummy_loc(0),
    line_start: false,
    hidden: @tokens.empty_hidden,
  }
  assert_eq(@tokens.token_text_with(interner, pool, bang_tok), "!")
  let op_pairs : Array[(@tokens.TokenKind, String)] = [
    (AmpAmp, "&&"),
    (PipePipe, "||"),
    (AmpAssign, "&="),
    (PipeAssign, "|="),
    (CaretAssign, "^="),
    (Hash, "#"),
    (HashHash, "##"),
  ]
  for pair in op_pairs {
    let (kind, text) = pair
    let tok : @tokens.Token = {
      kind,
      value: 0,
      loc: @source.dummy_loc(0),
      line_start: false,
      hidden: @tokens.empty_hidden,
    }
    assert_eq(@tokens.token_text_with(interner, pool, tok), text)
  }
}
