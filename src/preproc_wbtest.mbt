///|
fn pp_tokens(text : String) -> (Array[Token], DiagBag) {
  let bag = new_diag_bag()
  let map = new_source_map()
  let file = add_file(map, "<test>", text)
  let pp = new_preprocessor(file, bag)
  let out = dump_tokens(pp, 512)
  (out.filter(tok => tok.kind != Eof), bag)
}

///|
test "preprocess define expansion" {
  let (toks, bag) = pp_tokens("#define X 1\nint a = X;")
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=[
    "KwInt:int", "Ident:a", "Assign:=", "IntLit:1", "Semicolon:;",
  ])
}

///|
test "preprocess ifdef and else" {
  let (toks, bag) = pp_tokens(
    "#define FOO 1\n#ifdef FOO\nint x;\n#else\nint y;\n#endif",
  )
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=["KwInt:int", "Ident:x", "Semicolon:;"])
}

///|
test "preprocess if 0 skip" {
  let (toks, bag) = pp_tokens("#if 0\nint x;\n#endif\nint y;")
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=["KwInt:int", "Ident:y", "Semicolon:;"])
}

///|
test "preprocess defined operator" {
  let (toks, bag) = pp_tokens("#define A 1\n#if defined(A)\nint x;\n#endif")
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=["KwInt:int", "Ident:x", "Semicolon:;"])
}
