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
pub(all) struct TypeQual {
  is_const : Bool
  is_volatile : Bool
  is_restrict : Bool
  is_atomic : Bool
} derive(Show, Eq, ToJson)

///|
pub(all) enum AlignSpec {
  Default
  Expr(expr~ : Expr)
} derive(Show, Eq, ToJson)

///|
pub(all) enum Visibility {
  Default
  Hidden
  Internal
  Protected
} derive(Show, Eq, ToJson)

///|
pub(all) enum CallConv {
  Default
  Cdecl
  Stdcall
  Fastcall
  Thiscall
  Regparm(count~ : Int)
} derive(Show, Eq, ToJson)

///|
pub fn normalize_call_conv(call_conv : CallConv?) -> CallConv {
  match call_conv {
    None => Default
    Some(Default) => Default
    Some(Cdecl) => Default
    Some(Regparm(count~)) => if count <= 0 { Default } else { Regparm(count~) }
    Some(conv) => conv
  }
}

///|
pub fn merge_call_conv(existing : CallConv, incoming : CallConv) -> CallConv {
  if existing == Default {
    incoming
  } else {
    existing
  }
}

///|
pub(all) struct Attributes {
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
pub fn empty_attrs() -> Attributes {
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
pub fn attrs_with(
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
pub fn merge_attrs(base : Attributes, incoming : Attributes) -> Attributes {
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
pub fn attrs_is_empty(attrs : Attributes) -> Bool {
  attrs.aligned is None &&
  !attrs.packed &&
  !attrs.weak &&
  attrs.visibility is None &&
  attrs.section is None &&
  attrs.alias_name is None &&
  attrs.asm_label is None &&
  attrs.cleanup is None &&
  !attrs.noreturn &&
  !attrs.constructor_attr &&
  !attrs.destructor &&
  !attrs.always_inline &&
  attrs.call_conv is None &&
  !attrs.dll_import &&
  !attrs.dll_export &&
  !attrs.nodecorate &&
  !attrs.nodebug
}

///|
pub fn type_attrs_from(attrs : Attributes) -> Attributes {
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
pub fn has_type_attrs(attrs : Attributes) -> Bool {
  attrs.aligned is Some(_) || attrs.packed
}

///|
pub fn apply_type_attrs(ty : CType, attrs : Attributes) -> CType {
  if !has_type_attrs(attrs) {
    return ty
  }
  match ty {
    Struct(name~, id~, fields~, attrs=existing) =>
      Struct(name~, id~, fields~, attrs=merge_attrs(existing, attrs))
    Union(name~, id~, fields~, attrs=existing) =>
      Union(name~, id~, fields~, attrs=merge_attrs(existing, attrs))
    Attributed(attrs=existing, base~) =>
      Attributed(attrs=merge_attrs(existing, attrs), base~)
    _ => Attributed(attrs~, base=ty)
  }
}

///|
pub fn apply_call_conv_to_type(ty : CType, call_conv : CallConv) -> CType {
  if call_conv == Default {
    return ty
  }
  match ty {
    Qualified(qual~, base~) =>
      Qualified(qual~, base=apply_call_conv_to_type(base, call_conv))
    Attributed(attrs~, base~) =>
      Attributed(attrs~, base=apply_call_conv_to_type(base, call_conv))
    Pointer(inner) => Pointer(apply_call_conv_to_type(inner, call_conv))
    Array(elem~, size~, size_expr~) =>
      Array(elem=apply_call_conv_to_type(elem, call_conv), size~, size_expr~)
    Function(return_type~, params~, varargs~, is_old_style~, call_conv=existing) =>
      Function(
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
pub(all) enum CIntKind {
  Char
  Short
  Int
  Long
  LongLong
} derive(Show, Eq, ToJson)

///|
pub(all) enum CFloatKind {
  Float
  Double
  LongDouble
} derive(Show, Eq, ToJson)

///|
pub(all) enum StorageClass {
  Default
  Extern
  Static
  Auto
  Register
} derive(Show, Eq, ToJson)

///|
pub(all) enum CType {
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
    attrs~ : Attributes
  )
  Union(
    name~ : String,
    id~ : Int,
    fields~ : Array[RecordItem]?,
    attrs~ : Attributes
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
pub(all) struct Field {
  name : String
  id : Int
  ty : CType
  bit_width : Expr?
  attrs : Attributes
  loc : @source.SrcLoc
} derive(Show, Eq, ToJson)

///|
pub(all) struct StaticAssert {
  expr : Expr
  message : String?
  loc : @source.SrcLoc
} derive(Show, Eq, ToJson)

///|
pub(all) enum RecordItem {
  Field(Field)
  StaticAssert(StaticAssert)
} derive(Show, Eq, ToJson)

///|
pub(all) struct EnumItem {
  name : String
  id : Int
  value : Expr?
  loc : @source.SrcLoc
} derive(Show, Eq, ToJson)

///|
pub(all) struct Param {
  name : String
  id : Int
  ty : CType
  loc : @source.SrcLoc
} derive(Show, Eq, ToJson)

///|
pub(all) struct FuncDef {
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
  loc : @source.SrcLoc
} derive(Show, Eq, ToJson)

///|
pub(all) struct FuncDecl {
  name : String
  id : Int
  return_type : CType
  params : Array[Param]
  varargs : Bool
  is_old_style : Bool
  storage : StorageClass
  is_inline : Bool
  attrs : Attributes
  loc : @source.SrcLoc
} derive(Show, Eq, ToJson)

///|
pub(all) struct VarDecl {
  name : String
  id : Int
  ty : CType
  init : Initializer?
  storage : StorageClass
  attrs : Attributes
  loc : @source.SrcLoc
} derive(Show, Eq, ToJson)

///|
pub(all) enum Decl {
  FuncDef(FuncDef)
  FuncDecl(FuncDecl)
  Var(VarDecl)
  Typedef(
    name~ : String,
    ty~ : CType,
    attrs~ : Attributes,
    loc~ : @source.SrcLoc
  )
  TagDef(ty~ : CType, loc~ : @source.SrcLoc)
  StaticAssert(StaticAssert)
  Asm(AsmStmt)
} derive(Show, Eq, ToJson)

///|
pub(all) struct TranslationUnit {
  decls : Array[Decl]
  expr_id_max : Int
} derive(Show, Eq, ToJson)

///|
pub(all) enum UnaryOp {
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
pub(all) enum BinaryOp {
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
pub(all) enum Expr {
  IntLit(value~ : String, node_id~ : Int, loc~ : @source.SrcLoc)
  FloatLit(value~ : String, node_id~ : Int, loc~ : @source.SrcLoc)
  CharLit(value~ : Int, node_id~ : Int, loc~ : @source.SrcLoc)
  StringLit(
    value~ : String,
    length~ : Int,
    node_id~ : Int,
    loc~ : @source.SrcLoc
  )
  Ident(name~ : String, id~ : Int, node_id~ : Int, loc~ : @source.SrcLoc)
  LabelAddr(name~ : String, id~ : Int, node_id~ : Int, loc~ : @source.SrcLoc)
  BuiltinTypesCompatibleP(
    a~ : CType,
    b~ : CType,
    node_id~ : Int,
    loc~ : @source.SrcLoc
  )
  BuiltinOffsetof(
    ty~ : CType,
    path~ : Array[String],
    node_id~ : Int,
    loc~ : @source.SrcLoc
  )
  BuiltinVaArg(list~ : Expr, ty~ : CType, node_id~ : Int, loc~ : @source.SrcLoc)
  Unary(op~ : UnaryOp, expr~ : Expr, node_id~ : Int, loc~ : @source.SrcLoc)
  Cast(ty~ : CType, expr~ : Expr, node_id~ : Int, loc~ : @source.SrcLoc)
  CompoundLiteral(
    ty~ : CType,
    init~ : Initializer,
    node_id~ : Int,
    loc~ : @source.SrcLoc
  )
  StmtExpr(stmts~ : Array[Stmt], node_id~ : Int, loc~ : @source.SrcLoc)
  SizeofExpr(expr~ : Expr, node_id~ : Int, loc~ : @source.SrcLoc)
  SizeofType(ty~ : CType, node_id~ : Int, loc~ : @source.SrcLoc)
  AlignofExpr(expr~ : Expr, node_id~ : Int, loc~ : @source.SrcLoc)
  AlignofType(ty~ : CType, node_id~ : Int, loc~ : @source.SrcLoc)
  Binary(
    op~ : BinaryOp,
    left~ : Expr,
    right~ : Expr,
    node_id~ : Int,
    loc~ : @source.SrcLoc
  )
  Conditional(
    cond~ : Expr,
    then_expr~ : Expr,
    else_expr~ : Expr,
    node_id~ : Int,
    loc~ : @source.SrcLoc
  )
  Call(
    callee~ : Expr,
    args~ : Array[Expr],
    node_id~ : Int,
    loc~ : @source.SrcLoc
  )
  Index(base~ : Expr, index~ : Expr, node_id~ : Int, loc~ : @source.SrcLoc)
  Member(
    base~ : Expr,
    name~ : String,
    id~ : Int,
    is_arrow~ : Bool,
    node_id~ : Int,
    loc~ : @source.SrcLoc
  )
} derive(Show, Eq, ToJson)

///|
pub(all) enum InitDesignator {
  Index(expr~ : Expr, loc~ : @source.SrcLoc)
  IndexRange(start~ : Expr, end~ : Expr, loc~ : @source.SrcLoc)
  Field(name~ : String, id~ : Int, loc~ : @source.SrcLoc)
} derive(Show, Eq, ToJson)

///|
pub(all) struct InitItem {
  designators : Array[InitDesignator]
  value : Initializer
  loc : @source.SrcLoc
} derive(Show, Eq, ToJson)

///|
pub(all) enum Initializer {
  Expr(expr~ : Expr, loc~ : @source.SrcLoc)
  List(items~ : Array[InitItem], loc~ : @source.SrcLoc)
} derive(Show, Eq, ToJson)

///|
pub(all) struct AsmOperand {
  name : String?
  constraint : String
  expr : Expr
  loc : @source.SrcLoc
} derive(Show, Eq, ToJson)

///|
pub(all) struct AsmStmt {
  template : String
  outputs : Array[AsmOperand]
  inputs : Array[AsmOperand]
  clobbers : Array[String]
  labels : Array[String]
  is_volatile : Bool
  is_goto : Bool
  loc : @source.SrcLoc
} derive(Show, Eq, ToJson)

///|
pub(all) enum Stmt {
  Compound(stmts~ : Array[Stmt], loc~ : @source.SrcLoc)
  If(
    cond~ : Expr,
    then_branch~ : Stmt,
    else_branch~ : Stmt?,
    loc~ : @source.SrcLoc
  )
  While(cond~ : Expr, body~ : Stmt, loc~ : @source.SrcLoc)
  DoWhile(cond~ : Expr, body~ : Stmt, loc~ : @source.SrcLoc)
  For(
    init~ : Stmt?,
    cond~ : Expr?,
    step~ : Expr?,
    body~ : Stmt,
    loc~ : @source.SrcLoc
  )
  Switch(cond~ : Expr, body~ : Stmt, loc~ : @source.SrcLoc)
  Case(expr~ : Expr, end_expr~ : Expr?, body~ : Stmt, loc~ : @source.SrcLoc)
  Default(body~ : Stmt, loc~ : @source.SrcLoc)
  Label(name~ : String, body~ : Stmt, loc~ : @source.SrcLoc)
  Goto(name~ : String, loc~ : @source.SrcLoc)
  GotoExpr(expr~ : Expr, loc~ : @source.SrcLoc)
  Break(loc~ : @source.SrcLoc)
  Continue(loc~ : @source.SrcLoc)
  Return(value~ : Expr?, loc~ : @source.SrcLoc)
  Asm(AsmStmt)
  ExprStmt(expr~ : Expr, loc~ : @source.SrcLoc)
  DeclStmt(decls~ : Array[VarDecl], loc~ : @source.SrcLoc)
  TagDef(ty~ : CType, loc~ : @source.SrcLoc)
  StaticAssert(StaticAssert)
  Empty(loc~ : @source.SrcLoc)
} derive(Show, Eq, ToJson)

///|
let default_int_type_value : CType = Int(kind=Int, unsigned=false)

///|
pub fn default_int_type() -> CType {
  default_int_type_value
}
