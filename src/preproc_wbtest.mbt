///|
fn pp_tokens(text : String) ->
  (Array[@tokens.Token], @diag.DiagBag, @intern.StringInterner, @tokens.LexemePool) {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<test>", text)
  let pp = new_preprocessor(map, file, bag)
  let out = dump_tokens(pp, 512)
  (out.filter(tok => tok.kind != @tokens.TokenKind::Eof), bag, pp.interner, pp.lexeme_pool)
}

///|
fn pp_tokens_with_paths(
  text : String,
  paths : Array[String],
) -> (Array[@tokens.Token], @diag.DiagBag, @intern.StringInterner, @tokens.LexemePool) {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<test>", text)
  let pp = new_preprocessor(map, file, bag)
  for path in paths {
    add_include_path(pp, path)
  }
  let out = dump_tokens(pp, 512)
  (out.filter(tok => tok.kind != @tokens.TokenKind::Eof), bag, pp.interner, pp.lexeme_pool)
}

///|
fn pp_items(
  toks : Array[@tokens.Token],
  interner : @intern.StringInterner,
  lexeme_pool : @tokens.LexemePool,
) -> Array[String] {
  toks.map(
    tok => "\{tok.kind}:\{@tokens.token_text_with(interner, lexeme_pool, tok)}",
  )
}

///|
test "preprocess define expansion" {
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens("#define X 1\nint a = X;")
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=[
    "@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:a", "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::IntLit:1", "@tokens.TokenKind::Semicolon:;",
  ])
}

///|
test "preprocess ifdef and else" {
  let (toks, bag, interner, lexeme_pool) = pp_tokens(
    "#define FOO 1\n#ifdef FOO\nint x;\n#else\nint y;\n#endif",
  )
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=["@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:x", "@tokens.TokenKind::Semicolon:;"])
}

///|
test "preprocess if 0 skip" {
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens("#if 0\nint x;\n#endif\nint y;")
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=["@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:y", "@tokens.TokenKind::Semicolon:;"])
}

///|
test "preprocess defined operator" {
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens("#define A 1\n#if defined(A)\nint x;\n#endif")
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=["@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:x", "@tokens.TokenKind::Semicolon:;"])
}

///|
test "preprocess include" {
  let path = "/tmp/tinyccmbt_include_test.h"
  @fs.write_string_to_file(path, "int inc;") catch {
    err => fail("write include failed: \{err.to_string()}")
  }
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens("#include \"\{path}\"")
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=["@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:inc", "@tokens.TokenKind::Semicolon:;"])
}

///|
test "preprocess include with macro" {
  let path = "/tmp/tinyccmbt_include_macro.h"
  @fs.write_string_to_file(path, "int inc2;") catch {
    err => fail("write include failed: \{err.to_string()}")
  }
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens("#define HDR \"\{path}\"\n#include HDR")
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=["@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:inc2", "@tokens.TokenKind::Semicolon:;"])
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
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens_with_paths("#include <inc.h>", [dir])
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=["@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:inc3", "@tokens.TokenKind::Semicolon:;"])
}

///|
test "preprocess empty function-like macro expansion" {
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens("#define DEF(x)\nDEF(1)\nint ok;")
  if @diag.has_errors(bag) {
    let messages = bag.diags.map(d => d.message)
    @json.inspect(messages)
  }
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=["@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:ok", "@tokens.TokenKind::Semicolon:;"])
}

///|
test "preprocess quickjs opcode header with empty DEF" {
  let text = "#define DEF(id, size, n_pop, n_push, f)\n#include \"quickjs-opcode.h\"\nint ok;"
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens_with_paths(text, ["refs/quickjs"])
  if @diag.has_errors(bag) {
    let messages = bag.diags.map(d => d.message)
    @json.inspect(messages)
  }
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=["@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:ok", "@tokens.TokenKind::Semicolon:;"])
}

///|
test "preprocess _Float16 builtin macro" {
  let (toks, bag, interner, lexeme_pool) = pp_tokens("_Float16 x;")
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=[
    "@tokens.TokenKind::KwShort:short", "@tokens.TokenKind::KwUnsigned:unsigned", "@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:x", "@tokens.TokenKind::Semicolon:;",
  ])
}

///|
test "preprocess _Float16 prototype tokens" {
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens("extern _Float16 foo(_Float16);")
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=[
    "@tokens.TokenKind::KwExtern:extern",
    "@tokens.TokenKind::KwShort:short",
    "@tokens.TokenKind::KwUnsigned:unsigned",
    "@tokens.TokenKind::KwInt:int",
    "@tokens.TokenKind::Ident:foo",
    "@tokens.TokenKind::LParen:(",
    "@tokens.TokenKind::KwShort:short",
    "@tokens.TokenKind::KwUnsigned:unsigned",
    "@tokens.TokenKind::KwInt:int",
    "@tokens.TokenKind::RParen:)",
    "@tokens.TokenKind::Semicolon:;",
  ])
}

///|
test "preprocess function-like macro" {
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens("#define ADD(a,b) a + b\nint x = ADD(1, 2);")
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=[
    "@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:x", "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::IntLit:1", "@tokens.TokenKind::Plus:+", "@tokens.TokenKind::IntLit:2", "@tokens.TokenKind::Semicolon:;",
  ])
}

///|
test "preprocess stringize and paste" {
  let (toks, bag, interner, lexeme_pool) = pp_tokens(
    "#define STR(x) #x\n#define CAT(a,b) a ## b\nchar* s = STR(hi);\nint xy = CAT(x, y);",
  )
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=[
    "@tokens.TokenKind::KwChar:char", "@tokens.TokenKind::Star:*", "@tokens.TokenKind::Ident:s", "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::StrLit:\"hi\"", "@tokens.TokenKind::Semicolon:;",
    "@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:xy", "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::Ident:xy", "@tokens.TokenKind::Semicolon:;",
  ])
}

