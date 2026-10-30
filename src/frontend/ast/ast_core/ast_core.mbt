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
} derive(Eq, ToJson, Debug)

///|
pub(all) enum AlignSpec {
  Default
  Expr(expr~ : Expr)
} derive(Eq, ToJson, Debug)

///|
pub(all) enum Visibility {
  Default
  Hidden
  Internal
  Protected
} derive(Eq, ToJson, Debug)

///|
pub(all) enum CallConv {
  Default
  Cdecl
  Stdcall
  Fastcall
  Thiscall
  Regparm(count~ : Int32)
} derive(Eq, ToJson, Debug)

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
  ms_struct : Bool
  transparent_union : Bool
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
} derive(Eq, ToJson, Debug)

///|
pub fn empty_attrs() -> Attributes {
  {
    aligned: None,
    packed: false,
    ms_struct: false,
    transparent_union: false,
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
  aligned~ : AlignSpec? = None,
  packed~ : Bool = false,
  ms_struct~ : Bool = false,
  transparent_union~ : Bool = false,
  weak~ : Bool = false,
  visibility~ : Visibility? = None,
  section~ : String? = None,
  alias_name~ : String? = None,
  asm_label~ : String? = None,
  cleanup~ : String? = None,
  noreturn~ : Bool = false,
  constructor_attr~ : Bool = false,
  destructor~ : Bool = false,
  always_inline~ : Bool = false,
  call_conv~ : CallConv? = None,
  dll_import~ : Bool = false,
  dll_export~ : Bool = false,
  nodecorate~ : Bool = false,
  nodebug~ : Bool = false,
) -> Attributes {
  {
    aligned,
    packed,
    ms_struct,
    transparent_union,
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
    ms_struct: base.ms_struct || incoming.ms_struct,
    transparent_union: base.transparent_union || incoming.transparent_union,
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
  !attrs.ms_struct &&
  !attrs.transparent_union &&
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
    ms_struct: attrs.ms_struct,
    transparent_union: attrs.transparent_union,
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
  attrs.aligned is Some(_) ||
  attrs.packed ||
  attrs.ms_struct ||
  attrs.transparent_union
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
} derive(Eq, ToJson, Debug)

///|
pub(all) enum CFloatKind {
  Float
  Double
  LongDouble
} derive(Eq, ToJson, Debug)

///|
pub(all) enum StorageClass {
  Default
  Extern
  Static
  Auto
  Register
} derive(Eq, ToJson, Debug)

///|
pub(all) enum CType {
  Void
  Bool
  Int(kind~ : CIntKind, unsigned~ : Bool)
  Float(kind~ : CFloatKind)
  Pointer(CType)
  Array(elem~ : CType, size~ : Int32?, size_expr~ : Expr?)
  Struct(
    name~ : String,
    id~ : Int32,
    fields~ : Array[RecordItem]?,
    attrs~ : Attributes
  )
  Union(
    name~ : String,
    id~ : Int32,
    fields~ : Array[RecordItem]?,
    attrs~ : Attributes
  )
  Enum(name~ : String, id~ : Int32, items~ : Array[EnumItem]?)
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
} derive(Eq, ToJson, Debug)

///|
pub(all) struct Field {
  name : String
  id : Int32
  ty : CType
  bit_width : Expr?
  attrs : Attributes
  loc : @source.SrcLoc
} derive(Eq, ToJson, Debug)

///|
pub(all) struct StaticAssert {
  expr : Expr
  message : String?
  loc : @source.SrcLoc
} derive(Eq, ToJson, Debug)

///|
pub(all) enum RecordItem {
  Field(Field)
  StaticAssert(StaticAssert)
} derive(Eq, ToJson, Debug)

///|
pub(all) struct EnumItem {
  name : String
  id : Int32
  value : Expr?
  loc : @source.SrcLoc
} derive(Eq, ToJson, Debug)

///|
pub(all) struct Param {
  name : String
  id : Int32
  ty : CType
  loc : @source.SrcLoc
} derive(Eq, ToJson, Debug)

///|
pub(all) struct FuncDef {
  name : String
  id : Int32
  return_type : CType
  params : Array[Param]
  varargs : Bool
  is_old_style : Bool
  storage : StorageClass
  is_inline : Bool
  attrs : Attributes
  body : Stmt
  loc : @source.SrcLoc
} derive(Eq, ToJson, Debug)

///|
pub(all) struct FuncDecl {
  name : String
  id : Int32
  return_type : CType
  params : Array[Param]
  varargs : Bool
  is_old_style : Bool
  storage : StorageClass
  is_inline : Bool
  attrs : Attributes
  loc : @source.SrcLoc
} derive(Eq, ToJson, Debug)

///|
pub(all) struct VarDecl {
  name : String
  id : Int32
  ty : CType
  init : Initializer?
  storage : StorageClass
  attrs : Attributes
  loc : @source.SrcLoc
} derive(Eq, ToJson, Debug)

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
} derive(Eq, ToJson, Debug)

///|
pub(all) struct TranslationUnit {
  decls : Array[Decl]
  expr_id_max : Int32
} derive(Eq, ToJson, Debug)

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
} derive(Eq, ToJson, Debug)

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
} derive(Eq, ToJson, Debug)

///|
pub(all) enum Expr {
  IntLit(value~ : String, node_id~ : Int32, loc~ : @source.SrcLoc)
  FloatLit(value~ : String, node_id~ : Int32, loc~ : @source.SrcLoc)
  CharLit(value~ : Int32, node_id~ : Int32, loc~ : @source.SrcLoc)
  StringLit(
    value~ : String,
    length~ : Int32,
    node_id~ : Int32,
    loc~ : @source.SrcLoc
  )
  Ident(name~ : String, id~ : Int32, node_id~ : Int32, loc~ : @source.SrcLoc)
  LabelAddr(
    name~ : String,
    id~ : Int32,
    node_id~ : Int32,
    loc~ : @source.SrcLoc
  )
  BuiltinTypesCompatibleP(
    a~ : CType,
    b~ : CType,
    node_id~ : Int32,
    loc~ : @source.SrcLoc
  )
  BuiltinOffsetof(
    ty~ : CType,
    path~ : Array[String],
    node_id~ : Int32,
    loc~ : @source.SrcLoc
  )
  BuiltinVaArg(
    list~ : Expr,
    ty~ : CType,
    node_id~ : Int32,
    loc~ : @source.SrcLoc
  )
  Unary(op~ : UnaryOp, expr~ : Expr, node_id~ : Int32, loc~ : @source.SrcLoc)
  Cast(ty~ : CType, expr~ : Expr, node_id~ : Int32, loc~ : @source.SrcLoc)
  CompoundLiteral(
    ty~ : CType,
    init~ : Initializer,
    node_id~ : Int32,
    loc~ : @source.SrcLoc
  )
  StmtExpr(stmts~ : Array[Stmt], node_id~ : Int32, loc~ : @source.SrcLoc)
  SizeofExpr(expr~ : Expr, node_id~ : Int32, loc~ : @source.SrcLoc)
  SizeofType(ty~ : CType, node_id~ : Int32, loc~ : @source.SrcLoc)
  AlignofExpr(expr~ : Expr, node_id~ : Int32, loc~ : @source.SrcLoc)
  AlignofType(ty~ : CType, node_id~ : Int32, loc~ : @source.SrcLoc)
  Binary(
    op~ : BinaryOp,
    left~ : Expr,
    right~ : Expr,
    node_id~ : Int32,
    loc~ : @source.SrcLoc
  )
  Conditional(
    cond~ : Expr,
    then_expr~ : Expr,
    else_expr~ : Expr,
    node_id~ : Int32,
    loc~ : @source.SrcLoc
  )
  Call(
    callee~ : Expr,
    args~ : Array[Expr],
    node_id~ : Int32,
    loc~ : @source.SrcLoc
  )
  Index(base~ : Expr, index~ : Expr, node_id~ : Int32, loc~ : @source.SrcLoc)
  Member(
    base~ : Expr,
    name~ : String,
    id~ : Int32,
    is_arrow~ : Bool,
    node_id~ : Int32,
    loc~ : @source.SrcLoc
  )
} derive(Eq, ToJson, Debug)

