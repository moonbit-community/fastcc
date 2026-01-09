///|
struct Lexer {
  file_id : Int
  text : String
  mut index : Int
  mut line : Int
  mut col : Int
  mut line_start : Bool
  diags : DiagBag
}

///|
fn new_lexer(file : SourceFile, diags : DiagBag) -> Lexer {
  {
    file_id: file.id,
    text: file.text,
    index: 0,
    line: 1,
    col: 1,
    line_start: true,
    diags,
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
) -> Token {
  { kind, lexeme, loc, line_start }
}

///|
fn peek_char(lex : Lexer) -> UInt16? {
  if lex.index >= lex.text.length() {
    return None
  }
  Some(lex.text[lex.index])
}

///|
fn peek_char_offset(lex : Lexer, offset : Int) -> UInt16? {
  let idx = lex.index + offset
  if idx >= lex.text.length() {
    return None
  }
  Some(lex.text[idx])
}

///|
fn advance(lex : Lexer) -> UInt16? {
  let c = peek_char(lex)
  match c {
    None => None
    Some(code) => {
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
  }
}

///|
fn advance_comment(lex : Lexer) -> UInt16? {
  let c = peek_char(lex)
  match c {
    None => None
    Some(code) => {
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
  }
}

///|
fn add_lex_error(lex : Lexer, loc : SrcLoc, message : String) -> Unit {
  add_error(lex.diags, loc, message)
}

///|
fn is_ws(code : UInt16) -> Bool {
  code == 32 ||
  code == 9 ||
  code == 10 ||
  code == 13 ||
  code == 12 ||
  code == 11
}

///|
fn is_ws_no_newline(code : UInt16) -> Bool {
  code == 32 || code == 9 || code == 13 || code == 12 || code == 11
}

///|
fn skip_ws(lex : Lexer) -> Unit {
  while true {
    match peek_char(lex) {
      None => return
      Some(code) => {
        if is_ws(code) {
          let _ = advance(lex)
          continue
        }
        if code == 92 && peek_char_offset(lex, 1) is Some(10) {
          let _ = advance_comment(lex)
          let _ = advance_comment(lex)
          continue
        }
        if code == 47 {
          match peek_char_offset(lex, 1) {
            Some(47) => {
              let _ = advance_comment(lex)
              let _ = advance_comment(lex)
              skip_line_comment(lex)
              continue
            }
            Some(42) => {
              let start_loc = lexer_loc(lex)
              let _ = advance_comment(lex)
              let _ = advance_comment(lex)
              skip_block_comment(lex, start_loc)
              continue
            }
            _ => ()
          }
        }
        return
      }
    }
  }
}

///|
fn skip_line_comment(lex : Lexer) -> Unit {
  while true {
    match peek_char(lex) {
      None => return
      Some(code) => {
        if code == 10 {
          return
        }
        let _ = advance_comment(lex)

      }
    }
  }
}

///|
fn skip_block_comment(lex : Lexer, start_loc : SrcLoc) -> Unit {
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
  (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == 95
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
  try text[start:end] catch {
    _ => ""
  } noraise {
    view => view.to_string()
  }
}

///|
fn lex_ident(lex : Lexer, loc : SrcLoc, line_start : Bool) -> Token {
  let start = lex.index
  let _ = advance(lex)
  while true {
    match peek_char(lex) {
      Some(code) => {
        if is_ident_continue(code) {
          let _ = advance(lex)
          continue
        }
        break
      }
      None => break
    }
  }
  let name = slice_to_string(lex.text, start, lex.index)
  make_token(keyword_or_ident(name), name, loc, line_start)
}

///|
fn lex_number(
  lex : Lexer,
  loc : SrcLoc,
  line_start : Bool,
  started_with_dot : Bool,
) -> Token {
  let start = lex.index
  let mut is_float = started_with_dot
  let mut is_hex = false
  if started_with_dot {
    let _ = advance(lex)
    while true {
      match peek_char(lex) {
        Some(code) if is_digit(code) => {
          let _ = advance(lex)
          continue
        }
        _ => break
      }
    }
  } else {
    match peek_char(lex) {
      Some(48) =>
        match peek_char_offset(lex, 1) {
          Some(88) => {
            is_hex = true
            let _ = advance(lex)
            let _ = advance(lex)
            while true {
              match peek_char(lex) {
                Some(code) if is_hex_digit(code) => {
                  let _ = advance(lex)
                  continue
                }
                _ => break
              }
            }
          }
          Some(120) => {
            is_hex = true
            let _ = advance(lex)
            let _ = advance(lex)
            while true {
              match peek_char(lex) {
                Some(code) if is_hex_digit(code) => {
                  let _ = advance(lex)
                  continue
                }
                _ => break
              }
            }
          }
          Some(66) => {
            let _ = advance(lex)
            let _ = advance(lex)
            while true {
              match peek_char(lex) {
                Some(code) if is_bin_digit(code) => {
                  let _ = advance(lex)
                  continue
                }
                _ => break
              }
            }
          }
          Some(98) => {
            let _ = advance(lex)
            let _ = advance(lex)
            while true {
              match peek_char(lex) {
                Some(code) if is_bin_digit(code) => {
                  let _ = advance(lex)
                  continue
                }
                _ => break
              }
            }
          }
          _ => {
            let _ = advance(lex)
            while true {
              match peek_char(lex) {
                Some(code) if is_digit(code) => {
                  let _ = advance(lex)
                  continue
                }
                _ => break
              }
            }
          }
        }
      _ => {
        let _ = advance(lex)
        while true {
          match peek_char(lex) {
            Some(code) if is_digit(code) => {
              let _ = advance(lex)
              continue
            }
            _ => break
          }
        }
      }
    }
    let mut dot_ok = true
    if peek_char_offset(lex, 1) is Some(46) {
      dot_ok = false
    }
    if peek_char(lex) is Some(46) && dot_ok {
      is_float = true
      let _ = advance(lex)
      while true {
        match peek_char(lex) {
          Some(code) if is_digit(code) => {
            let _ = advance(lex)
            continue
          }
          _ => break
        }
      }
    }
  }
  let exp_char : UInt16 = if is_hex { 112 } else { 101 }
  let exp_char_upper : UInt16 = if is_hex { 80 } else { 69 }
  if peek_char(lex) is Some(code) &&
    (code == exp_char || code == exp_char_upper) {
    is_float = true
    let _ = advance(lex)
    match peek_char(lex) {
      Some(43) => {
        let _ = advance(lex)

      }
      Some(45) => {
        let _ = advance(lex)

      }
      _ => ()
    }
    while true {
      match peek_char(lex) {
        Some(code) if is_digit(code) => {
          let _ = advance(lex)
          continue
        }
        _ => break
      }
    }
  }
  while true {
    match peek_char(lex) {
      Some(code) if is_ident_continue(code) => {
        let _ = advance(lex)
        continue
      }
      _ => break
    }
  }
  let lit = slice_to_string(lex.text, start, lex.index)
  let kind = if is_float { FloatLit } else { IntLit }
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
  let _ = advance(lex)
  while true {
    match peek_char(lex) {
      None => {
        add_lex_error(lex, loc, "unterminated string or char literal")
        break
      }
      Some(code) => {
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
        } else {
          let _ = advance(lex)

        }
      }
    }
  }
  let lit = slice_to_string(lex.text, start, lex.index)
  let kind = if quote == 34 { StrLit } else { CharLit }
  make_token(kind, lit, loc, line_start)
}

///|
fn lex_punct(lex : Lexer, loc : SrcLoc, line_start : Bool) -> Token {
  match advance(lex) {
    None => make_token(Eof, "", loc, line_start)
    Some(code) => {
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
        if peek_char(lex) is Some(35) {
          let _ = advance(lex)
          return make_token(HashHash, "##", loc, line_start)
        }
        return make_token(Hash, "#", loc, line_start)
      }
      if code == 46 {
        if peek_char(lex) is Some(46) && peek_char_offset(lex, 1) is Some(46) {
          let _ = advance(lex)
          let _ = advance(lex)
          return make_token(Ellipsis, "...", loc, line_start)
        }
        return make_token(Dot, ".", loc, line_start)
      }
      if code == 45 {
        if peek_char(lex) is Some(62) {
          let _ = advance(lex)
          return make_token(Arrow, "->", loc, line_start)
        }
        if peek_char(lex) is Some(45) {
          let _ = advance(lex)
          return make_token(MinusMinus, "--", loc, line_start)
        }
        if peek_char(lex) is Some(61) {
          let _ = advance(lex)
          return make_token(MinusAssign, "-=", loc, line_start)
        }
        return make_token(Minus, "-", loc, line_start)
      }
      if code == 43 {
        if peek_char(lex) is Some(43) {
          let _ = advance(lex)
          return make_token(PlusPlus, "++", loc, line_start)
        }
        if peek_char(lex) is Some(61) {
          let _ = advance(lex)
          return make_token(PlusAssign, "+=", loc, line_start)
        }
        return make_token(Plus, "+", loc, line_start)
      }
      if code == 42 {
        if peek_char(lex) is Some(61) {
          let _ = advance(lex)
          return make_token(StarAssign, "*=", loc, line_start)
        }
        return make_token(Star, "*", loc, line_start)
      }
      if code == 47 {
        if peek_char(lex) is Some(61) {
          let _ = advance(lex)
          return make_token(SlashAssign, "/=", loc, line_start)
        }
        return make_token(Slash, "/", loc, line_start)
      }
      if code == 37 {
        if peek_char(lex) is Some(61) {
          let _ = advance(lex)
          return make_token(PercentAssign, "%=", loc, line_start)
        }
        return make_token(Percent, "%", loc, line_start)
      }
      if code == 61 {
        if peek_char(lex) is Some(61) {
          let _ = advance(lex)
          return make_token(Eq, "==", loc, line_start)
        }
        return make_token(Assign, "=", loc, line_start)
      }
      if code == 33 {
        if peek_char(lex) is Some(61) {
          let _ = advance(lex)
          return make_token(Ne, "!=", loc, line_start)
        }
        return make_token(Bang, "!", loc, line_start)
      }
      if code == 60 {
        if peek_char(lex) is Some(60) {
          let _ = advance(lex)
          if peek_char(lex) is Some(61) {
            let _ = advance(lex)
            return make_token(ShiftLeftAssign, "<<=", loc, line_start)
          }
          return make_token(ShiftLeft, "<<", loc, line_start)
        }
        if peek_char(lex) is Some(61) {
          let _ = advance(lex)
          return make_token(Le, "<=", loc, line_start)
        }
        return make_token(Lt, "<", loc, line_start)
      }
      if code == 62 {
        if peek_char(lex) is Some(62) {
          let _ = advance(lex)
          if peek_char(lex) is Some(61) {
            let _ = advance(lex)
            return make_token(ShiftRightAssign, ">>=", loc, line_start)
          }
          return make_token(ShiftRight, ">>", loc, line_start)
        }
        if peek_char(lex) is Some(61) {
          let _ = advance(lex)
          return make_token(Ge, ">=", loc, line_start)
        }
        return make_token(Gt, ">", loc, line_start)
      }
      if code == 38 {
        if peek_char(lex) is Some(38) {
          let _ = advance(lex)
          return make_token(AmpAmp, "&&", loc, line_start)
        }
        if peek_char(lex) is Some(61) {
          let _ = advance(lex)
          return make_token(AmpAssign, "&=", loc, line_start)
        }
        return make_token(Amp, "&", loc, line_start)
      }
      if code == 124 {
        if peek_char(lex) is Some(124) {
          let _ = advance(lex)
          return make_token(PipePipe, "||", loc, line_start)
        }
        if peek_char(lex) is Some(61) {
          let _ = advance(lex)
          return make_token(PipeAssign, "|=", loc, line_start)
        }
        return make_token(Pipe, "|", loc, line_start)
      }
      if code == 94 {
        if peek_char(lex) is Some(61) {
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
  }
}
