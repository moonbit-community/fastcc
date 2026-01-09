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

///|
test "preprocess include" {
  let path = "/tmp/tinyccmbt_include_test.h"
  @fs.write_string_to_file(path, "int inc;") catch {
    err => fail("write include failed: \{err.to_string()}")
  }
  let (toks, bag) = pp_tokens("#include \"\{path}\"")
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=["KwInt:int", "Ident:inc", "Semicolon:;"])
}

///|
test "preprocess function-like macro" {
  let (toks, bag) = pp_tokens("#define ADD(a,b) a + b\nint x = ADD(1, 2);")
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=[
    "KwInt:int", "Ident:x", "Assign:=", "IntLit:1", "Plus:+", "IntLit:2", "Semicolon:;",
  ])
}

///|
test "preprocess stringize and paste" {
  let (toks, bag) = pp_tokens(
    "#define STR(x) #x\n#define CAT(a,b) a ## b\nchar* s = STR(hi);\nint xy = CAT(x, y);",
  )
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=[
    "KwChar:char", "Star:*", "Ident:s", "Assign:=", "StrLit:\"hi\"", "Semicolon:;",
    "KwInt:int", "Ident:xy", "Assign:=", "Ident:xy", "Semicolon:;",
  ])
}

///|
test "preprocess if expression" {
  let (toks, bag) = pp_tokens(
    "#define A 4\n#if A + 2 * 3 == 10\nint ok;\n#endif",
  )
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=["KwInt:int", "Ident:ok", "Semicolon:;"])
}
