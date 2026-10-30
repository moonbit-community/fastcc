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
pub(all) enum TokenKind {
  Eof
  Invalid
  Ident
  IntLit
  FloatLit
  CharLit
  StrLit
  KwIf
  KwElse
  KwWhile
  KwFor
  KwDo
  KwContinue
  KwBreak
  KwReturn
  KwGoto
  KwSwitch
  KwCase
  KwDefault
  KwExtern
  KwStatic
  KwUnsigned
  KwSigned
  KwConst
  KwVolatile
  KwRegister
  KwAuto
  KwInline
  KwNoreturn
  KwRestrict
  KwAtomic
  KwVoid
  KwChar
  KwInt
  KwFloat
  KwDouble
  KwBool
  KwShort
  KwLong
  KwStruct
  KwUnion
  KwTypedef
  KwEnum
  KwSizeof
  KwAlignof
  KwTypeof
  KwAttribute
  KwStaticAssert
  KwAsm
  LParen
  RParen
  LBrace
  RBrace
  LBracket
  RBracket
  Comma
  Semicolon
  Colon
  Question
  Dot
  Ellipsis
  Arrow
  Assign
  Plus
  Minus
  Star
  Slash
  Percent
  PlusPlus
  MinusMinus
  PlusAssign
  MinusAssign
  StarAssign
  SlashAssign
  PercentAssign
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
  ShiftLeft
  ShiftRight
  ShiftLeftAssign
  ShiftRightAssign
  Amp
  Pipe
  Caret
  Tilde
  Bang
  AmpAmp
  PipePipe
  AmpAssign
  PipeAssign
  CaretAssign
  Hash
  HashHash
} derive(Eq, ToJson, Debug)

///|
pub(all) struct Token {
  kind : TokenKind
  value : Int32
  loc : @source.SrcLoc
  line_start : Bool
  hidden : Int32
} derive(Eq, ToJson, Debug)

///|
pub let empty_hidden : Int32 = 0

///|
pub fn token_value_from_parts(id : Int32, lexeme_id : Int32) -> Int32 {
  if lexeme_id != 0 {
    return -lexeme_id
  }
  if id != 0 {
    return id
  }
  0
}

///|
pub fn token_id(tok : Token) -> Int32 {
  let value = tok.value
  if value > 0 {
    value
  } else {
    0
  }
}

///|
pub fn token_lexeme_id(tok : Token) -> Int32 {
  let value = tok.value
  if value < 0 {
    -value
  } else {
    0
  }
}

///|
pub fn token_has_id(tok : Token) -> Bool {
  tok.value > 0
}

///|
pub(all) enum LexemeEntry {
  Owned(String)
  Slice(text~ : String, start~ : Int32, len~ : Int32)
}

///|
pub(all) struct LexemePool {
  entries : Array[LexemeEntry]
}

///|
pub fn new_lexeme_pool(capacity? : Int32) -> LexemePool {
  match capacity {
    None => { entries: [], }
    Some(value) => {
      let cap = if value > 0 { value } else { 0 }
      { entries: Array::new(capacity=cap), }
    }
  }
}

///|
pub fn lexeme_pool_intern(pool : LexemePool, text : String) -> Int32 {
  if text.length() == 0 {
    return 0
  }
  pool.entries.push(Owned(text))
  pool.entries.length()
}

///|
pub fn lexeme_pool_get(pool : LexemePool, id : Int32) -> String {
  if id <= 0 {
    return ""
  }
  let idx = id - 1
  match pool.entries[idx] {
    Owned(value) => value
    Slice(text~, start~, len~) => {
      let value = @util.slice_string(text, start, start + len)
      pool.entries[idx] = Owned(value)
      value
    }
  }
}

///|
pub fn lexeme_pool_intern_slice(
  pool : LexemePool,
  text : String,
  start : Int32,
  end : Int32,
) -> Int32 {
  let len = end - start
  if len <= 0 {
    return 0
  }
  pool.entries.push(Slice(text~, start~, len~))
  pool.entries.length()
}

///|
pub fn lexeme_pool_len(pool : LexemePool, id : Int32) -> Int32 {
  if id <= 0 {
    return 0
  }
  match pool.entries[id - 1] {
    Owned(value) => value.length()
    Slice(len~, ..) => len
  }
}

///|
pub(all) struct KeywordIds {
  kind_by_id : Array[TokenKind?]
}

