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
  lexeme : String
  id : Int
  loc : SrcLoc
  line_start : Bool
  hidden : Array[Int]
} derive(Show, Eq, ToJson)

///|
let empty_hidden : Array[Int] = []

///|
struct KeywordIds {
  kw_if : Int
  kw_do : Int
  kw_for : Int
  kw_int : Int
  kw_asm : Int
  kw_else : Int
  kw_goto : Int
  kw_case : Int
  kw_auto : Int
  kw_void : Int
  kw_char : Int
  kw_long : Int
  kw_enum : Int
  kw_while : Int
  kw_break : Int
  kw_const : Int
  kw_float : Int
  kw_u_bool : Int
  kw_short : Int
  kw_union : Int
  kw_du_asm : Int
  kw_return : Int
  kw_switch : Int
  kw_extern : Int
  kw_static : Int
  kw_signed : Int
  kw_inline : Int
  kw_double : Int
  kw_struct : Int
  kw_sizeof : Int
  kw_typeof : Int
  kw_default : Int
  kw_typedef : Int
  kw_du_asm_du : Int
  kw_du_const : Int
  kw_continue : Int
  kw_unsigned : Int
  kw_volatile : Int
  kw_register : Int
  kw_restrict : Int
  kw_u_alignof : Int
  kw_du_typeof : Int
  kw_du_inline : Int
  kw_du_signed : Int
  kw_u_float16 : Int
  kw_u_noreturn : Int
  kw_du_alignof : Int
  kw_du_const_du : Int
  kw_du_typeof_du : Int
  kw_du_volatile : Int
  kw_du_restrict : Int
  kw_du_inline_du : Int
  kw_du_signed_du : Int
  kw_du_unsigned : Int
  kw_du_alignof_du : Int
  kw_du_attribute : Int
  kw_du_volatile_du : Int
  kw_du_restrict_du : Int
  kw_du_unsigned_du : Int
  kw_du_attribute_du : Int
  kw_u_static_assert : Int
}

///|
fn init_keyword_ids(interner : StringInterner) -> KeywordIds {
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
  {
    kw_if,
    kw_do,
    kw_for,
    kw_int,
    kw_asm,
    kw_else,
    kw_goto,
    kw_case,
    kw_auto,
    kw_void,
    kw_char,
    kw_long,
    kw_enum,
    kw_while,
    kw_break,
    kw_const,
    kw_float,
    kw_u_bool,
    kw_short,
    kw_union,
    kw_du_asm,
    kw_return,
    kw_switch,
    kw_extern,
    kw_static,
    kw_signed,
    kw_inline,
    kw_double,
    kw_struct,
    kw_sizeof,
    kw_typeof,
    kw_default,
    kw_typedef,
    kw_du_asm_du,
    kw_du_const,
    kw_continue,
    kw_unsigned,
    kw_volatile,
    kw_register,
    kw_restrict,
    kw_u_alignof,
    kw_du_typeof,
    kw_du_inline,
    kw_du_signed,
    kw_u_float16,
    kw_u_noreturn,
    kw_du_alignof,
    kw_du_const_du,
    kw_du_typeof_du,
    kw_du_volatile,
    kw_du_restrict,
    kw_du_inline_du,
    kw_du_signed_du,
    kw_du_unsigned,
    kw_du_alignof_du,
    kw_du_attribute,
    kw_du_volatile_du,
    kw_du_restrict_du,
    kw_du_unsigned_du,
    kw_du_attribute_du,
    kw_u_static_assert,
  }
}

