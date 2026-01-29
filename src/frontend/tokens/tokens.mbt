///|
pub type KeywordIds = @tokens_core.KeywordIds

///|
pub type LexemeEntry = @tokens_core.LexemeEntry

///|
pub type LexemePool = @tokens_core.LexemePool

///|
pub type Token = @tokens_core.Token

///|
pub type TokenKind = @tokens_core.TokenKind

///|
pub let empty_hidden : Int = @tokens_core.empty_hidden



///|
pub fn token_value_from_parts(id : Int, lexeme_id : Int) -> Int {
  @tokens_core.token_value_from_parts(id, lexeme_id)
}
///|
pub fn token_id(tok : Token) -> Int {
  @tokens_core.token_id(tok)
}
///|
pub fn token_lexeme_id(tok : Token) -> Int {
  @tokens_core.token_lexeme_id(tok)
}
///|
pub fn token_has_id(tok : Token) -> Bool {
  @tokens_core.token_has_id(tok)
}
///|
pub fn new_lexeme_pool(capacity? : Int) -> LexemePool {
  match capacity {
    None => @tokens_core.new_lexeme_pool()
    Some(value) => @tokens_core.new_lexeme_pool(capacity=value)
  }
}
///|
pub fn lexeme_pool_intern(pool : LexemePool, text : String) -> Int {
  @tokens_core.lexeme_pool_intern(pool, text)
}
///|
pub fn lexeme_pool_get(pool : LexemePool, id : Int) -> String {
  @tokens_core.lexeme_pool_get(pool, id)
}
///|
pub fn lexeme_pool_intern_slice(pool : LexemePool, text : String, start : Int, end : Int) -> Int {
  @tokens_core.lexeme_pool_intern_slice(pool, text, start, end)
}
///|
pub fn lexeme_pool_len(pool : LexemePool, id : Int) -> Int {
  @tokens_core.lexeme_pool_len(pool, id)
}
///|
pub fn init_keyword_ids(interner : @intern.StringInterner) -> KeywordIds {
  @tokens_core.init_keyword_ids(interner)
}
///|
pub fn keyword_kind_from_id(id : Int, ids : KeywordIds) -> TokenKind? {
  @tokens_core.keyword_kind_from_id(id, ids)
}
///|
pub fn token_kind_text(kind : TokenKind) -> String {
  @tokens_core.token_kind_text(kind)
}
///|
pub fn token_kind_text_len(kind : TokenKind) -> Int {
  @tokens_core.token_kind_text_len(kind)
}
///|
pub fn token_text_with(interner : @intern.StringInterner, pool : LexemePool, tok : Token) -> String {
  @tokens_core.token_text_with(interner, pool, tok)
}
///|
pub fn token_text_len_with(interner : @intern.StringInterner, pool : LexemePool, tok : Token) -> Int {
  @tokens_core.token_text_len_with(interner, pool, tok)
}
