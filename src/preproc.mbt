///|
struct CondState {
  parent_active : Bool
  mut taken : Bool
  mut active : Bool
}

///|
struct Macro {
  params : Array[Int]
  is_variadic : Bool
  is_function : Bool
  replacement : Array[Token]
  replacement_has_id : Bool
  replacement_needs_expand : Bool
  replacement_needs_epoch : Int
}

///|
struct IncludeSpec {
  path : String
  is_angle : Bool
}

///|
struct PreprocBuiltinIds {
  line_macro : Int
  file_macro : Int
  date_macro : Int
  time_macro : Int
  defined : Int
  has_include : Int
  has_include_next : Int
  dir_define : Int
  dir_undef : Int
  dir_if : Int
  dir_ifdef : Int
  dir_ifndef : Int
  dir_elif : Int
  dir_else : Int
  dir_endif : Int
  dir_include : Int
  dir_include_next : Int
  dir_line : Int
  dir_error : Int
  dir_warning : Int
  dir_pragma : Int
}

///|
struct HiddenNode {
  id : Int
  next : Int
}

///|
struct HiddenPool {
  nodes : Array[HiddenNode]
  singleton_by_id : Array[Int]
}

///|
struct Preprocessor {
  mut lexer : Lexer
  lexer_stack : Array[Lexer]
  held_stack : Array[Token?]
  path_stack : Array[String]
  dir_stack : Array[String]
  mut current_path : String
  mut current_dir : String
  mut logical_path : String
  logical_path_stack : Array[String]
  mut line_adjust : Int
  line_adjust_stack : Array[Int]
  include_paths : Array[String]
  diags : @diag.DiagBag
  map : @source.SourceMap
  macros : Array[Macro?]
  mut macro_epoch : Int
  pending : Array[Token]
  mut held : Token?
  cond_stack : Array[CondState]
  mut active : Bool
  expanding : Array[Int]
  expanding_guards : Array[ExpandingGuard]
  date_literal : String
  time_literal : String
  interner : @intern.StringInterner
  keyword_ids : KeywordIds
  lexeme_pool : LexemePool
  hidden_pool : HiddenPool
  builtin_ids : PreprocBuiltinIds
}

///|
struct ExpandingGuard { restore_len : Int }

///|
fn new_hidden_pool() -> HiddenPool {
  { nodes: [], singleton_by_id: [] }
}

///|
fn clear_hidden_pool(pool : HiddenPool) -> Unit {
  pool.nodes.clear()
  pool.singleton_by_id.clear()
}

///|
fn make_builtin_token(
  kind : TokenKind,
  id? : Int = 0,
  lexeme_id? : Int = 0,
) -> Token {
  let value = token_value_from_parts(id, lexeme_id)
  {
    kind,
    value,
    loc: @source.dummy_loc(0),
    line_start: false,
    hidden: empty_hidden,
  }
}

///|
fn make_builtin_word_token(pp : Preprocessor, word : String) -> Token {
  let (_, id) = pp.interner.intern_view_with_id(word[:])
  match keyword_kind_from_id(id, pp.keyword_ids) {
    Some(kind) => make_builtin_token(kind, id=id)
    None => make_builtin_token(Ident, id=id)
  }
}

///|
fn pp_token_lexeme(pp : Preprocessor, tok : Token) -> String {
  token_text_with(pp.interner, pp.lexeme_pool, tok)
}

///|
fn pp_token_lexeme_len(pp : Preprocessor, tok : Token) -> Int {
  token_text_len_with(pp.interner, pp.lexeme_pool, tok)
}

///|
fn define_macro(
  pp : Preprocessor,
  name : String,
  replacement : Array[Token],
) -> Unit {
  let id = macro_id_from_name(pp, name)
  if id == 0 {
    return
  }
  let replacement_has_id = tokens_have_id(replacement)
  set_macro(pp, id, {
    params: [],
    is_variadic: false,
    is_function: false,
    replacement,
    replacement_has_id,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  })
}

///|
fn define_words_macro(pp : Preprocessor, name : String, words : Array[String]) ->
  Unit {
  let tokens = words.map(w => make_builtin_word_token(pp, w))
  define_macro(pp, name, tokens)
}

///|
fn define_int_macro(pp : Preprocessor, name : String, value : Int) -> Unit {
  let lexeme_id = lexeme_pool_intern(pp.lexeme_pool, value.to_string())
  define_macro(pp, name, [make_builtin_token(IntLit, lexeme_id=lexeme_id)])
}

///|
fn define_func_macro_zero(pp : Preprocessor, name : String) -> Unit {
  let id = macro_id_from_name(pp, name)
  if id == 0 {
    return
  }
  let param_id = macro_id_from_name(pp, "x")
  let lexeme_id = lexeme_pool_intern(pp.lexeme_pool, "0")
  let replacement = [make_builtin_token(IntLit, lexeme_id=lexeme_id)]
  set_macro(pp, id, {
    params: [param_id],
    is_variadic: true,
    is_function: true,
    replacement,
    replacement_has_id: tokens_have_id(replacement),
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  })
}

///|
fn define_func_macro_empty(pp : Preprocessor, name : String) -> Unit {
  let id = macro_id_from_name(pp, name)
  if id == 0 {
    return
  }
  let param_id = macro_id_from_name(pp, "x")
  let replacement : Array[Token] = []
  set_macro(pp, id, {
    params: [param_id],
    is_variadic: true,
    is_function: true,
    replacement,
    replacement_has_id: false,
    replacement_needs_expand: false,
    replacement_needs_epoch: -1,
  })
}

///|
fn init_builtin_macros(pp : Preprocessor) -> Unit {
  define_int_macro(pp, "__APPLE__", 1)
  define_int_macro(pp, "__MACH__", 1)
  define_int_macro(pp, "__aarch64__", 1)
  define_int_macro(pp, "__arm64__", 1)
  define_int_macro(pp, "__LP64__", 1)
  define_int_macro(pp, "__TINYC__", 928)

  define_macro(pp, "__ORDER_LITTLE_ENDIAN__", [
    make_builtin_token(
      IntLit,
      lexeme_id=lexeme_pool_intern(pp.lexeme_pool, "1234"),
    ),
  ])
  define_macro(pp, "__ORDER_BIG_ENDIAN__", [
    make_builtin_token(
      IntLit,
      lexeme_id=lexeme_pool_intern(pp.lexeme_pool, "4321"),
    ),
  ])
  define_macro(pp, "__ORDER_PDP_ENDIAN__", [
    make_builtin_token(
      IntLit,
      lexeme_id=lexeme_pool_intern(pp.lexeme_pool, "3412"),
    ),
  ])
  define_macro(pp, "__BYTE_ORDER__", [
    make_builtin_word_token(pp, "__ORDER_LITTLE_ENDIAN__"),
  ])
  define_int_macro(pp, "__LITTLE_ENDIAN__", 1)

  define_words_macro(pp, "__SIZE_TYPE__", ["unsigned", "long"])
  define_words_macro(pp, "__PTRDIFF_TYPE__", ["long"])
  define_words_macro(pp, "__INTMAX_TYPE__", ["long", "int"])
  define_words_macro(pp, "__UINTMAX_TYPE__", ["long", "unsigned", "int"])
  define_words_macro(pp, "__INTPTR_TYPE__", ["long"])
  define_words_macro(pp, "__UINTPTR_TYPE__", ["unsigned", "long"])
  define_words_macro(pp, "__INT8_TYPE__", ["signed", "char"])
  define_words_macro(pp, "__UINT8_TYPE__", ["unsigned", "char"])
  define_words_macro(pp, "__INT16_TYPE__", ["short"])
  define_words_macro(pp, "__UINT16_TYPE__", ["unsigned", "short"])
  define_words_macro(pp, "__INT32_TYPE__", ["int"])
  define_words_macro(pp, "__UINT32_TYPE__", ["unsigned", "int"])
  define_words_macro(pp, "__INT64_TYPE__", ["long", "long"])
  define_words_macro(pp, "__UINT64_TYPE__", ["unsigned", "long", "long"])
  define_words_macro(pp, "__int128_t", ["long", "double"])
  define_words_macro(pp, "__uint128_t", ["long", "double"])

  define_int_macro(pp, "__CHAR_BIT__", 8)
  if @util.char_is_unsigned {
    define_int_macro(pp, "__CHAR_UNSIGNED__", 1)
  }
  define_int_macro(pp, "__SIZEOF_POINTER__", 8)
  define_int_macro(pp, "__SIZEOF_LONG__", 8)
  define_int_macro(pp, "__SIZEOF_LONG_LONG__", 8)
  define_int_macro(pp, "__SIZEOF_INT__", 4)
  define_int_macro(pp, "__SIZEOF_SHORT__", 2)
  define_int_macro(pp, "__SIZEOF_SIZE_T__", 8)
  define_int_macro(pp, "__SIZEOF_PTRDIFF_T__", 8)
  define_int_macro(pp, "__SIZEOF_WCHAR_T__", 4)
  define_int_macro(pp, "__SIZEOF_WINT_T__", 4)

  define_words_macro(pp, "__WCHAR_TYPE__", ["int"])
  define_words_macro(pp, "__WINT_TYPE__", ["int"])

  define_int_macro(pp, "__STDC__", 1)
  define_int_macro(pp, "__STDC_HOSTED__", 1)
  define_macro(pp, "__STDC_VERSION__", [
    make_builtin_token(
      IntLit,
      lexeme_id=lexeme_pool_intern(pp.lexeme_pool, "201112"),
    ),
  ])

  define_int_macro(pp, "__GNUC__", 4)
  define_int_macro(pp, "__GNUC_MINOR__", 2)
  define_int_macro(pp, "__GNUC_PATCHLEVEL__", 1)
  define_int_macro(pp, "__GNUC_STDC_INLINE__", 1)
  define_int_macro(pp, "__APPLE_CC__", 1)
  define_int_macro(pp, "__FINITE_MATH_ONLY__", 1)
  define_int_macro(pp, "_DONT_USE_CTYPE_INLINE_", 1)
  define_int_macro(pp, "_FORTIFY_SOURCE", 0)
  define_words_macro(pp, "_Float16", ["short", "unsigned", "int"])

  define_func_macro_zero(pp, "__has_builtin")
  define_func_macro_zero(pp, "__has_feature")
  define_func_macro_zero(pp, "__has_extension")
  define_func_macro_zero(pp, "__has_attribute")
  define_func_macro_zero(pp, "__has_include")
  define_func_macro_zero(pp, "__has_include_next")
  define_func_macro_empty(pp, "__API_AVAILABLE")
  define_func_macro_empty(pp, "__API_AVAILABLE_BEGIN")
  define_func_macro_empty(pp, "__API_AVAILABLE_END")
  define_func_macro_empty(pp, "__API_DEPRECATED")
  define_func_macro_empty(pp, "__API_DEPRECATED_WITH_REPLACEMENT")
  define_func_macro_empty(pp, "__API_UNAVAILABLE")
  define_func_macro_empty(pp, "__API_UNAVAILABLE_BEGIN")
  define_func_macro_empty(pp, "__API_UNAVAILABLE_END")
  define_func_macro_empty(pp, "API_AVAILABLE")
  define_func_macro_empty(pp, "API_AVAILABLE_BEGIN")
  define_func_macro_empty(pp, "API_AVAILABLE_END")
  define_func_macro_empty(pp, "API_UNAVAILABLE")
  define_func_macro_empty(pp, "API_UNAVAILABLE_BEGIN")
  define_func_macro_empty(pp, "API_UNAVAILABLE_END")
  define_func_macro_empty(pp, "API_DEPRECATED")
}

