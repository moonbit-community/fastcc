///|
struct Lexer {
  file_id : Int
  text : String
  text_len : Int
  mut index : Int
  mut line : Int
  mut col : Int
  mut line_start : Bool
  diags : @diag.DiagBag
  interner : @intern.StringInterner
  keyword_ids : KeywordIds
  lexeme_pool : LexemePool
}

///|
fn new_lexer(
  file : @source.SourceFile,
  diags : @diag.DiagBag,
  interner : @intern.StringInterner,
  keyword_ids : KeywordIds,
  lexeme_pool : LexemePool,
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
    lexeme_pool,
  }
}

///|
fn lexer_loc(lex : Lexer) -> @source.SrcLoc {
  @source.SrcLoc::{
    file_id: lex.file_id,
    line: lex.line,
    col: lex.col,
    offset: lex.index,
  }
}

///|
fn next_token(lex : Lexer) -> Token {
  skip_ws(lex)
  let loc = lexer_loc(lex)
  let line_start = lex.line_start
  match peek_char(lex) {
    None => make_token(Eof, loc, line_start)
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
  loc : @source.SrcLoc,
  line_start : Bool,
  id? : Int = 0,
  lexeme_id? : Int = 0,
) -> Token {
  let value = token_value_from_parts(id, lexeme_id)
  { kind, value, loc, line_start, hidden: empty_hidden }
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
fn advance_punct(lex : Lexer) -> Unit {
  lex.index = lex.index + 1
  lex.col = lex.col + 1
  lex.line_start = false
}

///|
fn add_lex_error(lex : Lexer, loc : @source.SrcLoc, message : String) -> Unit {
  @diag.add_error(lex.diags, loc, message)
}

///|
fn is_ws_no_newline(code : UInt16) -> Bool {
  code == 32 || code == 9 || code == 13 || code == 12 || code == 11
}

///|
fn skip_ws(lex : Lexer) -> Unit {
  let text = lex.text
  let len = lex.text_len
  while true {
    let idx = lex.index
    if idx >= len {
      return
    }
    let code = text[idx]
    if is_ws_no_newline(code) {
      let mut next = idx + 1
      while next < len {
        let next_code = text[next]
        if !is_ws_no_newline(next_code) {
          break
        }
        next = next + 1
      }
      let delta = next - idx
      lex.index = next
      lex.col = lex.col + delta
      continue
    }
    if code == 10 {
      lex.index = idx + 1
      lex.line = lex.line + 1
      lex.col = 1
      lex.line_start = true
      continue
    }
    if code == 92 {
      let next = idx + 1
      if next < len && text[next] == 10 {
        lex.index = idx + 2
        lex.line = lex.line + 1
        lex.col = 1
        lex.line_start = false
        continue
      }
    }
    if code == 47 {
      let next = idx + 1
      if next < len {
        let next_code = text[next]
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
  let mut col = lex.col
  while i < len {
    if text[i] == 10 {
      lex.index = i + 1
      lex.line = lex.line + 1
      lex.col = 1
      lex.line_start = true
      return
    }
    i = i + 1
    col = col + 1
  }
  lex.index = len
  lex.col = col
}

///|
fn skip_block_comment(lex : Lexer, start_loc : @source.SrcLoc) -> Unit {
  let idx = lex.index
  let len = lex.text_len
  if idx >= len {
    add_lex_error(lex, start_loc, "unterminated block comment")
    return
  }
  let text = lex.text
  let mut i = idx
  let mut line = lex.line
  let mut col = lex.col
  let mut line_start = lex.line_start
  while i < len {
    let code = text[i]
    if code == 10 {
      line = line + 1
      col = 1
      line_start = true
      i = i + 1
      continue
    }
    if code == 42 && i + 1 < len && text[i + 1] == 47 {
      col = col + 2
      lex.index = i + 2
      lex.line = line
      lex.col = col
      lex.line_start = line_start
      return
    }
    col = col + 1
    i = i + 1
  }
  lex.index = len
  lex.line = line
  lex.col = col
  lex.line_start = line_start
  add_lex_error(lex, start_loc, "unterminated block comment")
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
///|
fn slice_to_view(text : String, start : Int, end : Int) -> StringView {
  text.view(start_offset=start, end_offset=end)
}

///|
fn lex_ident(lex : Lexer, loc : @source.SrcLoc, line_start : Bool) -> Token {
  let start = lex.index
  let text = lex.text
  let len = lex.text_len
  let mut hash : UInt = @intern.tok_hash_init
  let mut idx = start + 1
  hash = @intern.tok_hash_step(hash, text[start])
  while idx < len && is_ident_continue(text[idx]) {
    hash = @intern.tok_hash_step(hash, text[idx])
    idx = idx + 1
  }
  lex.index = idx
  lex.col = lex.col + (idx - start)
  lex.line_start = false
  let name_view = slice_to_view(text, start, idx)
  let (_, id) = lex.interner.intern_view_with_id_hash(name_view, hash)
  match keyword_kind_from_id(id, lex.keyword_ids) {
    Some(kind) => make_token(kind, loc, line_start, id=id)
    None => make_token(Ident, loc, line_start, id=id)
  }
}

///|
fn lex_number(
  lex : Lexer,
  loc : @source.SrcLoc,
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
  let kind = if is_float { TokenKind::FloatLit } else { TokenKind::IntLit }
  let lexeme_id = lexeme_pool_intern_slice(lex.lexeme_pool, text, start, idx)
  make_token(kind, loc, line_start, lexeme_id=lexeme_id)
}

///|
///|
fn skip_string_literal(lex : Lexer, loc : @source.SrcLoc, quote : UInt16) -> Unit {
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
}

///|
fn lex_string_literal(
  lex : Lexer,
  loc : @source.SrcLoc,
  line_start : Bool,
  quote : UInt16,
) -> Token {
  let start = lex.index
  skip_string_literal(lex, loc, quote)
  let kind = if quote == 34 { StrLit } else { CharLit }
  let lexeme_id = lexeme_pool_intern_slice(lex.lexeme_pool, lex.text, start, lex.index)
  make_token(kind, loc, line_start, lexeme_id=lexeme_id)
}

///|
fn lex_punct(lex : Lexer, loc : @source.SrcLoc, line_start : Bool) -> Token {
  let idx = lex.index
  if idx >= lex.text_len {
    return make_token(Eof, loc, line_start)
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
  match code {
    40 => make_token(LParen, loc, line_start)
    41 => make_token(RParen, loc, line_start)
    123 => make_token(LBrace, loc, line_start)
    125 => make_token(RBrace, loc, line_start)
    91 => make_token(LBracket, loc, line_start)
    93 => make_token(RBracket, loc, line_start)
    59 => make_token(Semicolon, loc, line_start)
    44 => make_token(Comma, loc, line_start)
    58 => make_token(Colon, loc, line_start)
    63 => make_token(Question, loc, line_start)
    35 => {
      if lex.index < len && text[lex.index] == 35 {
        advance_punct(lex)
        return make_token(HashHash, loc, line_start)
      }
      make_token(Hash, loc, line_start)
    }
    46 => {
      if lex.index + 1 < len &&
        text[lex.index] == 46 &&
        text[lex.index + 1] == 46 {
        advance_punct(lex)
        advance_punct(lex)
        return make_token(Ellipsis, loc, line_start)
      }
      make_token(Dot, loc, line_start)
    }
    45 => {
      if lex.index < len {
        let next = text[lex.index]
        if next == 62 {
          advance_punct(lex)
          return make_token(Arrow, loc, line_start)
        }
        if next == 45 {
          advance_punct(lex)
          return make_token(MinusMinus, loc, line_start)
        }
        if next == 61 {
          advance_punct(lex)
          return make_token(MinusAssign, loc, line_start)
        }
      }
      make_token(Minus, loc, line_start)
    }
    43 => {
      if lex.index < len {
        let next = text[lex.index]
        if next == 43 {
          advance_punct(lex)
          return make_token(PlusPlus, loc, line_start)
        }
        if next == 61 {
          advance_punct(lex)
          return make_token(PlusAssign, loc, line_start)
        }
      }
      make_token(Plus, loc, line_start)
    }
    42 => {
      if lex.index < len && text[lex.index] == 61 {
        advance_punct(lex)
        return make_token(StarAssign, loc, line_start)
      }
      make_token(Star, loc, line_start)
    }
    47 => {
      if lex.index < len && text[lex.index] == 61 {
        advance_punct(lex)
        return make_token(SlashAssign, loc, line_start)
      }
      make_token(Slash, loc, line_start)
    }
    37 => {
      if lex.index < len && text[lex.index] == 61 {
        advance_punct(lex)
        return make_token(PercentAssign, loc, line_start)
      }
      make_token(Percent, loc, line_start)
    }
    61 => {
      if lex.index < len && text[lex.index] == 61 {
        advance_punct(lex)
        return make_token(Eq, loc, line_start)
      }
      make_token(Assign, loc, line_start)
    }
    33 => {
      if lex.index < len && text[lex.index] == 61 {
        advance_punct(lex)
        return make_token(Ne, loc, line_start)
      }
      make_token(Bang, loc, line_start)
    }
    60 => {
      if lex.index < len && text[lex.index] == 60 {
        advance_punct(lex)
        if lex.index < len && text[lex.index] == 61 {
          advance_punct(lex)
          return make_token(ShiftLeftAssign, loc, line_start)
        }
        return make_token(ShiftLeft, loc, line_start)
      }
      if lex.index < len && text[lex.index] == 61 {
        advance_punct(lex)
        return make_token(Le, loc, line_start)
      }
      make_token(Lt, loc, line_start)
    }
    62 => {
      if lex.index < len && text[lex.index] == 62 {
        advance_punct(lex)
        if lex.index < len && text[lex.index] == 61 {
          advance_punct(lex)
          return make_token(ShiftRightAssign, loc, line_start)
        }
        return make_token(ShiftRight, loc, line_start)
      }
      if lex.index < len && text[lex.index] == 61 {
        advance_punct(lex)
        return make_token(Ge, loc, line_start)
      }
      make_token(Gt, loc, line_start)
    }
    38 => {
      if lex.index < len {
        let next = text[lex.index]
        if next == 38 {
          advance_punct(lex)
          return make_token(AmpAmp, loc, line_start)
        }
        if next == 61 {
          advance_punct(lex)
          return make_token(AmpAssign, loc, line_start)
        }
      }
      make_token(Amp, loc, line_start)
    }
    124 => {
      if lex.index < len {
        let next = text[lex.index]
        if next == 124 {
          advance_punct(lex)
          return make_token(PipePipe, loc, line_start)
        }
        if next == 61 {
          advance_punct(lex)
          return make_token(PipeAssign, loc, line_start)
        }
      }
      make_token(Pipe, loc, line_start)
    }
    94 => {
      if lex.index < len && text[lex.index] == 61 {
        advance_punct(lex)
        return make_token(CaretAssign, loc, line_start)
      }
      make_token(Caret, loc, line_start)
    }
    126 => make_token(Tilde, loc, line_start)
    _ => {
      add_lex_error(lex, loc, "unexpected character")
      let lexeme_id =
        lexeme_pool_intern_slice(lex.lexeme_pool, lex.text, loc.offset, lex.index)
      make_token(Invalid, loc, line_start, lexeme_id=lexeme_id)
    }
  }
}
