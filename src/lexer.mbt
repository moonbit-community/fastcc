///|
struct Lexer {
  file_id : Int
  text : String
  text_len : Int
  mut index : Int
  mut line : Int
  mut col : Int
  mut line_start : Bool
  diags : DiagBag
  interner : StringInterner
  keyword_ids : KeywordIds
}

///|
fn new_lexer(
  file : SourceFile,
  diags : DiagBag,
  interner : StringInterner,
  keyword_ids : KeywordIds,
) -> Lexer {
  {
    file_id: file.id,
    text: file.text,
    text_len: file.text.length(),
    index: 0,
    line: 1,
    col: 1,
    line_start: true,
    diags,
    interner,
    keyword_ids,
  }
}

///|
fn lexer_loc(lex : Lexer) -> SrcLoc {
  { file_id: lex.file_id, line: lex.line, col: lex.col, offset: lex.index }
}

///|
fn next_token(lex : Lexer) -> Token {
  skip_ws(lex)
  let loc = lexer_loc(lex)
  let line_start = lex.line_start
  match peek_char(lex) {
    None => make_token(Eof, "", loc, line_start)
    Some(code) => {
      if is_ident_start(code) {
        return lex_ident(lex, loc, line_start)
      }
      if is_digit(code) {
        return lex_number(lex, loc, line_start, false)
      }
      if code == 46 &&
        peek_char_offset(lex, 1) is Some(next_code) &&
        is_digit(next_code) {
        return lex_number(lex, loc, line_start, true)
      }
      if code == 34 || code == 39 {
        return lex_string_literal(lex, loc, line_start, code)
      }
      return lex_punct(lex, loc, line_start)
    }
  }
}

///|
fn make_token(
  kind : TokenKind,
  lexeme : String,
  loc : SrcLoc,
  line_start : Bool,
  id? : Int = 0,
) -> Token {
  { kind, lexeme, id, loc, line_start, hidden: empty_hidden }
}

///|
fn peek_char(lex : Lexer) -> UInt16? {
  if lex.index >= lex.text_len {
    return None
  }
  Some(lex.text[lex.index])
}

///|
fn peek_char_offset(lex : Lexer, offset : Int) -> UInt16? {
  let idx = lex.index + offset
  if idx >= lex.text_len {
    return None
  }
  Some(lex.text[idx])
}

///|
fn advance(lex : Lexer) -> UInt16? {
  if lex.index >= lex.text_len {
    return None
  }
  let code = lex.text[lex.index]
  lex.index = lex.index + 1
  if code == 10 {
    lex.line = lex.line + 1
    lex.col = 1
    lex.line_start = true
  } else {
    lex.col = lex.col + 1
    if !is_ws_no_newline(code) {
      lex.line_start = false
    }
  }
  Some(code)
}

///|
fn advance_comment(lex : Lexer) -> UInt16? {
  if lex.index >= lex.text_len {
    return None
  }
  let code = lex.text[lex.index]
  lex.index = lex.index + 1
  if code == 10 {
    lex.line = lex.line + 1
    lex.col = 1
    lex.line_start = true
  } else {
    lex.col = lex.col + 1
  }
  Some(code)
}

///|
fn add_lex_error(lex : Lexer, loc : SrcLoc, message : String) -> Unit {
  add_error(lex.diags, loc, message)
}

///|
fn is_ws_no_newline(code : UInt16) -> Bool {
  code == 32 || code == 9 || code == 13 || code == 12 || code == 11
}

///|
fn skip_ws(lex : Lexer) -> Unit {
  while true {
    let idx = lex.index
    if idx >= lex.text_len {
      return
    }
    let code = lex.text[idx]
    if is_ws_no_newline(code) {
      let text = lex.text
      let len = lex.text_len
      let mut next = idx + 1
      while next < len && is_ws_no_newline(text[next]) {
        next = next + 1
      }
      let delta = next - idx
      lex.index = next
      lex.col = lex.col + delta
      continue
    }
    if code == 10 {
      let _ = advance(lex)
      continue
    }
    if code == 92 {
      let next = idx + 1
      if next < lex.text_len && lex.text[next] == 10 {
        let _ = advance_comment(lex) // '\'
        let _ = advance_comment(lex) // '\n'
        lex.line_start = false
        continue
      }
    }
    if code == 47 {
      let next = idx + 1
      if next < lex.text_len {
        let next_code = lex.text[next]
        if next_code == 47 {
          let _ = advance_comment(lex)
          let _ = advance_comment(lex)
          skip_line_comment(lex)
          continue
        }
        if next_code == 42 {
          let start_loc = lexer_loc(lex)
          let _ = advance_comment(lex)
          let _ = advance_comment(lex)
          skip_block_comment(lex, start_loc)
          continue
        }
      }
    }
    return
  }
}