///|
pub(all) enum InitDesignator {
  Index(expr~ : Expr, loc~ : @source.SrcLoc)
  IndexRange(start~ : Expr, end~ : Expr, loc~ : @source.SrcLoc)
  Field(name~ : String, id~ : Int32, loc~ : @source.SrcLoc)
} derive(Eq, ToJson, Debug)

///|
pub(all) struct InitItem {
  designators : Array[InitDesignator]
  value : Initializer
  loc : @source.SrcLoc
} derive(Eq, ToJson, Debug)

///|
pub(all) enum Initializer {
  Expr(expr~ : Expr, loc~ : @source.SrcLoc)
  List(items~ : Array[InitItem], loc~ : @source.SrcLoc)
} derive(Eq, ToJson, Debug)

///|
pub(all) struct AsmOperand {
  name : String?
  constraint : String
  expr : Expr
  loc : @source.SrcLoc
} derive(Eq, ToJson, Debug)

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
} derive(Eq, ToJson, Debug)

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
} derive(Eq, ToJson, Debug)

///|
let default_int_type_value : CType = Int(kind=Int, unsigned=false)

///|
pub fn default_int_type() -> CType {
  default_int_type_value
}

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|

///|
pub extend AlignSpec with Debug::{to_repr}

///|
pub extend AlignSpec with Eq::{not_equal, equal}

///|
pub extend AlignSpec with Show::{to_string, output}

///|
pub extend AlignSpec with ToJson::{to_json}

///|
pub extend AsmOperand with Debug::{to_repr}

///|
pub extend AsmOperand with Eq::{not_equal, equal}

///|
pub extend AsmOperand with Show::{to_string, output}

///|
pub extend AsmOperand with ToJson::{to_json}

///|
pub extend AsmStmt with Debug::{to_repr}

///|
pub extend AsmStmt with Eq::{not_equal, equal}

///|
pub extend AsmStmt with Show::{to_string, output}

///|
pub extend AsmStmt with ToJson::{to_json}

///|
pub extend Attributes with Debug::{to_repr}

///|
pub extend Attributes with Eq::{not_equal, equal}

///|
pub extend Attributes with Show::{to_string, output}

///|
pub extend Attributes with ToJson::{to_json}

///|
pub extend BinaryOp with Debug::{to_repr}

///|
pub extend BinaryOp with Eq::{not_equal, equal}

///|
pub extend BinaryOp with Show::{to_string, output}

///|
pub extend BinaryOp with ToJson::{to_json}

///|
pub extend CFloatKind with Debug::{to_repr}

///|
pub extend CFloatKind with Eq::{not_equal, equal}

///|
pub extend CFloatKind with Show::{to_string, output}

///|
pub extend CFloatKind with ToJson::{to_json}

///|
pub extend CIntKind with Debug::{to_repr}

///|
pub extend CIntKind with Eq::{not_equal, equal}

///|
pub extend CIntKind with Show::{to_string, output}

///|
pub extend CIntKind with ToJson::{to_json}

///|
pub extend CType with Debug::{to_repr}

///|
pub extend CType with Eq::{not_equal, equal}

///|
pub extend CType with Show::{to_string, output}

///|
pub extend CType with ToJson::{to_json}

///|
pub extend CallConv with Debug::{to_repr}

///|
pub extend CallConv with Eq::{not_equal, equal}

///|
pub extend CallConv with Show::{to_string, output}

///|
pub extend CallConv with ToJson::{to_json}

///|
pub extend Decl with Debug::{to_repr}

///|
pub extend Decl with Eq::{not_equal, equal}

///|
pub extend Decl with Show::{to_string, output}

///|
pub extend Decl with ToJson::{to_json}

///|
pub extend EnumItem with Debug::{to_repr}

///|
pub extend EnumItem with Eq::{not_equal, equal}

///|
pub extend EnumItem with Show::{to_string, output}

///|
pub extend EnumItem with ToJson::{to_json}

///|
pub extend Expr with Debug::{to_repr}

///|
pub extend Expr with Eq::{not_equal, equal}

///|
pub extend Expr with Show::{to_string, output}

///|
pub extend Expr with ToJson::{to_json}

///|
pub extend Field with Debug::{to_repr}

///|
pub extend Field with Eq::{not_equal, equal}

///|
pub extend Field with Show::{to_string, output}

///|
pub extend Field with ToJson::{to_json}

///|
pub extend FuncDecl with Debug::{to_repr}

///|
pub extend FuncDecl with Eq::{not_equal, equal}

///|
pub extend FuncDecl with Show::{to_string, output}

///|
pub extend FuncDecl with ToJson::{to_json}

///|
pub extend FuncDef with Debug::{to_repr}

///|
pub extend FuncDef with Eq::{not_equal, equal}

///|
pub extend FuncDef with Show::{to_string, output}

///|
pub extend FuncDef with ToJson::{to_json}

///|
pub extend InitDesignator with Debug::{to_repr}

///|
pub extend InitDesignator with Eq::{not_equal, equal}

///|
pub extend InitDesignator with Show::{to_string, output}

///|
pub extend InitDesignator with ToJson::{to_json}

///|
pub extend InitItem with Debug::{to_repr}

///|
pub extend InitItem with Eq::{not_equal, equal}

///|
pub extend InitItem with Show::{to_string, output}

///|
pub extend InitItem with ToJson::{to_json}

///|
pub extend Initializer with Debug::{to_repr}

///|
pub extend Initializer with Eq::{not_equal, equal}

