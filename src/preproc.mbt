///|
struct CondState {
  parent_active : Bool
  mut taken : Bool
  mut active : Bool
}

///|
struct Macro {
  params : Array[String]
  is_variadic : Bool
  is_function : Bool
  replacement : Array[Token]
}

///|
struct IncludeSpec {
  path : String
  is_angle : Bool
}

///|
struct Preprocessor {
  mut lexer : Lexer
  lexer_stack : Array[Lexer]
  held_stack : Array[Token?]
  path_stack : Array[String]
  mut current_path : String
  mut logical_path : String
  logical_path_stack : Array[String]
  mut line_adjust : Int
  line_adjust_stack : Array[Int]
  include_paths : Array[String]
  diags : DiagBag
  map : SourceMap
  macros : Map[String, Macro]
  pending : Array[Token]
  mut held : Token?
  cond_stack : Array[CondState]
  expanding : Array[String]
  date_literal : String
  time_literal : String
}

///|
fn make_builtin_token(kind : TokenKind, lexeme : String) -> Token {
  { kind, lexeme, loc: dummy_loc(0), line_start: false }
}

///|
fn define_macro(
  pp : Preprocessor,
  name : String,
  replacement : Array[Token],
) -> Unit {
  pp.macros.set(name, {
    params: [],
    is_variadic: false,
    is_function: false,
    replacement,
  })
}

///|
fn define_words_macro(pp : Preprocessor, name : String, words : Array[String]) ->
  Unit {
  let tokens = words.map(w => make_builtin_token(Ident, w))
  define_macro(pp, name, tokens)
}

///|
fn define_int_macro(pp : Preprocessor, name : String, value : Int) -> Unit {
  define_macro(pp, name, [make_builtin_token(IntLit, value.to_string())])
}

///|
fn define_func_macro_zero(pp : Preprocessor, name : String) -> Unit {
  pp.macros.set(name, {
    params: ["x"],
    is_variadic: true,
    is_function: true,
    replacement: [make_builtin_token(IntLit, "0")],
  })
}

///|
fn init_builtin_macros(pp : Preprocessor) -> Unit {
  define_int_macro(pp, "__APPLE__", 1)
  define_int_macro(pp, "__MACH__", 1)
  define_int_macro(pp, "__aarch64__", 1)
  define_int_macro(pp, "__arm64__", 1)
  define_int_macro(pp, "__LP64__", 1)

  define_macro(pp, "__ORDER_LITTLE_ENDIAN__", [
    make_builtin_token(IntLit, "1234"),
  ])
  define_macro(pp, "__ORDER_BIG_ENDIAN__", [
    make_builtin_token(IntLit, "4321"),
  ])
  define_macro(pp, "__ORDER_PDP_ENDIAN__", [
    make_builtin_token(IntLit, "3412"),
  ])
  define_macro(pp, "__BYTE_ORDER__", [
    make_builtin_token(Ident, "__ORDER_LITTLE_ENDIAN__"),
  ])
  define_int_macro(pp, "__LITTLE_ENDIAN__", 1)

  define_words_macro(pp, "__SIZE_TYPE__", ["unsigned", "long"])
  define_words_macro(pp, "__PTRDIFF_TYPE__", ["long"])
  define_words_macro(pp, "__INTMAX_TYPE__", ["long", "int"])
  define_words_macro(pp, "__UINTMAX_TYPE__", ["long", "unsigned", "int"])
  define_words_macro(pp, "__INTPTR_TYPE__", ["long"])
  define_words_macro(pp, "__UINTPTR_TYPE__", ["unsigned", "long"])
  define_words_macro(pp, "__INT32_TYPE__", ["int"])
  define_words_macro(pp, "__INT64_TYPE__", ["long", "long"])

  define_int_macro(pp, "__CHAR_BIT__", 8)
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
    make_builtin_token(IntLit, "201112"),
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
}

///|
fn new_preprocessor(map : SourceMap, file : SourceFile, diags : DiagBag) ->
  Preprocessor {
  let (date_literal, time_literal) = init_datetime_literals()
  let pp = {
    lexer: new_lexer(file, diags),
    lexer_stack: [],
    held_stack: [],
    path_stack: [],
    current_path: file.path,
    logical_path: file.path,
    logical_path_stack: [],
    line_adjust: 0,
    line_adjust_stack: [],
    include_paths: [],
    diags,
    map,
    macros: {},
    pending: [],
    held: None,
    cond_stack: [],
    expanding: [],
    date_literal,
    time_literal,
  }
  init_builtin_macros(pp)
  pp
}