///|
fn skip_line_comment(lex : Lexer) -> Unit {
  let idx = lex.index
  let len = lex.text_len
  if idx >= len {
    return
  }
  let text = lex.text
  let mut i = idx
  while i < len && text[i] != 10 {
    i = i + 1
  }
  if i > idx {
    lex.index = i
    lex.col = lex.col + (i - idx)
  }
  if i < len {
    let _ = advance_comment(lex)
  }
}

///|
fn skip_block_comment(lex : Lexer, start_loc : SrcLoc) -> Unit {
  let idx = lex.index
  let len = lex.text_len
  if idx < len {
    let text = lex.text
    let mut i = idx
    while i + 1 < len {
      let code = text[i]
      if code == 10 {
        break
      }
      if code == 42 && text[i + 1] == 47 {
        let delta = i + 2 - idx
        lex.index = idx + delta
        lex.col = lex.col + delta
        return
      }
      i = i + 1
    }
  }
  let mut saw_star = false
  while true {
    match advance_comment(lex) {
      None => {
        add_lex_error(lex, start_loc, "unterminated block comment")
        return
      }
      Some(code) => {
        if saw_star && code == 47 {
          return
        }
        saw_star = code == 42
      }
    }
  }
}

///|
fn is_ident_start(code : UInt16) -> Bool {
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  code == 95 ||
  code == 36 ||
  code == 64 // allow '@' so we can lex Objective-C tokens in skipped branches
}

///|
fn is_ident_continue(code : UInt16) -> Bool {
  is_ident_start(code) || is_digit(code)
}

///|
fn is_digit(code : UInt16) -> Bool {
  code >= 48 && code <= 57
}

///|
fn is_hex_digit(code : UInt16) -> Bool {
  is_digit(code) || (code >= 65 && code <= 70) || (code >= 97 && code <= 102)
}

///|
fn is_bin_digit(code : UInt16) -> Bool {
  code == 48 || code == 49
}

///|
fn slice_to_string(text : String, start : Int, end : Int) -> String {
  text.view(start_offset=start, end_offset=end).to_string()
}

///|
fn slice_to_view(text : String, start : Int, end : Int) -> StringView {
  text.view(start_offset=start, end_offset=end)
}

///|
fn lex_ident(lex : Lexer, loc : SrcLoc, line_start : Bool) -> Token {
  let start = lex.index
  let text = lex.text
  let len = lex.text_len
  let mut hash : UInt = tok_hash_init
  let mut idx = start + 1
  hash = tok_hash_step(hash, text[start])
  while idx < len && is_ident_continue(text[idx]) {
    hash = tok_hash_step(hash, text[idx])
    idx = idx + 1
  }
  lex.index = idx
  lex.col = lex.col + (idx - start)
  lex.line_start = false
  let name_view = slice_to_view(text, start, idx)
  let (name, id) = lex.interner.intern_view_with_id_hash(name_view, hash)
  match keyword_kind_from_id(id, lex.keyword_ids) {
    Some(kind) => make_token(kind, name, loc, line_start, id=id)
    None => make_token(Ident, name, loc, line_start, id=id)
  }
}

