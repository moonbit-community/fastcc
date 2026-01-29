///|
pub type Lexer = @lexer_core.Lexer

///|
pub fn new_lexer(
  file : @source.SourceFile,
  diags : @diag.DiagBag,
  interner : @intern.StringInterner,
  keyword_ids : @tokens.KeywordIds,
  lexeme_pool : @tokens.LexemePool,
) -> Lexer {
  @lexer_core.new_lexer(file, diags, interner, keyword_ids, lexeme_pool)
}

///|
pub fn lexer_loc(lex : Lexer) -> @source.SrcLoc {
  @lexer_core.lexer_loc(lex)
}

///|
pub fn next_token(lex : Lexer) -> @tokens.Token {
  @lexer_core.next_token(lex)
}

///|
pub fn make_token(
  kind : @tokens.TokenKind,
  loc : @source.SrcLoc,
  line_start : Bool,
  id? : Int = 0,
  lexeme_id? : Int = 0,
) -> @tokens.Token {
  @lexer_core.make_token(kind, loc, line_start, id=id, lexeme_id=lexeme_id)
}

///|
pub fn peek_char(lex : Lexer) -> UInt16? {
  @lexer_core.peek_char(lex)
}

///|
pub fn peek_char_offset(lex : Lexer, offset : Int) -> UInt16? {
  @lexer_core.peek_char_offset(lex, offset)
}

///|
pub fn advance(lex : Lexer) -> UInt16? {
  @lexer_core.advance(lex)
}

///|
pub fn skip_ws(lex : Lexer) -> Unit {
  @lexer_core.skip_ws(lex)
}

///|
pub fn skip_line_comment(lex : Lexer) -> Unit {
  @lexer_core.skip_line_comment(lex)
}

///|
pub fn skip_block_comment(lex : Lexer, loc : @source.SrcLoc) -> Unit {
  @lexer_core.skip_block_comment(lex, loc)
}

///|
pub fn skip_string_literal(lex : Lexer, loc : @source.SrcLoc, quote : UInt16) -> Unit {
  @lexer_core.skip_string_literal(lex, loc, quote)
}

///|
pub fn advance_punct(lex : Lexer) -> Unit {
  @lexer_core.advance_punct(lex)
}

///|
pub fn lex_ident(lex : Lexer, loc : @source.SrcLoc, line_start : Bool) -> @tokens.Token {
  @lexer_core.lex_ident(lex, loc, line_start)
}

///|
pub fn lex_number(
  lex : Lexer,
  loc : @source.SrcLoc,
  line_start : Bool,
  float_start : Bool,
) -> @tokens.Token {
  @lexer_core.lex_number(lex, loc, line_start, float_start)
}

///|
pub fn lex_string_literal(
  lex : Lexer,
  loc : @source.SrcLoc,
  line_start : Bool,
  quote : UInt16,
) -> @tokens.Token {
  @lexer_core.lex_string_literal(lex, loc, line_start, quote)
}

///|
pub fn lex_punct(lex : Lexer, loc : @source.SrcLoc, line_start : Bool) -> @tokens.Token {
  @lexer_core.lex_punct(lex, loc, line_start)
}

///|
pub fn is_digit(code : UInt16) -> Bool {
  @lexer_core.is_digit(code)
}

///|
pub fn is_hex_digit(code : UInt16) -> Bool {
  @lexer_core.is_hex_digit(code)
}

///|
pub fn is_bin_digit(code : UInt16) -> Bool {
  @lexer_core.is_bin_digit(code)
}

///|
pub fn is_ident_start(code : UInt16) -> Bool {
  @lexer_core.is_ident_start(code)
}

///|
pub fn is_ident_continue(code : UInt16) -> Bool {
  @lexer_core.is_ident_continue(code)
}

///|
pub fn is_ws_no_newline(code : UInt16) -> Bool {
  @lexer_core.is_ws_no_newline(code)
}

///|
pub fn slice_to_view(text : String, start : Int, end : Int) -> StringView {
  @lexer_core.slice_to_view(text, start, end)
}

///|
pub fn add_lex_error(lex : Lexer, loc : @source.SrcLoc, message : String) -> Unit {
  @lexer_core.add_lex_error(lex, loc, message)
}