///|
fn current_active(pp : Preprocessor) -> Bool {
  if pp.cond_stack.length() == 0 {
    return true
  }
  let idx = pp.cond_stack.length() - 1
  pp.cond_stack[idx].active
}

///|
fn add_pp_error(pp : Preprocessor, loc : SrcLoc, message : String) -> Unit {
  add_error(pp.diags, loc, message)
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
        if tok.kind == Eof && pp.lexer_stack.length() > 0 {
          match pp.lexer_stack.pop() {
            Some(prev) => pp.lexer = prev
            None => ()
          }
          match pp.held_stack.pop() {
            Some(prev_held) => pp.held = prev_held
            None => ()
          }
          match pp.path_stack.pop() {
            Some(prev_path) => pp.current_path = prev_path
            None => ()
          }
          match pp.logical_path_stack.pop() {
            Some(prev_path) => pp.logical_path = prev_path
            None => ()
          }
          match pp.line_adjust_stack.pop() {
            Some(prev_adjust) => pp.line_adjust = prev_adjust
            None => ()
          }
          continue
        }
        return tok
      }
    }
  } else {
    { kind: Eof, lexeme: "", loc: lexer_loc(pp.lexer), line_start: false }
  }
}

///|
fn read_directive_tokens(pp : Preprocessor) -> Array[Token] {
  let out : Array[Token] = []
  while true {
    let tok = next_input_token(pp)
    if tok.kind == Eof || tok.line_start {
      pp.held = Some(tok)
      break
    }
    out.push(tok)
  }
  out
}

///|
fn slice_tokens(tokens : Array[Token], start : Int) -> Array[Token] {
  if start >= tokens.length() {
    return []
  }
  tokens[start:tokens.length()].to_array()
}

///|
fn slice_string(text : String, start : Int, end : Int) -> String {
  try text[start:end] catch {
    _ => ""
  } noraise {
    view => view.to_string()
  }
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
  loc : SrcLoc,
) -> IncludeSpec? {
  if args.length() == 0 {
    add_pp_error(pp, loc, "missing include path")
    return None
  }
  if args[0].kind == StrLit {
    return Some({ path: strip_quotes(args[0].lexeme), is_angle: false })
  }
  if args[0].kind == Lt {
    let parts : Array[String] = []
    let mut i = 1
    while i < args.length() {
      if args[i].kind == Gt {
        return Some({ path: parts.join(""), is_angle: true })
      }
      parts.push(args[i].lexeme)
      i = i + 1
    }
    add_pp_error(pp, loc, "unterminated include path")
    return None
  }
  add_pp_error(pp, loc, "invalid include path")
  None
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
  let dirs : Array[String] = []
  if !is_angle {
    dirs.push(dir_name(pp.current_path))
  }
  for p in pp.include_paths {
    dirs.push(p)
  }
  let mut start = 0
  if include_next && dirs.length() > 0 {
    start = 1
  }
  let mut i = start
  while i < dirs.length() {
    let candidate = join_path(dirs[i], path)
    if @fs.path_exists(candidate) {
      return Some(candidate)
    }
    i = i + 1
  }
  None
}

///|
fn include_file(
  pp : Preprocessor,
  spec : IncludeSpec,
  loc : SrcLoc,
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
          let file = add_file(pp.map, resolved, text)
          pp.lexer_stack.push(pp.lexer)
          pp.held_stack.push(pp.held)
          pp.held = None
          pp.path_stack.push(pp.current_path)
          pp.logical_path_stack.push(pp.logical_path)
          pp.line_adjust_stack.push(pp.line_adjust)
          pp.lexer = new_lexer(file, pp.diags)
          pp.current_path = resolved
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
  loc : SrcLoc,
) -> Macro? {
  let is_function_like = args.length() > 0 &&
    args[0].kind == LParen &&
    is_adjacent(name_tok, args[0])
  if is_function_like {
    match parse_macro_params(pp, args, loc) {
      None => None
      Some((params, is_variadic, replacement)) =>
        Some({
          params,
          is_variadic,
          is_function: true,
          replacement: normalize_macro_tokens(replacement),
        })
    }
  } else {
    Some({
      params: [],
      is_variadic: false,
      is_function: false,
      replacement: normalize_macro_tokens(args),
    })
  }
}