///|
fn lex_number(
  lex : Lexer,
  loc : SrcLoc,
  line_start : Bool,
  started_with_dot : Bool,
) -> Token {
  let start = lex.index
  let text = lex.text
  let len = lex.text_len
  let mut idx = start
  let mut is_float = started_with_dot
  let mut is_hex = false
  if started_with_dot {
    idx = start + 1
    while idx < len && is_digit(text[idx]) {
      idx = idx + 1
    }
  } else {
    if idx < len && text[idx] == 48 {
      let next = idx + 1
      if next < len {
        let next_code = text[next]
        if next_code == 88 || next_code == 120 {
          is_hex = true
          idx = idx + 2
          while idx < len && is_hex_digit(text[idx]) {
            idx = idx + 1
          }
        } else if next_code == 66 || next_code == 98 {
          idx = idx + 2
          while idx < len && is_bin_digit(text[idx]) {
            idx = idx + 1
          }
        } else {
          idx = idx + 1
          while idx < len && is_digit(text[idx]) {
            idx = idx + 1
          }
        }
      } else {
        idx = idx + 1
      }
    } else {
      idx = idx + 1
      while idx < len && is_digit(text[idx]) {
        idx = idx + 1
      }
    }
    let mut dot_ok = true
    if idx + 1 < len && text[idx + 1] == 46 {
      dot_ok = false
    }
    if idx < len && text[idx] == 46 && dot_ok {
      is_float = true
      idx = idx + 1
      let accept_digit = if is_hex { is_hex_digit } else { is_digit }
      while idx < len && accept_digit(text[idx]) {
        idx = idx + 1
      }
    }
  }
  let exp_char : UInt16 = if is_hex { 112 } else { 101 }
  let exp_char_upper : UInt16 = if is_hex { 80 } else { 69 }
  if idx < len {
    let code = text[idx]
    if code == exp_char || code == exp_char_upper {
      is_float = true
      idx = idx + 1
      if idx < len {
        let sign = text[idx]
        if sign == 43 || sign == 45 {
          idx = idx + 1
        }
      }
      while idx < len && is_digit(text[idx]) {
        idx = idx + 1
      }
    }
  }
  while idx < len && is_ident_continue(text[idx]) {
    idx = idx + 1
  }
  lex.index = idx
  lex.col = lex.col + (idx - start)
  lex.line_start = false
  let lit = slice_to_string(text, start, idx)
  let kind = if is_float { TokenKind::FloatLit } else { TokenKind::IntLit }
  make_token(kind, lit, loc, line_start)
}

///|
fn lex_string_literal(
  lex : Lexer,
  loc : SrcLoc,
  line_start : Bool,
  quote : UInt16,
) -> Token {
  let start = lex.index
  let text = lex.text
  let len = lex.text_len
  let _ = advance(lex)
  while true {
    let mut idx = lex.index
    while idx < len {
      let code = text[idx]
      if code == quote || code == 10 || code == 92 {
        break
      }
      idx = idx + 1
    }
    if idx > lex.index {
      lex.col = lex.col + (idx - lex.index)
      lex.index = idx
    }
    if lex.index >= len {
      add_lex_error(lex, loc, "unterminated string or char literal")
      break
    }
    let code = text[lex.index]
    if code == quote {
      let _ = advance(lex)
      break
    }
    if code == 10 {
      add_lex_error(lex, loc, "unterminated string or char literal")
      break
    }
    if code == 92 {
      let _ = advance(lex)
      match peek_char(lex) {
        None => {
          add_lex_error(lex, loc, "unterminated escape sequence")
          break
        }
        Some(10) => {
          let _ = advance(lex)
          continue
        }
        Some(_) => {
          let _ = advance(lex)
          continue
        }
      }
    }
  }
  let lit = slice_to_string(text, start, lex.index)
  let kind = if quote == 34 { StrLit } else { CharLit }
  make_token(kind, lit, loc, line_start)
}