///|
pub extend Initializer with Show::{to_string, output}

///|
pub extend Initializer with ToJson::{to_json}

///|
pub extend Param with Debug::{to_repr}

///|
pub extend Param with Eq::{not_equal, equal}

///|
pub extend Param with Show::{to_string, output}

///|
pub extend Param with ToJson::{to_json}

///|
pub extend RecordItem with Debug::{to_repr}

///|
pub extend RecordItem with Eq::{not_equal, equal}

///|
pub extend RecordItem with Show::{to_string, output}

///|
pub extend RecordItem with ToJson::{to_json}

///|
pub extend StaticAssert with Debug::{to_repr}

///|
pub extend StaticAssert with Eq::{not_equal, equal}

///|
pub extend StaticAssert with Show::{to_string, output}

///|
pub extend StaticAssert with ToJson::{to_json}

///|
pub extend Stmt with Debug::{to_repr}

///|
pub extend Stmt with Eq::{not_equal, equal}

///|
pub extend Stmt with Show::{to_string, output}

///|
pub extend Stmt with ToJson::{to_json}

///|
pub extend StorageClass with Debug::{to_repr}

///|
pub extend StorageClass with Eq::{not_equal, equal}

///|
pub extend StorageClass with Show::{to_string, output}

///|
pub extend StorageClass with ToJson::{to_json}

///|
pub extend TranslationUnit with Debug::{to_repr}

///|
pub extend TranslationUnit with Eq::{not_equal, equal}

///|
pub extend TranslationUnit with Show::{to_string, output}

///|
pub extend TranslationUnit with ToJson::{to_json}

///|
pub extend TypeQual with Debug::{to_repr}

///|
pub extend TypeQual with Eq::{not_equal, equal}

///|
pub extend TypeQual with Show::{to_string, output}

///|
pub extend TypeQual with ToJson::{to_json}

///|
pub extend UnaryOp with Debug::{to_repr}

///|
pub extend UnaryOp with Eq::{not_equal, equal}

///|
pub extend UnaryOp with Show::{to_string, output}

///|
pub extend UnaryOp with ToJson::{to_json}

///|
pub extend VarDecl with Debug::{to_repr}

///|
pub extend VarDecl with Eq::{not_equal, equal}

///|
pub extend VarDecl with Show::{to_string, output}

///|
pub extend VarDecl with ToJson::{to_json}

///|
pub extend Visibility with Debug::{to_repr}

///|
pub extend Visibility with Eq::{not_equal, equal}

///|
pub extend Visibility with Show::{to_string, output}

///|
pub extend Visibility with ToJson::{to_json}

///|
pub impl Show for TypeQual with fn output(self, logger) {
  logger.write_string("{")
  logger.write_string("is_const: ")
  logger.write_object(self.is_const)
  logger.write_string(", is_volatile: ")
  logger.write_object(self.is_volatile)
  logger.write_string(", is_restrict: ")
  logger.write_object(self.is_restrict)
  logger.write_string(", is_atomic: ")
  logger.write_object(self.is_atomic)
  logger.write_string("}")
}

///|
pub impl Show for AlignSpec with fn output(self, logger) {
  match self {
    Default => logger.write_string("Default")
    Expr(expr=arg0) => {
      logger.write_string("Expr(")
      logger.write_string("expr=")
      logger.write_object(arg0)
      logger.write_string(")")
    }
  }
}

///|
pub impl Show for Visibility with fn output(self, logger) {
  match self {
    Default => logger.write_string("Default")
    Hidden => logger.write_string("Hidden")
    Internal => logger.write_string("Internal")
    Protected => logger.write_string("Protected")
  }
}

///|
pub impl Show for CallConv with fn output(self, logger) {
  match self {
    Default => logger.write_string("Default")
    Cdecl => logger.write_string("Cdecl")
    Stdcall => logger.write_string("Stdcall")
    Fastcall => logger.write_string("Fastcall")
    Thiscall => logger.write_string("Thiscall")
    Regparm(count=arg0) => {
      logger.write_string("Regparm(")
      logger.write_string("count=")
      logger.write_object(arg0)
      logger.write_string(")")
    }
  }
}

///|
pub impl Show for Attributes with fn output(self, logger) {
  logger.write_string("{")
  logger.write_string("aligned: ")
  match self.aligned {
    None => logger.write_string("None")
    Some(value26) => {
      logger.write_string("Some(")
      logger.write_object(value26)
      logger.write_string(")")
    }
  }
  logger.write_string(", packed: ")
  logger.write_object(self.packed)
  logger.write_string(", ms_struct: ")
  logger.write_object(self.ms_struct)
  logger.write_string(", transparent_union: ")
  logger.write_object(self.transparent_union)
  logger.write_string(", weak: ")
  logger.write_object(self.weak)
  logger.write_string(", visibility: ")
  match self.visibility {
    None => logger.write_string("None")
    Some(value32) => {
      logger.write_string("Some(")
      logger.write_object(value32)
      logger.write_string(")")
    }
  }
  logger.write_string(", section: ")
  match self.section {
    None => logger.write_string("None")
    Some(value34) => {
      logger.write_string("Some(")
      logger.write_object(value34)
      logger.write_string(")")
    }
  }
  logger.write_string(", alias_name: ")
  match self.alias_name {
    None => logger.write_string("None")
    Some(value36) => {
      logger.write_string("Some(")
      logger.write_object(value36)
      logger.write_string(")")
    }
  }
  logger.write_string(", asm_label: ")
  match self.asm_label {
    None => logger.write_string("None")
    Some(value38) => {
      logger.write_string("Some(")
      logger.write_object(value38)
      logger.write_string(")")
    }
  }
  logger.write_string(", cleanup: ")
  match self.cleanup {
    None => logger.write_string("None")
    Some(value40) => {
      logger.write_string("Some(")
      logger.write_object(value40)
      logger.write_string(")")
    }
  }
  logger.write_string(", noreturn: ")
  logger.write_object(self.noreturn)
  logger.write_string(", constructor_attr: ")
  logger.write_object(self.constructor_attr)
  logger.write_string(", destructor: ")
  logger.write_object(self.destructor)
  logger.write_string(", always_inline: ")
  logger.write_object(self.always_inline)
  logger.write_string(", call_conv: ")
  match self.call_conv {
    None => logger.write_string("None")
    Some(value46) => {
      logger.write_string("Some(")
      logger.write_object(value46)
      logger.write_string(")")
    }
  }
  logger.write_string(", dll_import: ")
  logger.write_object(self.dll_import)
  logger.write_string(", dll_export: ")
  logger.write_object(self.dll_export)
  logger.write_string(", nodecorate: ")
  logger.write_object(self.nodecorate)
  logger.write_string(", nodebug: ")
  logger.write_object(self.nodebug)
  logger.write_string("}")
}

