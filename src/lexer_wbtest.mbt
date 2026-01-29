///|
fn lex_tokens(text : String) -> (Array[Token], @diag.DiagBag, @intern.StringInterner, LexemePool) {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<test>", text)
  let interner = @intern.new_string_interner_with_capacity()
  let keyword_ids = init_keyword_ids(interner)
  let lexeme_pool = new_lexeme_pool()
  let lexer = new_lexer(file, bag, interner, keyword_ids, lexeme_pool)
  let out : Array[Token] = []
  while out.length() < 512 {
    let tok = next_token(lexer)
    out.push(tok)
    if tok.kind == Eof {
      break
    }
  }
  (out.filter(tok => tok.kind != Eof), bag, interner, lexeme_pool)
}

///|
test "lex keywords and operators" {
  let (toks, bag, interner, lexeme_pool) =
    lex_tokens("int x = 1 + 2; if (x >= 3) return x;")
  assert_true(!@diag.has_errors(bag))
  let items = toks.map(
    tok => "\{tok.kind}:\{token_text_with(interner, lexeme_pool, tok)}",
  )
  @json.inspect(items, content=[
    "KwInt:int", "Ident:x", "Assign:=", "IntLit:1", "Plus:+", "IntLit:2", "Semicolon:;",
    "KwIf:if", "LParen:(", "Ident:x", "Ge:>=", "IntLit:3", "RParen:)", "KwReturn:return",
    "Ident:x", "Semicolon:;",
  ])
}

///|
test "lex comments and literals" {
  let (toks, bag, interner, lexeme_pool) =
    lex_tokens("char c='\\n';/*c*/char* s=\"hi\\n\";//x\nc=c+1")
  assert_true(!@diag.has_errors(bag))
  let items = toks.map(
    tok => "\{tok.kind}:\{token_text_with(interner, lexeme_pool, tok)}",
  )
  @json.inspect(items, content=[
    "KwChar:char", "Ident:c", "Assign:=", "CharLit:'\\n'", "Semicolon:;", "KwChar:char",
    "Star:*", "Ident:s", "Assign:=", "StrLit:\"hi\\n\"", "Semicolon:;", "Ident:c",
    "Assign:=", "Ident:c", "Plus:+", "IntLit:1",
  ])
}

///|
test "lex numbers and preprocessor hash" {
  let (toks, bag, interner, lexeme_pool) =
    lex_tokens("#define X 0x1f\nfloat y = .5 + 2e3;")
  assert_true(!@diag.has_errors(bag))
  let items = toks.map(
    tok =>
      "\{tok.kind}:\{token_text_with(interner, lexeme_pool, tok)}:\{tok.line_start}",
  )
  @json.inspect(items, content=[
    "Hash:#:true", "Ident:define:false", "Ident:X:false", "IntLit:0x1f:false", "KwFloat:float:true",
    "Ident:y:false", "Assign:=:false", "FloatLit:.5:false", "Plus:+:false", "FloatLit:2e3:false",
    "Semicolon:;:false",
  ])
}
