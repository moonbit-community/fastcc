///|
fn new_pp_with_source(
  source : String,
) -> (@preproc.Preprocessor, @diag.DiagBag) {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<pp-api>", source)
  let pp = @preproc.new_preprocessor(map, file, bag, host=@default_host.new())
  (pp, bag)
}

///|
fn tok_word(pp : @preproc.Preprocessor, word : String) -> @tokens.Token {
  @preproc.make_builtin_word_token(pp, word)
}

///|
fn tok_with_offset(tok : @tokens.Token, offset : Int) -> @tokens.Token {
  {
    kind: tok.kind,
    value: tok.value,
    loc: { file_id: 0, line: 1, col: offset + 1, offset },
    line_start: false,
    hidden: tok.hidden,
  }
}

///|
test "preproc api hidden pool merge" {
  let pool = @preproc.new_hidden_pool()
  assert_true(@preproc.hidden_is_empty(0))
  let h1 = @preproc.hidden_add(pool, 0, 1)
  assert_true(!@preproc.hidden_is_empty(h1))
  assert_true(@preproc.hidden_contains(pool, h1, 1))
  let h1_again = @preproc.hidden_add(pool, h1, 1)
  assert_eq(h1_again, h1)
  @preproc.ensure_hidden_singleton_slot(pool, 2)
  let h2 = @preproc.hidden_add(pool, 0, 2)
  let merged = @preproc.merge_hidden(pool, h1, h2)
  assert_true(@preproc.hidden_contains(pool, merged, 1))
  assert_true(@preproc.hidden_contains(pool, merged, 2))
  let merged_same = @preproc.merge_hidden(pool, h1, 0)
  assert_eq(merged_same, h1)
  @preproc.clear_hidden_pool(pool)
  let h3 = @preproc.hidden_add(pool, 0, 3)
  assert_true(@preproc.hidden_contains(pool, h3, 3))
}