///|
fn new_preprocessor(map : @source.SourceMap, file : @source.SourceFile, diags : @diag.DiagBag) ->
  Preprocessor {
  let (date_literal, time_literal) = init_datetime_literals()
  let text_len = file.text.length()
  let mut interner_capacity = text_len / 128
  if interner_capacity < 4096 {
    interner_capacity = 4096
  } else if interner_capacity > 65536 {
    interner_capacity = 65536
  }
  let lexeme_capacity = interner_capacity
  let mut pending_capacity = text_len / 64
  if pending_capacity < 256 {
    pending_capacity = 256
  } else if pending_capacity > 8192 {
    pending_capacity = 8192
  }
  let include_stack_capacity = 16
  let cond_capacity = 64
  let interner = @intern.new_string_interner_with_capacity(capacity=interner_capacity)
  let keyword_ids = init_keyword_ids(interner)
  let (_, line_macro_id) = interner.intern_view_with_id("__LINE__"[:])
  let (_, file_macro_id) = interner.intern_view_with_id("__FILE__"[:])
  let (_, date_macro_id) = interner.intern_view_with_id("__DATE__"[:])
  let (_, time_macro_id) = interner.intern_view_with_id("__TIME__"[:])
  let (_, defined_id) = interner.intern_view_with_id("defined"[:])
  let (_, has_include_id) = interner.intern_view_with_id("__has_include"[:])
  let (_, has_include_next_id) =
    interner.intern_view_with_id("__has_include_next"[:])
  let (_, dir_define_id) = interner.intern_view_with_id("define"[:])
  let (_, dir_undef_id) = interner.intern_view_with_id("undef"[:])
  let (_, dir_if_id) = interner.intern_view_with_id("if"[:])
  let (_, dir_ifdef_id) = interner.intern_view_with_id("ifdef"[:])
  let (_, dir_ifndef_id) = interner.intern_view_with_id("ifndef"[:])
  let (_, dir_elif_id) = interner.intern_view_with_id("elif"[:])
  let (_, dir_else_id) = interner.intern_view_with_id("else"[:])
  let (_, dir_endif_id) = interner.intern_view_with_id("endif"[:])
  let (_, dir_include_id) = interner.intern_view_with_id("include"[:])
  let (_, dir_include_next_id) = interner.intern_view_with_id("include_next"[:])
  let (_, dir_line_id) = interner.intern_view_with_id("line"[:])
  let (_, dir_error_id) = interner.intern_view_with_id("error"[:])
  let (_, dir_warning_id) = interner.intern_view_with_id("warning"[:])
  let (_, dir_pragma_id) = interner.intern_view_with_id("pragma"[:])
  let lexeme_pool = new_lexeme_pool(capacity=lexeme_capacity)
  let pp = {
    lexer: new_lexer(file, diags, interner, keyword_ids, lexeme_pool),
    lexer_stack: Array::new(capacity=include_stack_capacity),
    held_stack: Array::new(capacity=include_stack_capacity),
    path_stack: Array::new(capacity=include_stack_capacity),
    dir_stack: Array::new(capacity=include_stack_capacity),
    current_path: file.path,
    current_dir: dir_name(file.path),
    logical_path: file.path,
    logical_path_stack: Array::new(capacity=include_stack_capacity),
    line_adjust: 0,
    line_adjust_stack: Array::new(capacity=include_stack_capacity),
    include_paths: Array::new(capacity=include_stack_capacity),
    diags,
    map,
    macros: [],
    macro_epoch: 0,
    pending: Array::new(capacity=pending_capacity),
    held: None,
    cond_stack: Array::new(capacity=cond_capacity),
    active: true,
    expanding: Array::new(capacity=cond_capacity),
    expanding_guards: Array::new(capacity=cond_capacity),
    date_literal,
    time_literal,
    interner,
    keyword_ids,
    lexeme_pool,
    hidden_pool: new_hidden_pool(),
    builtin_ids: {
      line_macro: line_macro_id,
      file_macro: file_macro_id,
      date_macro: date_macro_id,
      time_macro: time_macro_id,
      defined: defined_id,
      has_include: has_include_id,
      has_include_next: has_include_next_id,
      dir_define: dir_define_id,
      dir_undef: dir_undef_id,
      dir_if: dir_if_id,
      dir_ifdef: dir_ifdef_id,
      dir_ifndef: dir_ifndef_id,
      dir_elif: dir_elif_id,
      dir_else: dir_else_id,
      dir_endif: dir_endif_id,
      dir_include: dir_include_id,
      dir_include_next: dir_include_next_id,
      dir_line: dir_line_id,
      dir_error: dir_error_id,
      dir_warning: dir_warning_id,
      dir_pragma: dir_pragma_id,
    },
  }
  init_builtin_macros(pp)
  pp
}

///|
fn finalize_preprocessor(pp : Preprocessor) -> Unit {
  let dummy_file = @source.SourceFile::{
    id: pp.lexer.file_id,
    path: pp.current_path,
    text: "",
  }
  pp.lexer = new_lexer(dummy_file, pp.diags, pp.interner, pp.keyword_ids, pp.lexeme_pool)
  pp.lexer_stack.clear()
  pp.held_stack.clear()
  pp.path_stack.clear()
  pp.dir_stack.clear()
  pp.logical_path_stack.clear()
  pp.line_adjust_stack.clear()
  pp.include_paths.clear()
  pp.macros.clear()
  pp.macro_epoch = 0
  pp.pending.clear()
  pp.cond_stack.clear()
  pp.expanding.clear()
  pp.expanding_guards.clear()
  clear_hidden_pool(pp.hidden_pool)
  let mut i = 0
  while i < pp.map.files.length() {
    let file = pp.map.files[i]
    if file.text.length() > 0 {
      pp.map.files[i] = @source.SourceFile::{
        id: file.id,
        path: file.path,
        text: "",
      }
    }
    i = i + 1
  }
  pp.lexeme_pool.entries.clear()
  pp.interner.buckets.clear()
  pp.interner.next_by_id.clear()
  pp.interner.strings.clear()
  pp.interner.views.clear()
  pp.interner.hashes.clear()
}

///|
fn current_active(pp : Preprocessor) -> Bool {
  pp.active
}

///|
fn add_pp_error(pp : Preprocessor, loc : @source.SrcLoc, message : String) -> Unit {
  @diag.add_error(pp.diags, loc, message)
}

///|
///|
fn is_macro_name_token(tok : Token) -> Bool {
  token_id(tok) > 0
}

///|
fn macro_id_from_name(pp : Preprocessor, name : String) -> Int {
  if name == "" {
    return 0
  }
  let (_, id) = pp.interner.intern_view_with_id(name[:])
  id
}

///|
fn macro_id_from_token(_pp : Preprocessor, tok : Token) -> Int {
  token_id(tok)
}

///|
fn ensure_macro_capacity(pp : Preprocessor, id : Int) -> Unit {
  if id <= 0 {
    return
  }
  let len = pp.macros.length()
  if len >= id {
    return
  }
  let mut i = len
  while i < id {
    pp.macros.push(None)
    i = i + 1
  }
}

///|
fn get_macro(pp : Preprocessor, id : Int) -> Macro? {
  if id <= 0 {
    return None
  }
  let len = pp.macros.length()
  if id <= len {
    pp.macros[id - 1]
  } else {
    None
  }
}

///|
fn has_macro(pp : Preprocessor, id : Int) -> Bool {
  get_macro(pp, id) is Some(_)
}

///|
fn set_macro(pp : Preprocessor, id : Int, macro_def : Macro) -> Unit {
  ensure_macro_capacity(pp, id)
  if id > 0 {
    pp.macros[id - 1] = Some(macro_def)
    pp.macro_epoch = pp.macro_epoch + 1
  }
}

///|
fn remove_macro(pp : Preprocessor, id : Int) -> Unit {
  if id <= 0 {
    return
  }
  let len = pp.macros.length()
  if id <= len {
    pp.macros[id - 1] = None
    pp.macro_epoch = pp.macro_epoch + 1
  }
}

///|
fn next_input_token(pp : Preprocessor) -> Token {
  while true {
    match pp.held {
      Some(tok) => {
        pp.held = None
        return tok
      }
      None => {
        let tok = next_token(pp.lexer)
        match tok.kind {
          Eof if pp.lexer_stack.length() > 0 => {
            if pp.lexer_stack.pop() is Some(prev) {
              pp.lexer = prev
            }
            if pp.held_stack.pop() is Some(prev_held) {
              pp.held = prev_held
            }
            if pp.path_stack.pop() is Some(prev_path) {
              pp.current_path = prev_path
            }
            if pp.dir_stack.pop() is Some(prev_dir) {
              pp.current_dir = prev_dir
            }
            if pp.logical_path_stack.pop() is Some(prev_path) {
              pp.logical_path = prev_path
            }
            if pp.line_adjust_stack.pop() is Some(prev_adjust) {
              pp.line_adjust = prev_adjust
            }
            continue
          }
          _ => return tok
        }
      }
    }
  } else {
    {
      kind: Eof,
      value: 0,
      loc: lexer_loc(pp.lexer),
      line_start: false,
      hidden: empty_hidden,
    }
  }
}

///|
fn read_directive_tokens(pp : Preprocessor) -> Array[Token] {
  let out : Array[Token] = []
  while true {
    let tok = next_input_token(pp)
    match tok.kind {
      Eof => {
        pp.held = Some(tok)
        break
      }
      _ => {
        if tok.line_start {
          pp.held = Some(tok)
          break
        }
        out.push(tok)
      }
    }
  }
  out
}

///|
fn read_directive_head_token(pp : Preprocessor) -> Token? {
  let tok = next_input_token(pp)
  match tok.kind {
    Eof => {
      pp.held = Some(tok)
      None
    }
    _ =>
      if tok.line_start {
        pp.held = Some(tok)
        None
      } else {
        Some(tok)
      }
  }
}

///|
fn skip_directive_line(pp : Preprocessor) -> Unit {
  while true {
    match peek_char(pp.lexer) {
      None => return
      Some(code) => {
        if code == 92 && peek_char_offset(pp.lexer, 1) is Some(10) {
          let _ = advance(pp.lexer)
          let _ = advance(pp.lexer)
          continue
        }
        let _ = advance(pp.lexer)
        if code == 10 {
          return
        }
      }
    }
  }
}

