///|
pub type AlignSpec = @ast_core.AlignSpec

///|
pub type AsmOperand = @ast_core.AsmOperand

///|
pub type AsmStmt = @ast_core.AsmStmt

///|
pub type Attributes = @ast_core.Attributes

///|
pub type BinaryOp = @ast_core.BinaryOp

///|
pub type CFloatKind = @ast_core.CFloatKind

///|
pub type CIntKind = @ast_core.CIntKind

///|
pub type CType = @ast_core.CType

///|
pub type CallConv = @ast_core.CallConv

///|
pub type Decl = @ast_core.Decl

///|
pub type EnumItem = @ast_core.EnumItem

///|
pub type Expr = @ast_core.Expr

///|
pub type Field = @ast_core.Field

///|
pub type FuncDecl = @ast_core.FuncDecl

///|
pub type FuncDef = @ast_core.FuncDef

///|
pub type InitDesignator = @ast_core.InitDesignator

///|
pub type InitItem = @ast_core.InitItem

///|
pub type Initializer = @ast_core.Initializer

///|
pub type Param = @ast_core.Param

///|
pub type RecordItem = @ast_core.RecordItem

///|
pub type StaticAssert = @ast_core.StaticAssert

///|
pub type Stmt = @ast_core.Stmt

///|
pub type StorageClass = @ast_core.StorageClass

///|
pub type TranslationUnit = @ast_core.TranslationUnit

///|
pub type TypeQual = @ast_core.TypeQual

///|
pub type UnaryOp = @ast_core.UnaryOp

///|
pub type VarDecl = @ast_core.VarDecl

///|
pub type Visibility = @ast_core.Visibility

///|
pub fn normalize_call_conv(call_conv : CallConv?) -> CallConv {
  @ast_core.normalize_call_conv(call_conv)
}

///|
pub fn merge_call_conv(existing : CallConv, incoming : CallConv) -> CallConv {
  @ast_core.merge_call_conv(existing, incoming)
}

///|
pub fn empty_attrs() -> Attributes {
  @ast_core.empty_attrs()
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
  @ast_core.attrs_with(
    aligned~,
    packed~,
    weak~,
    visibility~,
    section~,
    alias_name~,
    asm_label~,
    cleanup~,
    noreturn~,
    constructor_attr~,
    destructor~,
    always_inline~,
    call_conv~,
    dll_import~,
    dll_export~,
    nodecorate~,
    nodebug~,
  )
}

///|
pub fn merge_attrs(base : Attributes, incoming : Attributes) -> Attributes {
  @ast_core.merge_attrs(base, incoming)
}

///|
pub fn attrs_is_empty(attrs : Attributes) -> Bool {
  @ast_core.attrs_is_empty(attrs)
}

///|
pub fn type_attrs_from(attrs : Attributes) -> Attributes {
  @ast_core.type_attrs_from(attrs)
}

///|
pub fn has_type_attrs(attrs : Attributes) -> Bool {
  @ast_core.has_type_attrs(attrs)
}

///|
pub fn apply_type_attrs(ty : CType, attrs : Attributes) -> CType {
  @ast_core.apply_type_attrs(ty, attrs)
}

///|
pub fn apply_call_conv_to_type(ty : CType, call_conv : CallConv) -> CType {
  @ast_core.apply_call_conv_to_type(ty, call_conv)
}

///|
pub fn default_int_type() -> CType {
  @ast_core.default_int_type()
}

///|
pub fn expr_is_lvalue_simple(expr : Expr) -> Bool {
  @ast_core.expr_is_lvalue_simple(expr)
}

///|
pub fn expr_may_call(expr : Expr) -> Bool {
  @ast_core.expr_may_call(expr)
}

///|
pub fn parse_int64_literal(text : String) -> Int64? {
  @ast_core.parse_int64_literal(text)
}

///|
pub fn const_i64_from_expr(expr : Expr) -> Int64? {
  @ast_core.const_i64_from_expr(expr)
}

///|
pub fn expr_loc(expr : Expr) -> @source.SrcLoc {
  @ast_core.expr_loc(expr)
}

///|
pub fn expr_node_id(expr : Expr) -> Int {
  @ast_core.expr_node_id(expr)
}

///|
pub fn empty_qual() -> TypeQual {
  @ast_core.empty_qual()
}

///|
pub fn merge_qual(a : TypeQual, b : TypeQual) -> TypeQual {
  @ast_core.merge_qual(a, b)
}

///|
pub fn with_const(qual : TypeQual) -> TypeQual {
  @ast_core.with_const(qual)
}

///|
pub fn with_volatile(qual : TypeQual) -> TypeQual {
  @ast_core.with_volatile(qual)
}

///|
pub fn with_restrict(qual : TypeQual) -> TypeQual {
  @ast_core.with_restrict(qual)
}

///|
pub fn with_atomic(qual : TypeQual) -> TypeQual {
  @ast_core.with_atomic(qual)
}

///|
pub fn apply_qualifiers(ty : CType, qual : TypeQual) -> CType {
  @ast_core.apply_qualifiers(ty, qual)
}
