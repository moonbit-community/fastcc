// Copyright (C) 2026 International Digital Economy Academy
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License as published by the Free Software Foundation; version 2.1
// of the License.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public
// License along with this library.  If not, see <https://www.gnu.org/licenses/>.

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
pub let empty_hidden : Int32 = @tokens_core.empty_hidden

///|
pub fn token_value_from_parts(id : Int32, lexeme_id : Int32) -> Int32 {
  @tokens_core.token_value_from_parts(id, lexeme_id)
}

///|
pub fn token_id(tok : Token) -> Int32 {
  @tokens_core.token_id(tok)
}

///|
pub fn token_lexeme_id(tok : Token) -> Int32 {
  @tokens_core.token_lexeme_id(tok)
}

///|
pub fn token_has_id(tok : Token) -> Bool {
  @tokens_core.token_has_id(tok)
}

///|
pub fn new_lexeme_pool(capacity? : Int32) -> LexemePool {
  match capacity {
    None => @tokens_core.new_lexeme_pool()
    Some(value) => @tokens_core.new_lexeme_pool(capacity=value)
  }
}

///|
pub fn lexeme_pool_intern(pool : LexemePool, text : String) -> Int32 {
  @tokens_core.lexeme_pool_intern(pool, text)
}

///|
pub fn lexeme_pool_get(pool : LexemePool, id : Int32) -> String {
  @tokens_core.lexeme_pool_get(pool, id)
}

///|
pub fn lexeme_pool_intern_slice(
  pool : LexemePool,
  text : String,
  start : Int32,
  end : Int32,
) -> Int32 {
  @tokens_core.lexeme_pool_intern_slice(pool, text, start, end)
}

///|
pub fn lexeme_pool_len(pool : LexemePool, id : Int32) -> Int32 {
  @tokens_core.lexeme_pool_len(pool, id)
}

///|
pub fn init_keyword_ids(interner : @intern.StringInterner) -> KeywordIds {
  @tokens_core.init_keyword_ids(interner)
}

///|
pub fn keyword_kind_from_id(id : Int32, ids : KeywordIds) -> TokenKind? {
  @tokens_core.keyword_kind_from_id(id, ids)
}

///|
pub fn token_kind_text(kind : TokenKind) -> String {
  @tokens_core.token_kind_text(kind)
}

///|
pub fn token_kind_text_len(kind : TokenKind) -> Int32 {
  @tokens_core.token_kind_text_len(kind)
}

///|
pub fn token_text_with(
  interner : @intern.StringInterner,
  pool : LexemePool,
  tok : Token,
) -> String {
  @tokens_core.token_text_with(interner, pool, tok)
}

///|
pub fn token_text_len_with(
  interner : @intern.StringInterner,
  pool : LexemePool,
  tok : Token,
) -> Int32 {
  @tokens_core.token_text_len_with(interner, pool, tok)
}
