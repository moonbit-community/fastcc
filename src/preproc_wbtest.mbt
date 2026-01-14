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
fn pp_tokens_with_paths(
  text : String,
  paths : Array[String],
) -> (Array[Token], DiagBag) {
  let bag = new_diag_bag()
  let map = new_source_map()
  let file = add_file(map, "<test>", text)
  let pp = new_preprocessor(file, bag)
  for path in paths {
    add_include_path(pp, path)
  }
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
test "preprocess include with macro" {
  let path = "/tmp/tinyccmbt_include_macro.h"
  @fs.write_string_to_file(path, "int inc2;") catch {
    err => fail("write include failed: \{err.to_string()}")
  }
  let (toks, bag) = pp_tokens("#define HDR \"\{path}\"\n#include HDR")
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=["KwInt:int", "Ident:inc2", "Semicolon:;"])
}

///|
test "preprocess include search path" {
  let dir = "/tmp/tinyccmbt_include_dir"
  if !@fs.path_exists(dir) {
    @fs.create_dir(dir) catch {
      err => fail("create include dir failed: \{err.to_string()}")
    }
  }
  let path = dir + "/inc.h"
  @fs.write_string_to_file(path, "int inc3;") catch {
    err => fail("write include failed: \{err.to_string()}")
  }
  let (toks, bag) = pp_tokens_with_paths("#include <inc.h>", [dir])
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=["KwInt:int", "Ident:inc3", "Semicolon:;"])
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

///|
test "preprocess if macro expression" {
  let (toks, bag) = pp_tokens("#define A 1 + 2\n#if A == 3\nint ok;\n#endif")
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=["KwInt:int", "Ident:ok", "Semicolon:;"])
}

///|
test "preprocess whitespace before paren" {
  let (toks, bag) = pp_tokens("#define F(x) x\nint y = F (1);")
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=[
    "KwInt:int", "Ident:y", "Assign:=", "Ident:F", "LParen:(", "IntLit:1", "RParen:)",
    "Semicolon:;",
  ])
}

///|
test "preprocess recursion guard" {
  let (toks, bag) = pp_tokens("#define A A\nint z = A;")
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=[
    "KwInt:int", "Ident:z", "Assign:=", "Ident:A", "Semicolon:;",
  ])
}

///|
test "preprocess builtin line and file" {
  let (toks, bag) = pp_tokens("int x = __LINE__;\nconst char *f = __FILE__;")
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=[
    "KwInt:int", "Ident:x", "Assign:=", "IntLit:1", "Semicolon:;", "KwConst:const",
    "KwChar:char", "Star:*", "Ident:f", "Assign:=", "StrLit:\"<test>\"", "Semicolon:;",
  ])
}

///|
test "preprocess line directive" {
  let (toks, bag) = pp_tokens(
    "#line 200 \"foo.c\"\nint x = __LINE__;\nconst char *f = __FILE__;",
  )
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=[
    "KwInt:int", "Ident:x", "Assign:=", "IntLit:200", "Semicolon:;", "KwConst:const",
    "KwChar:char", "Star:*", "Ident:f", "Assign:=", "StrLit:\"foo.c\"", "Semicolon:;",
  ])
}

///|
test "preprocess date and time" {
  let (toks, bag) = pp_tokens(
    "const char *d = __DATE__; const char *t = __TIME__;",
  )
  assert_true(!has_errors(bag))
  assert_true(toks.length() >= 13)
  assert_true(toks[5].kind == StrLit)
  assert_true(toks[12].kind == StrLit)
  assert_true(toks[12].lexeme.contains(":"))
}