///|
fn lex_punct(lex : Lexer, loc : SrcLoc, line_start : Bool) -> Token {
  let idx = lex.index
  if idx >= lex.text_len {
    return make_token(Eof, "", loc, line_start)
  }
  let text = lex.text
  let len = lex.text_len
  let code = text[idx]
  lex.index = idx + 1
  if code == 10 {
    lex.line = lex.line + 1
    lex.col = 1
    lex.line_start = true
  } else {
    lex.col = lex.col + 1
    lex.line_start = false
  }
  if code == 40 {
    return make_token(LParen, "(", loc, line_start)
  }
  if code == 41 {
    return make_token(RParen, ")", loc, line_start)
  }
  if code == 123 {
    return make_token(LBrace, "{", loc, line_start)
  }
  if code == 125 {
    return make_token(RBrace, "}", loc, line_start)
  }
  if code == 91 {
    return make_token(LBracket, "[", loc, line_start)
  }
  if code == 93 {
    return make_token(RBracket, "]", loc, line_start)
  }
  if code == 59 {
    return make_token(Semicolon, ";", loc, line_start)
  }
  if code == 44 {
    return make_token(Comma, ",", loc, line_start)
  }
  if code == 58 {
    return make_token(Colon, ":", loc, line_start)
  }
  if code == 63 {
    return make_token(Question, "?", loc, line_start)
  }
  if code == 35 {
    if lex.index < len && text[lex.index] == 35 {
      let _ = advance(lex)
      return make_token(HashHash, "##", loc, line_start)
    }
    return make_token(Hash, "#", loc, line_start)
  }
  if code == 46 {
    if lex.index + 1 < len &&
      text[lex.index] == 46 &&
      text[lex.index + 1] == 46 {
      let _ = advance(lex)
      let _ = advance(lex)
      return make_token(Ellipsis, "...", loc, line_start)
    }
    return make_token(Dot, ".", loc, line_start)
  }
  if code == 45 {
    if lex.index < len {
      let next = text[lex.index]
      if next == 62 {
        let _ = advance(lex)
        return make_token(Arrow, "->", loc, line_start)
      }
      if next == 45 {
        let _ = advance(lex)
        return make_token(MinusMinus, "--", loc, line_start)
      }
      if next == 61 {
        let _ = advance(lex)
        return make_token(MinusAssign, "-=", loc, line_start)
      }
    }
    return make_token(Minus, "-", loc, line_start)
  }
  if code == 43 {
    if lex.index < len {
      let next = text[lex.index]
      if next == 43 {
        let _ = advance(lex)
        return make_token(PlusPlus, "++", loc, line_start)
      }
      if next == 61 {
        let _ = advance(lex)
        return make_token(PlusAssign, "+=", loc, line_start)
      }
    }
    return make_token(Plus, "+", loc, line_start)
  }
  if code == 42 {
    if lex.index < len && text[lex.index] == 61 {
      let _ = advance(lex)
      return make_token(StarAssign, "*=", loc, line_start)
    }
    return make_token(Star, "*", loc, line_start)
  }
  if code == 47 {
    if lex.index < len && text[lex.index] == 61 {
      let _ = advance(lex)
      return make_token(SlashAssign, "/=", loc, line_start)
    }
    return make_token(Slash, "/", loc, line_start)
  }
  if code == 37 {
    if lex.index < len && text[lex.index] == 61 {
      let _ = advance(lex)
      return make_token(PercentAssign, "%=", loc, line_start)
    }
    return make_token(Percent, "%", loc, line_start)
  }
  if code == 61 {
    if lex.index < len && text[lex.index] == 61 {
      let _ = advance(lex)
      return make_token(Eq, "==", loc, line_start)
    }
    return make_token(Assign, "=", loc, line_start)
  }
  if code == 33 {
    if lex.index < len && text[lex.index] == 61 {
      let _ = advance(lex)
      return make_token(Ne, "!=", loc, line_start)
    }
    return make_token(Bang, "!", loc, line_start)
  }
  if code == 60 {
    if lex.index < len && text[lex.index] == 60 {
      let _ = advance(lex)
      if lex.index < len && text[lex.index] == 61 {
        let _ = advance(lex)
        return make_token(ShiftLeftAssign, "<<=", loc, line_start)
      }
      return make_token(ShiftLeft, "<<", loc, line_start)
    }
    if lex.index < len && text[lex.index] == 61 {
      let _ = advance(lex)
      return make_token(Le, "<=", loc, line_start)
    }
    return make_token(Lt, "<", loc, line_start)
  }
  if code == 62 {
    if lex.index < len && text[lex.index] == 62 {
      let _ = advance(lex)
      if lex.index < len && text[lex.index] == 61 {
        let _ = advance(lex)
        return make_token(ShiftRightAssign, ">>=", loc, line_start)
      }
      return make_token(ShiftRight, ">>", loc, line_start)
    }
    if lex.index < len && text[lex.index] == 61 {
      let _ = advance(lex)
      return make_token(Ge, ">=", loc, line_start)
    }
    return make_token(Gt, ">", loc, line_start)
  }
  if code == 38 {
    if lex.index < len {
      let next = text[lex.index]
      if next == 38 {
        let _ = advance(lex)
        return make_token(AmpAmp, "&&", loc, line_start)
      }
      if next == 61 {
        let _ = advance(lex)
        return make_token(AmpAssign, "&=", loc, line_start)
      }
    }
    return make_token(Amp, "&", loc, line_start)
  }
  if code == 124 {
    if lex.index < len {
      let next = text[lex.index]
      if next == 124 {
        let _ = advance(lex)
        return make_token(PipePipe, "||", loc, line_start)
      }
      if next == 61 {
        let _ = advance(lex)
        return make_token(PipeAssign, "|=", loc, line_start)
      }
    }
    return make_token(Pipe, "|", loc, line_start)
  }
  if code == 94 {
    if lex.index < len && text[lex.index] == 61 {
      let _ = advance(lex)
      return make_token(CaretAssign, "^=", loc, line_start)
    }
    return make_token(Caret, "^", loc, line_start)
  }
  if code == 126 {
    return make_token(Tilde, "~", loc, line_start)
  }
  add_lex_error(lex, loc, "unexpected character")
  make_token(
    Invalid,
    slice_to_string(lex.text, loc.offset, lex.index),
    loc,
    line_start,
  )
}