///|
fn parse_macro_params(
  pp : Preprocessor,
  args : Array[Token],
  loc : SrcLoc,
) -> (Array[String], Bool, Array[Token])? {
  let params : Array[String] = []
  let mut i = 1
  let mut is_variadic = false
  while i < args.length() {
    let tok = args[i]
    if tok.kind == RParen {
      i = i + 1
      let replacement = slice_tokens(args, i)
      return Some((params, is_variadic, replacement))
    }
    if tok.kind == Ellipsis {
      is_variadic = true
      params.push("__VA_ARGS__")
      i = i + 1
      continue
    }
    if tok.kind != Ident {
      add_pp_error(pp, loc, "invalid macro parameter")
      return None
    }
    params.push(tok.lexeme)
    i = i + 1
    if i < args.length() && args[i].kind == Comma {
      i = i + 1
      if i < args.length() && args[i].kind == Ellipsis {
        is_variadic = true
        params.push("__VA_ARGS__")
        i = i + 1
      }
      continue
    }
  }
  add_pp_error(pp, loc, "unterminated macro parameter list")
  None
}

///|
fn next_raw_token(pp : Preprocessor) -> Token {
  if pp.pending.length() > 0 {
    match pp.pending.pop() {
      Some(tok) => return tok
      None => ()
    }
  }
  next_input_token(pp)
}

///|
fn push_back(pp : Preprocessor, tok : Token) -> Unit {
  pp.pending.push(tok)
}

///|
fn read_macro_args(pp : Preprocessor, loc : SrcLoc) -> Array[Array[Token]]? {
  let args : Array[Array[Token]] = []
  let mut current : Array[Token] = []
  let mut depth = 0
  while true {
    let tok = next_raw_token(pp)
    if tok.kind == Eof {
      add_pp_error(pp, loc, "unterminated macro invocation")
      return None
    }
    if tok.kind == LParen {
      depth = depth + 1
      current.push(tok)
      continue
    }
    if tok.kind == RParen {
      if depth == 0 {
        if current.length() > 0 || args.length() > 0 {
          args.push(current)
        }
        return Some(args)
      }
      depth = depth - 1
      current.push(tok)
      continue
    }
    if tok.kind == Comma && depth == 0 {
      args.push(current)
      current = []
      continue
    }
    current.push(tok)
  }
  None
}