///|
fn skip_inactive(pp : Preprocessor) -> Unit {
  let lex = pp.lexer
  let text = lex.text
  let len = lex.text_len
  while lex.index < len {
    let idx = lex.index
    let code = text[idx]
    if lex.line_start {
      if is_ws_no_newline(code) {
        lex.index = idx + 1
        lex.col = lex.col + 1
        continue
      }
      if code == 10 {
        lex.index = idx + 1
        lex.line = lex.line + 1
        lex.col = 1
        lex.line_start = true
        continue
      }
      if code == 92 && idx + 1 < len && text[idx + 1] == 10 {
        lex.index = idx + 2
        lex.line = lex.line + 1
        lex.col = 1
        lex.line_start = false
        continue
      }
      if code == 47 && idx + 1 < len {
        let next_code = text[idx + 1]
        if next_code == 47 {
          lex.index = idx + 2
          lex.col = lex.col + 2
          skip_line_comment(lex)
          continue
        }
        if next_code == 42 {
          let start_loc = lexer_loc(lex)
          lex.index = idx + 2
          lex.col = lex.col + 2
          skip_block_comment(lex, start_loc)
          continue
        }
      }
      if code == 35 {
        return
      }
    }
    if code == 10 {
      lex.index = idx + 1
      lex.line = lex.line + 1
      lex.col = 1
      lex.line_start = true
      continue
    }
    if code == 92 && idx + 1 < len && text[idx + 1] == 10 {
      lex.index = idx + 2
      lex.line = lex.line + 1
      lex.col = 1
      lex.line_start = false
      continue
    }
    if code == 47 && idx + 1 < len {
      let next_code = text[idx + 1]
      if next_code == 47 {
        lex.index = idx + 2
        lex.col = lex.col + 2
        skip_line_comment(lex)
        continue
      }
      if next_code == 42 {
        let start_loc = lexer_loc(lex)
        lex.index = idx + 2
        lex.col = lex.col + 2
        skip_block_comment(lex, start_loc)
        continue
      }
    }
    if code == 34 || code == 39 {
      let start_loc = lexer_loc(lex)
      skip_string_literal(lex, start_loc, code)
      continue
    }
    lex.index = idx + 1
    lex.col = lex.col + 1
    lex.line_start = false
  }
}

///|
fn read_directive_text(pp : Preprocessor) -> String {
  let sb = StringBuilder::new()
  let mut saw_non_ws = false
  while true {
    match peek_char(pp.lexer) {
      None => return sb.to_string()
      Some(code) => {
        if code == 92 && peek_char_offset(pp.lexer, 1) is Some(10) {
          let _ = advance(pp.lexer)
          let _ = advance(pp.lexer)
          continue
        }
        if code == 10 {
          let _ = advance(pp.lexer)
          return sb.to_string()
        }
        if !saw_non_ws && is_ws_no_newline(code) {
          let _ = advance(pp.lexer)
          continue
        }
        saw_non_ws = true
        sb.write_char(code.unsafe_to_char())
        let _ = advance(pp.lexer)
      }
    }
  }
  sb.to_string()
}

///|
fn slice_tokens(tokens : Array[Token], start : Int) -> Array[Token] {
  if start <= 0 {
    return tokens
  }
  if start >= tokens.length() {
    return []
  }
  tokens[start:tokens.length()].to_array()
}

///|
fn prefix_tokens(tokens : Array[Token], end : Int) -> Array[Token] {
  if end <= 0 {
    return []
  }
  let total_len = tokens.length()
  let capacity = if total_len > end { total_len } else { end }
  let out : Array[Token] = Array::new(capacity=capacity)
  let mut i = 0
  while i < end {
    out.push(tokens[i])
    i = i + 1
  }
  out
}

///|
fn slice_string(text : String, start : Int, end : Int) -> String {
  text.view(start_offset=start, end_offset=end).to_string()
}

///|
fn dir_name(path : String) -> String {
  match path.rev_find("/") {
    None => ""
    Some(idx) => slice_string(path, 0, idx)
  }
}

///|
fn join_path(base : String, name : String) -> String {
  if base == "" {
    return name
  }
  if base.has_suffix("/") {
    base + name
  } else {
    base + "/" + name
  }
}

///|
fn add_include_path(pp : Preprocessor, path : String) -> Unit {
  pp.include_paths.push(path)
}

///|
fn strip_quotes(lexeme : String) -> String {
  let len = lexeme.length()
  if len >= 2 && lexeme[0] == 34 && lexeme[len - 1] == 34 {
    return slice_string(lexeme, 1, len - 1)
  }
  lexeme
}

///|
fn parse_include_path(
  pp : Preprocessor,
  args : Array[Token],
  loc : @source.SrcLoc,
) -> IncludeSpec? {
  if args.length() == 0 {
    add_pp_error(pp, loc, "missing include path")
    return None
  }
  if args[0].kind == StrLit {
    return Some({
      path: strip_quotes(pp_token_lexeme(pp, args[0])),
      is_angle: false,
    })
  }
  if args[0].kind == Lt {
    let sb = StringBuilder::new()
    let mut i = 1
    while i < args.length() {
      if args[i].kind == Gt {
        return Some({ path: sb.to_string(), is_angle: true })
      }
      sb.write_string(pp_token_lexeme(pp, args[i]))
      i = i + 1
    }
    add_pp_error(pp, loc, "unterminated include path")
    return None
  }
  add_pp_error(pp, loc, "invalid include path")
  None
}

///|
fn parse_has_include_path(pp : Preprocessor, args : Array[Token]) -> IncludeSpec? {
  if args.length() == 0 {
    return None
  }
  if args[0].kind == StrLit {
    return Some({
      path: strip_quotes(pp_token_lexeme(pp, args[0])),
      is_angle: false,
    })
  }
  if args[0].kind == Lt {
    let sb = StringBuilder::new()
    let mut i = 1
    while i < args.length() {
      if args[i].kind == Gt {
        return Some({ path: sb.to_string(), is_angle: true })
      }
      sb.write_string(pp_token_lexeme(pp, args[i]))
      i = i + 1
    }
  }
  None
}

///|
fn eval_has_include(
  pp : Preprocessor,
  args : Array[Token],
  include_next~ : Bool,
) -> Int {
  match parse_has_include_path(pp, args) {
    None => 0
    Some(spec) =>
      match resolve_include_path(pp, spec.path, spec.is_angle, include_next~) {
        None => 0
        Some(_) => 1
      }
  }
}

///|
fn resolve_include_path(
  pp : Preprocessor,
  path : String,
  is_angle : Bool,
  include_next~ : Bool,
) -> String? {
  if path.has_prefix("/") {
    return Some(path)
  }
  let mut skip_first = include_next
  if !is_angle {
    if skip_first {
      skip_first = false
    } else {
      let candidate = join_path(pp.current_dir, path)
      if @fs.path_exists(candidate) {
        return Some(candidate)
      }
    }
  }
  for p in pp.include_paths {
    if skip_first {
      skip_first = false
      continue
    }
    let candidate = join_path(p, path)
    if @fs.path_exists(candidate) {
      return Some(candidate)
    }
  }
  None
}

///|
fn include_file(
  pp : Preprocessor,
  spec : IncludeSpec,
  loc : @source.SrcLoc,
  include_next~ : Bool,
) -> Unit {
  match resolve_include_path(pp, spec.path, spec.is_angle, include_next~) {
    None => add_pp_error(pp, loc, "include not found: \{spec.path}")
    Some(resolved) =>
      try @fs.read_file_to_string(resolved) catch {
        err =>
          add_pp_error(pp, loc, "failed to read include: \{err.to_string()}")
      } noraise {
        text => {
          let file = @source.add_file(pp.map, resolved, text)
          pp.lexer_stack.push(pp.lexer)
          pp.held_stack.push(pp.held)
          pp.held = None
          pp.path_stack.push(pp.current_path)
          pp.dir_stack.push(pp.current_dir)
          pp.logical_path_stack.push(pp.logical_path)
          pp.line_adjust_stack.push(pp.line_adjust)
          pp.lexer = new_lexer(
            file,
            pp.diags,
            pp.interner,
            pp.keyword_ids,
            pp.lexeme_pool,
          )
          pp.current_path = resolved
          pp.current_dir = dir_name(resolved)
          pp.logical_path = resolved
          pp.line_adjust = 0
        }
      }
  }
}

///|
fn parse_define_macro(
  pp : Preprocessor,
  name_tok : Token,
  args : Array[Token],
  loc : @source.SrcLoc,
) -> Macro? {
  let is_function_like = args.length() > 0 &&
    args[0].kind == LParen &&
    is_adjacent(pp, name_tok, args[0])
  if is_function_like {
    match parse_macro_params(pp, args, loc) {
      None => None
      Some((params, is_variadic, replacement)) => {
        let normalized = normalize_macro_tokens(replacement)
        Some({
          params,
          is_variadic,
          is_function: true,
          replacement: normalized,
          replacement_has_id: tokens_have_id(normalized),
          replacement_needs_expand: false,
          replacement_needs_epoch: -1,
        })
      }
    }
  } else {
    let normalized = normalize_macro_tokens(args)
    Some({
      params: [],
      is_variadic: false,
      is_function: false,
      replacement: normalized,
      replacement_has_id: tokens_have_id(normalized),
      replacement_needs_expand: false,
      replacement_needs_epoch: -1,
    })
  }
}

///|
fn parse_macro_params(
  pp : Preprocessor,
  args : Array[Token],
  loc : @source.SrcLoc,
) -> (Array[Int], Bool, Array[Token])? {
  let params : Array[Int] = []
  let mut i = 1
  let mut is_variadic = false
  while i < args.length() {
    let tok = args[i]
    match tok.kind {
      RParen => {
        i = i + 1
        let replacement = slice_tokens(args, i)
        return Some((params, is_variadic, replacement))
      }
      Ellipsis => {
        is_variadic = true
        let varargs_id = macro_id_from_name(pp, "__VA_ARGS__")
        params.push(varargs_id)
        i = i + 1
        continue
      }
      Ident => {
        let param_id = macro_id_from_token(pp, tok)
        if param_id == 0 {
          add_pp_error(pp, loc, "invalid macro parameter")
          return None
        }
        params.push(param_id)
        i = i + 1
        if i < args.length() {
          match args[i].kind {
            Comma => {
              i = i + 1
              if i < args.length() {
                match args[i].kind {
                  Ellipsis => {
                    is_variadic = true
                    let varargs_id = macro_id_from_name(pp, "__VA_ARGS__")
                    params.push(varargs_id)
                    i = i + 1
                  }
                  _ => ()
                }
              }
              continue
            }
            _ => ()
          }
        }
      }
      _ => {
        add_pp_error(pp, loc, "invalid macro parameter")
        return None
      }
    }
  }
  add_pp_error(pp, loc, "unterminated macro parameter list")
  None
}

///|
fn next_raw_token(pp : Preprocessor) -> Token {
  if pp.pending.length() > 0 {
    if pp.pending.pop() is Some(tok) {
      release_expanding_guards(pp)
      return tok
    }
  }
  next_input_token(pp)
}

///|
fn push_back(pp : Preprocessor, tok : Token) -> Unit {
  pp.pending.push(tok)
}

