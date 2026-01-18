///|
struct TypeQual {
  is_const : Bool
  is_volatile : Bool
  is_restrict : Bool
} derive(Show, Eq, ToJson)

///|
enum AlignSpec {
  Default
  Expr(expr~ : Expr)
} derive(Show, Eq, ToJson)

///|
enum Visibility {
  Default
  Hidden
  Internal
  Protected
} derive(Show, Eq, ToJson)

///|
enum CallConv {
  Default
  Cdecl
  Stdcall
  Fastcall
  Thiscall
  Regparm(count~ : Int)
} derive(Show, Eq, ToJson)

///|
fn normalize_call_conv(call_conv : CallConv?) -> CallConv {
  match call_conv {
    None => CallConv::Default
    Some(CallConv::Default) => CallConv::Default
    Some(CallConv::Cdecl) => CallConv::Default
    Some(CallConv::Regparm(count~)) =>
      if count <= 0 {
        CallConv::Default
      } else {
        CallConv::Regparm(count~)
      }
    Some(conv) => conv
  }
}

///|
fn merge_call_conv(existing : CallConv, incoming : CallConv) -> CallConv {
  if existing == CallConv::Default {
    incoming
  } else {
    existing
  }
}

///|
struct Attributes {
  aligned : AlignSpec?
  packed : Bool
  weak : Bool
  visibility : Visibility?
  section : String?
  alias_name : String?
  asm_label : String?
  cleanup : String?
  noreturn : Bool
  constructor_attr : Bool
  destructor : Bool
  always_inline : Bool
  call_conv : CallConv?
  dll_import : Bool
  dll_export : Bool
  nodecorate : Bool
  nodebug : Bool
} derive(Show, Eq, ToJson)

///|
fn empty_attrs() -> Attributes {
  {
    aligned: None,
    packed: false,
    weak: false,
    visibility: None,
    section: None,
    alias_name: None,
    asm_label: None,
    cleanup: None,
    noreturn: false,
    constructor_attr: false,
    destructor: false,
    always_inline: false,
    call_conv: None,
    dll_import: false,
    dll_export: false,
    nodecorate: false,
    nodebug: false,
  }
}

///|
fn attrs_with(
  aligned? : AlignSpec? = None,
  packed? : Bool = false,
  weak? : Bool = false,
  visibility? : Visibility? = None,
  section? : String? = None,
  alias_name? : String? = None,
  asm_label? : String? = None,
  cleanup? : String? = None,
  noreturn? : Bool = false,
  constructor_attr? : Bool = false,
  destructor? : Bool = false,
  always_inline? : Bool = false,
  call_conv? : CallConv? = None,
  dll_import? : Bool = false,
  dll_export? : Bool = false,
  nodecorate? : Bool = false,
  nodebug? : Bool = false,
) -> Attributes {
  {
    aligned,
    packed,
    weak,
    visibility,
    section,
    alias_name,
    asm_label,
    cleanup,
    noreturn,
    constructor_attr,
    destructor,
    always_inline,
    call_conv,
    dll_import,
    dll_export,
    nodecorate,
    nodebug,
  }
}

///|
fn merge_attrs(base : Attributes, incoming : Attributes) -> Attributes {
  if attrs_is_empty(incoming) {
    return base
  }
  if attrs_is_empty(base) {
    return incoming
  }
  let visibility = match base.visibility {
    Some(val) => Some(val)
    None => incoming.visibility
  }
  let section = match incoming.section {
    Some(_) => incoming.section
    None => base.section
  }
  let alias_name = match incoming.alias_name {
    Some(_) => incoming.alias_name
    None => base.alias_name
  }
  let asm_label = match incoming.asm_label {
    Some(_) => incoming.asm_label
    None => base.asm_label
  }
  let cleanup = match incoming.cleanup {
    Some(_) => incoming.cleanup
    None => base.cleanup
  }
  let call_conv = match base.call_conv {
    Some(val) => Some(val)
    None => incoming.call_conv
  }
  {
    aligned: if base.aligned is Some(_) {
      base.aligned
    } else {
      incoming.aligned
    },
    packed: base.packed || incoming.packed,
    weak: base.weak || incoming.weak,
    visibility,
    section,
    alias_name,
    asm_label,
    cleanup,
    noreturn: base.noreturn || incoming.noreturn,
    constructor_attr: base.constructor_attr || incoming.constructor_attr,
    destructor: base.destructor || incoming.destructor,
    always_inline: base.always_inline || incoming.always_inline,
    call_conv,
    dll_import: base.dll_import || incoming.dll_import,
    dll_export: base.dll_export || incoming.dll_export,
    nodecorate: base.nodecorate || incoming.nodecorate,
    nodebug: base.nodebug || incoming.nodebug,
  }
}

///|
fn type_attrs_from(attrs : Attributes) -> Attributes {
  {
    aligned: attrs.aligned,
    packed: attrs.packed,
    weak: false,
    visibility: None,
    section: None,
    alias_name: None,
    asm_label: None,
    cleanup: None,
    noreturn: false,
    constructor_attr: false,
    destructor: false,
    always_inline: false,
    call_conv: None,
    dll_import: false,
    dll_export: false,
    nodecorate: false,
    nodebug: false,
  }
}