///|
pub impl Show for CIntKind with fn output(self, logger) {
  match self {
    Char => logger.write_string("Char")
    Short => logger.write_string("Short")
    Int => logger.write_string("Int")
    Long => logger.write_string("Long")
    LongLong => logger.write_string("LongLong")
  }
}

///|
pub impl Show for CFloatKind with fn output(self, logger) {
  match self {
    Float => logger.write_string("Float")
    Double => logger.write_string("Double")
    LongDouble => logger.write_string("LongDouble")
  }
}

///|
pub impl Show for StorageClass with fn output(self, logger) {
  match self {
    Default => logger.write_string("Default")
    Extern => logger.write_string("Extern")
    Static => logger.write_string("Static")
    Auto => logger.write_string("Auto")
    Register => logger.write_string("Register")
  }
}

///|
pub impl Show for CType with fn output(self, logger) {
  match self {
    Void => logger.write_string("Void")
    Bool => logger.write_string("Bool")
    Int(kind=arg0, unsigned=arg1) => {
      logger.write_string("Int(")
      logger.write_string("kind=")
      logger.write_object(arg0)
      logger.write_string(", unsigned=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
    Float(kind=arg0) => {
      logger.write_string("Float(")
      logger.write_string("kind=")
      logger.write_object(arg0)
      logger.write_string(")")
    }
    Pointer(arg0) => {
      logger.write_string("Pointer(")
      logger.write_object(arg0)
      logger.write_string(")")
    }
    Array(elem=arg0, size=arg1, size_expr=arg2) => {
      logger.write_string("Array(")
      logger.write_string("elem=")
      logger.write_object(arg0)
      logger.write_string(", size=")
      match arg1 {
        None => logger.write_string("None")
        Some(value57) => {
          logger.write_string("Some(")
          logger.write_object(value57)
          logger.write_string(")")
        }
      }
      logger.write_string(", size_expr=")
      match arg2 {
        None => logger.write_string("None")
        Some(value59) => {
          logger.write_string("Some(")
          logger.write_object(value59)
          logger.write_string(")")
        }
      }
      logger.write_string(")")
    }
    Struct(name=arg0, id=arg1, fields=arg2, attrs=arg3) => {
      logger.write_string("Struct(")
      logger.write_string("name=")
      logger.write_object(arg0)
      logger.write_string(", id=")
      logger.write_object(arg1)
      logger.write_string(", fields=")
      match arg2 {
        None => logger.write_string("None")
        Some(value63) => {
          logger.write_string("Some(")
          logger.write_string("[")
          for i64, value64 in value63 {
            if i64 > 0 {
              logger.write_string(", ")
            }
            logger.write_object(value64)
          }
          logger.write_string("]")
          logger.write_string(")")
        }
      }
      logger.write_string(", attrs=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    Union(name=arg0, id=arg1, fields=arg2, attrs=arg3) => {
      logger.write_string("Union(")
      logger.write_string("name=")
      logger.write_object(arg0)
      logger.write_string(", id=")
      logger.write_object(arg1)
      logger.write_string(", fields=")
      match arg2 {
        None => logger.write_string("None")
        Some(value69) => {
          logger.write_string("Some(")
          logger.write_string("[")
          for i70, value70 in value69 {
            if i70 > 0 {
              logger.write_string(", ")
            }
            logger.write_object(value70)
          }
          logger.write_string("]")
          logger.write_string(")")
        }
      }
      logger.write_string(", attrs=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    Enum(name=arg0, id=arg1, items=arg2) => {
      logger.write_string("Enum(")
      logger.write_string("name=")
      logger.write_object(arg0)
      logger.write_string(", id=")
      logger.write_object(arg1)
      logger.write_string(", items=")
      match arg2 {
        None => logger.write_string("None")
        Some(value75) => {
          logger.write_string("Some(")
          logger.write_string("[")
          for i76, value76 in value75 {
            if i76 > 0 {
              logger.write_string(", ")
            }
            logger.write_object(value76)
          }
          logger.write_string("]")
          logger.write_string(")")
        }
      }
      logger.write_string(")")
    }
    TypeofExpr(expr=arg0) => {
      logger.write_string("TypeofExpr(")
      logger.write_string("expr=")
      logger.write_object(arg0)
      logger.write_string(")")
    }
    Function(
      return_type=arg0,
      params=arg1,
      varargs=arg2,
      is_old_style=arg3,
      call_conv=arg4
    ) => {
      logger.write_string("Function(")
      logger.write_string("return_type=")
      logger.write_object(arg0)
      logger.write_string(", params=")
      logger.write_string("[")
      for i80, value80 in arg1 {
        if i80 > 0 {
          logger.write_string(", ")
        }
        logger.write_object(value80)
      }
      logger.write_string("]")
      logger.write_string(", varargs=")
      logger.write_object(arg2)
      logger.write_string(", is_old_style=")
      logger.write_object(arg3)
      logger.write_string(", call_conv=")
      logger.write_object(arg4)
      logger.write_string(")")
    }
    Attributed(attrs=arg0, base=arg1) => {
      logger.write_string("Attributed(")
      logger.write_string("attrs=")
      logger.write_object(arg0)
      logger.write_string(", base=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
    Qualified(qual=arg0, base=arg1) => {
      logger.write_string("Qualified(")
      logger.write_string("qual=")
      logger.write_object(arg0)
      logger.write_string(", base=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
  }
}

///|
pub impl Show for Field with fn output(self, logger) {
  logger.write_string("{")
  logger.write_string("name: ")
  logger.write_object(self.name)
  logger.write_string(", id: ")
  logger.write_object(self.id)
  logger.write_string(", ty: ")
  logger.write_object(self.ty)
  logger.write_string(", bit_width: ")
  match self.bit_width {
    None => logger.write_string("None")
    Some(value92) => {
      logger.write_string("Some(")
      logger.write_object(value92)
      logger.write_string(")")
    }
  }
  logger.write_string(", attrs: ")
  logger.write_object(self.attrs)
  logger.write_string(", loc: ")
  logger.write_object(self.loc)
  logger.write_string("}")
}

///|
pub impl Show for StaticAssert with fn output(self, logger) {
  logger.write_string("{")
  logger.write_string("expr: ")
  logger.write_object(self.expr)
  logger.write_string(", message: ")
  match self.message {
    None => logger.write_string("None")
    Some(value97) => {
      logger.write_string("Some(")
      logger.write_object(value97)
      logger.write_string(")")
    }
  }
  logger.write_string(", loc: ")
  logger.write_object(self.loc)
  logger.write_string("}")
}

///|
pub impl Show for RecordItem with fn output(self, logger) {
  match self {
    Field(arg0) => {
      logger.write_string("Field(")
      logger.write_object(arg0)
      logger.write_string(")")
    }
    StaticAssert(arg0) => {
      logger.write_string("StaticAssert(")
      logger.write_object(arg0)
      logger.write_string(")")
    }
  }
}

///|
pub impl Show for EnumItem with fn output(self, logger) {
  logger.write_string("{")
  logger.write_string("name: ")
  logger.write_object(self.name)
  logger.write_string(", id: ")
  logger.write_object(self.id)
  logger.write_string(", value: ")
  match self.value {
    None => logger.write_string("None")
    Some(value104) => {
      logger.write_string("Some(")
      logger.write_object(value104)
      logger.write_string(")")
    }
  }
  logger.write_string(", loc: ")
  logger.write_object(self.loc)
  logger.write_string("}")
}

///|
pub impl Show for Param with fn output(self, logger) {
  logger.write_string("{")
  logger.write_string("name: ")
  logger.write_object(self.name)
  logger.write_string(", id: ")
  logger.write_object(self.id)
  logger.write_string(", ty: ")
  logger.write_object(self.ty)
  logger.write_string(", loc: ")
  logger.write_object(self.loc)
  logger.write_string("}")
}

///|
pub impl Show for FuncDef with fn output(self, logger) {
  logger.write_string("{")
  logger.write_string("name: ")
  logger.write_object(self.name)
  logger.write_string(", id: ")
  logger.write_object(self.id)
  logger.write_string(", return_type: ")
  logger.write_object(self.return_type)
  logger.write_string(", params: ")
  logger.write_string("[")
  for i114, value114 in self.params {
    if i114 > 0 {
      logger.write_string(", ")
    }
    logger.write_object(value114)
  }
  logger.write_string("]")
  logger.write_string(", varargs: ")
  logger.write_object(self.varargs)
  logger.write_string(", is_old_style: ")
  logger.write_object(self.is_old_style)
  logger.write_string(", storage: ")
  logger.write_object(self.storage)
  logger.write_string(", is_inline: ")
  logger.write_object(self.is_inline)
  logger.write_string(", attrs: ")
  logger.write_object(self.attrs)
  logger.write_string(", body: ")
  logger.write_object(self.body)
  logger.write_string(", loc: ")
  logger.write_object(self.loc)
  logger.write_string("}")
}

///|
pub impl Show for FuncDecl with fn output(self, logger) {
  logger.write_string("{")
  logger.write_string("name: ")
  logger.write_object(self.name)
  logger.write_string(", id: ")
  logger.write_object(self.id)
  logger.write_string(", return_type: ")
  logger.write_object(self.return_type)
  logger.write_string(", params: ")
  logger.write_string("[")
  for i126, value126 in self.params {
    if i126 > 0 {
      logger.write_string(", ")
    }
    logger.write_object(value126)
  }
  logger.write_string("]")
  logger.write_string(", varargs: ")
  logger.write_object(self.varargs)
  logger.write_string(", is_old_style: ")
  logger.write_object(self.is_old_style)
  logger.write_string(", storage: ")
  logger.write_object(self.storage)
  logger.write_string(", is_inline: ")
  logger.write_object(self.is_inline)
  logger.write_string(", attrs: ")
  logger.write_object(self.attrs)
  logger.write_string(", loc: ")
  logger.write_object(self.loc)
  logger.write_string("}")
}

///|
pub impl Show for VarDecl with fn output(self, logger) {
  logger.write_string("{")
  logger.write_string("name: ")
  logger.write_object(self.name)
  logger.write_string(", id: ")
  logger.write_object(self.id)
  logger.write_string(", ty: ")
  logger.write_object(self.ty)
  logger.write_string(", init: ")
  match self.init {
    None => logger.write_string("None")
    Some(value137) => {
      logger.write_string("Some(")
      logger.write_object(value137)
      logger.write_string(")")
    }
  }
  logger.write_string(", storage: ")
  logger.write_object(self.storage)
  logger.write_string(", attrs: ")
  logger.write_object(self.attrs)
  logger.write_string(", loc: ")
  logger.write_object(self.loc)
  logger.write_string("}")
}

///|
pub impl Show for Decl with fn output(self, logger) {
  match self {
    FuncDef(arg0) => {
      logger.write_string("FuncDef(")
      logger.write_object(arg0)
      logger.write_string(")")
    }
    FuncDecl(arg0) => {
      logger.write_string("FuncDecl(")
      logger.write_object(arg0)
      logger.write_string(")")
    }
    Var(arg0) => {
      logger.write_string("Var(")
      logger.write_object(arg0)
      logger.write_string(")")
    }
    Typedef(name=arg0, ty=arg1, attrs=arg2, loc=arg3) => {
      logger.write_string("Typedef(")
      logger.write_string("name=")
      logger.write_object(arg0)
      logger.write_string(", ty=")
      logger.write_object(arg1)
      logger.write_string(", attrs=")
      logger.write_object(arg2)
      logger.write_string(", loc=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    TagDef(ty=arg0, loc=arg1) => {
      logger.write_string("TagDef(")
      logger.write_string("ty=")
      logger.write_object(arg0)
      logger.write_string(", loc=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
    StaticAssert(arg0) => {
      logger.write_string("StaticAssert(")
      logger.write_object(arg0)
      logger.write_string(")")
    }
    Asm(arg0) => {
      logger.write_string("Asm(")
      logger.write_object(arg0)
      logger.write_string(")")
    }
  }
}

///|
pub impl Show for TranslationUnit with fn output(self, logger) {
  logger.write_string("{")
  logger.write_string("decls: ")
  logger.write_string("[")
  for i153, value153 in self.decls {
    if i153 > 0 {
      logger.write_string(", ")
    }
    logger.write_object(value153)
  }
  logger.write_string("]")
  logger.write_string(", expr_id_max: ")
  logger.write_object(self.expr_id_max)
  logger.write_string("}")
}

///|
pub impl Show for UnaryOp with fn output(self, logger) {
  match self {
    Plus => logger.write_string("Plus")
    Minus => logger.write_string("Minus")
    Not => logger.write_string("Not")
    BitNot => logger.write_string("BitNot")
    Addr => logger.write_string("Addr")
    Deref => logger.write_string("Deref")
    PreInc => logger.write_string("PreInc")
    PreDec => logger.write_string("PreDec")
    PostInc => logger.write_string("PostInc")
    PostDec => logger.write_string("PostDec")
  }
}

///|
pub impl Show for BinaryOp with fn output(self, logger) {
  match self {
    Assign => logger.write_string("Assign")
    AddAssign => logger.write_string("AddAssign")
    SubAssign => logger.write_string("SubAssign")
    MulAssign => logger.write_string("MulAssign")
    DivAssign => logger.write_string("DivAssign")
    ModAssign => logger.write_string("ModAssign")
    ShlAssign => logger.write_string("ShlAssign")
    ShrAssign => logger.write_string("ShrAssign")
    BitAndAssign => logger.write_string("BitAndAssign")
    BitXorAssign => logger.write_string("BitXorAssign")
    BitOrAssign => logger.write_string("BitOrAssign")
    Comma => logger.write_string("Comma")
    Add => logger.write_string("Add")
    Sub => logger.write_string("Sub")
    Mul => logger.write_string("Mul")
    Div => logger.write_string("Div")
    Mod => logger.write_string("Mod")
    Shl => logger.write_string("Shl")
    Shr => logger.write_string("Shr")
    Eq => logger.write_string("Eq")
    Ne => logger.write_string("Ne")
    Lt => logger.write_string("Lt")
    Le => logger.write_string("Le")
    Gt => logger.write_string("Gt")
    Ge => logger.write_string("Ge")
    BitAnd => logger.write_string("BitAnd")
    BitXor => logger.write_string("BitXor")
    BitOr => logger.write_string("BitOr")
    LogAnd => logger.write_string("LogAnd")
    LogOr => logger.write_string("LogOr")
  }
}

///|
pub impl Show for Expr with fn output(self, logger) {
  match self {
    IntLit(value=arg0, node_id=arg1, loc=arg2) => {
      logger.write_string("IntLit(")
      logger.write_string("value=")
      logger.write_object(arg0)
      logger.write_string(", node_id=")
      logger.write_object(arg1)
      logger.write_string(", loc=")
      logger.write_object(arg2)
      logger.write_string(")")
    }
    FloatLit(value=arg0, node_id=arg1, loc=arg2) => {
      logger.write_string("FloatLit(")
      logger.write_string("value=")
      logger.write_object(arg0)
      logger.write_string(", node_id=")
      logger.write_object(arg1)
      logger.write_string(", loc=")
      logger.write_object(arg2)
      logger.write_string(")")
    }
    CharLit(value=arg0, node_id=arg1, loc=arg2) => {
      logger.write_string("CharLit(")
      logger.write_string("value=")
      logger.write_object(arg0)
      logger.write_string(", node_id=")
      logger.write_object(arg1)
      logger.write_string(", loc=")
      logger.write_object(arg2)
      logger.write_string(")")
    }
    StringLit(value=arg0, length=arg1, node_id=arg2, loc=arg3) => {
      logger.write_string("StringLit(")
      logger.write_string("value=")
      logger.write_object(arg0)
      logger.write_string(", length=")
      logger.write_object(arg1)
      logger.write_string(", node_id=")
      logger.write_object(arg2)
      logger.write_string(", loc=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    Ident(name=arg0, id=arg1, node_id=arg2, loc=arg3) => {
      logger.write_string("Ident(")
      logger.write_string("name=")
      logger.write_object(arg0)
      logger.write_string(", id=")
      logger.write_object(arg1)
      logger.write_string(", node_id=")
      logger.write_object(arg2)
      logger.write_string(", loc=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    LabelAddr(name=arg0, id=arg1, node_id=arg2, loc=arg3) => {
      logger.write_string("LabelAddr(")
      logger.write_string("name=")
      logger.write_object(arg0)
      logger.write_string(", id=")
      logger.write_object(arg1)
      logger.write_string(", node_id=")
      logger.write_object(arg2)
      logger.write_string(", loc=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    BuiltinTypesCompatibleP(a=arg0, b=arg1, node_id=arg2, loc=arg3) => {
      logger.write_string("BuiltinTypesCompatibleP(")
      logger.write_string("a=")
      logger.write_object(arg0)
      logger.write_string(", b=")
      logger.write_object(arg1)
      logger.write_string(", node_id=")
      logger.write_object(arg2)
      logger.write_string(", loc=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    BuiltinOffsetof(ty=arg0, path=arg1, node_id=arg2, loc=arg3) => {
      logger.write_string("BuiltinOffsetof(")
      logger.write_string("ty=")
      logger.write_object(arg0)
      logger.write_string(", path=")
      logger.write_string("[")
      for i182, value182 in arg1 {
        if i182 > 0 {
          logger.write_string(", ")
        }
        logger.write_object(value182)
      }
      logger.write_string("]")
      logger.write_string(", node_id=")
      logger.write_object(arg2)
      logger.write_string(", loc=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    BuiltinVaArg(list=arg0, ty=arg1, node_id=arg2, loc=arg3) => {
      logger.write_string("BuiltinVaArg(")
      logger.write_string("list=")
      logger.write_object(arg0)
      logger.write_string(", ty=")
      logger.write_object(arg1)
      logger.write_string(", node_id=")
      logger.write_object(arg2)
      logger.write_string(", loc=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    Unary(op=arg0, expr=arg1, node_id=arg2, loc=arg3) => {
      logger.write_string("Unary(")
      logger.write_string("op=")
      logger.write_object(arg0)
      logger.write_string(", expr=")
      logger.write_object(arg1)
      logger.write_string(", node_id=")
      logger.write_object(arg2)
      logger.write_string(", loc=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    Cast(ty=arg0, expr=arg1, node_id=arg2, loc=arg3) => {
      logger.write_string("Cast(")
      logger.write_string("ty=")
      logger.write_object(arg0)
      logger.write_string(", expr=")
      logger.write_object(arg1)
      logger.write_string(", node_id=")
      logger.write_object(arg2)
      logger.write_string(", loc=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    CompoundLiteral(ty=arg0, init=arg1, node_id=arg2, loc=arg3) => {
      logger.write_string("CompoundLiteral(")
      logger.write_string("ty=")
      logger.write_object(arg0)
      logger.write_string(", init=")
      logger.write_object(arg1)
      logger.write_string(", node_id=")
      logger.write_object(arg2)
      logger.write_string(", loc=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    StmtExpr(stmts=arg0, node_id=arg1, loc=arg2) => {
      logger.write_string("StmtExpr(")
      logger.write_string("stmts=")
      logger.write_string("[")
      for i202, value202 in arg0 {
        if i202 > 0 {
          logger.write_string(", ")
        }
        logger.write_object(value202)
      }
      logger.write_string("]")
      logger.write_string(", node_id=")
      logger.write_object(arg1)
      logger.write_string(", loc=")
      logger.write_object(arg2)
      logger.write_string(")")
    }
    SizeofExpr(expr=arg0, node_id=arg1, loc=arg2) => {
      logger.write_string("SizeofExpr(")
      logger.write_string("expr=")
      logger.write_object(arg0)
      logger.write_string(", node_id=")
      logger.write_object(arg1)
      logger.write_string(", loc=")
      logger.write_object(arg2)
      logger.write_string(")")
    }
    SizeofType(ty=arg0, node_id=arg1, loc=arg2) => {
      logger.write_string("SizeofType(")
      logger.write_string("ty=")
      logger.write_object(arg0)
      logger.write_string(", node_id=")
      logger.write_object(arg1)
      logger.write_string(", loc=")
      logger.write_object(arg2)
      logger.write_string(")")
    }
    AlignofExpr(expr=arg0, node_id=arg1, loc=arg2) => {
      logger.write_string("AlignofExpr(")
      logger.write_string("expr=")
      logger.write_object(arg0)
      logger.write_string(", node_id=")
      logger.write_object(arg1)
      logger.write_string(", loc=")
      logger.write_object(arg2)
      logger.write_string(")")
    }
    AlignofType(ty=arg0, node_id=arg1, loc=arg2) => {
      logger.write_string("AlignofType(")
      logger.write_string("ty=")
      logger.write_object(arg0)
      logger.write_string(", node_id=")
      logger.write_object(arg1)
      logger.write_string(", loc=")
      logger.write_object(arg2)
      logger.write_string(")")
    }
    Binary(op=arg0, left=arg1, right=arg2, node_id=arg3, loc=arg4) => {
      logger.write_string("Binary(")
      logger.write_string("op=")
      logger.write_object(arg0)
      logger.write_string(", left=")
      logger.write_object(arg1)
      logger.write_string(", right=")
      logger.write_object(arg2)
      logger.write_string(", node_id=")
      logger.write_object(arg3)
      logger.write_string(", loc=")
      logger.write_object(arg4)
      logger.write_string(")")
    }
    Conditional(
      cond=arg0,
      then_expr=arg1,
      else_expr=arg2,
      node_id=arg3,
      loc=arg4
    ) => {
      logger.write_string("Conditional(")
      logger.write_string("cond=")
      logger.write_object(arg0)
      logger.write_string(", then_expr=")
      logger.write_object(arg1)
      logger.write_string(", else_expr=")
      logger.write_object(arg2)
      logger.write_string(", node_id=")
      logger.write_object(arg3)
      logger.write_string(", loc=")
      logger.write_object(arg4)
      logger.write_string(")")
    }
    Call(callee=arg0, args=arg1, node_id=arg2, loc=arg3) => {
      logger.write_string("Call(")
      logger.write_string("callee=")
      logger.write_object(arg0)
      logger.write_string(", args=")
      logger.write_string("[")
      for i229, value229 in arg1 {
        if i229 > 0 {
          logger.write_string(", ")
        }
        logger.write_object(value229)
      }
      logger.write_string("]")
      logger.write_string(", node_id=")
      logger.write_object(arg2)
      logger.write_string(", loc=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    Index(base=arg0, index=arg1, node_id=arg2, loc=arg3) => {
      logger.write_string("Index(")
      logger.write_string("base=")
      logger.write_object(arg0)
      logger.write_string(", index=")
      logger.write_object(arg1)
      logger.write_string(", node_id=")
      logger.write_object(arg2)
      logger.write_string(", loc=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    Member(base=arg0, name=arg1, id=arg2, is_arrow=arg3, node_id=arg4, loc=arg5) => {
      logger.write_string("Member(")
      logger.write_string("base=")
      logger.write_object(arg0)
      logger.write_string(", name=")
      logger.write_object(arg1)
      logger.write_string(", id=")
      logger.write_object(arg2)
      logger.write_string(", is_arrow=")
      logger.write_object(arg3)
      logger.write_string(", node_id=")
      logger.write_object(arg4)
      logger.write_string(", loc=")
      logger.write_object(arg5)
      logger.write_string(")")
    }
  }
}

///|
pub impl Show for InitDesignator with fn output(self, logger) {
  match self {
    Index(expr=arg0, loc=arg1) => {
      logger.write_string("Index(")
      logger.write_string("expr=")
      logger.write_object(arg0)
      logger.write_string(", loc=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
    IndexRange(start=arg0, end=arg1, loc=arg2) => {
      logger.write_string("IndexRange(")
      logger.write_string("start=")
      logger.write_object(arg0)
      logger.write_string(", end=")
      logger.write_object(arg1)
      logger.write_string(", loc=")
      logger.write_object(arg2)
      logger.write_string(")")
    }
    Field(name=arg0, id=arg1, loc=arg2) => {
      logger.write_string("Field(")
      logger.write_string("name=")
      logger.write_object(arg0)
      logger.write_string(", id=")
      logger.write_object(arg1)
      logger.write_string(", loc=")
      logger.write_object(arg2)
      logger.write_string(")")
    }
  }
}

///|
pub impl Show for InitItem with fn output(self, logger) {
  logger.write_string("{")
  logger.write_string("designators: ")
  logger.write_string("[")
  for i251, value251 in self.designators {
    if i251 > 0 {
      logger.write_string(", ")
    }
    logger.write_object(value251)
  }
  logger.write_string("]")
  logger.write_string(", value: ")
  logger.write_object(self.value)
  logger.write_string(", loc: ")
  logger.write_object(self.loc)
  logger.write_string("}")
}

///|
pub impl Show for Initializer with fn output(self, logger) {
  match self {
    Expr(expr=arg0, loc=arg1) => {
      logger.write_string("Expr(")
      logger.write_string("expr=")
      logger.write_object(arg0)
      logger.write_string(", loc=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
    List(items=arg0, loc=arg1) => {
      logger.write_string("List(")
      logger.write_string("items=")
      logger.write_string("[")
      for i257, value257 in arg0 {
        if i257 > 0 {
          logger.write_string(", ")
        }
        logger.write_object(value257)
      }
      logger.write_string("]")
      logger.write_string(", loc=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
  }
}

///|
pub impl Show for AsmOperand with fn output(self, logger) {
  logger.write_string("{")
  logger.write_string("name: ")
  match self.name {
    None => logger.write_string("None")
    Some(value260) => {
      logger.write_string("Some(")
      logger.write_object(value260)
      logger.write_string(")")
    }
  }
  logger.write_string(", constraint: ")
  logger.write_object(self.constraint)
  logger.write_string(", expr: ")
  logger.write_object(self.expr)
  logger.write_string(", loc: ")
  logger.write_object(self.loc)
  logger.write_string("}")
}

///|
pub impl Show for AsmStmt with fn output(self, logger) {
  logger.write_string("{")
  logger.write_string("template: ")
  logger.write_object(self.template)
  logger.write_string(", outputs: ")
  logger.write_string("[")
  for i266, value266 in self.outputs {
    if i266 > 0 {
      logger.write_string(", ")
    }
    logger.write_object(value266)
  }
  logger.write_string("]")
  logger.write_string(", inputs: ")
  logger.write_string("[")
  for i268, value268 in self.inputs {
    if i268 > 0 {
      logger.write_string(", ")
    }
    logger.write_object(value268)
  }
  logger.write_string("]")
  logger.write_string(", clobbers: ")
  logger.write_string("[")
  for i270, value270 in self.clobbers {
    if i270 > 0 {
      logger.write_string(", ")
    }
    logger.write_object(value270)
  }
  logger.write_string("]")
  logger.write_string(", labels: ")
  logger.write_string("[")
  for i272, value272 in self.labels {
    if i272 > 0 {
      logger.write_string(", ")
    }
    logger.write_object(value272)
  }
  logger.write_string("]")
  logger.write_string(", is_volatile: ")
  logger.write_object(self.is_volatile)
  logger.write_string(", is_goto: ")
  logger.write_object(self.is_goto)
  logger.write_string(", loc: ")
  logger.write_object(self.loc)
  logger.write_string("}")
}

///|
pub impl Show for Stmt with fn output(self, logger) {
  match self {
    Compound(stmts=arg0, loc=arg1) => {
      logger.write_string("Compound(")
      logger.write_string("stmts=")
      logger.write_string("[")
      for i277, value277 in arg0 {
        if i277 > 0 {
          logger.write_string(", ")
        }
        logger.write_object(value277)
      }
      logger.write_string("]")
      logger.write_string(", loc=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
    If(cond=arg0, then_branch=arg1, else_branch=arg2, loc=arg3) => {
      logger.write_string("If(")
      logger.write_string("cond=")
      logger.write_object(arg0)
      logger.write_string(", then_branch=")
      logger.write_object(arg1)
      logger.write_string(", else_branch=")
      match arg2 {
        None => logger.write_string("None")
        Some(value282) => {
          logger.write_string("Some(")
          logger.write_object(value282)
          logger.write_string(")")
        }
      }
      logger.write_string(", loc=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    While(cond=arg0, body=arg1, loc=arg2) => {
      logger.write_string("While(")
      logger.write_string("cond=")
      logger.write_object(arg0)
      logger.write_string(", body=")
      logger.write_object(arg1)
      logger.write_string(", loc=")
      logger.write_object(arg2)
      logger.write_string(")")
    }
    DoWhile(cond=arg0, body=arg1, loc=arg2) => {
      logger.write_string("DoWhile(")
      logger.write_string("cond=")
      logger.write_object(arg0)
      logger.write_string(", body=")
      logger.write_object(arg1)
      logger.write_string(", loc=")
      logger.write_object(arg2)
      logger.write_string(")")
    }
    For(init=arg0, cond=arg1, step=arg2, body=arg3, loc=arg4) => {
      logger.write_string("For(")
      logger.write_string("init=")
      match arg0 {
        None => logger.write_string("None")
        Some(value291) => {
          logger.write_string("Some(")
          logger.write_object(value291)
          logger.write_string(")")
        }
      }
      logger.write_string(", cond=")
      match arg1 {
        None => logger.write_string("None")
        Some(value293) => {
          logger.write_string("Some(")
          logger.write_object(value293)
          logger.write_string(")")
        }
      }
      logger.write_string(", step=")
      match arg2 {
        None => logger.write_string("None")
        Some(value295) => {
          logger.write_string("Some(")
          logger.write_object(value295)
          logger.write_string(")")
        }
      }
      logger.write_string(", body=")
      logger.write_object(arg3)
      logger.write_string(", loc=")
      logger.write_object(arg4)
      logger.write_string(")")
    }
    Switch(cond=arg0, body=arg1, loc=arg2) => {
      logger.write_string("Switch(")
      logger.write_string("cond=")
      logger.write_object(arg0)
      logger.write_string(", body=")
      logger.write_object(arg1)
      logger.write_string(", loc=")
      logger.write_object(arg2)
      logger.write_string(")")
    }
    Case(expr=arg0, end_expr=arg1, body=arg2, loc=arg3) => {
      logger.write_string("Case(")
      logger.write_string("expr=")
      logger.write_object(arg0)
      logger.write_string(", end_expr=")
      match arg1 {
        None => logger.write_string("None")
        Some(value303) => {
          logger.write_string("Some(")
          logger.write_object(value303)
          logger.write_string(")")
        }
      }
      logger.write_string(", body=")
      logger.write_object(arg2)
      logger.write_string(", loc=")
      logger.write_object(arg3)
      logger.write_string(")")
    }
    Default(body=arg0, loc=arg1) => {
      logger.write_string("Default(")
      logger.write_string("body=")
      logger.write_object(arg0)
      logger.write_string(", loc=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
    Label(name=arg0, body=arg1, loc=arg2) => {
      logger.write_string("Label(")
      logger.write_string("name=")
      logger.write_object(arg0)
      logger.write_string(", body=")
      logger.write_object(arg1)
      logger.write_string(", loc=")
      logger.write_object(arg2)
      logger.write_string(")")
    }
    Goto(name=arg0, loc=arg1) => {
      logger.write_string("Goto(")
      logger.write_string("name=")
      logger.write_object(arg0)
      logger.write_string(", loc=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
    GotoExpr(expr=arg0, loc=arg1) => {
      logger.write_string("GotoExpr(")
      logger.write_string("expr=")
      logger.write_object(arg0)
      logger.write_string(", loc=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
    Break(loc=arg0) => {
      logger.write_string("Break(")
      logger.write_string("loc=")
      logger.write_object(arg0)
      logger.write_string(")")
    }
    Continue(loc=arg0) => {
      logger.write_string("Continue(")
      logger.write_string("loc=")
      logger.write_object(arg0)
      logger.write_string(")")
    }
    Return(value=arg0, loc=arg1) => {
      logger.write_string("Return(")
      logger.write_string("value=")
      match arg0 {
        None => logger.write_string("None")
        Some(value318) => {
          logger.write_string("Some(")
          logger.write_object(value318)
          logger.write_string(")")
        }
      }
      logger.write_string(", loc=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
    Asm(arg0) => {
      logger.write_string("Asm(")
      logger.write_object(arg0)
      logger.write_string(")")
    }
    ExprStmt(expr=arg0, loc=arg1) => {
      logger.write_string("ExprStmt(")
      logger.write_string("expr=")
      logger.write_object(arg0)
      logger.write_string(", loc=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
    DeclStmt(decls=arg0, loc=arg1) => {
      logger.write_string("DeclStmt(")
      logger.write_string("decls=")
      logger.write_string("[")
      for i324, value324 in arg0 {
        if i324 > 0 {
          logger.write_string(", ")
        }
        logger.write_object(value324)
      }
      logger.write_string("]")
      logger.write_string(", loc=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
    TagDef(ty=arg0, loc=arg1) => {
      logger.write_string("TagDef(")
      logger.write_string("ty=")
      logger.write_object(arg0)
      logger.write_string(", loc=")
      logger.write_object(arg1)
      logger.write_string(")")
    }
    StaticAssert(arg0) => {
      logger.write_string("StaticAssert(")
      logger.write_object(arg0)
      logger.write_string(")")
    }
    Empty(loc=arg0) => {
      logger.write_string("Empty(")
      logger.write_string("loc=")
      logger.write_object(arg0)
      logger.write_string(")")
    }
  }
}