///|
fn keyword_or_ident_view_with_id(
  name : StringView,
  ids : KeywordIds,
) -> (TokenKind, String?, Int) {
  let len = name.length()
  if len == 2 {
    if name.equal("if"[:]) {
      (KwIf, Some("if"), ids.kw_if)
    } else if name.equal("do"[:]) {
      (KwDo, Some("do"), ids.kw_do)
    } else {
      (Ident, None, 0)
    }
  } else if len == 3 {
    if name.equal("for"[:]) {
      (KwFor, Some("for"), ids.kw_for)
    } else if name.equal("int"[:]) {
      (KwInt, Some("int"), ids.kw_int)
    } else if name.equal("asm"[:]) {
      (KwAsm, Some("asm"), ids.kw_asm)
    } else {
      (Ident, None, 0)
    }
  } else if len == 4 {
    if name.equal("else"[:]) {
      (KwElse, Some("else"), ids.kw_else)
    } else if name.equal("goto"[:]) {
      (KwGoto, Some("goto"), ids.kw_goto)
    } else if name.equal("case"[:]) {
      (KwCase, Some("case"), ids.kw_case)
    } else if name.equal("auto"[:]) {
      (KwAuto, Some("auto"), ids.kw_auto)
    } else if name.equal("void"[:]) {
      (KwVoid, Some("void"), ids.kw_void)
    } else if name.equal("char"[:]) {
      (KwChar, Some("char"), ids.kw_char)
    } else if name.equal("long"[:]) {
      (KwLong, Some("long"), ids.kw_long)
    } else if name.equal("enum"[:]) {
      (KwEnum, Some("enum"), ids.kw_enum)
    } else {
      (Ident, None, 0)
    }
  } else if len == 5 {
    if name.equal("while"[:]) {
      (KwWhile, Some("while"), ids.kw_while)
    } else if name.equal("break"[:]) {
      (KwBreak, Some("break"), ids.kw_break)
    } else if name.equal("const"[:]) {
      (KwConst, Some("const"), ids.kw_const)
    } else if name.equal("float"[:]) {
      (KwFloat, Some("float"), ids.kw_float)
    } else if name.equal("_Bool"[:]) {
      (KwBool, Some("_Bool"), ids.kw_u_bool)
    } else if name.equal("short"[:]) {
      (KwShort, Some("short"), ids.kw_short)
    } else if name.equal("union"[:]) {
      (KwUnion, Some("union"), ids.kw_union)
    } else if name.equal("__asm"[:]) {
      (KwAsm, Some("__asm"), ids.kw_du_asm)
    } else {
      (Ident, None, 0)
    }
  } else if len == 6 {
    if name.equal("return"[:]) {
      (KwReturn, Some("return"), ids.kw_return)
    } else if name.equal("switch"[:]) {
      (KwSwitch, Some("switch"), ids.kw_switch)
    } else if name.equal("extern"[:]) {
      (KwExtern, Some("extern"), ids.kw_extern)
    } else if name.equal("static"[:]) {
      (KwStatic, Some("static"), ids.kw_static)
    } else if name.equal("signed"[:]) {
      (KwSigned, Some("signed"), ids.kw_signed)
    } else if name.equal("inline"[:]) {
      (KwInline, Some("inline"), ids.kw_inline)
    } else if name.equal("double"[:]) {
      (KwDouble, Some("double"), ids.kw_double)
    } else if name.equal("struct"[:]) {
      (KwStruct, Some("struct"), ids.kw_struct)
    } else if name.equal("sizeof"[:]) {
      (KwSizeof, Some("sizeof"), ids.kw_sizeof)
    } else if name.equal("typeof"[:]) {
      (KwTypeof, Some("typeof"), ids.kw_typeof)
    } else {
      (Ident, None, 0)
    }
  } else if len == 7 {
    if name.equal("default"[:]) {
      (KwDefault, Some("default"), ids.kw_default)
    } else if name.equal("typedef"[:]) {
      (KwTypedef, Some("typedef"), ids.kw_typedef)
    } else if name.equal("__asm__"[:]) {
      (KwAsm, Some("__asm__"), ids.kw_du_asm_du)
    } else if name.equal("__const"[:]) {
      (KwConst, Some("__const"), ids.kw_du_const)
    } else {
      (Ident, None, 0)
    }
  } else if len == 8 {
    if name.equal("continue"[:]) {
      (KwContinue, Some("continue"), ids.kw_continue)
    } else if name.equal("unsigned"[:]) {
      (KwUnsigned, Some("unsigned"), ids.kw_unsigned)
    } else if name.equal("volatile"[:]) {
      (KwVolatile, Some("volatile"), ids.kw_volatile)
    } else if name.equal("register"[:]) {
      (KwRegister, Some("register"), ids.kw_register)
    } else if name.equal("restrict"[:]) {
      (KwRestrict, Some("restrict"), ids.kw_restrict)
    } else if name.equal("_Alignof"[:]) {
      (KwAlignof, Some("_Alignof"), ids.kw_u_alignof)
    } else if name.equal("__typeof"[:]) {
      (KwTypeof, Some("__typeof"), ids.kw_du_typeof)
    } else if name.equal("__inline"[:]) {
      (KwInline, Some("__inline"), ids.kw_du_inline)
    } else if name.equal("__signed"[:]) {
      (KwSigned, Some("__signed"), ids.kw_du_signed)
    } else if name.equal("_Float16"[:]) {
      (KwFloat, Some("_Float16"), ids.kw_u_float16)
    } else {
      (Ident, None, 0)
    }
  } else if len == 9 {
    if name.equal("_Noreturn"[:]) {
      (KwNoreturn, Some("_Noreturn"), ids.kw_u_noreturn)
    } else if name.equal("__alignof"[:]) {
      (KwAlignof, Some("__alignof"), ids.kw_du_alignof)
    } else if name.equal("__const__"[:]) {
      (KwConst, Some("__const__"), ids.kw_du_const_du)
    } else {
      (Ident, None, 0)
    }
  } else if len == 10 {
    if name.equal("__typeof__"[:]) {
      (KwTypeof, Some("__typeof__"), ids.kw_du_typeof_du)
    } else if name.equal("__volatile"[:]) {
      (KwVolatile, Some("__volatile"), ids.kw_du_volatile)
    } else if name.equal("__restrict"[:]) {
      (KwRestrict, Some("__restrict"), ids.kw_du_restrict)
    } else if name.equal("__inline__"[:]) {
      (KwInline, Some("__inline__"), ids.kw_du_inline_du)
    } else if name.equal("__signed__"[:]) {
      (KwSigned, Some("__signed__"), ids.kw_du_signed_du)
    } else if name.equal("__unsigned"[:]) {
      (KwUnsigned, Some("__unsigned"), ids.kw_du_unsigned)
    } else {
      (Ident, None, 0)
    }
  } else if len == 11 {
    if name.equal("__alignof__"[:]) {
      (KwAlignof, Some("__alignof__"), ids.kw_du_alignof_du)
    } else if name.equal("__attribute"[:]) {
      (KwAttribute, Some("__attribute"), ids.kw_du_attribute)
    } else {
      (Ident, None, 0)
    }
  } else if len == 12 {
    if name.equal("__volatile__"[:]) {
      (KwVolatile, Some("__volatile__"), ids.kw_du_volatile_du)
    } else if name.equal("__restrict__"[:]) {
      (KwRestrict, Some("__restrict__"), ids.kw_du_restrict_du)
    } else if name.equal("__unsigned__"[:]) {
      (KwUnsigned, Some("__unsigned__"), ids.kw_du_unsigned_du)
    } else {
      (Ident, None, 0)
    }
  } else if len == 13 {
    if name.equal("__attribute__"[:]) {
      (KwAttribute, Some("__attribute__"), ids.kw_du_attribute_du)
    } else {
      (Ident, None, 0)
    }
  } else if len == 14 {
    if name.equal("_Static_assert"[:]) {
      (KwStaticAssert, Some("_Static_assert"), ids.kw_u_static_assert)
    } else {
      (Ident, None, 0)
    }
  } else {
    (Ident, None, 0)
  }
}
