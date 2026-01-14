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
} derive(Show, Eq, ToJson)

///|
fn keyword_or_ident(name : String) -> TokenKind {
  match name {
    "if" => KwIf
    "else" => KwElse
    "while" => KwWhile
    "for" => KwFor
    "do" => KwDo
    "continue" => KwContinue
    "break" => KwBreak
    "return" => KwReturn
    "goto" => KwGoto
    "switch" => KwSwitch
    "case" => KwCase
    "default" => KwDefault
    "extern" => KwExtern
    "static" => KwStatic
    "unsigned" => KwUnsigned
    "signed" => KwSigned
    "const" => KwConst
    "volatile" => KwVolatile
    "register" => KwRegister
    "auto" => KwAuto
    "inline" => KwInline
    "restrict" => KwRestrict
    "void" => KwVoid
    "char" => KwChar
    "int" => KwInt
    "float" => KwFloat
    "double" => KwDouble
    "_Bool" => KwBool
    "short" => KwShort
    "long" => KwLong
    "struct" => KwStruct
    "union" => KwUnion
    "typedef" => KwTypedef
    "enum" => KwEnum
    "sizeof" => KwSizeof
    "__alignof" => KwAlignof
    "__alignof__" => KwAlignof
    "_Alignof" => KwAlignof
    "typeof" => KwTypeof
    "__typeof" => KwTypeof
    "__typeof__" => KwTypeof
    "__attribute" => KwAttribute
    "__attribute__" => KwAttribute
    "_Static_assert" => KwStaticAssert
    "asm" => KwAsm
    "__asm" => KwAsm
    "__asm__" => KwAsm
    _ => Ident
  }
}