///|
test "preprocess stringize keeps adjacency" {
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens("#define STR(x) #x\nchar* s = STR(->>);")
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=[
    "@tokens.TokenKind::KwChar:char", "@tokens.TokenKind::Star:*", "@tokens.TokenKind::Ident:s", "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::StrLit:\"->>\"", "@tokens.TokenKind::Semicolon:;",
  ])
}

///|
test "preprocess if expression" {
  let (toks, bag, interner, lexeme_pool) = pp_tokens(
    "#define A 4\n#if A + 2 * 3 == 10\nint ok;\n#endif",
  )
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=["@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:ok", "@tokens.TokenKind::Semicolon:;"])
}

///|
test "preprocess if char literal" {
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens("#if 'A' == '\\101'\nint ok;\n#endif")
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=["@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:ok", "@tokens.TokenKind::Semicolon:;"])
}

///|
test "preprocess if macro expression" {
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens("#define A 1 + 2\n#if A == 3\nint ok;\n#endif")
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=["@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:ok", "@tokens.TokenKind::Semicolon:;"])
}

///|
test "preprocess if defined and numeric macro" {
  let text =
    "#define FOO 1\n#define BAR 0\n#if defined(FOO) && BAR\nint bad;\n#endif\nint ok;\n"
  let (toks, bag, interner, lexeme_pool) = pp_tokens(text)
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=["@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:ok", "@tokens.TokenKind::Semicolon:;"])
}

///|
test "preprocess gcc style version check" {
  let text =
    "#if defined(__GNUC__) && (__GNUC__ == 3 && __GNUC_MINOR__ >= 5 || __GNUC__ > 3)\nint ok;\n#endif\nint main(){return 0;}\n"
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<test>", text)
  let pp = new_preprocessor(map, file, bag)
  ignore(next_input_token(pp)) // consume '#'
  let directive_tokens = read_directive_tokens(pp)
  let args = slice_tokens(directive_tokens, 1)
  let expanded = expand_if_tokens(pp, args)
  let gcc_id = macro_id_from_name(pp, "__GNUC__")
  let has_gcc = gcc_id != 0 && has_macro(pp, gcc_id)
  let cond = eval_if_expr(pp, expanded, directive_tokens[0].loc)
  let simple_file = @source.add_file(map, "<simple>", "#if 1 && (0 && 0 || 1)\n")
  let simple_pp = new_preprocessor(map, simple_file, @diag.new_diag_bag())
  ignore(next_input_token(simple_pp))
  let simple_toks = read_directive_tokens(simple_pp)
  let simple_cond = eval_if_expr(simple_pp, slice_tokens(simple_toks, 1), simple_toks[0].loc)
  if @diag.has_errors(bag) {
    for d in bag.diags {
      println("\{d.loc.file_id}:\{d.loc.line}:\{d.loc.col}: \{d.message}")
    }
    println(
      expanded.map(
        tok => "\{tok.kind}:\{@tokens.token_text_with(pp.interner, pp.lexeme_pool, tok)}",
      ).join(" "),
    )
  }
  assert_true(has_gcc)
  assert_true(cond)
  assert_true(simple_cond)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preprocess whitespace before paren" {
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens("#define F(x) x\nint y = F (1);")
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=[
    "@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:y", "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::IntLit:1", "@tokens.TokenKind::Semicolon:;",
  ])
}

///|
test "preprocess recursion guard" {
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens("#define A A\nint z = A;")
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=[
    "@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:z", "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::Ident:A", "@tokens.TokenKind::Semicolon:;",
  ])
}

///|
test "preprocess builtin line and file" {
  let (toks, bag, interner, lexeme_pool) =
    pp_tokens("int x = __LINE__;\nconst char *f = __FILE__;")
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=[
    "@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:x", "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::IntLit:1", "@tokens.TokenKind::Semicolon:;", "@tokens.TokenKind::KwConst:const",
    "@tokens.TokenKind::KwChar:char", "@tokens.TokenKind::Star:*", "@tokens.TokenKind::Ident:f", "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::StrLit:\"<test>\"", "@tokens.TokenKind::Semicolon:;",
  ])
}

///|
test "preprocess line directive" {
  let (toks, bag, interner, lexeme_pool) = pp_tokens(
    "#line 200 \"foo.c\"\nint x = __LINE__;\nconst char *f = __FILE__;",
  )
  assert_true(!@diag.has_errors(bag))
  let items = pp_items(toks, interner, lexeme_pool)
  @json.inspect(items, content=[
    "@tokens.TokenKind::KwInt:int", "@tokens.TokenKind::Ident:x", "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::IntLit:200", "@tokens.TokenKind::Semicolon:;", "@tokens.TokenKind::KwConst:const",
    "@tokens.TokenKind::KwChar:char", "@tokens.TokenKind::Star:*", "@tokens.TokenKind::Ident:f", "@tokens.TokenKind::Assign:=", "@tokens.TokenKind::StrLit:\"foo.c\"", "@tokens.TokenKind::Semicolon:;",
  ])
}

///|
test "preprocess date and time" {
  let (toks, bag, interner, lexeme_pool) = pp_tokens(
    "const char *d = __DATE__; const char *t = __TIME__;",
  )
  assert_true(!@diag.has_errors(bag))
  assert_true(toks.length() >= 13)
  assert_true(toks[5].kind == @tokens.TokenKind::StrLit)
  assert_true(toks[12].kind == @tokens.TokenKind::StrLit)
  assert_true(
    @tokens.token_text_with(interner, lexeme_pool, toks[12]).contains(":"),
  )
}