///|
fn has_type_attrs(attrs : Attributes) -> Bool {
  attrs.aligned is Some(_) || attrs.packed
}

///|
fn apply_type_attrs(ty : CType, attrs : Attributes) -> CType {
  if !has_type_attrs(attrs) {
    return ty
  }
  match ty {
    CType::Struct(name~, id~, fields~, attrs=existing) =>
      CType::Struct(name~, id~, fields~, attrs=merge_attrs(existing, attrs))
    CType::Union(name~, id~, fields~, attrs=existing) =>
      CType::Union(name~, id~, fields~, attrs=merge_attrs(existing, attrs))
    CType::Attributed(attrs=existing, base~) =>
      CType::Attributed(attrs=merge_attrs(existing, attrs), base~)
    _ => CType::Attributed(attrs~, base=ty)
  }
}

///|
fn apply_call_conv_to_type(ty : CType, call_conv : CallConv) -> CType {
  if call_conv == CallConv::Default {
    return ty
  }
  match ty {
    CType::Qualified(qual~, base~) =>
      CType::Qualified(qual~, base=apply_call_conv_to_type(base, call_conv))
    CType::Attributed(attrs~, base~) =>
      CType::Attributed(attrs~, base=apply_call_conv_to_type(base, call_conv))
    CType::Pointer(inner) =>
      CType::Pointer(apply_call_conv_to_type(inner, call_conv))
    CType::Array(elem~, size~, size_expr~) =>
      CType::Array(
        elem=apply_call_conv_to_type(elem, call_conv),
        size~,
        size_expr~,
      )
    CType::Function(
      return_type~,
      params~,
      varargs~,
      is_old_style~,
      call_conv=existing
    ) =>
      CType::Function(
        return_type~,
        params~,
        varargs~,
        is_old_style~,
        call_conv=merge_call_conv(existing, call_conv),
      )
    _ => ty
  }
}

///|
enum CIntKind {
  Char
  Short
  Int
  Long
  LongLong
} derive(Show, Eq, ToJson)

///|
enum CFloatKind {
  Float
  Double
  LongDouble
} derive(Show, Eq, ToJson)

///|
enum StorageClass {
  Default
  Extern
  Static
  Auto
  Register
} derive(Show, Eq, ToJson)

///|
enum CType {
  Void
  Bool
  Int(kind~ : CIntKind, unsigned~ : Bool)
  Float(kind~ : CFloatKind)
  Pointer(CType)
  Array(elem~ : CType, size~ : Int?, size_expr~ : Expr?)
  Struct(
    name~ : String,
    id~ : Int,
    fields~ : Array[RecordItem]?,
    attrs~ : Attributes,
  )
  Union(
    name~ : String,
    id~ : Int,
    fields~ : Array[RecordItem]?,
    attrs~ : Attributes,
  )
  Enum(name~ : String, id~ : Int, items~ : Array[EnumItem]?)
  TypeofExpr(expr~ : Expr)
  Function(
    return_type~ : CType,
    params~ : Array[CType],
    varargs~ : Bool,
    is_old_style~ : Bool,
    call_conv~ : CallConv
  )
  Attributed(attrs~ : Attributes, base~ : CType)
  Qualified(qual~ : TypeQual, base~ : CType)
} derive(Show, Eq, ToJson)

