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
  loc : SrcLoc
  line_start : Bool
  hidden : Array[String]
} derive(Show, Eq, ToJson)

///|
let empty_hidden : Array[String] = []

///|
fn keyword_or_ident_view(name : StringView) -> (TokenKind, String?) {
  let len = name.length()
  if len == 2 {
    if name.equal("if"[:]) {
      (KwIf, Some("if"))
    } else if name.equal("do"[:]) {
      (KwDo, Some("do"))
    } else {
      (Ident, None)
    }
  } else if len == 3 {
    if name.equal("for"[:]) {
      (KwFor, Some("for"))
    } else if name.equal("int"[:]) {
      (KwInt, Some("int"))
    } else if name.equal("asm"[:]) {
      (KwAsm, Some("asm"))
    } else {
      (Ident, None)
    }
  } else if len == 4 {
    if name.equal("else"[:]) {
      (KwElse, Some("else"))
    } else if name.equal("goto"[:]) {
      (KwGoto, Some("goto"))
    } else if name.equal("case"[:]) {
      (KwCase, Some("case"))
    } else if name.equal("auto"[:]) {
      (KwAuto, Some("auto"))
    } else if name.equal("void"[:]) {
      (KwVoid, Some("void"))
    } else if name.equal("char"[:]) {
      (KwChar, Some("char"))
    } else if name.equal("long"[:]) {
      (KwLong, Some("long"))
    } else if name.equal("enum"[:]) {
      (KwEnum, Some("enum"))
    } else {
      (Ident, None)
    }
  } else if len == 5 {
    if name.equal("while"[:]) {
      (KwWhile, Some("while"))
    } else if name.equal("break"[:]) {
      (KwBreak, Some("break"))
    } else if name.equal("const"[:]) {
      (KwConst, Some("const"))
    } else if name.equal("float"[:]) {
      (KwFloat, Some("float"))
    } else if name.equal("_Bool"[:]) {
      (KwBool, Some("_Bool"))
    } else if name.equal("short"[:]) {
      (KwShort, Some("short"))
    } else if name.equal("union"[:]) {
      (KwUnion, Some("union"))
    } else if name.equal("__asm"[:]) {
      (KwAsm, Some("__asm"))
    } else {
      (Ident, None)
    }
  } else if len == 6 {
    if name.equal("return"[:]) {
      (KwReturn, Some("return"))
    } else if name.equal("switch"[:]) {
      (KwSwitch, Some("switch"))
    } else if name.equal("extern"[:]) {
      (KwExtern, Some("extern"))
    } else if name.equal("static"[:]) {
      (KwStatic, Some("static"))
    } else if name.equal("signed"[:]) {
      (KwSigned, Some("signed"))
    } else if name.equal("inline"[:]) {
      (KwInline, Some("inline"))
    } else if name.equal("double"[:]) {
      (KwDouble, Some("double"))
    } else if name.equal("struct"[:]) {
      (KwStruct, Some("struct"))
    } else if name.equal("sizeof"[:]) {
      (KwSizeof, Some("sizeof"))
    } else if name.equal("typeof"[:]) {
      (KwTypeof, Some("typeof"))
    } else {
      (Ident, None)
    }
  } else if len == 7 {
    if name.equal("default"[:]) {
      (KwDefault, Some("default"))
    } else if name.equal("typedef"[:]) {
      (KwTypedef, Some("typedef"))
    } else if name.equal("__asm__"[:]) {
      (KwAsm, Some("__asm__"))
    } else if name.equal("__const"[:]) {
      (KwConst, Some("__const"))
    } else {
      (Ident, None)
    }
  } else if len == 8 {
    if name.equal("continue"[:]) {
      (KwContinue, Some("continue"))
    } else if name.equal("unsigned"[:]) {
      (KwUnsigned, Some("unsigned"))
    } else if name.equal("volatile"[:]) {
      (KwVolatile, Some("volatile"))
    } else if name.equal("register"[:]) {
      (KwRegister, Some("register"))
    } else if name.equal("restrict"[:]) {
      (KwRestrict, Some("restrict"))
    } else if name.equal("_Alignof"[:]) {
      (KwAlignof, Some("_Alignof"))
    } else if name.equal("__typeof"[:]) {
      (KwTypeof, Some("__typeof"))
    } else if name.equal("__inline"[:]) {
      (KwInline, Some("__inline"))
    } else if name.equal("__signed"[:]) {
      (KwSigned, Some("__signed"))
    } else if name.equal("_Float16"[:]) {
      (KwFloat, Some("_Float16"))
    } else {
      (Ident, None)
    }
  } else if len == 9 {
    if name.equal("_Noreturn"[:]) {
      (KwNoreturn, Some("_Noreturn"))
    } else if name.equal("__alignof"[:]) {
      (KwAlignof, Some("__alignof"))
    } else if name.equal("__const__"[:]) {
      (KwConst, Some("__const__"))
    } else {
      (Ident, None)
    }
  } else if len == 10 {
    if name.equal("__typeof__"[:]) {
      (KwTypeof, Some("__typeof__"))
    } else if name.equal("__volatile"[:]) {
      (KwVolatile, Some("__volatile"))
    } else if name.equal("__restrict"[:]) {
      (KwRestrict, Some("__restrict"))
    } else if name.equal("__inline__"[:]) {
      (KwInline, Some("__inline__"))
    } else if name.equal("__signed__"[:]) {
      (KwSigned, Some("__signed__"))
    } else if name.equal("__unsigned"[:]) {
      (KwUnsigned, Some("__unsigned"))
    } else {
      (Ident, None)
    }
  } else if len == 11 {
    if name.equal("__alignof__"[:]) {
      (KwAlignof, Some("__alignof__"))
    } else if name.equal("__attribute"[:]) {
      (KwAttribute, Some("__attribute"))
    } else {
      (Ident, None)
    }
  } else if len == 12 {
    if name.equal("__volatile__"[:]) {
      (KwVolatile, Some("__volatile__"))
    } else if name.equal("__restrict__"[:]) {
      (KwRestrict, Some("__restrict__"))
    } else if name.equal("__unsigned__"[:]) {
      (KwUnsigned, Some("__unsigned__"))
    } else {
      (Ident, None)
    }
  } else if len == 13 {
    if name.equal("__attribute__"[:]) {
      (KwAttribute, Some("__attribute__"))
    } else {
      (Ident, None)
    }
  } else if len == 14 {
    if name.equal("_Static_assert"[:]) {
      (KwStaticAssert, Some("_Static_assert"))
    } else {
      (Ident, None)
    }
  } else {
    (Ident, None)
  }
}