///|
pub fn init_keyword_ids(interner : @intern.StringInterner) -> KeywordIds {
  let (_, kw_if) = interner.intern_view_with_id("if"[:])
  let (_, kw_do) = interner.intern_view_with_id("do"[:])
  let (_, kw_for) = interner.intern_view_with_id("for"[:])
  let (_, kw_int) = interner.intern_view_with_id("int"[:])
  let (_, kw_asm) = interner.intern_view_with_id("asm"[:])
  let (_, kw_else) = interner.intern_view_with_id("else"[:])
  let (_, kw_goto) = interner.intern_view_with_id("goto"[:])
  let (_, kw_case) = interner.intern_view_with_id("case"[:])
  let (_, kw_auto) = interner.intern_view_with_id("auto"[:])
  let (_, kw_void) = interner.intern_view_with_id("void"[:])
  let (_, kw_char) = interner.intern_view_with_id("char"[:])
  let (_, kw_long) = interner.intern_view_with_id("long"[:])
  let (_, kw_enum) = interner.intern_view_with_id("enum"[:])
  let (_, kw_while) = interner.intern_view_with_id("while"[:])
  let (_, kw_break) = interner.intern_view_with_id("break"[:])
  let (_, kw_const) = interner.intern_view_with_id("const"[:])
  let (_, kw_float) = interner.intern_view_with_id("float"[:])
  let (_, kw_u_bool) = interner.intern_view_with_id("_Bool"[:])
  let (_, kw_short) = interner.intern_view_with_id("short"[:])
  let (_, kw_union) = interner.intern_view_with_id("union"[:])
  let (_, kw_du_asm) = interner.intern_view_with_id("__asm"[:])
  let (_, kw_return) = interner.intern_view_with_id("return"[:])
  let (_, kw_switch) = interner.intern_view_with_id("switch"[:])
  let (_, kw_extern) = interner.intern_view_with_id("extern"[:])
  let (_, kw_static) = interner.intern_view_with_id("static"[:])
  let (_, kw_signed) = interner.intern_view_with_id("signed"[:])
  let (_, kw_inline) = interner.intern_view_with_id("inline"[:])
  let (_, kw_double) = interner.intern_view_with_id("double"[:])
  let (_, kw_struct) = interner.intern_view_with_id("struct"[:])
  let (_, kw_sizeof) = interner.intern_view_with_id("sizeof"[:])
  let (_, kw_typeof) = interner.intern_view_with_id("typeof"[:])
  let (_, kw_default) = interner.intern_view_with_id("default"[:])
  let (_, kw_typedef) = interner.intern_view_with_id("typedef"[:])
  let (_, kw_du_asm_du) = interner.intern_view_with_id("__asm__"[:])
  let (_, kw_du_const) = interner.intern_view_with_id("__const"[:])
  let (_, kw_continue) = interner.intern_view_with_id("continue"[:])
  let (_, kw_unsigned) = interner.intern_view_with_id("unsigned"[:])
  let (_, kw_volatile) = interner.intern_view_with_id("volatile"[:])
  let (_, kw_register) = interner.intern_view_with_id("register"[:])
  let (_, kw_restrict) = interner.intern_view_with_id("restrict"[:])
  let (_, kw_u_alignof) = interner.intern_view_with_id("_Alignof"[:])
  let (_, kw_du_typeof) = interner.intern_view_with_id("__typeof"[:])
  let (_, kw_du_inline) = interner.intern_view_with_id("__inline"[:])
  let (_, kw_du_signed) = interner.intern_view_with_id("__signed"[:])
  let (_, kw_u_float16) = interner.intern_view_with_id("_Float16"[:])
  let (_, kw_u_noreturn) = interner.intern_view_with_id("_Noreturn"[:])
  let (_, kw_u_atomic) = interner.intern_view_with_id("_Atomic"[:])
  let (_, kw_du_alignof) = interner.intern_view_with_id("__alignof"[:])
  let (_, kw_du_const_du) = interner.intern_view_with_id("__const__"[:])
  let (_, kw_du_typeof_du) = interner.intern_view_with_id("__typeof__"[:])
  let (_, kw_du_volatile) = interner.intern_view_with_id("__volatile"[:])
  let (_, kw_du_restrict) = interner.intern_view_with_id("__restrict"[:])
  let (_, kw_du_inline_du) = interner.intern_view_with_id("__inline__"[:])
  let (_, kw_du_signed_du) = interner.intern_view_with_id("__signed__"[:])
  let (_, kw_du_unsigned) = interner.intern_view_with_id("__unsigned"[:])
  let (_, kw_du_alignof_du) = interner.intern_view_with_id("__alignof__"[:])
  let (_, kw_du_attribute) = interner.intern_view_with_id("__attribute"[:])
  let (_, kw_du_volatile_du) = interner.intern_view_with_id("__volatile__"[:])
  let (_, kw_du_restrict_du) = interner.intern_view_with_id("__restrict__"[:])
  let (_, kw_du_unsigned_du) = interner.intern_view_with_id("__unsigned__"[:])
  let (_, kw_du_attribute_du) = interner.intern_view_with_id("__attribute__"[:])
  let (_, kw_u_static_assert) = interner.intern_view_with_id(
    "_Static_assert"[:],
  )
  let kind_by_id : Array[TokenKind?] = Array::make(kw_u_static_assert + 1, None)
  kind_by_id[kw_if] = Some(KwIf)
  kind_by_id[kw_do] = Some(KwDo)
  kind_by_id[kw_for] = Some(KwFor)
  kind_by_id[kw_int] = Some(KwInt)
  kind_by_id[kw_asm] = Some(KwAsm)
  kind_by_id[kw_else] = Some(KwElse)
  kind_by_id[kw_goto] = Some(KwGoto)
  kind_by_id[kw_case] = Some(KwCase)
  kind_by_id[kw_auto] = Some(KwAuto)
  kind_by_id[kw_void] = Some(KwVoid)
  kind_by_id[kw_char] = Some(KwChar)
  kind_by_id[kw_long] = Some(KwLong)
  kind_by_id[kw_enum] = Some(KwEnum)
  kind_by_id[kw_while] = Some(KwWhile)
  kind_by_id[kw_break] = Some(KwBreak)
  kind_by_id[kw_const] = Some(KwConst)
  kind_by_id[kw_float] = Some(KwFloat)
  kind_by_id[kw_u_bool] = Some(KwBool)
  kind_by_id[kw_short] = Some(KwShort)
  kind_by_id[kw_union] = Some(KwUnion)
  kind_by_id[kw_du_asm] = Some(KwAsm)
  kind_by_id[kw_return] = Some(KwReturn)
  kind_by_id[kw_switch] = Some(KwSwitch)
  kind_by_id[kw_extern] = Some(KwExtern)
  kind_by_id[kw_static] = Some(KwStatic)
  kind_by_id[kw_signed] = Some(KwSigned)
  kind_by_id[kw_inline] = Some(KwInline)
  kind_by_id[kw_double] = Some(KwDouble)
  kind_by_id[kw_struct] = Some(KwStruct)
  kind_by_id[kw_sizeof] = Some(KwSizeof)
  kind_by_id[kw_typeof] = Some(KwTypeof)
  kind_by_id[kw_default] = Some(KwDefault)
  kind_by_id[kw_typedef] = Some(KwTypedef)
  kind_by_id[kw_du_asm_du] = Some(KwAsm)
  kind_by_id[kw_du_const] = Some(KwConst)
  kind_by_id[kw_continue] = Some(KwContinue)
  kind_by_id[kw_unsigned] = Some(KwUnsigned)
  kind_by_id[kw_volatile] = Some(KwVolatile)
  kind_by_id[kw_register] = Some(KwRegister)
  kind_by_id[kw_restrict] = Some(KwRestrict)
  kind_by_id[kw_u_alignof] = Some(KwAlignof)
  kind_by_id[kw_du_typeof] = Some(KwTypeof)
  kind_by_id[kw_du_inline] = Some(KwInline)
  kind_by_id[kw_du_signed] = Some(KwSigned)
  kind_by_id[kw_u_float16] = Some(KwFloat)
  kind_by_id[kw_u_noreturn] = Some(KwNoreturn)
  kind_by_id[kw_u_atomic] = Some(KwAtomic)
  kind_by_id[kw_du_alignof] = Some(KwAlignof)
  kind_by_id[kw_du_const_du] = Some(KwConst)
  kind_by_id[kw_du_typeof_du] = Some(KwTypeof)
  kind_by_id[kw_du_volatile] = Some(KwVolatile)
  kind_by_id[kw_du_restrict] = Some(KwRestrict)
  kind_by_id[kw_du_inline_du] = Some(KwInline)
  kind_by_id[kw_du_signed_du] = Some(KwSigned)
  kind_by_id[kw_du_unsigned] = Some(KwUnsigned)
  kind_by_id[kw_du_alignof_du] = Some(KwAlignof)
  kind_by_id[kw_du_attribute] = Some(KwAttribute)
  kind_by_id[kw_du_volatile_du] = Some(KwVolatile)
  kind_by_id[kw_du_restrict_du] = Some(KwRestrict)
  kind_by_id[kw_du_unsigned_du] = Some(KwUnsigned)
  kind_by_id[kw_du_attribute_du] = Some(KwAttribute)
  kind_by_id[kw_u_static_assert] = Some(KwStaticAssert)
  { kind_by_id, }
}

