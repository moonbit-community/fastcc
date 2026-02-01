///|
fn new_lex(
  text : String,
) -> (@lexer.Lexer, @diag.DiagBag, @intern.StringInterner, @tokens.LexemePool) {
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<lex>", text)
  let bag = @diag.new_diag_bag()
  let interner = @intern.new_string_interner_with_capacity()
  let keyword_ids = @tokens.init_keyword_ids(interner)
  let pool = @tokens.new_lexeme_pool()
  let lexer = @lexer.new_lexer(file, bag, interner, keyword_ids, pool)
  (lexer, bag, interner, pool)
}

///|
fn lex_tokens(
  text : String,
) -> (
  Array[@tokens.Token],
  @diag.DiagBag,
  @intern.StringInterner,
  @tokens.LexemePool,
) {
  let (lexer, bag, interner, pool) = new_lex(text)
  let out : Array[@tokens.Token] = []
  while out.length() < 256 {
    let tok = @lexer.next_token(lexer)
    if tok.kind == @tokens.TokenKind::Eof {
      break
    }
    out.push(tok)
  }
  (out, bag, interner, pool)
}

///|
test "lexer wrapper helpers" {
  assert_true(@lexer.is_digit(48))
  assert_true(!@lexer.is_digit(65))
  assert_true(@lexer.is_hex_digit(70))
  assert_true(@lexer.is_bin_digit(49))
  assert_true(@lexer.is_ident_start(95))
  assert_true(@lexer.is_ident_start(64))
  assert_true(@lexer.is_ident_continue(48))
  assert_true(@lexer.is_ws_no_newline(9))
  let view = @lexer.slice_to_view("hello", 1, 4)
  assert_eq(view.to_string(), "ell")
  let tok = @lexer.make_token(
    @tokens.TokenKind::Plus,
    @source.dummy_loc(0),
    true,
  )
  assert_eq(tok.kind, @tokens.TokenKind::Plus)
  assert_true(tok.line_start)
  let (lex, bag, _interner, _pool) = new_lex("ab\n")
  assert_eq(@lexer.peek_char(lex), Some(97))
  assert_eq(@lexer.peek_char_offset(lex, 1), Some(98))
  assert_eq(@lexer.advance(lex), Some(97))
  assert_eq(@lexer.advance(lex), Some(98))
  assert_eq(@lexer.advance(lex), Some(10))
  assert_eq(@lexer.peek_char_offset(lex, 0), None)
  assert_eq(@lexer.advance(lex), None)
  let loc = @lexer.lexer_loc(lex)
  assert_eq(loc.line, 2)
  assert_eq(loc.col, 1)
  assert_eq(loc.offset, 3)
  @lexer.add_lex_error(lex, loc, "oops")
  assert_eq(@diag.error_count(bag), 1)
  let (adv_lex, _bag, _interner2, _pool2) = new_lex("++")
  @lexer.advance_punct(adv_lex)
  assert_eq(@lexer.peek_char(adv_lex), Some(43))
}