///|
test "preproc api macro registry" {
  let (pp, bag) = new_pp_with_source("")
  @preproc.init_builtin_macros(pp)
  assert_eq(@preproc.macro_id_from_name(pp, ""), 0)
  let foo_id = @preproc.macro_id_from_name(pp, "FOO")
  assert_true(foo_id > 0)
  let foo_tok = tok_word(pp, "FOO")
  assert_eq(@preproc.macro_id_from_token(pp, foo_tok), foo_id)
  assert_true(@preproc.is_macro_name_token(foo_tok))
  let empty_tok = @preproc.make_builtin_token(Ident)
  assert_true(!@preproc.is_macro_name_token(empty_tok))
  assert_eq(@preproc.macro_id_from_token(pp, empty_tok), 0)
  @preproc.ensure_macro_capacity(pp, foo_id + 2)
  @preproc.define_int_macro(pp, "FOO", 7)
  assert_true(@preproc.has_macro(pp, foo_id))
  match @preproc.get_macro(pp, foo_id) {
    None => fail("expected macro FOO")
    Some(macro_def) => assert_true(!macro_def.is_function)
  }
  @preproc.define_words_macro(pp, "WORDS", ["x", "y"])
  let words_id = @preproc.macro_id_from_name(pp, "WORDS")
  assert_true(@preproc.has_macro(pp, words_id))
  @preproc.define_func_macro_zero(pp, "FZERO")
  let fzero_id = @preproc.macro_id_from_name(pp, "FZERO")
  assert_true(@preproc.has_macro(pp, fzero_id))
  match @preproc.get_macro(pp, fzero_id) {
    None => fail("expected macro FZERO")
    Some(macro_def) => assert_true(macro_def.is_function)
  }
  @preproc.define_func_macro_empty(pp, "FEMPTY")
  let fempty_id = @preproc.macro_id_from_name(pp, "FEMPTY")
  assert_true(@preproc.has_macro(pp, fempty_id))
  match @preproc.get_macro(pp, fempty_id) {
    None => fail("expected macro FEMPTY")
    Some(macro_def) => assert_true(macro_def.is_function)
  }
  match @preproc.get_macro(pp, fzero_id) {
    None => ()
    Some(macro_def) => @preproc.set_macro(pp, fzero_id, macro_def)
  }
  @preproc.remove_macro(pp, fzero_id)
  assert_true(!@preproc.has_macro(pp, fzero_id))
  @preproc.finalize_preprocessor(pp)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc api directive tokens" {
  let (pp, bag) = new_pp_with_source("#define FOO 1\n")
  let hash = @preproc.next_input_token(pp)
  assert_eq(hash.kind, Hash)
  let name = @preproc.next_input_token(pp)
  assert_eq(name.kind, Ident)
  let args = @preproc.read_directive_tokens(pp)
  assert_eq(args.length(), 2)
  assert_eq(@preproc.pp_token_lexeme(pp, args[0]), "FOO")
  assert_eq(@preproc.pp_token_lexeme(pp, args[1]), "1")
  @preproc.finalize_preprocessor(pp)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc api directive head and skip" {
  let (pp, bag) = new_pp_with_source("#undef BAR\n#pragma once\nint x;")
  let _hash = @preproc.next_input_token(pp)
  let _name = @preproc.next_input_token(pp)
  let head = @preproc.read_directive_head_token(pp)
  match head {
    None => fail("expected head token")
    Some(tok) => assert_eq(@preproc.pp_token_lexeme(pp, tok), "BAR")
  }
  let _hash2 = @preproc.next_input_token(pp)
  let _name2 = @preproc.next_input_token(pp)
  @preproc.skip_directive_line(pp)
  let next_tok = @preproc.next_input_token(pp)
  assert_eq(next_tok.kind, KwInt)
  @preproc.finalize_preprocessor(pp)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc api directive text" {
  let (pp, bag) = new_pp_with_source("#error hello \\\nworld\n")
  let _hash = @preproc.next_input_token(pp)
  let _name = @preproc.next_input_token(pp)
  let text = @preproc.read_directive_text(pp)
  assert_eq(text, "hello world")
  @preproc.finalize_preprocessor(pp)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc api include helpers" {
  let case_dir = @testutil.make_case_dir("pp-api-include")
  let inc_dir = @testutil.join_path(case_dir, "inc")
  @testutil.ensure_dir(inc_dir)
  let header_path = @testutil.join_path(inc_dir, "foo.h")
  @testutil.write_string(header_path, "int from_header;\n")
  let (pp, bag) = new_pp_with_source("")
  @preproc.add_include_path(pp, inc_dir)
  assert_eq(@preproc.dir_name(header_path), inc_dir)
  assert_eq(@preproc.join_path(inc_dir, "foo.h"), header_path)
  assert_eq(@preproc.strip_quotes("\"foo.h\""), "foo.h")
  let str_tok = @preproc.make_string_literal(pp, "foo.h", @source.dummy_loc(0))
  match @preproc.parse_include_path(pp, [str_tok], @source.dummy_loc(0)) {
    None => fail("expected include spec")
    Some(spec) => {
      assert_eq(spec.path, "foo.h")
      assert_true(!spec.is_angle)
    }
  }
  let lt = @preproc.make_builtin_token(Lt)
  let gt = @preproc.make_builtin_token(Gt)
  let word = tok_word(pp, "foo.h")
  match @preproc.parse_has_include_path(pp, [lt, word, gt]) {
    None => fail("expected has-include spec")
    Some(spec) => {
      assert_eq(spec.path, "foo.h")
      assert_true(spec.is_angle)
    }
  }
  assert_eq(@preproc.eval_has_include(pp, [str_tok], include_next=false), 1)
  let miss_tok = @preproc.make_string_literal(
    pp,
    "missing.h",
    @source.dummy_loc(0),
  )
  assert_eq(@preproc.eval_has_include(pp, [miss_tok], include_next=false), 0)
  assert_true(
    @preproc.resolve_include_path(pp, "foo.h", false, include_next=false)
    is Some(_),
  )
  let spec = @preproc.IncludeSpec::{ path: "foo.h", is_angle: false }
  @preproc.include_file(pp, spec, @source.dummy_loc(0), include_next=false)
  let tok = @preproc.next_input_token(pp)
  assert_eq(tok.kind, KwInt)
  @preproc.finalize_preprocessor(pp)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc api token helpers" {
  let (pp, bag) = new_pp_with_source("")
  let tokens = [
    tok_word(pp, "a"),
    tok_word(pp, "b"),
    @preproc.make_builtin_token(Plus),
  ]
  let slice = @preproc.slice_tokens(tokens, 1)
  assert_eq(slice.length(), 2)
  let prefix = @preproc.prefix_tokens(tokens, 2)
  assert_eq(prefix.length(), 2)
  assert_eq(@preproc.pp_token_lexeme(pp, prefix[0]), "a")
  let stringized = @preproc.stringize_tokens(pp, [
    tok_word(pp, "x"),
    tok_word(pp, "y"),
  ])
  assert_eq(stringized, "x y")
  let escaped = @preproc.escape_string("a\"b\\c")
  assert_eq(escaped, "a\\\"b\\\\c")
  let str_lit = @preproc.make_string_literal(pp, "hello", @source.dummy_loc(0))
  assert_eq(@preproc.pp_token_lexeme(pp, str_lit), "\"hello\"")
  let int_lit = @preproc.make_int_literal_token(pp, 42, @source.dummy_loc(0))
  assert_eq(@preproc.pp_token_lexeme(pp, int_lit), "42")
  let line_tok = tok_word(pp, "__LINE__")
  assert_true(@preproc.is_builtin_macro_id(pp, @tokens.token_id(line_tok)))
  match @preproc.builtin_macro_tokens(pp, line_tok) {
    None => fail("expected builtin tokens")
    Some(out) => assert_eq(out[0].kind, IntLit)
  }
  let file_tok = tok_word(pp, "__FILE__")
  pp.logical_path = ""
  match @preproc.builtin_macro_tokens(pp, file_tok) {
    None => fail("expected file tokens")
    Some(out) => assert_eq(out[0].kind, StrLit)
  }
  @preproc.define_int_macro(pp, "FOO", 1)
  let foo_tok = tok_word(pp, "FOO")
  assert_true(@preproc.tokens_have_id([foo_tok]))
  assert_true(@preproc.token_needs_expansion(pp, foo_tok))
  assert_true(@preproc.tokens_need_expansion(pp, [foo_tok]))
  @preproc.push_expanding(pp, @preproc.macro_id_from_name(pp, "FOO"))
  assert_true(@preproc.is_expanding(pp, @preproc.macro_id_from_name(pp, "FOO")))
  @preproc.pop_expanding(pp)
  assert_true(
    !@preproc.is_expanding(pp, @preproc.macro_id_from_name(pp, "FOO")),
  )
  let pushed = @preproc.make_builtin_token(Ident)
  @preproc.push_back(pp, pushed)
  let raw = @preproc.next_raw_token(pp)
  assert_eq(raw.kind, Ident)
  @preproc.add_pp_error(pp, @source.dummy_loc(0), "oops")
  assert_true(@diag.has_errors(bag))
  @preproc.finalize_preprocessor(pp)
}

