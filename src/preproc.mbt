///|
struct CondState {
  parent_active : Bool
  mut taken : Bool
  mut active : Bool
}

///|
struct Preprocessor {
  lexer : Lexer
  diags : DiagBag
  macros : Map[String, Array[Token]]
  pending : Array[Token]
  mut held : Token?
  cond_stack : Array[CondState]
}

///|
fn new_preprocessor(file : SourceFile, diags : DiagBag) -> Preprocessor {
  {
    lexer: new_lexer(file, diags),
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
  match pp.held {
    None => next_token(pp.lexer)
    Some(tok) => {
      pp.held = None
      tok
    }
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
fn is_zero_literal(lexeme : String) -> Bool {
  lexeme == "0" ||
  lexeme == "0x0" ||
  lexeme == "0X0" ||
  lexeme == "0b0" ||
  lexeme == "0B0"
}

///|
fn eval_if_expr(pp : Preprocessor, tokens : Array[Token], loc : SrcLoc) -> Bool {
  if tokens.length() == 0 {
    add_pp_error(pp, loc, "empty #if expression")
    return false
  }
  let first = tokens[0]
  if first.lexeme == "defined" {
    if tokens.length() >= 2 && tokens[1].kind == Ident {
      return pp.macros.contains(tokens[1].lexeme)
    }
    if tokens.length() >= 4 &&
      tokens[1].kind == LParen &&
      tokens[2].kind == Ident &&
      tokens[3].kind == RParen {
      return pp.macros.contains(tokens[2].lexeme)
    }
    add_pp_error(pp, loc, "malformed defined operator")
    return false
  }
  if first.kind == IntLit {
    return !is_zero_literal(first.lexeme)
  }
  add_pp_error(pp, loc, "unsupported #if expression")
  false
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
    let replacement = slice_tokens(args, 1)
    pp.macros.set(macro_name, normalize_macro_tokens(replacement))
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
      add_pp_error(pp, name_tok.loc, "#include not implemented")
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
        Some(expansion) => push_tokens(pp, expansion)
        None => ()
      }
      continue
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