///|
test "lexer lex ident and numbers" {
  let (lex, bag, interner, pool) = new_lex(
    "int foo 0123 0 1e-3 0b101 0x1p2 .5 12e3",
  )
  let loc0 = @lexer.lexer_loc(lex)
  let tok0 = @lexer.lex_ident(lex, loc0, true)
  assert_eq(tok0.kind, @tokens.TokenKind::KwInt)
  assert_eq(@tokens.token_text_with(interner, pool, tok0), "int")
  @lexer.skip_ws(lex)
  let loc1 = @lexer.lexer_loc(lex)
  let tok1 = @lexer.lex_ident(lex, loc1, false)
  assert_eq(tok1.kind, @tokens.TokenKind::Ident)
  assert_eq(@tokens.token_text_with(interner, pool, tok1), "foo")
  @lexer.skip_ws(lex)
  let loc2 = @lexer.lexer_loc(lex)
  let tok2 = @lexer.lex_number(lex, loc2, false, false)
  assert_eq(tok2.kind, @tokens.TokenKind::IntLit)
  assert_eq(@tokens.token_text_with(interner, pool, tok2), "0123")
  @lexer.skip_ws(lex)
  let loc3 = @lexer.lexer_loc(lex)
  let tok3 = @lexer.lex_number(lex, loc3, false, false)
  assert_eq(tok3.kind, @tokens.TokenKind::IntLit)
  assert_eq(@tokens.token_text_with(interner, pool, tok3), "0")
  @lexer.skip_ws(lex)
  let loc4 = @lexer.lexer_loc(lex)
  let tok4 = @lexer.lex_number(lex, loc4, false, false)
  assert_eq(tok4.kind, @tokens.TokenKind::FloatLit)
  assert_eq(@tokens.token_text_with(interner, pool, tok4), "1e-3")
  @lexer.skip_ws(lex)
  let loc5 = @lexer.lexer_loc(lex)
  let tok5 = @lexer.lex_number(lex, loc5, false, false)
  assert_eq(tok5.kind, @tokens.TokenKind::IntLit)
  assert_eq(@tokens.token_text_with(interner, pool, tok5), "0b101")
  @lexer.skip_ws(lex)
  let loc6 = @lexer.lexer_loc(lex)
  let tok6 = @lexer.lex_number(lex, loc6, false, false)
  assert_eq(tok6.kind, @tokens.TokenKind::FloatLit)
  assert_eq(@tokens.token_text_with(interner, pool, tok6), "0x1p2")
  @lexer.skip_ws(lex)
  let loc7 = @lexer.lexer_loc(lex)
  let tok7 = @lexer.lex_number(lex, loc7, false, true)
  assert_eq(tok7.kind, @tokens.TokenKind::FloatLit)
  assert_eq(@tokens.token_text_with(interner, pool, tok7), ".5")
  @lexer.skip_ws(lex)
  let loc8 = @lexer.lexer_loc(lex)
  let tok8 = @lexer.lex_number(lex, loc8, false, false)
  assert_eq(tok8.kind, @tokens.TokenKind::FloatLit)
  assert_eq(@tokens.token_text_with(interner, pool, tok8), "12e3")
  assert_true(!@diag.has_errors(bag))
  let (zero_lex, zero_bag, zero_interner, zero_pool) = new_lex("0")
  let zero_loc = @lexer.lexer_loc(zero_lex)
  let zero_tok = @lexer.lex_number(zero_lex, zero_loc, true, false)
  assert_eq(zero_tok.kind, @tokens.TokenKind::IntLit)
  assert_eq(@tokens.token_text_with(zero_interner, zero_pool, zero_tok), "0")
  assert_true(!@diag.has_errors(zero_bag))
}

///|
test "lexer lex strings and errors" {
  let (lex, bag, interner, pool) = new_lex("\"hi\" 'a'")
  let loc0 = @lexer.lexer_loc(lex)
  let tok0 = @lexer.lex_string_literal(lex, loc0, true, 34)
  assert_eq(tok0.kind, @tokens.TokenKind::StrLit)
  assert_eq(@tokens.token_text_with(interner, pool, tok0), "\"hi\"")
  @lexer.skip_ws(lex)
  let loc1 = @lexer.lexer_loc(lex)
  let tok1 = @lexer.lex_string_literal(lex, loc1, false, 39)
  assert_eq(tok1.kind, @tokens.TokenKind::CharLit)
  assert_eq(@tokens.token_text_with(interner, pool, tok1), "'a'")
  assert_true(!@diag.has_errors(bag))
  let (bad_lex, bad_bag, _bad_interner, _bad_pool) = new_lex("\"\\")
  let bad_loc = @lexer.lexer_loc(bad_lex)
  @lexer.skip_string_literal(bad_lex, bad_loc, 34)
  assert_eq(@diag.error_count(bad_bag), 1)
  let (eof_lex, eof_bag, _eof_interner, _eof_pool) = new_lex("\"")
  let eof_loc = @lexer.lexer_loc(eof_lex)
  @lexer.skip_string_literal(eof_lex, eof_loc, 34)
  assert_eq(@diag.error_count(eof_bag), 1)
  let (newline_lex, newline_bag, _newline_interner, _newline_pool) = new_lex(
    "\"line\n",
  )
  let newline_loc = @lexer.lexer_loc(newline_lex)
  @lexer.skip_string_literal(newline_lex, newline_loc, 34)
  assert_eq(@diag.error_count(newline_bag), 1)
  let (cont_lex, cont_bag, _cont_interner, _cont_pool) = new_lex("\"a\\\n b\"")
  let cont_loc = @lexer.lexer_loc(cont_lex)
  @lexer.skip_string_literal(cont_lex, cont_loc, 34)
  assert_true(!@diag.has_errors(cont_bag))
}

