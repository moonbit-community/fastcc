///|
fn lex_tokens(text : String) -> (Array[@tokens.Token], @diag.DiagBag, @intern.StringInterner, @tokens.LexemePool) {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<test>", text)
  let interner = @intern.new_string_interner_with_capacity()
  let keyword_ids = @tokens.init_keyword_ids(interner)
  let lexeme_pool = @tokens.new_lexeme_pool()
  let lexer = new_lexer(file, bag, interner, keyword_ids, lexeme_pool)
  let out : Array[@tokens.Token] = []
  while out.length() < 512 {
    let tok = next_token(lexer)
    out.push(tok)
    if tok.kind == @tokens.TokenKind::Eof {
      break
    }
  }
  (out.filter(tok => tok.kind != @tokens.TokenKind::Eof), bag, interner, lexeme_pool)
}

///|
test "lex keywords and operators" {
  let (toks, bag, interner, lexeme_pool) =
    lex_tokens("int x = 1 + 2; if (x >= 3) return x;")
  assert_true(!@diag.has_errors(bag))
  let items = toks.map(
    tok => "\{tok.kind}:\{@tokens.token_text_with(interner, lexeme_pool, tok)}",
  )
  @json.inspect(items, content=[
    "@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:x", "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::IntLit:1", "@tokens.TokenKind::Plus:+", "@tokens.TokenKind::IntLit:2", "@tokens.TokenKind::Semicolon:;",
    "@tokens.TokenKind::KwIf:if", "@tokens.TokenKind::LParen:(", "@tokens.TokenKind::Ident:x", "@tokens.TokenKind::Ge:>=", "@tokens.TokenKind::IntLit:3", "@tokens.TokenKind::RParen:)", "@tokens.TokenKind::KwReturn:return",
    "@tokens.TokenKind::Ident:x", "@tokens.TokenKind::Semicolon:;",
  ])
}

///|
test "lex comments and literals" {
  let (toks, bag, interner, lexeme_pool) =
    lex_tokens("char c='\\n';/*c*/char* s=\"hi\\n\";//x\nc=c+1")
  assert_true(!@diag.has_errors(bag))
  let items = toks.map(
    tok => "\{tok.kind}:\{@tokens.token_text_with(interner, lexeme_pool, tok)}",
  )
  @json.inspect(items, content=[
    "@tokens.TokenKind::KwChar:char", "@tokens.TokenKind::Ident:c", "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::CharLit:'\\n'", "@tokens.TokenKind::Semicolon:;", "@tokens.TokenKind::KwChar:char",
    "@tokens.TokenKind::Star:*", "@tokens.TokenKind::Ident:s", "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::StrLit:\"hi\\n\"", "@tokens.TokenKind::Semicolon:;", "@tokens.TokenKind::Ident:c",
    "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::Ident:c", "@tokens.TokenKind::Plus:+", "@tokens.TokenKind::IntLit:1",
  ])
}

///|
test "lex numbers and preprocessor hash" {
  let (toks, bag, interner, lexeme_pool) =
    lex_tokens("#define X 0x1f\nfloat y = .5 + 2e3;")
  assert_true(!@diag.has_errors(bag))
  let items = toks.map(
    tok =>
      "\{tok.kind}:\{@tokens.token_text_with(interner, lexeme_pool, tok)}:\{tok.line_start}",
  )
  @json.inspect(items, content=[
    "@tokens.TokenKind::Hash:#:true", "@tokens.TokenKind::Ident:define:false", "@tokens.TokenKind::Ident:X:false", "@tokens.TokenKind::IntLit:0x1f:false", "@tokens.TokenKind::KwFloat:float:true",
    "@tokens.TokenKind::Ident:y:false", "@tokens.TokenKind::Assign:=:false", "@tokens.TokenKind::FloatLit:.5:false", "@tokens.TokenKind::Plus:+:false", "@tokens.TokenKind::FloatLit:2e3:false",
    "@tokens.TokenKind::Semicolon:;:false",
  ])
}
