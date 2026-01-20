///|
fn pp_tokens(text : String) -> (Array[Token], DiagBag) {
  let bag = new_diag_bag()
  let map = new_source_map()
  let file = add_file(map, "<test>", text)
  let pp = new_preprocessor(map, file, bag)
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
  let pp = new_preprocessor(map, file, bag)
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
test "preprocess empty function-like macro expansion" {
  let (toks, bag) = pp_tokens("#define DEF(x)\nDEF(1)\nint ok;")
  if has_errors(bag) {
    let messages = bag.diags.map(d => d.message)
    @json.inspect(messages)
  }
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=["KwInt:int", "Ident:ok", "Semicolon:;"])
}

///|
test "preprocess quickjs opcode header with empty DEF" {
  let text = "#define DEF(id, size, n_pop, n_push, f)\n#include \"quickjs-opcode.h\"\nint ok;"
  let (toks, bag) = pp_tokens_with_paths(text, ["refs/quickjs"])
  if has_errors(bag) {
    let messages = bag.diags.map(d => d.message)
    @json.inspect(messages)
  }
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=["KwInt:int", "Ident:ok", "Semicolon:;"])
}

///|
test "preprocess _Float16 builtin macro" {
  let (toks, bag) = pp_tokens("_Float16 x;")
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=[
    "KwShort:short", "KwUnsigned:unsigned", "KwInt:int", "Ident:x", "Semicolon:;",
  ])
}

///|
test "preprocess _Float16 prototype tokens" {
  let (toks, bag) = pp_tokens("extern _Float16 foo(_Float16);")
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=[
    "KwExtern:extern",
    "KwShort:short",
    "KwUnsigned:unsigned",
    "KwInt:int",
    "Ident:foo",
    "LParen:(",
    "KwShort:short",
    "KwUnsigned:unsigned",
    "KwInt:int",
    "RParen:)",
    "Semicolon:;",
  ])
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
test "preprocess stringize keeps adjacency" {
  let (toks, bag) = pp_tokens("#define STR(x) #x\nchar* s = STR(->>);")
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=[
    "KwChar:char", "Star:*", "Ident:s", "Assign:=", "StrLit:\"->>\"", "Semicolon:;",
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
test "preprocess if char literal" {
  let (toks, bag) = pp_tokens("#if 'A' == '\\101'\nint ok;\n#endif")
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
test "preprocess if defined and numeric macro" {
  let text =
    "#define FOO 1\n#define BAR 0\n#if defined(FOO) && BAR\nint bad;\n#endif\nint ok;\n"
  let (toks, bag) = pp_tokens(text)
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=["KwInt:int", "Ident:ok", "Semicolon:;"])
}

///|
test "preprocess gcc style version check" {
  let text =
    "#if defined(__GNUC__) && (__GNUC__ == 3 && __GNUC_MINOR__ >= 5 || __GNUC__ > 3)\nint ok;\n#endif\nint main(){return 0;}\n"
  let bag = new_diag_bag()
  let map = new_source_map()
  let file = add_file(map, "<test>", text)
  let pp = new_preprocessor(map, file, bag)
  ignore(next_input_token(pp)) // consume '#'
  let directive_tokens = read_directive_tokens(pp)
  let args = slice_tokens(directive_tokens, 1)
  let expanded = expand_if_tokens(pp, args)
  let gcc_id = macro_id_from_name(pp, "__GNUC__")
  let has_gcc = gcc_id != 0 && has_macro(pp, gcc_id)
  let cond = eval_if_expr(pp, expanded, directive_tokens[0].loc)
  let simple_file = add_file(map, "<simple>", "#if 1 && (0 && 0 || 1)\n")
  let simple_pp = new_preprocessor(map, simple_file, new_diag_bag())
  ignore(next_input_token(simple_pp))
  let simple_toks = read_directive_tokens(simple_pp)
  let simple_cond = eval_if_expr(simple_pp, slice_tokens(simple_toks, 1), simple_toks[0].loc)
  if has_errors(bag) {
    for d in bag.diags {
      println("\{d.loc.file_id}:\{d.loc.line}:\{d.loc.col}: \{d.message}")
    }
    println(expanded.map(tok => "\{tok.kind}:\{tok.lexeme}").join(" "))
  }
  assert_true(has_gcc)
  assert_true(cond)
  assert_true(simple_cond)
  assert_true(!has_errors(bag))
}

///|
test "preprocess whitespace before paren" {
  let (toks, bag) = pp_tokens("#define F(x) x\nint y = F (1);")
  assert_true(!has_errors(bag))
  let items = toks.map(tok => "\{tok.kind}:\{tok.lexeme}")
  @json.inspect(items, content=[
    "KwInt:int", "Ident:y", "Assign:=", "IntLit:1", "Semicolon:;",
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