///|
test "lexer comments and punct errors" {
  let (line_lex, line_bag, _line_interner, _line_pool) = new_lex("// hi\nX")
  let _ = @lexer.advance(line_lex)
  let _ = @lexer.advance(line_lex)
  @lexer.skip_line_comment(line_lex)
  let line_loc = @lexer.lexer_loc(line_lex)
  assert_eq(@lexer.peek_char(line_lex), Some(88))
  assert_eq(line_loc.line, 2)
  assert_eq(line_loc.col, 1)
  assert_true(!@diag.has_errors(line_bag))
  let (line_eof, line_eof_bag, _line_eof_interner, _line_eof_pool) = new_lex(
    "//hi",
  )
  let _ = @lexer.advance(line_eof)
  let _ = @lexer.advance(line_eof)
  @lexer.skip_line_comment(line_eof)
  assert_true(!@diag.has_errors(line_eof_bag))
  let (line_empty, line_empty_bag, _line_empty_interner, _line_empty_pool) = new_lex(
    "//",
  )
  let _ = @lexer.advance(line_empty)
  let _ = @lexer.advance(line_empty)
  @lexer.skip_line_comment(line_empty)
  assert_true(!@diag.has_errors(line_empty_bag))
  let (block_lex, block_bag, _block_interner, _block_pool) = new_lex(
    "/* ok */Y",
  )
  let start_loc = @lexer.lexer_loc(block_lex)
  let _ = @lexer.advance(block_lex)
  let _ = @lexer.advance(block_lex)
  @lexer.skip_block_comment(block_lex, start_loc)
  assert_eq(@lexer.peek_char(block_lex), Some(89))
  assert_true(!@diag.has_errors(block_bag))
  let (bad_block, bad_bag, _bad_interner2, _bad_pool2) = new_lex("/* oops")
  let bad_start = @lexer.lexer_loc(bad_block)
  let _ = @lexer.advance(bad_block)
  let _ = @lexer.advance(bad_block)
  @lexer.skip_block_comment(bad_block, bad_start)
  assert_eq(@diag.error_count(bad_bag), 1)
  let (bad_empty_block, bad_empty_bag, _bad_empty_interner, _bad_empty_pool) = new_lex(
    "/*",
  )
  let bad_empty_start = @lexer.lexer_loc(bad_empty_block)
  let _ = @lexer.advance(bad_empty_block)
  let _ = @lexer.advance(bad_empty_block)
  @lexer.skip_block_comment(bad_empty_block, bad_empty_start)
  assert_eq(@diag.error_count(bad_empty_bag), 1)
  let (ws_lex, ws_bag, _ws_interner, _ws_pool) = new_lex(" \\\nX")
  @lexer.skip_ws(ws_lex)
  assert_eq(@lexer.peek_char(ws_lex), Some(88))
  let ws_loc = @lexer.lexer_loc(ws_lex)
  assert_eq(ws_loc.line, 2)
  assert_eq(ws_loc.col, 1)
  assert_true(!@diag.has_errors(ws_bag))
  let (bad_punct, bad_punct_bag, bad_interner, bad_pool) = new_lex("\\")
  let bad_loc = @lexer.lexer_loc(bad_punct)
  let bad_tok = @lexer.lex_punct(bad_punct, bad_loc, true)
  assert_eq(bad_tok.kind, @tokens.TokenKind::Invalid)
  assert_eq(@tokens.token_text_with(bad_interner, bad_pool, bad_tok), "\\")
  assert_true(@diag.has_errors(bad_punct_bag))
  let (eof_punct, eof_punct_bag, _eof_interner2, _eof_pool2) = new_lex("")
  let eof_loc = @lexer.lexer_loc(eof_punct)
  let eof_tok = @lexer.lex_punct(eof_punct, eof_loc, true)
  assert_eq(eof_tok.kind, @tokens.TokenKind::Eof)
  assert_true(!@diag.has_errors(eof_punct_bag))
  let (nl_punct, nl_bag, nl_interner, nl_pool) = new_lex("\n")
  let nl_loc = @lexer.lexer_loc(nl_punct)
  let nl_tok = @lexer.lex_punct(nl_punct, nl_loc, true)
  assert_eq(nl_tok.kind, @tokens.TokenKind::Invalid)
  assert_eq(@tokens.token_text_with(nl_interner, nl_pool, nl_tok), "\n")
  assert_true(@diag.has_errors(nl_bag))
  let (dec_lex, dec_bag, _dec_interner, _dec_pool) = new_lex("--")
  let dec_loc = @lexer.lexer_loc(dec_lex)
  let dec_tok = @lexer.lex_punct(dec_lex, dec_loc, true)
  assert_eq(dec_tok.kind, @tokens.TokenKind::MinusMinus)
  assert_true(!@diag.has_errors(dec_bag))
  let (star_lex, star_bag, _star_interner, _star_pool) = new_lex("*=")
  let star_loc = @lexer.lexer_loc(star_lex)
  let star_tok = @lexer.lex_punct(star_lex, star_loc, true)
  assert_eq(star_tok.kind, @tokens.TokenKind::StarAssign)
  assert_true(!@diag.has_errors(star_bag))
  let (percent_lex, percent_bag, _percent_interner, _percent_pool) = new_lex(
    "%=",
  )
  let percent_loc = @lexer.lexer_loc(percent_lex)
  let percent_tok = @lexer.lex_punct(percent_lex, percent_loc, true)
  assert_eq(percent_tok.kind, @tokens.TokenKind::PercentAssign)
  assert_true(!@diag.has_errors(percent_bag))
  let (shr_lex, shr_bag, _shr_interner, _shr_pool) = new_lex(">>=")
  let shr_loc = @lexer.lexer_loc(shr_lex)
  let shr_tok = @lexer.lex_punct(shr_lex, shr_loc, true)
  assert_eq(shr_tok.kind, @tokens.TokenKind::ShiftRightAssign)
  assert_true(!@diag.has_errors(shr_bag))
  let (caret_lex, caret_bag, _caret_interner, _caret_pool) = new_lex("^=")
  let caret_loc = @lexer.lexer_loc(caret_lex)
  let caret_tok = @lexer.lex_punct(caret_lex, caret_loc, true)
  assert_eq(caret_tok.kind, @tokens.TokenKind::CaretAssign)
  assert_true(!@diag.has_errors(caret_bag))
}

///|
test "lexer next_token smoke" {
  let (toks, bag, interner, pool) = lex_tokens(
    "int x=1+2; if (x>=3) return x; #define A 0x1f ^=",
  )
  assert_true(!@diag.has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{@tokens.token_text_with(interner, pool, tok)}")
  json_inspect(items, content=[
    "KwInt:int", "Ident:x", "Assign:=", "IntLit:1", "Plus:+", "IntLit:2", "Semicolon:;",
    "KwIf:if", "LParen:(", "Ident:x", "Ge:>=", "IntLit:3", "RParen:)", "KwReturn:return",
    "Ident:x", "Semicolon:;", "Hash:#", "Ident:define", "Ident:A", "IntLit:0x1f",
    "CaretAssign:^=",
  ])
}