///|
pub fn keyword_kind_from_id(id : Int32, ids : KeywordIds) -> TokenKind? {
  if id <= 0 {
    return None
  }
  let kind_by_id = ids.kind_by_id
  if id >= kind_by_id.length() {
    return None
  }
  kind_by_id[id]
}

///|
pub fn token_kind_text(kind : TokenKind) -> String {
  match kind {
    LParen => "("
    RParen => ")"
    LBrace => "{"
    RBrace => "}"
    LBracket => "["
    RBracket => "]"
    Comma => ","
    Semicolon => ";"
    Colon => ":"
    Question => "?"
    Dot => "."
    Ellipsis => "..."
    Arrow => "->"
    Assign => "="
    Plus => "+"
    Minus => "-"
    Star => "*"
    Slash => "/"
    Percent => "%"
    PlusPlus => "++"
    MinusMinus => "--"
    PlusAssign => "+="
    MinusAssign => "-="
    StarAssign => "*="
    SlashAssign => "/="
    PercentAssign => "%="
    Eq => "=="
    Ne => "!="
    Lt => "<"
    Le => "<="
    Gt => ">"
    Ge => ">="
    ShiftLeft => "<<"
    ShiftRight => ">>"
    ShiftLeftAssign => "<<="
    ShiftRightAssign => ">>="
    Amp => "&"
    Pipe => "|"
    Caret => "^"
    Tilde => "~"
    Bang => "!"
    AmpAmp => "&&"
    PipePipe => "||"
    AmpAssign => "&="
    PipeAssign => "|="
    CaretAssign => "^="
    Hash => "#"
    HashHash => "##"
    _ => ""
  }
}

