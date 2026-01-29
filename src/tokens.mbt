///|
enum TokenKind {
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
} derive(Show, Eq, ToJson)

///|
struct Token {
  kind : TokenKind
  value : Int
  loc : @source.SrcLoc
  line_start : Bool
  hidden : Int
} derive(Show, Eq, ToJson)

///|
let empty_hidden : Int = 0

///|
fn token_value_from_parts(id : Int, lexeme_id : Int) -> Int {
  if lexeme_id != 0 {
    return -lexeme_id
  }
  if id != 0 {
    return id
  }
  0
}

///|
fn token_id(tok : Token) -> Int {
  let value = tok.value
  if value > 0 { value } else { 0 }
}

///|
fn token_lexeme_id(tok : Token) -> Int {
  let value = tok.value
  if value < 0 { -value } else { 0 }
}

///|
fn token_has_id(tok : Token) -> Bool {
  tok.value > 0
}

///|
enum LexemeEntry {
  Owned(String)
  Slice(text~ : String, start~ : Int, len~ : Int)
}

///|
struct LexemePool {
  entries : Array[LexemeEntry]
}

///|
fn new_lexeme_pool(capacity? : Int) -> LexemePool {
  match capacity {
    None => { entries: [] }
    Some(value) => {
      let cap = if value > 0 { value } else { 0 }
      { entries: Array::new(capacity=cap) }
    }
  }
}

///|
fn lexeme_pool_intern(pool : LexemePool, text : String) -> Int {
  if text.length() == 0 {
    return 0
  }
  pool.entries.push(LexemeEntry::Owned(text))
  pool.entries.length()
}

///|
fn lexeme_pool_get(pool : LexemePool, id : Int) -> String {
  if id <= 0 {
    return ""
  }
  let idx = id - 1
  match pool.entries[idx] {
    LexemeEntry::Owned(value) => value
    LexemeEntry::Slice(text=text, start=start, len=len) => {
      let value = slice_string(text, start, start + len)
      pool.entries[idx] = LexemeEntry::Owned(value)
      value
    }
  }
}

///|
fn lexeme_pool_intern_slice(
  pool : LexemePool,
  text : String,
  start : Int,
  end : Int,
) -> Int {
  let len = end - start
  if len <= 0 {
    return 0
  }
  pool.entries.push(LexemeEntry::Slice(text=text, start=start, len=len))
  pool.entries.length()
}

///|
fn lexeme_pool_len(pool : LexemePool, id : Int) -> Int {
  if id <= 0 {
    return 0
  }
  match pool.entries[id - 1] {
    LexemeEntry::Owned(value) => value.length()
    LexemeEntry::Slice(len=len, ..) => len
  }
}

///|
struct KeywordIds {
  kind_by_id : Array[TokenKind?]
}

///|
fn init_keyword_ids(interner : @intern.StringInterner) -> KeywordIds {
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
  let (_, kw_u_static_assert) =
    interner.intern_view_with_id("_Static_assert"[:])
  let kind_by_id : Array[TokenKind?] =
    Array::make(kw_u_static_assert + 1, None)
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
  {
    kind_by_id,
  }
}

///|
fn keyword_kind_from_id(id : Int, ids : KeywordIds) -> TokenKind? {
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
fn token_kind_text(kind : TokenKind) -> String {
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
fn token_kind_text_len(kind : TokenKind) -> Int {
  match kind {
    LParen |
    RParen |
    LBrace |
    RBrace |
    LBracket |
    RBracket |
    Comma |
    Semicolon |
    Colon |
    Question |
    Dot |
    Assign |
    Plus |
    Minus |
    Star |
    Slash |
    Percent |
    Lt |
    Gt |
    Amp |
    Pipe |
    Caret |
    Tilde |
    Bang |
    Hash => 1
    Ellipsis => 3
    Arrow |
    PlusPlus |
    MinusMinus |
    PlusAssign |
    MinusAssign |
    StarAssign |
    SlashAssign |
    PercentAssign |
    Eq |
    Ne |
    Le |
    Ge |
    ShiftLeft |
    ShiftRight |
    AmpAmp |
    PipePipe |
    AmpAssign |
    PipeAssign |
    CaretAssign |
    HashHash => 2
    ShiftLeftAssign |
    ShiftRightAssign => 3
    _ => 0
  }
}

///|
fn token_text_with(
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
fn token_text_len_with(
  interner : @intern.StringInterner,
  pool : LexemePool,
  tok : Token,
) -> Int {
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
