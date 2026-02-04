///|
fn new_pp() -> (@preproc.Preprocessor, @diag.DiagBag) {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<pp-expr>", "")
  let pp = @preproc.new_preprocessor(map, file, bag, host=@default_host.new())
  (pp, bag)
}

///|
fn tok_kind(kind : @tokens.TokenKind) -> @tokens.Token {
  @preproc.make_builtin_token(kind)
}

///|
fn tok_int(pp : @preproc.Preprocessor, text : String) -> @tokens.Token {
  let lexeme_id = @tokens.lexeme_pool_intern(pp.lexeme_pool, text)
  @preproc.make_builtin_token(IntLit, lexeme_id~)
}

///|
fn tok_char(pp : @preproc.Preprocessor, text : String) -> @tokens.Token {
  let lexeme_id = @tokens.lexeme_pool_intern(pp.lexeme_pool, text)
  @preproc.make_builtin_token(CharLit, lexeme_id~)
}

///|
fn tok_ident(pp : @preproc.Preprocessor, name : String) -> @tokens.Token {
  let (_, id) = pp.interner.intern_view_with_id(name[:])
  @preproc.make_builtin_token(Ident, id~)
}

///|
test "preproc if expr unsigned ops" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [
    tok_int(pp, "6U"),
    tok_kind(Slash),
    tok_int(pp, "3U"),
    tok_kind(Eq),
    tok_int(pp, "2"),
    tok_kind(AmpAmp),
    tok_int(pp, "7U"),
    tok_kind(Percent),
    tok_int(pp, "3U"),
    tok_kind(Eq),
    tok_int(pp, "1"),
    tok_kind(AmpAmp),
    tok_int(pp, "8U"),
    tok_kind(ShiftRight),
    tok_int(pp, "2"),
    tok_kind(Eq),
    tok_int(pp, "2"),
    tok_kind(AmpAmp),
    tok_int(pp, "3U"),
    tok_kind(Lt),
    tok_int(pp, "4U"),
    tok_kind(AmpAmp),
    tok_int(pp, "4U"),
    tok_kind(Le),
    tok_int(pp, "4U"),
    tok_kind(AmpAmp),
    tok_int(pp, "5U"),
    tok_kind(Gt),
    tok_int(pp, "4U"),
    tok_kind(AmpAmp),
    tok_int(pp, "5U"),
    tok_kind(Ge),
    tok_int(pp, "5U"),
    tok_kind(AmpAmp),
    tok_int(pp, "5"),
    tok_kind(Minus),
    tok_int(pp, "3"),
    tok_kind(Eq),
    tok_int(pp, "2"),
  ]
  let ok = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(ok)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc if expr char escapes" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [
    tok_char(pp, "'\\a'"),
    tok_kind(Eq),
    tok_int(pp, "7"),
    tok_kind(AmpAmp),
    tok_char(pp, "'\\b'"),
    tok_kind(Eq),
    tok_int(pp, "8"),
    tok_kind(AmpAmp),
    tok_char(pp, "'\\f'"),
    tok_kind(Eq),
    tok_int(pp, "12"),
    tok_kind(AmpAmp),
    tok_char(pp, "'\\r'"),
    tok_kind(Eq),
    tok_int(pp, "13"),
    tok_kind(AmpAmp),
    tok_char(pp, "'\\v'"),
    tok_kind(Eq),
    tok_int(pp, "11"),
    tok_kind(AmpAmp),
    tok_char(pp, "'\\q'"),
    tok_kind(Eq),
    tok_int(pp, "113"),
    tok_kind(AmpAmp),
    tok_char(pp, "'\\\\'"),
    tok_kind(Eq),
    tok_int(pp, "92"),
    tok_kind(AmpAmp),
    tok_char(pp, "'\\xAf'"),
    tok_kind(Eq),
    tok_int(pp, "175"),
  ]
  let ok = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(ok)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc if expr macro int value" {
  let (pp, bag) = new_pp()
  @preproc.define_int_macro(pp, "MACRO_INT", 7)
  let tokens : Array[@tokens.Token] = [tok_ident(pp, "MACRO_INT")]
  let ok = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(ok)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc if expr macro non-int" {
  let (pp, bag) = new_pp()
  @preproc.define_func_macro_zero(pp, "MACRO_FN")
  let tokens : Array[@tokens.Token] = [tok_ident(pp, "MACRO_FN")]
  let ok = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(!ok)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc if expr macro invalid id" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [@preproc.make_builtin_token(Ident)]
  let ok = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(!ok)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc if expr defined missing ident" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [tok_ident(pp, "defined")]
  let ok = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(!ok)
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc if expr defined missing rparen" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [
    tok_ident(pp, "defined"),
    tok_kind(LParen),
    tok_ident(pp, "FOO"),
  ]
  let _ = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc if expr defined empty" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [
    tok_ident(pp, "defined"),
    tok_kind(LParen),
    tok_kind(RParen),
  ]
  let _ = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc if expr rparen token" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [tok_kind(RParen)]
  let ok = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(!ok)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc if expr skip paren expr" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [
    tok_ident(pp, "FOO"),
    tok_kind(LParen),
    tok_int(pp, "1"),
  ]
  let _ = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc if expr unexpected token" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [tok_kind(Comma)]
  let _ = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc if expr missing operand" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [tok_kind(Plus)]
  let _ = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc if expr paren resync" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [
    tok_kind(LParen),
    tok_int(pp, "1"),
    tok_kind(Plus),
    tok_int(pp, "2"),
  ]
  let ok = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(ok)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc if expr paren resync trailing rparen" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [
    tok_kind(LParen),
    tok_int(pp, "1"),
    tok_kind(Comma),
    tok_kind(RParen),
  ]
  let ok = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(ok)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc if expr skip paren nesting" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [
    tok_ident(pp, "FOO"),
    tok_kind(LParen),
    tok_kind(LParen),
    tok_int(pp, "1"),
    tok_kind(RParen),
    tok_kind(RParen),
  ]
  let ok = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(!ok)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc if expr subtraction" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [
    tok_int(pp, "5"),
    tok_kind(Minus),
    tok_int(pp, "3"),
  ]
  let ok = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(ok)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc if expr division and modulo" {
  let (pp, bag) = new_pp()
  let tokens : Array[@tokens.Token] = [
    tok_int(pp, "6U"),
    tok_kind(Slash),
    tok_int(pp, "3U"),
    tok_kind(AmpAmp),
    tok_int(pp, "7U"),
    tok_kind(Percent),
    tok_int(pp, "3U"),
  ]
  let ok = @preproc.eval_if_expr(pp, tokens, @source.dummy_loc(0))
  assert_true(ok)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc if expr break on rparen" {
  let (pp_and, bag_and) = new_pp()
  let tokens_and : Array[@tokens.Token] = [
    tok_int(pp_and, "1"),
    tok_kind(Amp),
    tok_kind(RParen),
  ]
  let ok_and = @preproc.eval_if_expr(pp_and, tokens_and, @source.dummy_loc(0))
  assert_true(ok_and)
  assert_true(!@diag.has_errors(bag_and))
  let (pp_xor, bag_xor) = new_pp()
  let tokens_xor : Array[@tokens.Token] = [
    tok_int(pp_xor, "1"),
    tok_kind(Caret),
    tok_kind(RParen),
  ]
  let ok_xor = @preproc.eval_if_expr(pp_xor, tokens_xor, @source.dummy_loc(0))
  assert_true(ok_xor)
  assert_true(!@diag.has_errors(bag_xor))
  let (pp_or, bag_or) = new_pp()
  let tokens_or : Array[@tokens.Token] = [
    tok_int(pp_or, "1"),
    tok_kind(Pipe),
    tok_kind(RParen),
  ]
  let ok_or = @preproc.eval_if_expr(pp_or, tokens_or, @source.dummy_loc(0))
  assert_true(ok_or)
  assert_true(!@diag.has_errors(bag_or))
}

///|
test "preproc char literal errors" {
  let (pp_short, bag_short) = new_pp()
  let short_tok = tok_char(pp_short, "''")
  let _ = @preproc.parse_pp_char_literal(pp_short, short_tok)
  assert_true(@diag.has_errors(bag_short))
  let (pp_multi, bag_multi) = new_pp()
  let multi_tok = tok_char(pp_multi, "'\\12x'")
  let _ = @preproc.parse_pp_char_literal(pp_multi, multi_tok)
  assert_true(@diag.has_errors(bag_multi))
  let (pp_escape, bag_escape) = new_pp()
  let _ = @preproc.decode_pp_escape_value(
    pp_escape,
    "\\",
    1,
    @source.dummy_loc(0),
  )
  assert_true(@diag.has_errors(bag_escape))
}