///|
struct Field {
  name : String
  id : Int
  ty : CType
  bit_width : Expr?
  attrs : Attributes
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
struct StaticAssert {
  expr : Expr
  message : String?
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
enum RecordItem {
  Field(Field)
  StaticAssert(StaticAssert)
} derive(Show, Eq, ToJson)

///|
struct EnumItem {
  name : String
  id : Int
  value : Expr?
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
struct Param {
  name : String
  id : Int
  ty : CType
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
struct FuncDef {
  name : String
  id : Int
  return_type : CType
  params : Array[Param]
  varargs : Bool
  is_old_style : Bool
  storage : StorageClass
  is_inline : Bool
  attrs : Attributes
  body : Stmt
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
struct FuncDecl {
  name : String
  id : Int
  return_type : CType
  params : Array[Param]
  varargs : Bool
  is_old_style : Bool
  storage : StorageClass
  is_inline : Bool
  attrs : Attributes
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
struct VarDecl {
  name : String
  id : Int
  ty : CType
  init : Initializer?
  storage : StorageClass
  attrs : Attributes
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
enum Decl {
  FuncDef(FuncDef)
  FuncDecl(FuncDecl)
  Var(VarDecl)
  Typedef(name~ : String, ty~ : CType, attrs~ : Attributes, loc~ : SrcLoc)
  TagDef(ty~ : CType, loc~ : SrcLoc)
  StaticAssert(StaticAssert)
  Asm(AsmStmt)
} derive(Show, Eq, ToJson)

///|
struct TranslationUnit {
  decls : Array[Decl]
} derive(Show, Eq, ToJson)

///|
enum UnaryOp {
  Plus
  Minus
  Not
  BitNot
  Addr
  Deref
  PreInc
  PreDec
  PostInc
  PostDec
} derive(Show, Eq, ToJson)

///|
enum BinaryOp {
  Assign
  AddAssign
  SubAssign
  MulAssign
  DivAssign
  ModAssign
  ShlAssign
  ShrAssign
  BitAndAssign
  BitXorAssign
  BitOrAssign
  Comma
  Add
  Sub
  Mul
  Div
  Mod
  Shl
  Shr
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
  BitAnd
  BitXor
  BitOr
  LogAnd
  LogOr
} derive(Show, Eq, ToJson)

///|
enum Expr {
  IntLit(value~ : String, loc~ : SrcLoc)
  FloatLit(value~ : String, loc~ : SrcLoc)
  CharLit(value~ : Int, loc~ : SrcLoc)
  StringLit(value~ : String, length~ : Int, loc~ : SrcLoc)
  Ident(name~ : String, id~ : Int, loc~ : SrcLoc)
  BuiltinTypesCompatibleP(a~ : CType, b~ : CType, loc~ : SrcLoc)
  BuiltinOffsetof(ty~ : CType, path~ : Array[String], loc~ : SrcLoc)
  BuiltinVaArg(list~ : Expr, ty~ : CType, loc~ : SrcLoc)
  Unary(op~ : UnaryOp, expr~ : Expr, loc~ : SrcLoc)
  Cast(ty~ : CType, expr~ : Expr, loc~ : SrcLoc)
  CompoundLiteral(ty~ : CType, init~ : Initializer, loc~ : SrcLoc)
  StmtExpr(stmts~ : Array[Stmt], loc~ : SrcLoc)
  SizeofExpr(expr~ : Expr, loc~ : SrcLoc)
  SizeofType(ty~ : CType, loc~ : SrcLoc)
  AlignofExpr(expr~ : Expr, loc~ : SrcLoc)
  AlignofType(ty~ : CType, loc~ : SrcLoc)
  Binary(op~ : BinaryOp, left~ : Expr, right~ : Expr, loc~ : SrcLoc)
  Conditional(cond~ : Expr, then_expr~ : Expr, else_expr~ : Expr, loc~ : SrcLoc)
  Call(callee~ : Expr, args~ : Array[Expr], loc~ : SrcLoc)
  Index(base~ : Expr, index~ : Expr, loc~ : SrcLoc)
  Member(base~ : Expr, name~ : String, id~ : Int, is_arrow~ : Bool, loc~ : SrcLoc)
} derive(Show, Eq, ToJson)

///|
enum InitDesignator {
  Index(expr~ : Expr, loc~ : SrcLoc)
  Field(name~ : String, id~ : Int, loc~ : SrcLoc)
} derive(Show, Eq, ToJson)

///|
struct InitItem {
  designators : Array[InitDesignator]
  value : Initializer
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
enum Initializer {
  Expr(expr~ : Expr, loc~ : SrcLoc)
  List(items~ : Array[InitItem], loc~ : SrcLoc)
} derive(Show, Eq, ToJson)

///|
struct AsmOperand {
  name : String?
  constraint : String
  expr : Expr
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
struct AsmStmt {
  template : String
  outputs : Array[AsmOperand]
  inputs : Array[AsmOperand]
  clobbers : Array[String]
  labels : Array[String]
  is_volatile : Bool
  is_goto : Bool
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
enum Stmt {
  Compound(stmts~ : Array[Stmt], loc~ : SrcLoc)
  If(cond~ : Expr, then_branch~ : Stmt, else_branch~ : Stmt?, loc~ : SrcLoc)
  While(cond~ : Expr, body~ : Stmt, loc~ : SrcLoc)
  DoWhile(cond~ : Expr, body~ : Stmt, loc~ : SrcLoc)
  For(init~ : Stmt?, cond~ : Expr?, step~ : Expr?, body~ : Stmt, loc~ : SrcLoc)
  Switch(cond~ : Expr, body~ : Stmt, loc~ : SrcLoc)
  Case(expr~ : Expr, end_expr~ : Expr?, body~ : Stmt, loc~ : SrcLoc)
  Default(body~ : Stmt, loc~ : SrcLoc)
  Label(name~ : String, body~ : Stmt, loc~ : SrcLoc)
  Goto(name~ : String, loc~ : SrcLoc)
  Break(loc~ : SrcLoc)
  Continue(loc~ : SrcLoc)
  Return(value~ : Expr?, loc~ : SrcLoc)
  Asm(AsmStmt)
  ExprStmt(expr~ : Expr, loc~ : SrcLoc)
  DeclStmt(decls~ : Array[VarDecl], loc~ : SrcLoc)
  TagDef(ty~ : CType, loc~ : SrcLoc)
  StaticAssert(StaticAssert)
  Empty(loc~ : SrcLoc)
} derive(Show, Eq, ToJson)