///|
fn normalize_macro_args(
  macro_def : Macro,
  args : Array[Array[Token]],
  loc : SrcLoc,
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
        var_tokens.push({ kind: Comma, lexeme: ",", loc, line_start: false })
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
fn is_adjacent(left : Token, right : Token) -> Bool {
  left.loc.file_id == right.loc.file_id &&
  right.loc.offset == left.loc.offset + left.lexeme.length()
}

///|
fn is_expanding(pp : Preprocessor, name : String) -> Bool {
  for n in pp.expanding {
    if n == name {
      return true
    }
  }
  false
}

///|
fn push_expanding(pp : Preprocessor, name : String) -> Unit {
  pp.expanding.push(name)
}

///|
fn pop_expanding(pp : Preprocessor) -> Unit {
  ignore(pp.expanding.pop())
}

///|
fn stringize_tokens(tokens : Array[Token]) -> String {
  if tokens.length() == 0 {
    return ""
  }
  let parts = tokens.map(tok => tok.lexeme)
  parts.join(" ")
}

///|
fn make_string_literal(text : String, loc : SrcLoc) -> Token {
  let escaped = escape_string(text)
  { kind: StrLit, lexeme: "\"" + escaped + "\"", loc, line_start: false }
}

///|
fn escape_string(text : String) -> String {
  let sb = StringBuilder::new()
  for ch in text {
    if ch == '\\' {
      sb.write_string("\\\\")
    } else if ch == '"' {
      sb.write_string("\\\"")
    } else {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
fn logical_line(pp : Preprocessor, loc : SrcLoc) -> Int {
  loc.line + pp.line_adjust
}

///|
fn make_int_literal_token(value : Int, loc : SrcLoc) -> Token {
  { kind: IntLit, lexeme: value.to_string(), loc, line_start: false }
}

///|
fn builtin_macro_tokens(pp : Preprocessor, tok : Token) -> Array[Token]? {
  match tok.lexeme {
    "__LINE__" =>
      Some([make_int_literal_token(logical_line(pp, tok.loc), tok.loc)])
    "__FILE__" => {
      let path = if pp.logical_path == "" {
        pp.current_path
      } else {
        pp.logical_path
      }
      Some([make_string_literal(path, tok.loc)])
    }
    "__DATE__" => Some([make_string_literal(pp.date_literal, tok.loc)])
    "__TIME__" => Some([make_string_literal(pp.time_literal, tok.loc)])
    _ => None
  }
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
fn lookup_param_index(params : Array[String], name : String) -> Int? {
  for i = 0; i < params.length(); i = i + 1 {
    if params[i] == name {
      return Some(i)
    }
  }
  None
}

///|
fn substitute_macro(
  macro_def : Macro,
  raw_args : Array[Array[Token]],
  expanded_args : Array[Array[Token]],
  loc : SrcLoc,
) -> Array[Token] {
  if !macro_def.is_function {
    return macro_def.replacement
  }
  let out : Array[Token] = []
  let params = macro_def.params
  let mut i = 0
  while i < macro_def.replacement.length() {
    let tok = macro_def.replacement[i]
    if tok.kind == Hash && i + 1 < macro_def.replacement.length() {
      let next_tok = macro_def.replacement[i + 1]
      if next_tok.kind == Ident {
        match lookup_param_index(params, next_tok.lexeme) {
          Some(idx) => {
            let arg_tokens = if idx < raw_args.length() {
              raw_args[idx]
            } else {
              []
            }
            out.push(make_string_literal(stringize_tokens(arg_tokens), loc))
            i = i + 2
            continue
          }
          None => ()
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
      let next_tok = macro_def.replacement[i + 1]
      if next_tok.kind == Ident {
        match lookup_param_index(params, next_tok.lexeme) {
          Some(idx) =>
            next_tokens = if idx < raw_args.length() {
              raw_args[idx]
            } else {
              []
            }
          None => next_tokens = [next_tok]
        }
      } else {
        next_tokens = [next_tok]
      }
      if next_tokens.length() == 0 {
        out.push(last)
        i = i + 2
        continue
      }
      let merged = {
        kind: Ident,
        lexeme: last.lexeme + next_tokens[0].lexeme,
        loc: last.loc,
        line_start: false,
      }
      out.push(merged)
      if next_tokens.length() > 1 {
        for j = 1; j < next_tokens.length(); j = j + 1 {
          out.push(next_tokens[j])
        }
      }
      i = i + 2
      continue
    }
    if tok.kind == Ident {
      match lookup_param_index(params, tok.lexeme) {
        Some(idx) => {
          let arg_tokens = if idx < expanded_args.length() {
            expanded_args[idx]
          } else {
            []
          }
          for t in arg_tokens {
            out.push({
              kind: t.kind,
              lexeme: t.lexeme,
              loc: t.loc,
              line_start: false,
            })
          }
          i = i + 1
          continue
        }
        None => ()
      }
    }
    out.push(tok)
    i = i + 1
  }
  out
}

///|
fn read_macro_args_from_tokens(
  pp : Preprocessor,
  tokens : Array[Token],
  start : Int,
  loc : SrcLoc,
) -> (Array[Array[Token]], Int)? {
  let args : Array[Array[Token]] = []
  let mut current : Array[Token] = []
  let mut depth = 0
  let mut i = start
  while i < tokens.length() {
    let tok = tokens[i]
    if tok.kind == LParen {
      depth = depth + 1
      current.push(tok)
      i = i + 1
      continue
    }
    if tok.kind == RParen {
      if depth == 0 {
        if current.length() > 0 || args.length() > 0 {
          args.push(current)
        }
        return Some((args, i + 1))
      }
      depth = depth - 1
      current.push(tok)
      i = i + 1
      continue
    }
    if tok.kind == Comma && depth == 0 {
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
fn expand_tokens(pp : Preprocessor, tokens : Array[Token]) -> Array[Token] {
  let out : Array[Token] = []
  let mut i = 0
  while i < tokens.length() {
    let tok = tokens[i]
    if tok.kind == Ident {
      match builtin_macro_tokens(pp, tok) {
        Some(tokens) => {
          for t in tokens {
            out.push(t)
          }
          i = i + 1
          continue
        }
        None => ()
      }
    }
    if tok.kind == Ident &&
      pp.macros.contains(tok.lexeme) &&
      !is_expanding(pp, tok.lexeme) {
      match pp.macros.get(tok.lexeme) {
        None => ()
        Some(macro_def) =>
          if macro_def.is_function {
            if i + 1 < tokens.length() && tokens[i + 1].kind == LParen {
              match read_macro_args_from_tokens(pp, tokens, i + 2, tok.loc) {
                None => {
                  out.push(tok)
                  i = i + 1
                  continue
                }
                Some((raw_args, next_i)) =>
                  match normalize_macro_args(macro_def, raw_args, tok.loc) {
                    None => {
                      add_pp_error(pp, tok.loc, "macro argument count mismatch")
                      out.push(tok)
                      i = next_i
                      continue
                    }
                    Some(norm_raw) => {
                      push_expanding(pp, tok.lexeme)
                      let expanded_args = norm_raw.map(arg => expand_tokens(
                        pp, arg,
                      ))
                      let replaced = substitute_macro(
                        macro_def,
                        norm_raw,
                        expanded_args,
                        tok.loc,
                      )
                      let expanded = expand_tokens(pp, replaced)
                      pop_expanding(pp)
                      for t in expanded {
                        out.push(t)
                      }
                      i = next_i
                      continue
                    }
                  }
              }
            }
            out.push(tok)
            i = i + 1
            continue
          } else {
            push_expanding(pp, tok.lexeme)
            let expanded = expand_tokens(pp, macro_def.replacement)
            pop_expanding(pp)
            for t in expanded {
              out.push(t)
            }
            i = i + 1
            continue
          }
      }
    }
    out.push(tok)
    i = i + 1
  }
  out
}

///|
fn push_cond(pp : Preprocessor, cond : Bool) -> Unit {
  let parent = current_active(pp)
  let active = parent && cond
  pp.cond_stack.push({ parent_active: parent, taken: active, active })
}

///|
fn update_elif(pp : Preprocessor, cond : Bool, loc : SrcLoc) -> Unit {
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
}

///|
fn update_else(pp : Preprocessor, loc : SrcLoc) -> Unit {
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
}

///|
fn pop_cond(pp : Preprocessor, loc : SrcLoc) -> Unit {
  if pp.cond_stack.length() == 0 {
    add_pp_error(pp, loc, "unexpected #endif without #if")
    return
  }
  ignore(pp.cond_stack.pop())
}

///|
fn normalize_macro_tokens(tokens : Array[Token]) -> Array[Token] {
  tokens.map(tok => {
    kind: tok.kind,
    lexeme: tok.lexeme,
    loc: tok.loc,
    line_start: false,
  })
}

///|
fn expand_if_tokens(pp : Preprocessor, tokens : Array[Token]) -> Array[Token] {
  let out : Array[Token] = []
  let mut segment : Array[Token] = []
  let mut i = 0
  while i < tokens.length() {
    let tok = tokens[i]
    if tok.kind == Ident && tok.lexeme == "defined" {
      if segment.length() > 0 {
        let expanded = expand_tokens(pp, segment)
        for t in expanded {
          out.push(t)
        }
        segment = []
      }
      out.push(tok)
      i = i + 1
      if i < tokens.length() && tokens[i].kind == LParen {
        out.push(tokens[i])
        i = i + 1
        if i < tokens.length() {
          out.push(tokens[i])
          i = i + 1
        }
        if i < tokens.length() && tokens[i].kind == RParen {
          out.push(tokens[i])
          i = i + 1
        }
      } else if i < tokens.length() {
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
fn handle_line_directive(
  pp : Preprocessor,
  tokens : Array[Token],
  loc : SrcLoc,
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
  let line_val = parse_int_literal(pp, line_tok.lexeme, line_tok.loc)
  if line_val <= 0 {
    add_pp_error(pp, loc, "invalid line number in #line")
    return
  }
  pp.line_adjust = line_val - (loc.line + 1)
  if tokens.length() > 1 && tokens[1].kind == StrLit {
    pp.logical_path = strip_quotes(tokens[1].lexeme)
  }
}

///|

///|
fn eval_if_expr(pp : Preprocessor, tokens : Array[Token], loc : SrcLoc) -> Bool {
  if tokens.length() == 0 {
    add_pp_error(pp, loc, "empty #if expression")
    return false
  }
  let parser = { tokens, index: 0, pp }
  let value = parse_logical_or(parser, loc)
  value != 0
}

///|
struct IfParser {
  tokens : Array[Token]
  mut index : Int
  pp : Preprocessor
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
fn parse_int_literal(pp : Preprocessor, lexeme : String, loc : SrcLoc) -> Int {
  let mut end = lexeme.length()
  while end > 0 {
    let ch = lexeme[end - 1]
    if ch == 'u' || ch == 'U' || ch == 'l' || ch == 'L' {
      end = end - 1
      continue
    }
    break
  }
  let trimmed = slice_string(lexeme, 0, end)
  try @strconv.parse_int(trimmed, base=0) catch {
    _ => {
      add_pp_error(pp, loc, "invalid integer in #if")
      0
    }
  } noraise {
    v => v
  }
}

///|
fn macro_int_value(pp : Preprocessor, name : String, loc : SrcLoc) -> Int? {
  match pp.macros.get(name) {
    None => None
    Some(macro_def) => {
      if macro_def.is_function {
        return None
      }
      if macro_def.replacement.length() == 1 &&
        macro_def.replacement[0].kind == IntLit {
        return Some(parse_int_literal(pp, macro_def.replacement[0].lexeme, loc))
      }
      None
    }
  }
}

///|
fn parse_primary(p : IfParser, loc : SrcLoc) -> Int {
  match advance_if(p) {
    None => {
      add_pp_error(p.pp, loc, "unexpected end of #if expression")
      0
    }
    Some(tok) => {
      if tok.kind == RParen {
        p.index = p.index - 1
        return 0
      }
      if tok.kind == IntLit {
        return parse_int_literal(p.pp, tok.lexeme, tok.loc)
      }
      if tok.kind == Ident {
        if tok.lexeme == "defined" {
          return parse_defined(p, loc)
        }
        match macro_int_value(p.pp, tok.lexeme, tok.loc) {
          Some(v) => return v
          None => {
            if match_kind(p, LParen) {
              skip_paren_expr(p, tok.loc)
              return 0
            }
            return 0
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
      0
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
fn parse_defined(p : IfParser, loc : SrcLoc) -> Int {
  if match_kind(p, LParen) {
    match advance_if(p) {
      Some(tok) if tok.kind == Ident => {
        if !match_kind(p, RParen) {
          add_pp_error(p.pp, loc, "missing ')' after defined")
        }
        return if p.pp.macros.contains(tok.lexeme) { 1 } else { 0 }
      }
      _ => {
        add_pp_error(p.pp, loc, "expected identifier after defined(")
        return 0
      }
    }
  }
  match advance_if(p) {
    Some(tok) if tok.kind == Ident =>
      if p.pp.macros.contains(tok.lexeme) {
        1
      } else {
        0
      }
    _ => {
      add_pp_error(p.pp, loc, "expected identifier after defined")
      0
    }
  }
}

///|
fn skip_paren_expr(p : IfParser, loc : SrcLoc) -> Unit {
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
fn parse_unary(p : IfParser, loc : SrcLoc) -> Int {
  if match_kind(p, Bang) {
    return if parse_unary(p, loc) == 0 { 1 } else { 0 }
  }
  if match_kind(p, Tilde) {
    return parse_unary(p, loc).lnot()
  }
  if match_kind(p, Plus) {
    return parse_unary(p, loc)
  }
  if match_kind(p, Minus) {
    return -parse_unary(p, loc)
  }
  parse_primary(p, loc)
}

///|
fn parse_mul(p : IfParser, loc : SrcLoc) -> Int {
  let mut value = parse_unary(p, loc)
  while true {
    if peek_is_rparen(p) {
      break
    }
    if match_kind(p, Star) {
      value = value * parse_unary(p, loc)
      continue
    }
    if match_kind(p, Slash) {
      let rhs = parse_unary(p, loc)
      if rhs == 0 {
        add_pp_error(p.pp, loc, "division by zero in #if")
        value = 0
      } else {
        value = value / rhs
      }
      continue
    }
    if match_kind(p, Percent) {
      let rhs = parse_unary(p, loc)
      if rhs == 0 {
        add_pp_error(p.pp, loc, "modulo by zero in #if")
        value = 0
      } else {
        value = value % rhs
      }
      continue
    }
    break
  }
  value
}

///|
fn parse_add(p : IfParser, loc : SrcLoc) -> Int {
  let mut value = parse_mul(p, loc)
  while true {
    if peek_is_rparen(p) {
      break
    }
    if match_kind(p, Plus) {
      value = value + parse_mul(p, loc)
      continue
    }
    if match_kind(p, Minus) {
      value = value - parse_mul(p, loc)
      continue
    }
    break
  }
  value
}

///|
fn parse_shift(p : IfParser, loc : SrcLoc) -> Int {
  let mut value = parse_add(p, loc)
  while true {
    if peek_is_rparen(p) {
      break
    }
    if match_kind(p, ShiftLeft) {
      value = value << parse_add(p, loc)
      continue
    }
    if match_kind(p, ShiftRight) {
      value = value >> parse_add(p, loc)
      continue
    }
    break
  }
  value
}

///|
fn parse_rel(p : IfParser, loc : SrcLoc) -> Int {
  let mut value = parse_shift(p, loc)
  while true {
    if peek_is_rparen(p) {
      break
    }
    if match_kind(p, Lt) {
      value = if value < parse_shift(p, loc) { 1 } else { 0 }
      continue
    }
    if match_kind(p, Le) {
      value = if value <= parse_shift(p, loc) { 1 } else { 0 }
      continue
    }
    if match_kind(p, Gt) {
      value = if value > parse_shift(p, loc) { 1 } else { 0 }
      continue
    }
    if match_kind(p, Ge) {
      value = if value >= parse_shift(p, loc) { 1 } else { 0 }
      continue
    }
    break
  }
  value
}

///|
fn parse_eq(p : IfParser, loc : SrcLoc) -> Int {
  let mut value = parse_rel(p, loc)
  while true {
    if peek_is_rparen(p) {
      break
    }
    if match_kind(p, Eq) {
      value = if value == parse_rel(p, loc) { 1 } else { 0 }
      continue
    }
    if match_kind(p, Ne) {
      value = if value != parse_rel(p, loc) { 1 } else { 0 }
      continue
    }
    break
  }
  value
}

///|
fn parse_bit_and(p : IfParser, loc : SrcLoc) -> Int {
  let mut value = parse_eq(p, loc)
  while match_kind(p, Amp) {
    if peek_is_rparen(p) {
      break
    }
    value = value & parse_eq(p, loc)
  }
  value
}

///|
fn parse_bit_xor(p : IfParser, loc : SrcLoc) -> Int {
  let mut value = parse_bit_and(p, loc)
  while match_kind(p, Caret) {
    if peek_is_rparen(p) {
      break
    }
    value = value ^ parse_bit_and(p, loc)
  }
  value
}

///|
fn parse_bit_or(p : IfParser, loc : SrcLoc) -> Int {
  let mut value = parse_bit_xor(p, loc)
  while match_kind(p, Pipe) {
    if peek_is_rparen(p) {
      break
    }
    value = value | parse_bit_xor(p, loc)
  }
  value
}

///|
fn parse_logical_and(p : IfParser, loc : SrcLoc) -> Int {
  let mut value = parse_bit_or(p, loc)
  while match_kind(p, AmpAmp) {
    let rhs = parse_bit_or(p, loc)
    value = if value != 0 && rhs != 0 { 1 } else { 0 }
  }
  value
}

///|
fn parse_logical_or(p : IfParser, loc : SrcLoc) -> Int {
  let mut value = parse_logical_and(p, loc)
  while match_kind(p, PipePipe) {
    let rhs = parse_logical_and(p, loc)
    value = if value != 0 || rhs != 0 { 1 } else { 0 }
  }
  value
}

///|
fn handle_directive(pp : Preprocessor, _hash_tok : Token) -> Unit {
  let tokens = read_directive_tokens(pp)
  if tokens.length() == 0 {
    return
  }
  let name_tok = tokens[0]
  let name = name_tok.lexeme
  let args = slice_tokens(tokens, 1)
  if name == "define" {
    if !current_active(pp) {
      return
    }
    if args.length() == 0 || args[0].kind != Ident {
      add_pp_error(pp, name_tok.loc, "missing macro name in #define")
      return
    }
    let macro_name = args[0].lexeme
    match parse_define_macro(pp, args[0], slice_tokens(args, 1), name_tok.loc) {
      Some(macro_def) => pp.macros.set(macro_name, macro_def)
      None => ()
    }
    return
  }
  if name == "undef" {
    if !current_active(pp) {
      return
    }
    if args.length() == 0 || args[0].kind != Ident {
      add_pp_error(pp, name_tok.loc, "missing macro name in #undef")
      return
    }
    pp.macros.remove(args[0].lexeme)
    return
  }
  if name == "ifdef" {
    let cond = args.length() > 0 &&
      args[0].kind == Ident &&
      pp.macros.contains(args[0].lexeme)
    push_cond(pp, cond)
    return
  }
  if name == "ifndef" {
    let cond = args.length() > 0 &&
      args[0].kind == Ident &&
      !pp.macros.contains(args[0].lexeme)
    push_cond(pp, cond)
    return
  }
  if name == "if" {
    let expanded = expand_if_tokens(pp, args)
    let cond = eval_if_expr(pp, expanded, name_tok.loc)
    push_cond(pp, cond)
    return
  }
  if name == "elif" {
    let expanded = expand_if_tokens(pp, args)
    let cond = eval_if_expr(pp, expanded, name_tok.loc)
    update_elif(pp, cond, name_tok.loc)
    return
  }
  if name == "else" {
    update_else(pp, name_tok.loc)
    return
  }
  if name == "endif" {
    pop_cond(pp, name_tok.loc)
    return
  }
  if name == "include" {
    if current_active(pp) {
      let expanded = expand_tokens(pp, args)
      match parse_include_path(pp, expanded, name_tok.loc) {
        Some(spec) => include_file(pp, spec, name_tok.loc, include_next=false)
        None => ()
      }
    }
    return
  }
  if name == "include_next" {
    if current_active(pp) {
      let expanded = expand_tokens(pp, args)
      match parse_include_path(pp, expanded, name_tok.loc) {
        Some(spec) => include_file(pp, spec, name_tok.loc, include_next=true)
        None => ()
      }
    }
    return
  }
  if name == "line" {
    if !current_active(pp) {
      return
    }
    let expanded = expand_tokens(pp, args)
    handle_line_directive(pp, expanded, name_tok.loc)
    return
  }
  if name == "error" {
    if current_active(pp) {
      add_pp_error(pp, name_tok.loc, "error: " + stringize_tokens(args))
    }
    return
  }
  if name == "warning" {
    if current_active(pp) {
      add_pp_error(pp, name_tok.loc, "warning: " + stringize_tokens(args))
    }
    return
  }
  if name == "pragma" {
    return
  }
  if current_active(pp) {
    add_pp_error(pp, name_tok.loc, "unknown preprocessor directive")
  }
}

///|
fn next_pp_token(pp : Preprocessor) -> Token {
  while true {
    if pp.pending.length() > 0 {
      match pp.pending.pop() {
        Some(tok) => return tok
        None => ()
      }
    }
    let tok = next_input_token(pp)
    if tok.kind == Eof {
      return tok
    }
    if tok.kind == Hash && tok.line_start {
      handle_directive(pp, tok)
      continue
    }
    if !current_active(pp) {
      continue
    }
    if tok.kind == Ident {
      match builtin_macro_tokens(pp, tok) {
        Some(tokens) => {
          push_tokens(pp, tokens)
          continue
        }
        None => ()
      }
    }
    if tok.kind == Ident && pp.macros.contains(tok.lexeme) {
      if is_expanding(pp, tok.lexeme) {
        return tok
      }
      match pp.macros.get(tok.lexeme) {
        None => ()
        Some(macro_def) =>
          if macro_def.is_function {
            let next_tok = next_raw_token(pp)
            if next_tok.kind != LParen || !is_adjacent(tok, next_tok) {
              push_back(pp, next_tok)
              return tok
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
                    push_expanding(pp, tok.lexeme)
                    let expanded_args = norm_args.map(arg => expand_tokens(
                      pp, arg,
                    ))
                    let replaced = substitute_macro(
                      macro_def,
                      norm_args,
                      expanded_args,
                      tok.loc,
                    )
                    let expanded = expand_tokens(pp, replaced)
                    pop_expanding(pp)
                    if expanded.length() > 0 {
                      push_tokens(pp, expanded)
                    }
                    continue
                  }
                }
            }
          } else {
            push_expanding(pp, tok.lexeme)
            let expanded = expand_tokens(pp, macro_def.replacement)
            pop_expanding(pp)
            push_tokens(pp, expanded)
            continue
          }
      }
    }
    return tok
  } else {
    { kind: Eof, lexeme: "", loc: lexer_loc(pp.lexer), line_start: false }
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