///|
test "preproc api error helpers" {
  let (pp, bag) = new_pp_with_source("")
  @preproc.define_macro(pp, "", [])
  @preproc.define_func_macro_zero(pp, "")
  @preproc.define_func_macro_empty(pp, "")
  @preproc.ensure_macro_capacity(pp, 0)
  assert_true(@preproc.get_macro(pp, 0) is None)
  @preproc.remove_macro(pp, 0)
  let empty_head = @preproc.read_directive_head_token(pp)
  assert_true(empty_head is None)
  let tokens = [tok_word(pp, "a")]
  let slice = @preproc.slice_tokens(tokens, 0)
  assert_eq(slice.length(), 1)
  assert_eq(@preproc.stringize_tokens(pp, []), "")
  assert_eq(@preproc.join_path("base/", "file.h"), "base/file.h")
  let loc = @source.dummy_loc(0)
  let _ = @preproc.parse_include_path(pp, [], loc)
  let lt = @preproc.make_builtin_token(Lt)
  let ident = tok_word(pp, "missing.h")
  let _ = @preproc.parse_include_path(pp, [lt, ident], loc)
  let _ = @preproc.parse_include_path(pp, [tok_word(pp, "bad")], loc)
  let _ = @preproc.lex_paste_tokens(pp, "a+b", "a", "+b", loc, 0)
  assert_true(@preproc.parse_has_include_path(pp, []) is None)
  assert_eq(@preproc.eval_has_include(pp, [], include_next=false), 0)
  let case_dir = @testutil.make_case_dir("pp-api-resolve")
  let inc_dir = @testutil.join_path(case_dir, "inc")
  @testutil.ensure_dir(inc_dir)
  @testutil.write_string(@testutil.join_path(inc_dir, "skip.h"), "int ok;\n")
  @preproc.add_include_path(pp, inc_dir)
  pp.current_dir = inc_dir
  assert_true(
    @preproc.resolve_include_path(pp, "skip.h", false, include_next=true)
    is Some(_),
  )
  let dir_path = @testutil.join_path(case_dir, "dir")
  @testutil.ensure_dir(dir_path)
  let spec = @preproc.IncludeSpec::{ path: "dir", is_angle: false }
  pp.current_dir = case_dir
  @preproc.include_file(pp, spec, loc, include_next=false)
  let name_tok = tok_with_offset(tok_word(pp, "F"), 0)
  let lparen = tok_with_offset(@preproc.make_builtin_token(LParen), 1)
  let bad_args = [lparen, @preproc.make_builtin_token(Comma)]
  assert_true(@preproc.parse_define_macro(pp, name_tok, bad_args, loc) is None)
  let args_ellipsis = [
    @preproc.make_builtin_token(LParen),
    @preproc.make_builtin_token(Ellipsis),
    @preproc.make_builtin_token(RParen),
  ]
  assert_true(@preproc.parse_macro_params(pp, args_ellipsis, loc) is Some(_))
  let args_bad_ident = [
    @preproc.make_builtin_token(LParen),
    @preproc.make_builtin_token(Ident),
    @preproc.make_builtin_token(RParen),
  ]
  assert_true(@preproc.parse_macro_params(pp, args_bad_ident, loc) is None)
  let args_bad_token = [
    @preproc.make_builtin_token(LParen),
    @preproc.make_builtin_token(Plus),
  ]
  assert_true(@preproc.parse_macro_params(pp, args_bad_token, loc) is None)
  let args_unterm = [@preproc.make_builtin_token(LParen), tok_word(pp, "x")]
  assert_true(@preproc.parse_macro_params(pp, args_unterm, loc) is None)
  let args_var = [
    @preproc.make_builtin_token(LParen),
    tok_word(pp, "x"),
    @preproc.make_builtin_token(Comma),
    @preproc.make_builtin_token(Ellipsis),
    @preproc.make_builtin_token(RParen),
  ]
  assert_true(@preproc.parse_macro_params(pp, args_var, loc) is Some(_))
  assert_true(@preproc.read_macro_args(pp, loc) is None)
  let non_fn_macro = @preproc.Macro::{
    params: [],
    is_variadic: false,
    is_function: false,
    replacement: [],
    replacement_has_id: false,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  }
  assert_true(@preproc.normalize_macro_args(non_fn_macro, [], loc) is Some(_))
  let var_macro = @preproc.Macro::{
    params: [
      @preproc.macro_id_from_name(pp, "x"),
      @preproc.macro_id_from_name(pp, "y"),
    ],
    is_variadic: true,
    is_function: true,
    replacement: [],
    replacement_has_id: false,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  }
  assert_true(@preproc.normalize_macro_args(var_macro, [], loc) is None)
  let norm = @preproc.normalize_macro_args(
    var_macro,
    [[], [tok_word(pp, "a")], [tok_word(pp, "b")]],
    loc,
  )
  assert_true(norm is Some(_))
  let out_of_range = @preproc.ensure_expanded_arg(
    pp,
    [[]],
    Array::make(1, None),
    2,
  )
  assert_eq(out_of_range.length(), 0)
  assert_eq(@preproc.parse_line_int_literal(pp, "x", loc), 0)
  assert_eq(@preproc.parse_line_int_literal(pp, "1z", loc), 0)
  let bad_pp2 = @preproc.parse_pp_int_literal(pp, "x", loc)
  assert_true(@preproc.pp_is_zero(bad_pp2))
  let bad_pp = @preproc.parse_pp_int_literal(pp, "1z", loc)
  assert_true(@preproc.pp_is_zero(bad_pp))
  let bad_char_id = @tokens.lexeme_pool_intern(pp.lexeme_pool, "''")
  let bad_char = @preproc.make_builtin_token(CharLit, lexeme_id=bad_char_id)
  ignore(@preproc.parse_pp_char_literal(pp, bad_char))
  ignore(@preproc.decode_pp_escape_value(pp, "\\'", 1, loc))
  @preproc.finalize_preprocessor(pp)
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc api cond helpers" {
  let (pp, bag) = new_pp_with_source("")
  assert_true(@preproc.current_active(pp))
  @preproc.push_cond(pp, false)
  assert_true(!@preproc.current_active(pp))
  @preproc.update_elif(pp, true, @source.dummy_loc(0))
  assert_true(@preproc.current_active(pp))
  @preproc.update_else(pp, @source.dummy_loc(0))
  assert_true(!@preproc.current_active(pp))
  @preproc.pop_cond(pp, @source.dummy_loc(0))
  assert_true(@preproc.current_active(pp))
  @preproc.update_else(pp, @source.dummy_loc(0))
  assert_true(@diag.has_errors(bag))
  @preproc.pop_cond(pp, @source.dummy_loc(0))
  assert_true(@diag.has_errors(bag))
  @preproc.push_cond(pp, false)
  @preproc.push_cond(pp, false)
  @preproc.update_elif(pp, true, @source.dummy_loc(0))
  assert_true(!@preproc.current_active(pp))
  @preproc.pop_cond(pp, @source.dummy_loc(0))
  @preproc.pop_cond(pp, @source.dummy_loc(0))
  @preproc.push_cond(pp, false)
  @preproc.update_else(pp, @source.dummy_loc(0))
  assert_true(@preproc.current_active(pp))
  @preproc.pop_cond(pp, @source.dummy_loc(0))
  @preproc.finalize_preprocessor(pp)
}