///|
fn read_macro_args(pp : Preprocessor, loc : @source.SrcLoc) -> Array[Array[Token]]? {
  let args : Array[Array[Token]] = []
  let mut current : Array[Token] = []
  let mut depth_paren = 0
  let mut depth_brace = 0
  let mut depth_bracket = 0
  while true {
    let tok = next_raw_token(pp)
    match tok.kind {
      Eof => {
        add_pp_error(pp, loc, "unterminated macro invocation")
        return None
      }
      LParen => {
        depth_paren = depth_paren + 1
        current.push(tok)
        continue
      }
      RParen => {
        if depth_paren == 0 && depth_brace == 0 && depth_bracket == 0 {
          if current.length() > 0 || args.length() > 0 {
            args.push(current)
          }
          return Some(args)
        }
        depth_paren = depth_paren - 1
        current.push(tok)
        continue
      }
      LBrace => {
        depth_brace = depth_brace + 1
        current.push(tok)
        continue
      }
      RBrace => {
        if depth_brace > 0 {
          depth_brace = depth_brace - 1
        }
        current.push(tok)
        continue
      }
      LBracket => {
        depth_bracket = depth_bracket + 1
        current.push(tok)
        continue
      }
      RBracket => {
        if depth_bracket > 0 {
          depth_bracket = depth_bracket - 1
        }
        current.push(tok)
        continue
      }
      Comma =>
        if depth_paren == 0 && depth_brace == 0 && depth_bracket == 0 {
          args.push(current)
          current = []
          continue
        } else {
          current.push(tok)
        }
      _ => current.push(tok)
    }
  }
  None
}

///|
fn normalize_macro_args(
  macro_def : Macro,
  args : Array[Array[Token]],
  loc : @source.SrcLoc,
) -> Array[Array[Token]]? {
  if !macro_def.is_function {
    return Some(args)
  }
  let param_count = macro_def.params.length()
  if macro_def.is_variadic {
    if args.length() < param_count - 1 {
      return None
    }
    let out : Array[Array[Token]] = []
    for i = 0; i < param_count - 1; i = i + 1 {
      out.push(args[i])
    }
    let var_tokens : Array[Token] = []
    for i = param_count - 1; i < args.length(); i = i + 1 {
      if var_tokens.length() > 0 {
        var_tokens.push(
          {
            kind: Comma,
            value: 0,
            loc,
            line_start: false,
            hidden: empty_hidden,
          },
        )
      }
      for t in args[i] {
        var_tokens.push(t)
      }
    }
    out.push(var_tokens)
    return Some(out)
  }
  if args.length() != param_count {
    return None
  }
  Some(args)
}

///|
fn is_adjacent(pp : Preprocessor, left : Token, right : Token) -> Bool {
  left.loc.file_id == right.loc.file_id &&
  right.loc.offset == left.loc.offset + pp_token_lexeme_len(pp, left)
}

///|
fn is_expanding(pp : Preprocessor, id : Int) -> Bool {
  for n in pp.expanding {
    if n == id {
      return true
    }
  }
  false
}

///|
fn push_expanding(pp : Preprocessor, id : Int) -> Unit {
  pp.expanding.push(id)
}

///|
fn pop_expanding(pp : Preprocessor) -> Unit {
  ignore(pp.expanding.pop())
}

///|
fn stringize_tokens(pp : Preprocessor, tokens : Array[Token]) -> String {
  if tokens.length() == 0 {
    return ""
  }
  if tokens.length() == 1 {
    return pp_token_lexeme(pp, tokens[0])
  }
  let mut size_hint = 0
  for tok in tokens {
    size_hint = size_hint + pp_token_lexeme_len(pp, tok) + 1
  }
  if size_hint > 0 {
    size_hint = size_hint - 1
  }
  let sb = StringBuilder::new(size_hint=size_hint)
  let mut first = true
  let mut prev : Token? = None
  for tok in tokens {
    if first {
      first = false
    } else {
      match prev {
        Some(prev_tok) => {
          if !is_adjacent(pp, prev_tok, tok) {
            sb.write_char(' ')
          }
        }
        None => sb.write_char(' ')
      }
    }
    sb.write_string(pp_token_lexeme(pp, tok))
    prev = Some(tok)
  }
  sb.to_string()
}

///|
fn make_string_literal(pp : Preprocessor, text : String, loc : @source.SrcLoc) -> Token {
  let escaped = escape_string(text)
  let lexeme_id = lexeme_pool_intern(pp.lexeme_pool, "\"" + escaped + "\"")
  let token_value = token_value_from_parts(0, lexeme_id)
  {
    kind: StrLit,
    value: token_value,
    loc,
    line_start: false,
    hidden: empty_hidden,
  }
}

///|
fn escape_string(text : String) -> String {
  let len = text.length()
  let mut i = 0
  while i < len {
    let code = text[i]
    if code == 92 || code == 34 {
      break
    }
    i = i + 1
  }
  if i == len {
    return text
  }
  let sb = StringBuilder::new(size_hint=len)
  let mut j = 0
  while j < len {
    let code = text[j]
    if code == 92 {
      sb.write_string("\\\\")
    } else if code == 34 {
      sb.write_string("\\\"")
    } else {
      sb.write_char(code.unsafe_to_char())
    }
    j = j + 1
  }
  sb.to_string()
}

///|
fn logical_line(pp : Preprocessor, loc : @source.SrcLoc) -> Int {
  loc.line + pp.line_adjust
}

///|
fn make_int_literal_token(pp : Preprocessor, value : Int, loc : @source.SrcLoc) -> Token {
  let lexeme_id = lexeme_pool_intern(pp.lexeme_pool, value.to_string())
  let token_value = token_value_from_parts(0, lexeme_id)
  {
    kind: IntLit,
    value: token_value,
    loc,
    line_start: false,
    hidden: empty_hidden,
  }
}

///|
fn builtin_macro_tokens(pp : Preprocessor, tok : Token) -> Array[Token]? {
  let id = token_id(tok)
  if id == pp.builtin_ids.line_macro {
    return Some([
      make_int_literal_token(pp, logical_line(pp, tok.loc), tok.loc),
    ])
  }
  if id == pp.builtin_ids.file_macro {
    let path = if pp.logical_path == "" {
      pp.current_path
    } else {
      pp.logical_path
    }
    return Some([make_string_literal(pp, path, tok.loc)])
  }
  if id == pp.builtin_ids.date_macro {
    return Some([make_string_literal(pp, pp.date_literal, tok.loc)])
  }
  if id == pp.builtin_ids.time_macro {
    return Some([make_string_literal(pp, pp.time_literal, tok.loc)])
  }
  None
}

///|
fn is_builtin_macro_id(pp : Preprocessor, id : Int) -> Bool {
  id == pp.builtin_ids.line_macro ||
  id == pp.builtin_ids.file_macro ||
  id == pp.builtin_ids.date_macro ||
  id == pp.builtin_ids.time_macro
}

///|
fn tokens_need_expansion(pp : Preprocessor, tokens : Array[Token]) -> Bool {
  for tok in tokens {
    if token_needs_expansion(pp, tok) {
      return true
    }
  }
  false
}

///|
fn token_needs_expansion(pp : Preprocessor, tok : Token) -> Bool {
  let id = token_id(tok)
  id > 0 && (is_builtin_macro_id(pp, id) || get_macro(pp, id) is Some(_))
}

///|
fn macro_replacement_needs_expand(
  pp : Preprocessor,
  macro_id : Int,
  macro_def : Macro,
) -> Bool {
  if !macro_def.replacement_has_id {
    return false
  }
  if macro_def.replacement_needs_epoch == pp.macro_epoch {
    return macro_def.replacement_needs_expand
  }
  let needs = tokens_need_expansion(pp, macro_def.replacement)
  if macro_id > 0 && macro_id <= pp.macros.length() {
    pp.macros[macro_id - 1] =
      Some({
        params: macro_def.params,
        is_variadic: macro_def.is_variadic,
        is_function: macro_def.is_function,
        replacement: macro_def.replacement,
        replacement_has_id: macro_def.replacement_has_id,
        replacement_needs_expand: needs,
        replacement_needs_epoch: pp.macro_epoch,
      })
  }
  needs
}

///|
fn tokens_have_id(tokens : Array[Token]) -> Bool {
  for tok in tokens {
    if token_has_id(tok) {
      return true
    }
  }
  false
}

///|
fn init_datetime_literals() -> (String, String) {
  let now_ms = @env.now()
  let now_sec = (now_ms / 1000UL).to_int().to_int64()
  try @time.unix(now_sec, zone=@time.utc_zone) catch {
    _ => ("Jan 01 1970", "00:00:00")
  } noraise {
    dt => (format_date(dt), format_time(dt))
  }
}

///|
fn format_date(dt : @time.ZonedDateTime) -> String {
  let month = month_name(dt.month())
  let day = pad2_space(dt.day())
  let year = dt.year().to_string()
  month + " " + day + " " + year
}

///|
fn format_time(dt : @time.ZonedDateTime) -> String {
  let hour = pad2(dt.hour())
  let minute = pad2(dt.minute())
  let second = pad2(dt.second())
  hour + ":" + minute + ":" + second
}

///|
fn month_name(month : Int) -> String {
  match month {
    1 => "Jan"
    2 => "Feb"
    3 => "Mar"
    4 => "Apr"
    5 => "May"
    6 => "Jun"
    7 => "Jul"
    8 => "Aug"
    9 => "Sep"
    10 => "Oct"
    11 => "Nov"
    12 => "Dec"
    _ => "Jan"
  }
}