///|
pub fn token_kind_text_len(kind : TokenKind) -> Int32 {
  match kind {
    LParen
    | RParen
    | LBrace
    | RBrace
    | LBracket
    | RBracket
    | Comma
    | Semicolon
    | Colon
    | Question
    | Dot
    | Assign
    | Plus
    | Minus
    | Star
    | Slash
    | Percent
    | Lt
    | Gt
    | Amp
    | Pipe
    | Caret
    | Tilde
    | Bang
    | Hash => 1
    Ellipsis => 3
    Arrow
    | PlusPlus
    | MinusMinus
    | PlusAssign
    | MinusAssign
    | StarAssign
    | SlashAssign
    | PercentAssign
    | Eq
    | Ne
    | Le
    | Ge
    | ShiftLeft
    | ShiftRight
    | AmpAmp
    | PipePipe
    | AmpAssign
    | PipeAssign
    | CaretAssign
    | HashHash => 2
    ShiftLeftAssign | ShiftRightAssign => 3
    _ => 0
  }
}

///|
pub fn token_text_with(
  interner : @intern.StringInterner,
  pool : LexemePool,
  tok : Token,
) -> String {
  let lexeme_id = token_lexeme_id(tok)
  if lexeme_id != 0 {
    return lexeme_pool_get(pool, lexeme_id)
  }
  let id = token_id(tok)
  if id != 0 {
    return interner.get(id)
  }
  token_kind_text(tok.kind)
}

///|
pub fn token_text_len_with(
  interner : @intern.StringInterner,
  pool : LexemePool,
  tok : Token,
) -> Int32 {
  let lexeme_id = token_lexeme_id(tok)
  if lexeme_id != 0 {
    return lexeme_pool_len(pool, lexeme_id)
  }
  let id = token_id(tok)
  if id != 0 {
    return interner.get(id).length()
  }
  token_kind_text_len(tok.kind)
}

///|

///|