///|
test "preproc api macro parsing helpers" {
  let (pp, bag) = new_pp_with_source("")
  let loc = @source.dummy_loc(0)
  let name_tok = tok_word(pp, "OBJ")
  let int_tok = @preproc.make_int_literal_token(pp, 3, loc)
  match @preproc.parse_define_macro(pp, name_tok, [int_tok], loc) {
    None => fail("expected macro")
    Some(macro_def) => {
      assert_true(!macro_def.is_function)
      assert_eq(macro_def.replacement.length(), 1)
    }
  }
  let args = [
    @preproc.make_builtin_token(LParen),
    tok_word(pp, "x"),
    @preproc.make_builtin_token(Comma),
    tok_word(pp, "y"),
    @preproc.make_builtin_token(RParen),
    tok_word(pp, "z"),
  ]
  match @preproc.parse_macro_params(pp, args, loc) {
    None => fail("expected macro params")
    Some((params, is_variadic, replacement)) => {
      assert_true(!is_variadic)
      assert_eq(params.length(), 2)
      assert_eq(replacement.length(), 1)
      assert_eq(@preproc.pp_token_lexeme(pp, replacement[0]), "z")
    }
  }
  let id_x = @preproc.macro_id_from_name(pp, "x")
  let id_y = @preproc.macro_id_from_name(pp, "y")
  let macro_def = @preproc.Macro::{
    params: [id_x, id_y],
    is_variadic: false,
    is_function: true,
    replacement: [],
    replacement_has_id: false,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  }
  @preproc.push_back(pp, @preproc.make_builtin_token(RParen))
  @preproc.push_back(pp, @preproc.make_int_literal_token(pp, 2, loc))
  @preproc.push_back(pp, @preproc.make_builtin_token(Comma))
  @preproc.push_back(pp, @preproc.make_int_literal_token(pp, 1, loc))
  match @preproc.read_macro_args(pp, loc) {
    None => fail("expected macro args")
    Some(raw_args) =>
      match @preproc.normalize_macro_args(macro_def, raw_args, loc) {
        None => fail("expected normalized args")
        Some(norm) => assert_eq(norm.length(), 2)
      }
  }
  let tokens = [
    tok_word(pp, "F"),
    @preproc.make_builtin_token(LParen),
    @preproc.make_int_literal_token(pp, 1, loc),
    @preproc.make_builtin_token(Comma),
    @preproc.make_int_literal_token(pp, 2, loc),
    @preproc.make_builtin_token(RParen),
  ]
  match @preproc.read_macro_args_from_tokens(pp, tokens, 2, loc) {
    None => fail("expected args from tokens")
    Some((args_from_tokens, end_idx)) => {
      assert_eq(args_from_tokens.length(), 2)
      assert_eq(end_idx, 6)
    }
  }
  let tokens_nested = [
    tok_word(pp, "F"),
    @preproc.make_builtin_token(LParen),
    @preproc.make_builtin_token(LParen),
    tok_word(pp, "x"),
    @preproc.make_builtin_token(RParen),
    @preproc.make_builtin_token(Comma),
    @preproc.make_builtin_token(LBrace),
    tok_word(pp, "y"),
    @preproc.make_builtin_token(RBrace),
    @preproc.make_builtin_token(Comma),
    @preproc.make_builtin_token(LBracket),
    tok_word(pp, "z"),
    @preproc.make_builtin_token(RBracket),
    @preproc.make_builtin_token(RParen),
  ]
  match @preproc.read_macro_args_from_tokens(pp, tokens_nested, 2, loc) {
    None => fail("expected nested args")
    Some((args_nested, _end_idx)) => assert_true(args_nested.length() > 0)
  }
  let tokens_unterm = [
    tok_word(pp, "F"),
    @preproc.make_builtin_token(LParen),
    tok_word(pp, "x"),
  ]
  assert_true(
    @preproc.read_macro_args_from_tokens(pp, tokens_unterm, 2, loc) is None,
  )
  @preproc.finalize_preprocessor(pp)
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc api expansion helpers" {
  let (pp, bag) = new_pp_with_source("/*skip*/\n#\n")
  @preproc.skip_inactive(pp)
  let hash = @preproc.next_input_token(pp)
  assert_eq(hash.kind, Hash)
  @preproc.finalize_preprocessor(pp)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc api substitute macro branches" {
  let (pp, bag) = new_pp_with_source("")
  let loc = @source.dummy_loc(0)
  @preproc.define_int_macro(pp, "EXP", 1)
  @preproc.define_int_macro(pp, "AB", 2)
  let exp_id = @preproc.macro_id_from_name(pp, "EXP")
  let a_tok = tok_word(pp, "A")
  let b_tok = tok_word(pp, "B")
  let x_id = @preproc.macro_id_from_name(pp, "x")
  let stringize_def = @preproc.Macro::{
    params: [x_id],
    is_variadic: false,
    is_function: true,
    replacement: [@preproc.make_builtin_token(Hash), tok_word(pp, "x")],
    replacement_has_id: true,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  }
  let (stringized, _) = @preproc.substitute_macro(pp, stringize_def, [], loc)
  assert_eq(@preproc.pp_token_lexeme(pp, stringized[0]), "\"\"")
  let empty_hash_def = @preproc.Macro::{
    params: [],
    is_variadic: false,
    is_function: true,
    replacement: [@preproc.make_builtin_token(HashHash), a_tok],
    replacement_has_id: true,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  }
  ignore(@preproc.substitute_macro(pp, empty_hash_def, [], loc))
  let hash_param_def = @preproc.Macro::{
    params: [x_id],
    is_variadic: false,
    is_function: true,
    replacement: [
      a_tok,
      @preproc.make_builtin_token(HashHash),
      tok_word(pp, "x"),
    ],
    replacement_has_id: true,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  }
  ignore(@preproc.substitute_macro(pp, hash_param_def, [], loc))
  let hash_no_param_def = @preproc.Macro::{
    params: [],
    is_variadic: false,
    is_function: true,
    replacement: [a_tok, @preproc.make_builtin_token(HashHash), b_tok],
    replacement_has_id: true,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  }
  ignore(@preproc.substitute_macro(pp, hash_no_param_def, [], loc))
  let hash_no_id_def = @preproc.Macro::{
    params: [],
    is_variadic: false,
    is_function: true,
    replacement: [
      a_tok,
      @preproc.make_builtin_token(HashHash),
      @preproc.make_builtin_token(Ident),
    ],
    replacement_has_id: false,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  }
  ignore(@preproc.substitute_macro(pp, hash_no_id_def, [], loc))
  let hash_non_ident_def = @preproc.Macro::{
    params: [],
    is_variadic: false,
    is_function: true,
    replacement: [
      a_tok,
      @preproc.make_builtin_token(HashHash),
      @preproc.make_int_literal_token(pp, 1, loc),
    ],
    replacement_has_id: false,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  }
  ignore(@preproc.substitute_macro(pp, hash_non_ident_def, [], loc))
  let hash_multi_def = @preproc.Macro::{
    params: [x_id],
    is_variadic: false,
    is_function: true,
    replacement: [
      a_tok,
      @preproc.make_builtin_token(HashHash),
      tok_word(pp, "x"),
    ],
    replacement_has_id: true,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  }
  let multi_args = [[tok_word(pp, "EXP"), tok_word(pp, "Y")]]
  ignore(@preproc.substitute_macro(pp, hash_multi_def, multi_args, loc))
  let single_param_def = @preproc.Macro::{
    params: [x_id],
    is_variadic: false,
    is_function: true,
    replacement: [tok_word(pp, "x")],
    replacement_has_id: true,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  }
  let arg_tokens = [[tok_word(pp, "EXP")]]
  ignore(@preproc.substitute_macro(pp, single_param_def, arg_tokens, loc))
  assert_true(!@preproc.is_expanding(pp, exp_id))
  @preproc.finalize_preprocessor(pp)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc api expand tokens branches" {
  let (pp, bag) = new_pp_with_source("")
  let loc = @source.dummy_loc(0)
  @preproc.define_int_macro(pp, "EXP", 1)
  let exp_id = @preproc.macro_id_from_name(pp, "EXP")
  let obj_repl = [tok_word(pp, "EXP")]
  @preproc.define_macro(pp, "OBJ", obj_repl)
  let param_id = @preproc.macro_id_from_name(pp, "x")
  let func_def = @preproc.Macro::{
    params: [param_id],
    is_variadic: false,
    is_function: true,
    replacement: [tok_word(pp, "EXP")],
    replacement_has_id: true,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  }
  let func_id = @preproc.macro_id_from_name(pp, "F")
  @preproc.set_macro(pp, func_id, func_def)
  let line_tok = tok_word(pp, "__LINE__")
  let has_inc = tok_word(pp, "__has_include")
  let lparen = @preproc.make_builtin_token(LParen)
  let rparen = @preproc.make_builtin_token(RParen)
  let int_tok = @preproc.make_int_literal_token(pp, 1, loc)
  @preproc.push_expanding(pp, exp_id)
  ignore(@preproc.expand_tokens(pp, [line_tok, tok_word(pp, "EXP")]))
  @preproc.pop_expanding(pp)
  ignore(@preproc.expand_tokens(pp, [line_tok, tok_word(pp, "F"), lparen]))
  ignore(
    @preproc.expand_tokens(pp, [line_tok, tok_word(pp, "F"), lparen, rparen]),
  )
  ignore(@preproc.expand_tokens(pp, [line_tok, has_inc, lparen, rparen]))
  ignore(
    @preproc.expand_tokens(pp, [
      line_tok,
      tok_word(pp, "F"),
      lparen,
      int_tok,
      rparen,
    ]),
  )
  ignore(
    @preproc.expand_tokens(pp, [line_tok, tok_word(pp, "F"), tok_word(pp, "x")]),
  )
  ignore(@preproc.expand_tokens(pp, [line_tok, tok_word(pp, "OBJ")]))
  let hidden_tok = @preproc.add_hidden(pp, tok_word(pp, "EXP"), exp_id)
  ignore(@preproc.expand_tokens(pp, [hidden_tok]))
  @preproc.finalize_preprocessor(pp)
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc api next_pp_token branches" {
  let (pp, bag) = new_pp_with_source("")
  @preproc.define_int_macro(pp, "EXP", 1)
  let exp_id = @preproc.macro_id_from_name(pp, "EXP")
  let param_id = @preproc.macro_id_from_name(pp, "x")
  let func_def = @preproc.Macro::{
    params: [param_id],
    is_variadic: false,
    is_function: true,
    replacement: [tok_word(pp, "EXP")],
    replacement_has_id: true,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  }
  let func_id = @preproc.macro_id_from_name(pp, "F")
  @preproc.set_macro(pp, func_id, func_def)
  @preproc.push_back(pp, tok_word(pp, "EXP"))
  @preproc.push_expanding(pp, exp_id)
  let t1 = @preproc.next_pp_token(pp)
  assert_eq(t1.kind, Ident)
  @preproc.pop_expanding(pp)
  @preproc.push_back(pp, tok_word(pp, "x"))
  @preproc.push_back(pp, tok_word(pp, "F"))
  let t2 = @preproc.next_pp_token(pp)
  assert_eq(t2.kind, Ident)
  @preproc.push_back(pp, @preproc.make_builtin_token(LParen))
  @preproc.push_back(pp, tok_word(pp, "F"))
  let t3 = @preproc.next_pp_token(pp)
  assert_eq(t3.kind, Ident)
  @preproc.push_back(pp, @preproc.make_builtin_token(RParen))
  @preproc.push_back(
    pp,
    @preproc.make_int_literal_token(pp, 1, @source.dummy_loc(0)),
  )
  @preproc.push_back(pp, @preproc.make_builtin_token(LParen))
  @preproc.push_back(pp, tok_word(pp, "F"))
  let _t4 = @preproc.next_pp_token(pp)
  @preproc.finalize_preprocessor(pp)
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc api handle_directive branches" {
  let source =
    #|#define 1
    #|#line 1
    #|#error boom
    #|#warning warn
  let (pp, bag) = new_pp_with_source(source)
  let hash_define = @preproc.next_input_token(pp)
  @preproc.handle_directive(pp, hash_define)
  pp.active = false
  let hash_line = @preproc.next_input_token(pp)
  @preproc.handle_directive(pp, hash_line)
  let hash_err = @preproc.next_input_token(pp)
  @preproc.handle_directive(pp, hash_err)
  let hash_warn = @preproc.next_input_token(pp)
  @preproc.handle_directive(pp, hash_warn)
  @preproc.finalize_preprocessor(pp)
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc api skip inactive branches" {
  let source = " \\\n//line\nx\\\n//comment\n#\n"
  let (pp, bag) = new_pp_with_source(source)
  @preproc.skip_inactive(pp)
  let tok = @preproc.next_input_token(pp)
  assert_eq(tok.kind, Hash)
  @preproc.finalize_preprocessor(pp)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc api skip inactive line comments" {
  let source = "//line\n#\n"
  let (pp, bag) = new_pp_with_source(source)
  @preproc.skip_inactive(pp)
  let tok = @preproc.next_input_token(pp)
  assert_eq(tok.kind, Hash)
  @preproc.finalize_preprocessor(pp)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc api large source capacities" {
  let size = 8_500_000
  let sb = StringBuilder::new(size_hint=size)
  for _ in 0..<size {
    sb.write_char('a')
  }
  let big = sb.to_string()
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<pp-big>", big)
  let pp = @preproc.new_preprocessor(map, file, bag, host=@default_host.new())
  @preproc.finalize_preprocessor(pp)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc api expansion and line helpers" {
  let (pp, bag) = new_pp_with_source("")
  let loc = @source.dummy_loc(0)
  let int_tok = @preproc.make_int_literal_token(pp, 9, loc)
  @preproc.define_macro(pp, "OBJ", [int_tok])
  let obj_id = @preproc.macro_id_from_name(pp, "OBJ")
  match @preproc.get_macro(pp, obj_id) {
    None => fail("expected macro OBJ")
    Some(macro_def) => {
      let needs = @preproc.macro_replacement_needs_expand(pp, obj_id, macro_def)
      assert_true(!needs)
      let expanded = @preproc.expand_tokens(pp, [tok_word(pp, "OBJ")])
      assert_eq(@preproc.pp_token_lexeme(pp, expanded[0]), "9")
      let (subbed, _needs) = @preproc.substitute_macro(pp, macro_def, [], loc)
      assert_eq(subbed.length(), 1)
    }
  }
  let marked = @tokens.Token::{
    kind: Ident,
    value: @tokens.token_value_from_parts(0, 0),
    loc,
    line_start: true,
    hidden: @tokens.empty_hidden,
  }
  let normalized = @preproc.normalize_macro_tokens([marked])
  assert_true(!normalized[0].line_start)
  let if_expanded = @preproc.expand_if_tokens(pp, [tok_word(pp, "OBJ")])
  assert_eq(@preproc.pp_token_lexeme(pp, if_expanded[0]), "9")
  let raw_args = [[tok_word(pp, "OBJ")]]
  let cache : Array[Array[@tokens.Token]?] = Array::make(1, None)
  let ensured = @preproc.ensure_expanded_arg(pp, raw_args, cache, 0)
  assert_eq(@preproc.pp_token_lexeme(pp, ensured[0]), "9")
  let pasted = @preproc.lex_paste_tokens(pp, "ab", "a", "b", loc, 0)
  assert_eq(pasted.length(), 1)
  let hidden_tok = @preproc.add_hidden(pp, tok_word(pp, "OBJ"), obj_id)
  assert_true(!@preproc.hidden_is_empty(hidden_tok.hidden))
  let hidden_same = @preproc.add_hidden(pp, hidden_tok, obj_id)
  assert_eq(hidden_same.hidden, hidden_tok.hidden)
  let hidden_list = @preproc.add_hidden_tokens(
    pp,
    [tok_word(pp, "OBJ")],
    obj_id,
  )
  assert_eq(hidden_list.length(), 1)
  @preproc.push_tokens(pp, [int_tok])
  let raw = @preproc.next_raw_token(pp)
  assert_eq(raw.kind, IntLit)
  @preproc.push_expanding(pp, obj_id)
  pp.expanding_guards.push({ restore_len: 0 })
  @preproc.release_expanding_guards(pp)
  assert_true(!@preproc.is_expanding(pp, obj_id))
  let line_tok = @preproc.make_int_literal_token(pp, 10, loc)
  let file_tok = @preproc.make_string_literal(pp, "line.c", loc)
  @preproc.handle_line_directive(pp, [line_tok, file_tok], loc)
  assert_eq(pp.logical_path, "line.c")
  @preproc.handle_line_directive(pp, [], loc)
  @preproc.handle_line_directive(pp, [file_tok], loc)
  let bad_line = @preproc.make_int_literal_token(pp, 0, loc)
  @preproc.handle_line_directive(pp, [bad_line], loc)
  @preproc.add_pp_error(pp, loc, "line-error")
  @preproc.finalize_preprocessor(pp)
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc api handle directive" {
  let (pp, bag) = new_pp_with_source("#define DEF 7\n")
  let hash = @preproc.next_input_token(pp)
  @preproc.handle_directive(pp, hash)
  let def_id = @preproc.macro_id_from_name(pp, "DEF")
  assert_true(@preproc.has_macro(pp, def_id))
  @preproc.finalize_preprocessor(pp)
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc api if parser wrappers" {
  let (pp, bag) = new_pp_with_source("")
  let loc = @source.dummy_loc(0)
  @preproc.define_int_macro(pp, "NUM", 5)
  let num_tok = tok_word(pp, "NUM")
  match @preproc.macro_int_value(pp, num_tok, loc) {
    None => fail("expected macro int value")
    Some(v) => assert_true(!@preproc.pp_is_zero(v))
  }
  let val = @preproc.pp_bool_value(true)
  assert_true(!@preproc.pp_is_zero(val))
  assert_true(
    @preproc.pp_unsigned_result(val, { value: (1 : UInt64), is_unsigned: true }),
  )
  assert_eq(
    @preproc.pp_shift_count({ value: (65 : UInt64), is_unsigned: false }),
    1,
  )
  let tok1 = @preproc.make_int_literal_token(pp, 1, loc)
  let tok2 = @preproc.make_int_literal_token(pp, 2, loc)
  let parser0 = @preproc.IfParser::{ tokens: [tok1], index: 0, pp }
  ignore(@preproc.parse_primary(parser0, loc))
  let parser1 = @preproc.IfParser::{ tokens: [tok1], index: 0, pp }
  ignore(@preproc.parse_unary(parser1, loc))
  let parser2 = @preproc.IfParser::{ tokens: [tok1], index: 0, pp }
  ignore(@preproc.parse_mul(parser2, loc))
  let parser3 = @preproc.IfParser::{ tokens: [tok1], index: 0, pp }
  ignore(@preproc.parse_add(parser3, loc))
  let parser4 = @preproc.IfParser::{ tokens: [tok1], index: 0, pp }
  ignore(@preproc.parse_shift(parser4, loc))
  let parser5 = @preproc.IfParser::{ tokens: [tok1], index: 0, pp }
  ignore(@preproc.parse_rel(parser5, loc))
  let parser6 = @preproc.IfParser::{ tokens: [tok1], index: 0, pp }
  ignore(@preproc.parse_eq(parser6, loc))
  let parser7 = @preproc.IfParser::{ tokens: [tok1], index: 0, pp }
  ignore(@preproc.parse_bit_and(parser7, loc))
  let parser8 = @preproc.IfParser::{ tokens: [tok1], index: 0, pp }
  ignore(@preproc.parse_bit_xor(parser8, loc))
  let parser9 = @preproc.IfParser::{ tokens: [tok1], index: 0, pp }
  ignore(@preproc.parse_bit_or(parser9, loc))
  let parser10 = @preproc.IfParser::{ tokens: [tok1], index: 0, pp }
  ignore(@preproc.parse_logical_and(parser10, loc))
  let parser11 = @preproc.IfParser::{ tokens: [tok1], index: 0, pp }
  ignore(@preproc.parse_logical_or(parser11, loc))
  let parser12 = @preproc.IfParser::{ tokens: [num_tok], index: 0, pp }
  ignore(@preproc.parse_defined(parser12, loc))
  let parser13 = @preproc.IfParser::{
    tokens: [@preproc.make_builtin_token(RParen)],
    index: 0,
    pp,
  }
  assert_true(@preproc.peek_is_rparen(parser13))
  let parser14 = @preproc.IfParser::{
    tokens: [tok2, @preproc.make_builtin_token(RParen)],
    index: 0,
    pp,
  }
  @preproc.skip_paren_expr(parser14, loc)
  let parser15 = @preproc.IfParser::{ tokens: [tok1, tok2], index: 0, pp }
  assert_true(@preproc.peek_if(parser15) is Some(_))
  assert_true(@preproc.advance_if(parser15) is Some(_))
  assert_true(@preproc.match_kind(parser15, IntLit))
  let line_val = @preproc.parse_line_int_literal(pp, "12", loc)
  assert_eq(line_val, 12)
  let int_val = @preproc.parse_pp_int_literal(pp, "13", loc)
  assert_eq(int_val.value.to_int(), 13)
  let char_id = @tokens.lexeme_pool_intern(pp.lexeme_pool, "'a'")
  let char_tok = @preproc.make_builtin_token(CharLit, lexeme_id=char_id)
  ignore(@preproc.parse_pp_char_literal(pp, char_tok))
  let (hex_val, _hex_idx) = @preproc.parse_pp_hex_escape(pp, "1f", 0, loc)
  assert_eq(hex_val, 31)
  let (oct_val, _oct_idx) = @preproc.parse_pp_octal_escape("77", 0)
  assert_eq(oct_val, 63)
  assert_true(@preproc.pp_is_oct_digit((55 : UInt16)))
  assert_true(!@preproc.pp_is_oct_digit((56 : UInt16)))
  match @preproc.pp_hex_digit_value((65 : UInt16)) {
    None => fail("expected hex digit")
    Some(v) => assert_eq(v, 10)
  }
  let left = tok_word(pp, "a")
  let right = tok_word(pp, "b")
  let left_loc = @source.SrcLoc::{ file_id: 0, line: 1, col: 1, offset: 0 }
  let right_loc = @source.SrcLoc::{ file_id: 0, line: 1, col: 2, offset: 1 }
  let left_adj = @tokens.Token::{
    kind: left.kind,
    value: left.value,
    loc: left_loc,
    line_start: false,
    hidden: left.hidden,
  }
  let right_adj = @tokens.Token::{
    kind: right.kind,
    value: right.value,
    loc: right_loc,
    line_start: false,
    hidden: right.hidden,
  }
  assert_true(@preproc.is_adjacent(pp, left_adj, right_adj))
  assert_eq(@preproc.pp_token_lexeme_len(pp, left_adj), 1)
  assert_eq(@preproc.logical_line(pp, left_loc), 1)
  let (date_lit, time_lit) = @preproc.init_datetime_literals()
  assert_true(date_lit.length() > 0)
  assert_true(time_lit.length() > 0)
  let dt = @time.unix(0, zone=@time.utc_zone)
  let date = @preproc.format_date(dt)
  let time = @preproc.format_time(dt)
  assert_true(date.length() > 0)
  assert_true(time.length() > 0)
  assert_eq(@preproc.month_name(1), "Jan")
  assert_eq(@preproc.month_name(2), "Feb")
  assert_eq(@preproc.month_name(3), "Mar")
  assert_eq(@preproc.month_name(4), "Apr")
  assert_eq(@preproc.month_name(5), "May")
  assert_eq(@preproc.pad2(3), "03")
  assert_eq(@preproc.pad2_space(3), " 3")
  let params = [
    @preproc.macro_id_from_name(pp, "x"),
    @preproc.macro_id_from_name(pp, "y"),
  ]
  match @preproc.lookup_param_index(params, params[1]) {
    None => fail("expected param index")
    Some(idx) => assert_eq(idx, 1)
  }
  @preproc.finalize_preprocessor(pp)
  assert_true(!@diag.has_errors(bag))
}