///|
fn pad2(value : Int) -> String {
  if value < 10 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
fn pad2_space(value : Int) -> String {
  if value < 10 {
    " " + value.to_string()
  } else {
    value.to_string()
  }
}

///|
fn lookup_param_index(params : Array[Int], id : Int) -> Int? {
  for i = 0; i < params.length(); i = i + 1 {
    if params[i] == id {
      return Some(i)
    }
  }
  None
}

///|
fn lex_paste_tokens(
  pp : Preprocessor,
  text : String,
  left : String,
  right : String,
  loc : @source.SrcLoc,
  hidden : Int,
) -> Array[Token] {
  let file = @source.SourceFile::{ id: loc.file_id, path: ":paste:", text }
  let lex = new_lexer(
    file,
    pp.diags,
    pp.interner,
    pp.keyword_ids,
    pp.lexeme_pool,
  )
  let out : Array[Token] = []
  while true {
    let tok = next_token(lex)
    match tok.kind {
      Eof => break
      _ =>
        out.push({
          kind: tok.kind,
          value: tok.value,
          loc,
          line_start: false,
          hidden,
        })
    }
  }
  if out.length() > 1 {
    add_pp_error(
      pp,
      loc,
      "warning: pasting \"" + left +
      "\" and \"" + right +
      "\" does not give a valid preprocessing token",
    )
  }
  out
}

fn substitute_macro(
  pp : Preprocessor,
  macro_def : Macro,
  raw_args : Array[Array[Token]],
  loc : @source.SrcLoc,
) -> (Array[Token], Bool) {
  if !macro_def.is_function {
    return (macro_def.replacement, tokens_need_expansion(pp, macro_def.replacement))
  }
  let out : Array[Token] = Array::new(capacity=macro_def.replacement.length())
  let mut needs_expand = false
  let params = macro_def.params
  let expanded_cache : Array[Array[Token]?] = Array::make(raw_args.length(), None)
  let mut i = 0
  while i < macro_def.replacement.length() {
    let tok = macro_def.replacement[i]
    if tok.kind == Hash && i + 1 < macro_def.replacement.length() {
      let next_tok = macro_def.replacement[i + 1]
      if next_tok.kind == Ident {
        let param_id = token_id(next_tok)
        if param_id > 0 {
          if lookup_param_index(params, param_id) is Some(idx) {
            let arg_tokens = if idx < raw_args.length() {
              raw_args[idx]
            } else {
              []
            }
            let string_tok =
              make_string_literal(pp, stringize_tokens(pp, arg_tokens), loc)
            out.push(string_tok)
            if !needs_expand && token_needs_expansion(pp, string_tok) {
              needs_expand = true
            }
            i = i + 2
            continue
          }
        }
      }
    }
    if tok.kind == HashHash &&
      out.length() > 0 &&
      i + 1 < macro_def.replacement.length() {
      let last = match out.pop() {
        Some(value) => value
        None => {
          i = i + 1
          continue
        }
      }
      let mut next_tokens : Array[Token] = []
      let mut next_from_param = false
      let next_tok = macro_def.replacement[i + 1]
      if next_tok.kind == Ident {
        let param_id = token_id(next_tok)
        if param_id > 0 {
          match lookup_param_index(params, param_id) {
            Some(idx) => {
              next_tokens = if idx < raw_args.length() {
                raw_args[idx]
              } else {
                []
              }
              next_from_param = true
            }
            None => next_tokens = [next_tok]
          }
        } else {
          next_tokens = [next_tok]
        }
      } else {
        next_tokens = [next_tok]
      }
      if next_tokens.length() == 0 {
        out.push(last)
        i = i + 2
        continue
      }
      let last_text = pp_token_lexeme(pp, last)
      let next_text = pp_token_lexeme(pp, next_tokens[0])
      let merged_lexeme = last_text + next_text
      let merged_hidden =
        merge_hidden(pp.hidden_pool, last.hidden, next_tokens[0].hidden)
      let merged_tokens = lex_paste_tokens(
        pp,
        merged_lexeme,
        last_text,
        next_text,
        loc,
        merged_hidden,
      )
      for t in merged_tokens {
        out.push(t)
        if !needs_expand && token_needs_expansion(pp, t) {
          needs_expand = true
        }
      }
      if next_tokens.length() > 1 {
        for j = 1; j < next_tokens.length(); j = j + 1 {
          let t = next_tokens[j]
          if next_from_param {
            out.push(t)
          } else {
            out.push({
              kind: t.kind,
              value: t.value,
              loc,
              line_start: false,
              hidden: t.hidden,
            })
          }
          if !needs_expand && token_needs_expansion(pp, t) {
            needs_expand = true
          }
        }
      }
      i = i + 2
      continue
    }
    if tok.kind == Ident {
      let param_id = token_id(tok)
      if param_id > 0 {
        if lookup_param_index(params, param_id) is Some(idx) {
          let arg_tokens = ensure_expanded_arg(pp, raw_args, expanded_cache, idx)
          for t in arg_tokens {
            let out_tok = {
              kind: t.kind,
              value: t.value,
              loc: t.loc,
              line_start: false,
              hidden: t.hidden,
            }
            out.push(out_tok)
            if !needs_expand && token_needs_expansion(pp, out_tok) {
              needs_expand = true
            }
          }
          i = i + 1
          continue
        }
      }
    }
    let out_tok = {
      kind: tok.kind,
      value: tok.value,
      loc,
      line_start: false,
      hidden: tok.hidden,
    }
    out.push(out_tok)
    if !needs_expand && token_needs_expansion(pp, out_tok) {
      needs_expand = true
    }
    i = i + 1
  }
  (out, needs_expand)
}

///|
fn read_macro_args_from_tokens(
  pp : Preprocessor,
  tokens : Array[Token],
  start : Int,
  loc : @source.SrcLoc,
) -> (Array[Array[Token]], Int)? {
  let len = tokens.length()
  let args : Array[Array[Token]] = []
  let mut current : Array[Token] = []
  let mut depth_paren = 0
  let mut depth_brace = 0
  let mut depth_bracket = 0
  let mut i = start
  while i < len {
    let tok = tokens[i]
    if tok.kind == LParen {
      depth_paren = depth_paren + 1
      current.push(tok)
      i = i + 1
      continue
    }
    if tok.kind == RParen {
      if depth_paren == 0 && depth_brace == 0 && depth_bracket == 0 {
        if current.length() > 0 || args.length() > 0 {
          args.push(current)
        }
        return Some((args, i + 1))
      }
      depth_paren = depth_paren - 1
      current.push(tok)
      i = i + 1
      continue
    }
    if tok.kind == LBrace {
      depth_brace = depth_brace + 1
      current.push(tok)
      i = i + 1
      continue
    }
    if tok.kind == RBrace {
      if depth_brace > 0 {
        depth_brace = depth_brace - 1
      }
      current.push(tok)
      i = i + 1
      continue
    }
    if tok.kind == LBracket {
      depth_bracket = depth_bracket + 1
      current.push(tok)
      i = i + 1
      continue
    }
    if tok.kind == RBracket {
      if depth_bracket > 0 {
        depth_bracket = depth_bracket - 1
      }
      current.push(tok)
      i = i + 1
      continue
    }
    if tok.kind == Comma &&
      depth_paren == 0 &&
      depth_brace == 0 &&
      depth_bracket == 0 {
      args.push(current)
      current = []
      i = i + 1
      continue
    }
    current.push(tok)
    i = i + 1
  }
  add_pp_error(pp, loc, "unterminated macro invocation")
  None
}

///|
fn ensure_expanded_arg(
  pp : Preprocessor,
  raw_args : Array[Array[Token]],
  expanded_cache : Array[Array[Token]?],
  idx : Int,
) -> Array[Token] {
  if idx < 0 || idx >= raw_args.length() {
    return []
  }
  match expanded_cache[idx] {
    Some(tokens) => tokens
    None => {
      let expanded = expand_tokens(pp, raw_args[idx])
      expanded_cache[idx] = Some(expanded)
      expanded
    }
  }
}

///|
fn expand_tokens(pp : Preprocessor, tokens : Array[Token]) -> Array[Token] {
  let mut out_opt : Array[Token]? = None
  let mut changed = false
  let len = tokens.length()
  let mut i = 0
  while i < len {
    let tok = tokens[i]
    let macro_id = token_id(tok)
    let is_macro_name = macro_id > 0
    if is_macro_name {
      if builtin_macro_tokens(pp, tok) is Some(replacement) {
        let out = match out_opt {
          Some(arr) => arr
          None => {
            let arr = prefix_tokens(tokens, i)
            out_opt = Some(arr)
            arr
          }
        }
        for t in replacement {
          out.push(t)
        }
        changed = true
        i = i + 1
        continue
      }
    }
    let hidden_ok = !is_macro_name ||
      hidden_is_empty(tok.hidden) ||
      (macro_id != 0 && !hidden_contains(pp.hidden_pool, tok.hidden, macro_id))
    if is_macro_name && macro_id != 0 && hidden_ok {
      if get_macro(pp, macro_id) is Some(macro_def) {
          if is_expanding(pp, macro_id) {
            if out_opt is Some(arr) {
              arr.push(tok)
            }
            i = i + 1
            continue
          }
          if macro_def.is_function {
            if i + 1 < len && tokens[i + 1].kind == LParen {
              match read_macro_args_from_tokens(pp, tokens, i + 2, tok.loc) {
                None => {
                  if out_opt is Some(arr) {
                    arr.push(tok)
                  }
                  i = i + 1
                  continue
                }
                Some((raw_args, next_i)) =>
                  match normalize_macro_args(macro_def, raw_args, tok.loc) {
                    None => {
                      add_pp_error(pp, tok.loc, "macro argument count mismatch")
                      if out_opt is Some(arr) {
                        arr.push(tok)
                      }
                      i = next_i
                      continue
                    }
                    Some(norm_raw) => {
                      if token_id(tok) == pp.builtin_ids.has_include ||
                        token_id(tok) == pp.builtin_ids.has_include_next {
                        let include_next =
                          token_id(tok) == pp.builtin_ids.has_include_next
                        let arg_tokens = if norm_raw.length() > 0 {
                          expand_tokens(pp, norm_raw[0])
                        } else {
                          []
                        }
                        let value = eval_has_include(
                          pp,
                          arg_tokens,
                          include_next~,
                        )
                        let out = match out_opt {
                          Some(arr) => arr
                          None => {
                            let arr = prefix_tokens(tokens, i)
                            out_opt = Some(arr)
                            arr
                          }
                        }
                        out.push(make_int_literal_token(pp, value, tok.loc))
                        changed = true
                        i = next_i
                        continue
                      }
                      let (replaced, needs_expand) = substitute_macro(
                        pp,
                        macro_def,
                        norm_raw,
                        tok.loc,
                      )
                      let expanded = if needs_expand {
                        push_expanding(pp, macro_id)
                        let expanded =
                          add_hidden_tokens(pp, expand_tokens(pp, replaced), macro_id)
                        pop_expanding(pp)
                        expanded
                      } else {
                        replaced
                      }
                      let out = match out_opt {
                        Some(arr) => arr
                        None => {
                          let arr = prefix_tokens(tokens, i)
                          out_opt = Some(arr)
                          arr
                        }
                      }
                      for t in expanded {
                        out.push(t)
                      }
                      changed = true
                      i = next_i
                      continue
                    }
                  }
              }
            }
            if out_opt is Some(arr) {
              arr.push(tok)
            }
            i = i + 1
            continue
          } else {
            let expanded =
              if macro_replacement_needs_expand(pp, macro_id, macro_def) {
                push_expanding(pp, macro_id)
                let expanded = add_hidden_tokens(
                  pp,
                  expand_tokens(pp, macro_def.replacement),
                  macro_id,
                )
                pop_expanding(pp)
                expanded
              } else {
                macro_def.replacement
              }
            let out = match out_opt {
              Some(arr) => arr
              None => {
                let arr = prefix_tokens(tokens, i)
                out_opt = Some(arr)
                arr
              }
            }
            for t in expanded {
              out.push(t)
            }
            changed = true
            i = i + 1
            continue
          }
      }
    }
    if out_opt is Some(arr) {
      arr.push(tok)
    }
    i = i + 1
  }
  match out_opt {
    None => tokens
    Some(out) =>
      if changed && tokens_need_expansion(pp, out) {
        expand_tokens(pp, out)
      } else {
        out
      }
  }
}

///|
fn push_cond(pp : Preprocessor, cond : Bool) -> Unit {
  let parent = current_active(pp)
  let active = parent && cond
  pp.cond_stack.push({ parent_active: parent, taken: active, active })
  pp.active = active
}

///|
fn update_elif(pp : Preprocessor, cond : Bool, loc : @source.SrcLoc) -> Unit {
  if pp.cond_stack.length() == 0 {
    add_pp_error(pp, loc, "unexpected #elif without #if")
    return
  }
  let idx = pp.cond_stack.length() - 1
  let state = pp.cond_stack[idx]
  if !state.parent_active {
    state.active = false
  } else if state.taken {
    state.active = false
  } else {
    state.active = cond
    if cond {
      state.taken = true
    }
  }
  pp.cond_stack[idx] = state
  pp.active = state.active
}

///|
fn update_else(pp : Preprocessor, loc : @source.SrcLoc) -> Unit {
  if pp.cond_stack.length() == 0 {
    add_pp_error(pp, loc, "unexpected #else without #if")
    return
  }
  let idx = pp.cond_stack.length() - 1
  let state = pp.cond_stack[idx]
  if !state.parent_active {
    state.active = false
  } else if state.taken {
    state.active = false
  } else {
    state.active = true
    state.taken = true
  }
  pp.cond_stack[idx] = state
  pp.active = state.active
}

///|
fn pop_cond(pp : Preprocessor, loc : @source.SrcLoc) -> Unit {
  if pp.cond_stack.length() == 0 {
    add_pp_error(pp, loc, "unexpected #endif without #if")
    return
  }
  ignore(pp.cond_stack.pop())
  if pp.cond_stack.length() == 0 {
    pp.active = true
  } else {
    let idx = pp.cond_stack.length() - 1
    pp.active = pp.cond_stack[idx].active
  }
}

///|
fn normalize_macro_tokens(tokens : Array[Token]) -> Array[Token] {
  let mut needs_copy = false
  for tok in tokens {
    if tok.line_start {
      needs_copy = true
      break
    }
  }
  if !needs_copy {
    return tokens
  }
  let out : Array[Token] = Array::new(capacity=tokens.length())
  for tok in tokens {
    out.push({
      kind: tok.kind,
      value: tok.value,
      loc: tok.loc,
      line_start: false,
      hidden: tok.hidden,
    })
  }
  out
}

///|
fn expand_if_tokens(pp : Preprocessor, tokens : Array[Token]) -> Array[Token] {
  let mut has_defined = false
  for tok in tokens {
    if tok.kind == Ident && token_id(tok) == pp.builtin_ids.defined {
      has_defined = true
      break
    }
  }
  if !has_defined {
    return expand_tokens(pp, tokens)
  }
  let len = tokens.length()
  let out : Array[Token] = Array::new(capacity=len)
  let segment : Array[Token] = []
  let mut i = 0
  while i < len {
    let tok = tokens[i]
    if tok.kind == Ident && token_id(tok) == pp.builtin_ids.defined {
      if segment.length() > 0 {
        let expanded = expand_tokens(pp, segment)
        for t in expanded {
          out.push(t)
        }
        segment.clear()
      }
      out.push(tok)
      i = i + 1
      if i < len && tokens[i].kind == LParen {
        out.push(tokens[i])
        i = i + 1
        if i < len {
          out.push(tokens[i])
          i = i + 1
        }
        if i < len && tokens[i].kind == RParen {
          out.push(tokens[i])
          i = i + 1
        }
      } else if i < len {
        out.push(tokens[i])
        i = i + 1
      }
      continue
    }
    segment.push(tok)
    i = i + 1
  }
  if segment.length() > 0 {
    let expanded = expand_tokens(pp, segment)
    for t in expanded {
      out.push(t)
    }
  }
  out
}

///|
fn push_tokens(pp : Preprocessor, tokens : Array[Token]) -> Unit {
  let mut i = tokens.length()
  while i > 0 {
    i = i - 1
    pp.pending.push(tokens[i])
  }
}

///|
fn release_expanding_guards(pp : Preprocessor) -> Unit {
  while pp.expanding_guards.length() > 0 {
    let guard_restore = pp.expanding_guards[
      pp.expanding_guards.length() - 1
    ].restore_len
    if pp.pending.length() <= guard_restore {
      pop_expanding(pp)
      ignore(pp.expanding_guards.pop())
    } else {
      break
    }
  }
}

///|
fn hidden_is_empty(hidden : Int) -> Bool {
  hidden == 0
}

///|
fn hidden_contains(pool : HiddenPool, hidden : Int, id : Int) -> Bool {
  let mut cur = hidden
  while cur != 0 {
    let node = pool.nodes[cur - 1]
    if node.id == id {
      return true
    }
    cur = node.next
  }
  false
}

///|
fn ensure_hidden_singleton_slot(pool : HiddenPool, id : Int) -> Unit {
  while pool.singleton_by_id.length() < id {
    pool.singleton_by_id.push(0)
  }
}

///|
fn hidden_add(pool : HiddenPool, hidden : Int, id : Int) -> Int {
  if hidden_contains(pool, hidden, id) {
    return hidden
  }
  if hidden == 0 {
    ensure_hidden_singleton_slot(pool, id)
    let existing = pool.singleton_by_id[id - 1]
    if existing != 0 {
      return existing
    }
  }
  let node_id = pool.nodes.length() + 1
  pool.nodes.push({ id, next: hidden })
  if hidden == 0 {
    pool.singleton_by_id[id - 1] = node_id
  }
  node_id
}

///|
fn merge_hidden(pool : HiddenPool, a : Int, b : Int) -> Int {
  if hidden_is_empty(a) {
    return b
  }
  if hidden_is_empty(b) {
    return a
  }
  let mut out = a
  let mut cur = b
  while cur != 0 {
    let node = pool.nodes[cur - 1]
    out = hidden_add(pool, out, node.id)
    cur = node.next
  }
  out
}

///|
fn add_hidden(pp : Preprocessor, tok : Token, id : Int) -> Token {
  let new_hidden = hidden_add(pp.hidden_pool, tok.hidden, id)
  if new_hidden == tok.hidden {
    tok
  } else {
    {
      kind: tok.kind,
      value: tok.value,
      loc: tok.loc,
      line_start: tok.line_start,
      hidden: new_hidden,
    }
  }
}

///|
fn add_hidden_tokens(
  pp : Preprocessor,
  tokens : Array[Token],
  id : Int,
) -> Array[Token] {
  let out : Array[Token] = Array::new(capacity=tokens.length())
  for tok in tokens {
    out.push(add_hidden(pp, tok, id))
  }
  out
}

///|
fn handle_line_directive(
  pp : Preprocessor,
  tokens : Array[Token],
  loc : @source.SrcLoc,
) -> Unit {
  if tokens.length() == 0 {
    add_pp_error(pp, loc, "missing line number in #line")
    return
  }
  let line_tok = tokens[0]
  if line_tok.kind != IntLit {
    add_pp_error(pp, loc, "invalid line number in #line")
    return
  }
  let line_val = parse_line_int_literal(
    pp,
    pp_token_lexeme(pp, line_tok),
    line_tok.loc,
  )
  if line_val <= 0 {
    add_pp_error(pp, loc, "invalid line number in #line")
    return
  }
  pp.line_adjust = line_val - (loc.line + 1)
  if tokens.length() > 1 && tokens[1].kind == StrLit {
    pp.logical_path = strip_quotes(pp_token_lexeme(pp, tokens[1]))
  }
}

///|

///|
fn eval_if_expr(pp : Preprocessor, tokens : Array[Token], loc : @source.SrcLoc) -> Bool {
  if tokens.length() == 0 {
    add_pp_error(pp, loc, "empty #if expression")
    return false
  }
  let parser = { tokens, index: 0, pp }
  let value = parse_logical_or(parser, loc)
  !pp_is_zero(value)
}

///|
struct IfParser {
  tokens : Array[Token]
  mut index : Int
  pp : Preprocessor
}

///|
struct PpValue {
  value : UInt64
  is_unsigned : Bool
}

///|
fn pp_bool_value(cond : Bool) -> PpValue {
  { value: if cond { 1 } else { 0 }, is_unsigned: false }
}

///|
fn pp_is_zero(v : PpValue) -> Bool {
  v.value == 0
}

///|
fn pp_unsigned_result(a : PpValue, b : PpValue) -> Bool {
  a.is_unsigned || b.is_unsigned
}

///|
fn pp_shift_count(v : PpValue) -> Int {
  (v.value & (63 : UInt64)).to_int()
}

///|
fn peek_if(p : IfParser) -> Token? {
  if p.index >= p.tokens.length() {
    return None
  }
  Some(p.tokens[p.index])
}

///|
fn advance_if(p : IfParser) -> Token? {
  match peek_if(p) {
    None => None
    Some(tok) => {
      p.index = p.index + 1
      Some(tok)
    }
  }
}

///|
fn match_kind(p : IfParser, kind : TokenKind) -> Bool {
  match peek_if(p) {
    Some(tok) if tok.kind == kind => {
      p.index = p.index + 1
      true
    }
    _ => false
  }
}

///|
fn parse_line_int_literal(pp : Preprocessor, lexeme : String, loc : @source.SrcLoc) -> Int {
  let end = int_literal_end(lexeme)
  if end <= 0 {
    add_pp_error(pp, loc, "invalid integer in #line")
    return 0
  }
  if end < lexeme.length() {
    let suffix = slice_string(lexeme, end, lexeme.length())
    for ch in suffix {
      if ch != 'u' && ch != 'U' && ch != 'l' && ch != 'L' {
        add_pp_error(pp, loc, "invalid integer in #line")
        return 0
      }
    }
  }
  let trimmed = slice_string(lexeme, 0, end)
  let base = int_literal_base(lexeme)
  let value = parse_uint64_literal(trimmed, base)
  value.reinterpret_as_int64().to_int()
}

///|
fn parse_pp_int_literal(
  pp : Preprocessor,
  lexeme : String,
  loc : @source.SrcLoc,
) -> PpValue {
  let end = int_literal_end(lexeme)
  if end <= 0 {
    add_pp_error(pp, loc, "invalid integer in #if")
    return { value: 0, is_unsigned: false }
  }
  let suffix = if end < lexeme.length() {
    slice_string(lexeme, end, lexeme.length())
  } else {
    ""
  }
  for ch in suffix {
    if ch != 'u' && ch != 'U' && ch != 'l' && ch != 'L' {
      add_pp_error(pp, loc, "invalid integer in #if")
      return { value: 0, is_unsigned: false }
    }
  }
  let trimmed = slice_string(lexeme, 0, end)
  let base = int_literal_base(lexeme)
  let value = parse_uint64_literal(trimmed, base)
  let (_, unsigned_suffix) = parse_int_suffix(suffix)
  let max_signed : UInt64 = 0x7fffffffffffffff
  let is_unsigned = unsigned_suffix || value > max_signed
  { value, is_unsigned }
}

///|
fn parse_pp_char_literal(pp : Preprocessor, tok : Token) -> PpValue {
  let lexeme = pp_token_lexeme(pp, tok)
  if lexeme.length() < 3 {
    add_pp_error(pp, tok.loc, "invalid character literal in #if")
    return { value: 0, is_unsigned: false }
  }
  let len = lexeme.length()
  let mut value = 0
  let mut i = 1
  if i + 1 >= len {
    add_pp_error(pp, tok.loc, "invalid character literal in #if")
    return { value: 0, is_unsigned: false }
  }
  let code = lexeme[i]
  if code == 92 {
    let (esc, next_index) = decode_pp_escape_value(pp, lexeme, i + 1, tok.loc)
    value = esc
    i = next_index
  } else {
    value = code.to_int()
    i = i + 1
  }
  if i + 1 < len {
    add_pp_error(pp, tok.loc, "multi-character literal in #if")
  }
  { value: value.to_uint64(), is_unsigned: false }
}

///|
fn decode_pp_escape_value(
  pp : Preprocessor,
  text : String,
  start : Int,
  loc : @source.SrcLoc,
) -> (Int, Int) {
  if start >= text.length() {
    add_pp_error(pp, loc, "unterminated escape sequence in #if")
    return (0, start)
  }
  let code = text[start]
  match code {
    97 => (7, start + 1) // \a
    98 => (8, start + 1) // \b
    102 => (12, start + 1) // \f
    110 => (10, start + 1) // \n
    114 => (13, start + 1) // \r
    116 => (9, start + 1) // \t
    118 => (11, start + 1) // \v
    92 => (92, start + 1) // \\
    39 => (39, start + 1) // \'
    34 => (34, start + 1) // \"
    63 => (63, start + 1) // \?
    120 | 88 => parse_pp_hex_escape(pp, text, start + 1, loc) // \x
    _ =>
      if pp_is_oct_digit(code) {
        parse_pp_octal_escape(text, start)
      } else {
        (code.to_int(), start + 1)
      }
  }
}

///|
fn parse_pp_hex_escape(
  pp : Preprocessor,
  text : String,
  start : Int,
  loc : @source.SrcLoc,
) -> (Int, Int) {
  let mut i = start
  let mut value = 0
  let mut saw = false
  while i < text.length() {
    let code = text[i]
    let digit = pp_hex_digit_value(code)
    match digit {
      None => break
      Some(v) => {
        value = value * 16 + v
        saw = true
        i = i + 1
      }
    }
  }
  if !saw {
    add_pp_error(pp, loc, "invalid hex escape in #if")
  }
  (value, i)
}

///|
fn parse_pp_octal_escape(text : String, start : Int) -> (Int, Int) {
  let mut i = start
  let mut value = 0
  let mut count = 0
  while i < text.length() && count < 3 {
    let code = text[i]
    if !pp_is_oct_digit(code) {
      break
    }
    value = value * 8 + (code.to_int() - 48)
    i = i + 1
    count = count + 1
  }
  (value, i)
}

///|
fn pp_is_oct_digit(code : UInt16) -> Bool {
  code >= 48 && code <= 55
}

///|
fn pp_hex_digit_value(code : UInt16) -> Int? {
  if code >= 48 && code <= 57 {
    return Some(code.to_int() - 48)
  }
  if code >= 65 && code <= 70 {
    return Some(code.to_int() - 65 + 10)
  }
  if code >= 97 && code <= 102 {
    return Some(code.to_int() - 97 + 10)
  }
  None
}

///|
fn macro_int_value(
  pp : Preprocessor,
  tok : Token,
  loc : @source.SrcLoc,
) -> PpValue? {
  let id = macro_id_from_token(pp, tok)
  if id == 0 {
    return None
  }
  match get_macro(pp, id) {
    None => None
    Some(macro_def) => {
      if macro_def.is_function {
        return None
      }
      if macro_def.replacement.length() == 1 &&
        macro_def.replacement[0].kind == IntLit {
        return Some(parse_pp_int_literal(
          pp,
          pp_token_lexeme(pp, macro_def.replacement[0]),
          loc,
        ))
      }
      None
    }
  }
}

///|
fn parse_primary(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  match advance_if(p) {
    None => {
      add_pp_error(p.pp, loc, "unexpected end of #if expression")
      { value: 0, is_unsigned: false }
    }
    Some(tok) => {
      if tok.kind == RParen {
        p.index = p.index - 1
        return { value: 0, is_unsigned: false }
      }
      if tok.kind == IntLit {
        return parse_pp_int_literal(p.pp, pp_token_lexeme(p.pp, tok), tok.loc)
      }
      if tok.kind == CharLit {
        return parse_pp_char_literal(p.pp, tok)
      }
      if tok.kind == Ident {
        if token_id(tok) == p.pp.builtin_ids.defined {
          return parse_defined(p, loc)
        }
        match macro_int_value(p.pp, tok, tok.loc) {
          Some(v) => return v
          None => {
            if match_kind(p, LParen) {
              skip_paren_expr(p, tok.loc)
              return { value: 0, is_unsigned: false }
            }
            return { value: 0, is_unsigned: false }
          }
        }
      }
      if tok.kind == LParen {
        let value = parse_logical_or(p, loc)
        if !match_kind(p, RParen) {
          // try to resync to a later ')', but don't hard-fail
          let mut idx = p.index
          while idx < p.tokens.length() {
            match p.tokens[idx] {
              { kind: RParen, .. } => {
                idx = idx + 1
                break
              }
              _ => idx = idx + 1
            }
          }
          p.index = idx
        }
        return value
      }
      add_pp_error(p.pp, loc, "unexpected token in #if expression")
      { value: 0, is_unsigned: false }
    }
  }
}

///|
fn peek_is_rparen(p : IfParser) -> Bool {
  match peek_if(p) {
    Some(tok) if tok.kind == RParen => true
    _ => false
  }
}

///|
fn parse_defined(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  if match_kind(p, LParen) {
    match advance_if(p) {
      Some(tok) if is_macro_name_token(tok) => {
        if !match_kind(p, RParen) {
          add_pp_error(p.pp, loc, "missing ')' after defined")
        }
        return pp_bool_value(has_macro(p.pp, macro_id_from_token(p.pp, tok)))
      }
      _ => {
        add_pp_error(p.pp, loc, "expected identifier after defined(")
        return { value: 0, is_unsigned: false }
      }
    }
  }
  match advance_if(p) {
    Some(tok) if is_macro_name_token(tok) =>
      pp_bool_value(has_macro(p.pp, macro_id_from_token(p.pp, tok)))
    _ => {
      add_pp_error(p.pp, loc, "expected identifier after defined")
      { value: 0, is_unsigned: false }
    }
  }
}

///|
fn skip_paren_expr(p : IfParser, loc : @source.SrcLoc) -> Unit {
  let mut depth = 1
  while depth > 0 {
    match advance_if(p) {
      None => {
        add_pp_error(p.pp, loc, "missing ')' in #if expression")
        return
      }
      Some(tok) =>
        if tok.kind == LParen {
          depth = depth + 1
        } else if tok.kind == RParen {
          depth = depth - 1
        }
    }
  }
}

///|
fn parse_unary(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  if match_kind(p, Bang) {
    return pp_bool_value(pp_is_zero(parse_unary(p, loc)))
  }
  if match_kind(p, Tilde) {
    let v = parse_unary(p, loc)
    return { value: v.value.lnot(), is_unsigned: v.is_unsigned }
  }
  if match_kind(p, Plus) {
    return parse_unary(p, loc)
  }
  if match_kind(p, Minus) {
    let v = parse_unary(p, loc)
    let value : UInt64 = 0 - v.value
    return { value, is_unsigned: v.is_unsigned }
  }
  parse_primary(p, loc)
}

///|
fn parse_mul(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  let mut value = parse_unary(p, loc)
  while true {
    if peek_is_rparen(p) {
      break
    }
    if match_kind(p, Star) {
      let rhs = parse_unary(p, loc)
      let unsigned = pp_unsigned_result(value, rhs)
      value = { value: value.value * rhs.value, is_unsigned: unsigned }
      continue
    }
    if match_kind(p, Slash) {
      let rhs = parse_unary(p, loc)
      if pp_is_zero(rhs) {
        add_pp_error(p.pp, loc, "division by zero in #if")
        value = { value: 0, is_unsigned: false }
      } else {
        let unsigned = pp_unsigned_result(value, rhs)
        let new_value = if unsigned {
          value.value / rhs.value
        } else {
          let lhs = value.value.reinterpret_as_int64()
          let rhs_val = rhs.value.reinterpret_as_int64()
          (lhs / rhs_val).reinterpret_as_uint64()
        }
        value = { value: new_value, is_unsigned: unsigned }
      }
      continue
    }
    if match_kind(p, Percent) {
      let rhs = parse_unary(p, loc)
      if pp_is_zero(rhs) {
        add_pp_error(p.pp, loc, "modulo by zero in #if")
        value = { value: 0, is_unsigned: false }
      } else {
        let unsigned = pp_unsigned_result(value, rhs)
        let new_value = if unsigned {
          value.value % rhs.value
        } else {
          let lhs = value.value.reinterpret_as_int64()
          let rhs_val = rhs.value.reinterpret_as_int64()
          (lhs % rhs_val).reinterpret_as_uint64()
        }
        value = { value: new_value, is_unsigned: unsigned }
      }
      continue
    }
    break
  }
  value
}

///|
fn parse_add(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  let mut value = parse_mul(p, loc)
  while true {
    if peek_is_rparen(p) {
      break
    }
    if match_kind(p, Plus) {
      let rhs = parse_mul(p, loc)
      let unsigned = pp_unsigned_result(value, rhs)
      value = { value: value.value + rhs.value, is_unsigned: unsigned }
      continue
    }
    if match_kind(p, Minus) {
      let rhs = parse_mul(p, loc)
      let unsigned = pp_unsigned_result(value, rhs)
      value = { value: value.value - rhs.value, is_unsigned: unsigned }
      continue
    }
    break
  }
  value
}

///|
fn parse_shift(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  let mut value = parse_add(p, loc)
  while true {
    if peek_is_rparen(p) {
      break
    }
    if match_kind(p, ShiftLeft) {
      let rhs = parse_add(p, loc)
      let shift = pp_shift_count(rhs)
      value = { value: value.value << shift, is_unsigned: value.is_unsigned }
      continue
    }
    if match_kind(p, ShiftRight) {
      let rhs = parse_add(p, loc)
      let shift = pp_shift_count(rhs)
      let new_value = if value.is_unsigned {
        value.value >> shift
      } else {
        let lhs = value.value.reinterpret_as_int64()
        (lhs >> shift).reinterpret_as_uint64()
      }
      value = { value: new_value, is_unsigned: value.is_unsigned }
      continue
    }
    break
  }
  value
}

///|
fn parse_rel(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  let mut value = parse_shift(p, loc)
  while true {
    if peek_is_rparen(p) {
      break
    }
    if match_kind(p, Lt) {
      let rhs = parse_shift(p, loc)
      let cond = if pp_unsigned_result(value, rhs) {
        value.value < rhs.value
      } else {
        value.value.reinterpret_as_int64() < rhs.value.reinterpret_as_int64()
      }
      value = pp_bool_value(cond)
      continue
    }
    if match_kind(p, Le) {
      let rhs = parse_shift(p, loc)
      let cond = if pp_unsigned_result(value, rhs) {
        value.value <= rhs.value
      } else {
        value.value.reinterpret_as_int64() <= rhs.value.reinterpret_as_int64()
      }
      value = pp_bool_value(cond)
      continue
    }
    if match_kind(p, Gt) {
      let rhs = parse_shift(p, loc)
      let cond = if pp_unsigned_result(value, rhs) {
        value.value > rhs.value
      } else {
        value.value.reinterpret_as_int64() > rhs.value.reinterpret_as_int64()
      }
      value = pp_bool_value(cond)
      continue
    }
    if match_kind(p, Ge) {
      let rhs = parse_shift(p, loc)
      let cond = if pp_unsigned_result(value, rhs) {
        value.value >= rhs.value
      } else {
        value.value.reinterpret_as_int64() >= rhs.value.reinterpret_as_int64()
      }
      value = pp_bool_value(cond)
      continue
    }
    break
  }
  value
}

///|
fn parse_eq(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  let mut value = parse_rel(p, loc)
  while true {
    if peek_is_rparen(p) {
      break
    }
    if match_kind(p, Eq) {
      let rhs = parse_rel(p, loc)
      value = pp_bool_value(value.value == rhs.value)
      continue
    }
    if match_kind(p, Ne) {
      let rhs = parse_rel(p, loc)
      value = pp_bool_value(value.value != rhs.value)
      continue
    }
    break
  }
  value
}

///|
fn parse_bit_and(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  let mut value = parse_eq(p, loc)
  while match_kind(p, Amp) {
    if peek_is_rparen(p) {
      break
    }
    let rhs = parse_eq(p, loc)
    let unsigned = pp_unsigned_result(value, rhs)
    value = { value: value.value & rhs.value, is_unsigned: unsigned }
  }
  value
}

///|
fn parse_bit_xor(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  let mut value = parse_bit_and(p, loc)
  while match_kind(p, Caret) {
    if peek_is_rparen(p) {
      break
    }
    let rhs = parse_bit_and(p, loc)
    let unsigned = pp_unsigned_result(value, rhs)
    value = { value: value.value ^ rhs.value, is_unsigned: unsigned }
  }
  value
}

///|
fn parse_bit_or(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  let mut value = parse_bit_xor(p, loc)
  while match_kind(p, Pipe) {
    if peek_is_rparen(p) {
      break
    }
    let rhs = parse_bit_xor(p, loc)
    let unsigned = pp_unsigned_result(value, rhs)
    value = { value: value.value | rhs.value, is_unsigned: unsigned }
  }
  value
}

///|
fn parse_logical_and(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  let mut value = parse_bit_or(p, loc)
  while match_kind(p, AmpAmp) {
    let rhs = parse_bit_or(p, loc)
    value = pp_bool_value(!pp_is_zero(value) && !pp_is_zero(rhs))
  }
  value
}

///|
fn parse_logical_or(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  let mut value = parse_logical_and(p, loc)
  while match_kind(p, PipePipe) {
    let rhs = parse_logical_and(p, loc)
    value = pp_bool_value(!pp_is_zero(value) || !pp_is_zero(rhs))
  }
  value
}

///|
fn handle_directive(pp : Preprocessor, _hash_tok : Token) -> Unit {
  let name_tok = next_input_token(pp)
  if name_tok.kind == Eof {
    return
  }
  if name_tok.line_start {
    pp.held = Some(name_tok)
    return
  }
  let name_id = token_id(name_tok)
  let ids = pp.builtin_ids
  let is_conditional = name_id == ids.dir_if ||
    name_id == ids.dir_ifdef ||
    name_id == ids.dir_ifndef ||
    name_id == ids.dir_elif ||
    name_id == ids.dir_else ||
    name_id == ids.dir_endif
  if !current_active(pp) && !is_conditional {
    skip_directive_line(pp)
    return
  }
  if name_id == ids.dir_define {
    let args = read_directive_tokens(pp)
    if args.length() == 0 || !is_macro_name_token(args[0]) {
      add_pp_error(pp, name_tok.loc, "missing macro name in #define")
      return
    }
    let macro_id = macro_id_from_token(pp, args[0])
    if macro_id == 0 {
      add_pp_error(pp, name_tok.loc, "invalid macro name in #define")
      return
    }
    if parse_define_macro(pp, args[0], slice_tokens(args, 1), name_tok.loc) is Some(macro_def) {
      set_macro(pp, macro_id, macro_def)
    }
    return
  }
  if name_id == ids.dir_undef {
    let macro_name_tok = read_directive_head_token(pp)
    if pp.held is None {
      skip_directive_line(pp)
    }
    match macro_name_tok {
      None => {
        add_pp_error(pp, name_tok.loc, "missing macro name in #undef")
        return
      }
      Some(tok) =>
        if !is_macro_name_token(tok) {
          add_pp_error(pp, name_tok.loc, "missing macro name in #undef")
          return
        } else {
          let macro_id = macro_id_from_token(pp, tok)
          if macro_id != 0 {
            remove_macro(pp, macro_id)
          }
          return
        }
    }
  }
  if name_id == ids.dir_ifdef {
    if !current_active(pp) {
      skip_directive_line(pp)
      push_cond(pp, false)
      return
    }
    let macro_name_tok = read_directive_head_token(pp)
    if pp.held is None {
      skip_directive_line(pp)
    }
    let cond = macro_name_tok is Some(tok) &&
      is_macro_name_token(tok) &&
      has_macro(pp, macro_id_from_token(pp, tok))
    push_cond(pp, cond)
    return
  }
  if name_id == ids.dir_ifndef {
    if !current_active(pp) {
      skip_directive_line(pp)
      push_cond(pp, false)
      return
    }
    let macro_name_tok = read_directive_head_token(pp)
    if pp.held is None {
      skip_directive_line(pp)
    }
    let cond = macro_name_tok is Some(tok) &&
      is_macro_name_token(tok) &&
      !has_macro(pp, macro_id_from_token(pp, tok))
    push_cond(pp, cond)
    return
  }
  if name_id == ids.dir_if {
    if !current_active(pp) {
      skip_directive_line(pp)
      push_cond(pp, false)
      return
    }
    let args = read_directive_tokens(pp)
    let expanded = expand_if_tokens(pp, args)
    let cond = eval_if_expr(pp, expanded, name_tok.loc)
    push_cond(pp, cond)
    return
  }
  if name_id == ids.dir_elif {
    if pp.cond_stack.length() == 0 {
      skip_directive_line(pp)
      update_elif(pp, false, name_tok.loc)
      return
    }
    let idx = pp.cond_stack.length() - 1
    let state = pp.cond_stack[idx]
    if !state.parent_active || state.taken {
      skip_directive_line(pp)
      update_elif(pp, false, name_tok.loc)
      return
    }
    let args = read_directive_tokens(pp)
    let expanded = expand_if_tokens(pp, args)
    let cond = eval_if_expr(pp, expanded, name_tok.loc)
    update_elif(pp, cond, name_tok.loc)
    return
  }
  if name_id == ids.dir_else {
    skip_directive_line(pp)
    update_else(pp, name_tok.loc)
    return
  }
  if name_id == ids.dir_endif {
    skip_directive_line(pp)
    pop_cond(pp, name_tok.loc)
    return
  }
  if name_id == ids.dir_include {
    let args = read_directive_tokens(pp)
    if current_active(pp) {
      let expanded = expand_tokens(pp, args)
      if parse_include_path(pp, expanded, name_tok.loc) is Some(spec) {
        include_file(pp, spec, name_tok.loc, include_next=false)
      }
    }
    return
  }
  if name_id == ids.dir_include_next {
    let args = read_directive_tokens(pp)
    if current_active(pp) {
      let expanded = expand_tokens(pp, args)
      if parse_include_path(pp, expanded, name_tok.loc) is Some(spec) {
        include_file(pp, spec, name_tok.loc, include_next=true)
      }
    }
    return
  }
  if name_id == ids.dir_line {
    let args = read_directive_tokens(pp)
    if !current_active(pp) {
      return
    }
    let expanded = expand_tokens(pp, args)
    handle_line_directive(pp, expanded, name_tok.loc)
    return
  }
  if name_id == ids.dir_error {
    if current_active(pp) {
      let text = read_directive_text(pp)
      add_pp_error(pp, name_tok.loc, "error: " + text)
    } else {
      skip_directive_line(pp)
    }
    return
  }
  if name_id == ids.dir_warning {
    if current_active(pp) {
      let text = read_directive_text(pp)
      add_pp_error(pp, name_tok.loc, "warning: " + text)
    } else {
      skip_directive_line(pp)
    }
    return
  }
  if name_id == ids.dir_pragma {
    skip_directive_line(pp)
    return
  }
  if current_active(pp) {
    skip_directive_line(pp)
    add_pp_error(pp, name_tok.loc, "unknown preprocessor directive")
  }
}

///|
fn next_pp_token(pp : Preprocessor) -> Token {
  while true {
    if !current_active(pp) && pp.held is None && pp.pending.length() == 0 {
      skip_inactive(pp)
    }
    let mut from_pending = false
    let tok = if pp.pending.length() > 0 {
      match pp.pending.pop() {
        Some(t) => {
          from_pending = true
          release_expanding_guards(pp)
          t
        }
        None => continue
      }
    } else {
      next_input_token(pp)
    }
    match tok.kind {
      Eof => return tok
      Hash if tok.line_start && !from_pending => {
        handle_directive(pp, tok)
        continue
      }
      _ => ()
    }
    if !current_active(pp) {
      continue
    }
    if token_id(tok) == 0 {
      return tok
    }
    let macro_id = token_id(tok)
    let is_macro_name = macro_id > 0
    if is_macro_name {
      if builtin_macro_tokens(pp, tok) is Some(tokens) {
        push_tokens(pp, tokens)
        continue
      }
    }
    let hidden_ok = !is_macro_name ||
      hidden_is_empty(tok.hidden) ||
      (macro_id != 0 && !hidden_contains(pp.hidden_pool, tok.hidden, macro_id))
    if is_macro_name && macro_id != 0 && hidden_ok {
      if get_macro(pp, macro_id) is Some(macro_def) {
          if is_expanding(pp, macro_id) {
            return tok
          }
          if macro_def.is_function {
            let next_tok = next_raw_token(pp)
            match next_tok.kind {
              LParen => ()
              _ => {
                push_back(pp, next_tok)
                return tok
              }
            }
            match read_macro_args(pp, tok.loc) {
              None => return tok
              Some(args) =>
                match normalize_macro_args(macro_def, args, tok.loc) {
                  None => {
                    add_pp_error(pp, tok.loc, "macro argument count mismatch")
                    return tok
                  }
                  Some(norm_args) => {
                    let restore_len = pp.pending.length()
                    let (replaced, needs_expand) = substitute_macro(
                      pp,
                      macro_def,
                      norm_args,
                      tok.loc,
                    )
                    let mut did_push = false
                    let expanded = if needs_expand {
                      push_expanding(pp, macro_id)
                      did_push = true
                      add_hidden_tokens(pp, expand_tokens(pp, replaced), macro_id)
                    } else {
                      replaced
                    }
                    if expanded.length() > 0 {
                      if did_push {
                        pp.expanding_guards.push({ restore_len, })
                      }
                      push_tokens(pp, expanded)
                      if did_push {
                        release_expanding_guards(pp)
                      }
                      if did_push && is_expanding(pp, macro_id) {
                        pop_expanding(pp)
                      }
                    } else if did_push {
                      pop_expanding(pp)
                    }
                    continue
                  }
                }
            }
          } else {
            let restore_len = pp.pending.length()
            let mut did_push = false
            let expanded =
              if macro_replacement_needs_expand(pp, macro_id, macro_def) {
                push_expanding(pp, macro_id)
                did_push = true
                add_hidden_tokens(pp, expand_tokens(pp, macro_def.replacement), macro_id)
              } else {
                macro_def.replacement
              }
            if expanded.length() > 0 {
              if did_push {
                pp.expanding_guards.push({ restore_len, })
              }
              push_tokens(pp, expanded)
              if did_push {
                release_expanding_guards(pp)
              }
              if did_push && is_expanding(pp, macro_id) {
                pop_expanding(pp)
              }
            } else if did_push {
              pop_expanding(pp)
            }
            continue
          }
      }
    }
    return tok
  } else {
    {
      kind: Eof,
      value: 0,
      loc: lexer_loc(pp.lexer),
      line_start: false,
      hidden: empty_hidden,
    }
  }
}

///|
fn dump_tokens(pp : Preprocessor, max_count : Int) -> Array[Token] {
  let out : Array[Token] = []
  while out.length() < max_count {
    let tok = next_pp_token(pp)
    out.push(tok)
    match tok.kind {
      Eof => break
      _ => ()
    }
  }
  out
}