///|
pub impl Show for TokenKind with fn output(self, logger) {
  match self {
    Eof => logger.write_string("Eof")
    Invalid => logger.write_string("Invalid")
    Ident => logger.write_string("Ident")
    IntLit => logger.write_string("IntLit")
    FloatLit => logger.write_string("FloatLit")
    CharLit => logger.write_string("CharLit")
    StrLit => logger.write_string("StrLit")
    KwIf => logger.write_string("KwIf")
    KwElse => logger.write_string("KwElse")
    KwWhile => logger.write_string("KwWhile")
    KwFor => logger.write_string("KwFor")
    KwDo => logger.write_string("KwDo")
    KwContinue => logger.write_string("KwContinue")
    KwBreak => logger.write_string("KwBreak")
    KwReturn => logger.write_string("KwReturn")
    KwGoto => logger.write_string("KwGoto")
    KwSwitch => logger.write_string("KwSwitch")
    KwCase => logger.write_string("KwCase")
    KwDefault => logger.write_string("KwDefault")
    KwExtern => logger.write_string("KwExtern")
    KwStatic => logger.write_string("KwStatic")
    KwUnsigned => logger.write_string("KwUnsigned")
    KwSigned => logger.write_string("KwSigned")
    KwConst => logger.write_string("KwConst")
    KwVolatile => logger.write_string("KwVolatile")
    KwRegister => logger.write_string("KwRegister")
    KwAuto => logger.write_string("KwAuto")
    KwInline => logger.write_string("KwInline")
    KwNoreturn => logger.write_string("KwNoreturn")
    KwRestrict => logger.write_string("KwRestrict")
    KwAtomic => logger.write_string("KwAtomic")
    KwVoid => logger.write_string("KwVoid")
    KwChar => logger.write_string("KwChar")
    KwInt => logger.write_string("KwInt")
    KwFloat => logger.write_string("KwFloat")
    KwDouble => logger.write_string("KwDouble")
    KwBool => logger.write_string("KwBool")
    KwShort => logger.write_string("KwShort")
    KwLong => logger.write_string("KwLong")
    KwStruct => logger.write_string("KwStruct")
    KwUnion => logger.write_string("KwUnion")
    KwTypedef => logger.write_string("KwTypedef")
    KwEnum => logger.write_string("KwEnum")
    KwSizeof => logger.write_string("KwSizeof")
    KwAlignof => logger.write_string("KwAlignof")
    KwTypeof => logger.write_string("KwTypeof")
    KwAttribute => logger.write_string("KwAttribute")
    KwStaticAssert => logger.write_string("KwStaticAssert")
    KwAsm => logger.write_string("KwAsm")
    LParen => logger.write_string("LParen")
    RParen => logger.write_string("RParen")
    LBrace => logger.write_string("LBrace")
    RBrace => logger.write_string("RBrace")
    LBracket => logger.write_string("LBracket")
    RBracket => logger.write_string("RBracket")
    Comma => logger.write_string("Comma")
    Semicolon => logger.write_string("Semicolon")
    Colon => logger.write_string("Colon")
    Question => logger.write_string("Question")
    Dot => logger.write_string("Dot")
    Ellipsis => logger.write_string("Ellipsis")
    Arrow => logger.write_string("Arrow")
    Assign => logger.write_string("Assign")
    Plus => logger.write_string("Plus")
    Minus => logger.write_string("Minus")
    Star => logger.write_string("Star")
    Slash => logger.write_string("Slash")
    Percent => logger.write_string("Percent")
    PlusPlus => logger.write_string("PlusPlus")
    MinusMinus => logger.write_string("MinusMinus")
    PlusAssign => logger.write_string("PlusAssign")
    MinusAssign => logger.write_string("MinusAssign")
    StarAssign => logger.write_string("StarAssign")
    SlashAssign => logger.write_string("SlashAssign")
    PercentAssign => logger.write_string("PercentAssign")
    Eq => logger.write_string("Eq")
    Ne => logger.write_string("Ne")
    Lt => logger.write_string("Lt")
    Le => logger.write_string("Le")
    Gt => logger.write_string("Gt")
    Ge => logger.write_string("Ge")
    ShiftLeft => logger.write_string("ShiftLeft")
    ShiftRight => logger.write_string("ShiftRight")
    ShiftLeftAssign => logger.write_string("ShiftLeftAssign")
    ShiftRightAssign => logger.write_string("ShiftRightAssign")
    Amp => logger.write_string("Amp")
    Pipe => logger.write_string("Pipe")
    Caret => logger.write_string("Caret")
    Tilde => logger.write_string("Tilde")
    Bang => logger.write_string("Bang")
    AmpAmp => logger.write_string("AmpAmp")
    PipePipe => logger.write_string("PipePipe")
    AmpAssign => logger.write_string("AmpAssign")
    PipeAssign => logger.write_string("PipeAssign")
    CaretAssign => logger.write_string("CaretAssign")
    Hash => logger.write_string("Hash")
    HashHash => logger.write_string("HashHash")
  }
}

///|
pub impl Show for Token with fn output(self, logger) {
  logger.write_string("{")
  logger.write_string("kind: ")
  logger.write_object(self.kind)
  logger.write_string(", value: ")
  logger.write_object(self.value)
  logger.write_string(", loc: ")
  logger.write_object(self.loc)
  logger.write_string(", line_start: ")
  logger.write_object(self.line_start)
  logger.write_string(", hidden: ")
  logger.write_object(self.hidden)
  logger.write_string("}")
}
