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
  mut next_file_id : Int
  include_paths : Array[String]
  diags : DiagBag
  macros : Map[String, Macro]
  pending : Array[Token]
  mut held : Token?
  cond_stack : Array[CondState]
}

///|
fn new_preprocessor(file : SourceFile, diags : DiagBag) -> Preprocessor {
  {
    lexer: new_lexer(file, diags),
    lexer_stack: [],
    held_stack: [],
    path_stack: [],
    current_path: file.path,
    next_file_id: file.id + 1,
    include_paths: [],
    diags,
    macros: {},
    pending: [],
    held: None,
    cond_stack: [],
  }
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
  for d in dirs {
    let candidate = join_path(d, path)
    if @fs.path_exists(candidate) {
      return Some(candidate)
    }
  }
  None
}

///|
fn include_file(pp : Preprocessor, spec : IncludeSpec, loc : SrcLoc) -> Unit {
  match resolve_include_path(pp, spec.path, spec.is_angle) {
    None => add_pp_error(pp, loc, "include not found: \{spec.path}")
    Some(resolved) =>
      try @fs.read_file_to_string(resolved) catch {
        err =>
          add_pp_error(pp, loc, "failed to read include: \{err.to_string()}")
      } noraise {
        text => {
          let file = { id: pp.next_file_id, path: resolved, text }
          pp.next_file_id = pp.next_file_id + 1
          pp.lexer_stack.push(pp.lexer)
          pp.held_stack.push(pp.held)
          pp.held = None
          pp.path_stack.push(pp.current_path)
          pp.lexer = new_lexer(file, pp.diags)
          pp.current_path = resolved
        }
      }
  }
}

///|
fn parse_define_macro(
  pp : Preprocessor,
  args : Array[Token],
  loc : SrcLoc,
) -> Macro? {
  if args.length() > 0 && args[0].kind == LParen {
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
  args : Array[Array[Token]],
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
            let arg_tokens = if idx < args.length() { args[idx] } else { [] }
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
            next_tokens = if idx < args.length() { args[idx] } else { [] }
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
          let arg_tokens = if idx < args.length() { args[idx] } else { [] }
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
fn push_tokens(pp : Preprocessor, tokens : Array[Token]) -> Unit {
  let mut i = tokens.length()
  while i > 0 {
    i = i - 1
    pp.pending.push(tokens[i])
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
  try @strconv.parse_int(lexeme, base=0) catch {
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
      if tok.kind == IntLit {
        return parse_int_literal(p.pp, tok.lexeme, tok.loc)
      }
      if tok.kind == Ident {
        if tok.lexeme == "defined" {
          return parse_defined(p, loc)
        }
        match macro_int_value(p.pp, tok.lexeme, tok.loc) {
          Some(v) => return v
          None => return 0
        }
      }
      if tok.kind == LParen {
        let value = parse_logical_or(p, loc)
        if !match_kind(p, RParen) {
          add_pp_error(p.pp, loc, "missing ')' in #if expression")
        }
        return value
      }
      add_pp_error(p.pp, loc, "unexpected token in #if expression")
      0
    }
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
    value = value & parse_eq(p, loc)
  }
  value
}

///|
fn parse_bit_xor(p : IfParser, loc : SrcLoc) -> Int {
  let mut value = parse_bit_and(p, loc)
  while match_kind(p, Caret) {
    value = value ^ parse_bit_and(p, loc)
  }
  value
}

///|
fn parse_bit_or(p : IfParser, loc : SrcLoc) -> Int {
  let mut value = parse_bit_xor(p, loc)
  while match_kind(p, Pipe) {
    value = value | parse_bit_xor(p, loc)
  }
  value
}

///|
fn parse_logical_and(p : IfParser, loc : SrcLoc) -> Int {
  let mut value = parse_bit_or(p, loc)
  while match_kind(p, AmpAmp) {
    value = if value != 0 && parse_bit_or(p, loc) != 0 { 1 } else { 0 }
  }
  value
}

///|
fn parse_logical_or(p : IfParser, loc : SrcLoc) -> Int {
  let mut value = parse_logical_and(p, loc)
  while match_kind(p, PipePipe) {
    value = if value != 0 || parse_logical_and(p, loc) != 0 { 1 } else { 0 }
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
    match parse_define_macro(pp, slice_tokens(args, 1), name_tok.loc) {
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
    let cond = eval_if_expr(pp, args, name_tok.loc)
    push_cond(pp, cond)
    return
  }
  if name == "elif" {
    let cond = eval_if_expr(pp, args, name_tok.loc)
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
      match parse_include_path(pp, args, name_tok.loc) {
        Some(spec) => include_file(pp, spec, name_tok.loc)
        None => ()
      }
    }
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
    if tok.kind == Ident && pp.macros.contains(tok.lexeme) {
      match pp.macros.get(tok.lexeme) {
        None => ()
        Some(macro_def) =>
          if macro_def.is_function {
            let next_tok = next_raw_token(pp)
            if next_tok.kind != LParen {
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
                    let expanded = substitute_macro(
                      macro_def,
                      norm_args,
                      tok.loc,
                    )
                    if expanded.length() > 0 {
                      push_tokens(pp, expanded)
                    }
                    continue
                  }
                }
            }
          } else {
            push_tokens(pp, macro_def.replacement)
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
