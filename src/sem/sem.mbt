///|
pub type FuncSig = @sem_core.FuncSig

///|
pub type RecordDef = @sem_core.RecordDef

///|
pub type FieldAccessInfo = @sem_core.FieldAccessInfo

///|
pub type BuiltinCallKind = @sem_core.BuiltinCallKind

///|
pub type SemContext = @sem_core.SemContext

///|
pub fn add_sem_error(
  ctx : SemContext,
  loc : @source.SrcLoc,
  msg : String,
) -> Unit {
  @sem_core.add_sem_error(ctx, loc, msg)
}

///|
pub fn adjust_param_type_for_local(ty : @ast.CType) -> @ast.CType {
  @sem_core.adjust_param_type_for_local(ty)
}

///|
pub fn align_to(value : Int, align : Int) -> Int {
  @sem_core.align_to(value, align)
}

///|
pub fn apply_inferred_array_size(ty : @ast.CType, size : Int) -> @ast.CType {
  @sem_core.apply_inferred_array_size(ty, size)
}

///|
pub fn atomic_builtin_return_type(
  ctx : SemContext,
  name : String,
  id : Int,
  args : Array[@ast.Expr],
  loc : @source.SrcLoc,
) -> @ast.CType? {
  @sem_core.atomic_builtin_return_type(ctx, name, id, args, loc)
}

///|
pub fn atomic_builtin_template_from_ident(
  ctx : SemContext,
  name : String,
  id : Int,
) -> String? {
  @sem_core.atomic_builtin_template_from_ident(ctx, name, id)
}

///|
pub fn attr_align_value(
  ctx : SemContext,
  attrs : @ast.Attributes,
  loc : @source.SrcLoc,
) -> Int? {
  @sem_core.attr_align_value(ctx, attrs, loc)
}

///|
pub fn attrs_layout_empty(attrs : @ast.Attributes) -> Bool {
  @sem_core.attrs_layout_empty(attrs)
}

///|
pub fn builtin_call_kind(
  ctx : SemContext,
  name : String,
  id : Int,
) -> BuiltinCallKind? {
  @sem_core.builtin_call_kind(ctx, name, id)
}

///|
pub fn check_translation_unit(
  unit : @ast.TranslationUnit,
  bag : @diag.DiagBag,
) -> SemContext {
  @sem_core.check_translation_unit(unit, bag)
}

///|
pub fn common_int_type(
  ctx : SemContext,
  lhs : @ast.CType,
  rhs : @ast.CType,
) -> @ast.CType {
  @sem_core.common_int_type(ctx, lhs, rhs)
}

///|
pub fn compound_literal_key(id : Int) -> Int {
  @sem_core.compound_literal_key(id)
}

///|
pub fn compound_literal_type(
  ctx : SemContext,
  ty : @ast.CType,
  init : @ast.Initializer,
  loc : @source.SrcLoc,
  node_id : Int,
) -> @ast.CType {
  @sem_core.compound_literal_type(ctx, ty, init, loc, node_id)
}

///|
pub fn const_int64_from_expr(
  ctx : SemContext,
  expr : @ast.Expr,
  loc : @source.SrcLoc,
) -> Int64? {
  @sem_core.const_int64_from_expr(ctx, expr, loc)
}

///|
pub fn const_int_from_expr(
  ctx : SemContext,
  expr : @ast.Expr,
  loc : @source.SrcLoc,
) -> Int? {
  @sem_core.const_int_from_expr(ctx, expr, loc)
}

///|
pub fn current_local_scope_id(ctx : SemContext) -> Int {
  @sem_core.current_local_scope_id(ctx)
}

///|
pub fn decay_type(ty : @ast.CType) -> @ast.CType {
  @sem_core.decay_type(ty)
}

///|
pub fn default_int_type() -> @ast.CType {
  @sem_core.default_int_type()
}

///|
pub fn ensure_struct_fields(
  ctx : SemContext,
  name : String,
  id : Int,
  items : Array[@ast.RecordItem]?,
  is_union~ : Bool,
  loc : @source.SrcLoc,
) -> RecordDef? {
  @sem_core.ensure_struct_fields(ctx, name, id, items, is_union~, loc)
}

///|
pub fn enum_const_value(ctx : SemContext, name : String, id : Int) -> Int? {
  @sem_core.enum_const_value(ctx, name, id)
}

///|
pub fn eval_builtin_offsetof(
  ctx : SemContext,
  ty : @ast.CType,
  path : Array[String],
  loc : @source.SrcLoc,
) -> Int? {
  @sem_core.eval_builtin_offsetof(ctx, ty, path, loc)
}

///|
pub fn find_field_index_cached(
  ctx : SemContext,
  ty : @ast.CType,
  name : String,
  id : Int,
  loc : @source.SrcLoc,
) -> Int? {
  @sem_core.find_field_index_cached(ctx, ty, name, id, loc)
}

///|
pub fn float_size(kind : @ast.CFloatKind) -> Int {
  @sem_core.float_size(kind)
}

///|
pub fn get_function_by_id(ctx : SemContext, id : Int) -> FuncSig? {
  @sem_core.get_function_by_id(ctx, id)
}

///|
pub fn get_global_by_id(ctx : SemContext, id : Int) -> @ast.CType? {
  @sem_core.get_global_by_id(ctx, id)
}

///|
pub fn[T] get_opt_by_id(arr : Array[T?], id : Int) -> T? {
  @sem_core.get_opt_by_id(arr, id)
}

///|
pub fn has_function_by_id(ctx : SemContext, id : Int) -> Bool {
  @sem_core.has_function_by_id(ctx, id)
}

///|
pub fn[T] has_opt_by_id(arr : Array[T?], id : Int) -> Bool {
  @sem_core.has_opt_by_id(arr, id)
}

///|
pub fn int_size(kind : @ast.CIntKind) -> Int {
  @sem_core.int_size(kind)
}

///|
pub fn is_char_type(ty : @ast.CType) -> Bool {
  @sem_core.is_char_type(ty)
}

///|
pub fn is_int_like(ty : @ast.CType) -> Bool {
  @sem_core.is_int_like(ty)
}

///|
pub fn next_init_field(
  fields : Array[@ast.Field],
  index : Int,
) -> (@ast.Field, Int)? {
  @sem_core.next_init_field(fields, index)
}

///|
pub fn pop_scope(ctx : SemContext) -> Unit {
  @sem_core.pop_scope(ctx)
}

///|
pub fn push_scope(ctx : SemContext) -> Unit {
  @sem_core.push_scope(ctx)
}

///|
pub fn record_local_binding(
  ctx : SemContext,
  id : Int,
  ty : @ast.CType,
) -> Unit {
  @sem_core.record_local_binding(ctx, id, ty)
}

///|
pub fn resolve_struct_fields(
  ctx : SemContext,
  name : String,
  id : Int,
  items : Array[@ast.RecordItem]?,
  is_union~ : Bool,
) -> Array[@ast.Field]? {
  @sem_core.resolve_struct_fields(ctx, name, id, items, is_union~)
}

///|
pub fn resolve_type(
  ctx : SemContext,
  ty : @ast.CType,
  loc : @source.SrcLoc,
) -> @ast.CType {
  @sem_core.resolve_type(ctx, ty, loc)
}

///|
pub fn[T] set_opt_by_id(arr : Array[T?], id : Int, value : T) -> Unit {
  @sem_core.set_opt_by_id(arr, id, value)
}

///|
pub fn strip_qual_attrs(ty : @ast.CType) -> @ast.CType {
  @sem_core.strip_qual_attrs(ty)
}

///|
pub fn strip_qualifiers(ty : @ast.CType) -> @ast.CType {
  @sem_core.strip_qualifiers(ty)
}

///|
pub fn strip_top_qualifiers(ty : @ast.CType) -> @ast.CType {
  @sem_core.strip_top_qualifiers(ty)
}

///|
pub fn strip_top_qualifiers_keep_attrs(ty : @ast.CType) -> @ast.CType {
  @sem_core.strip_top_qualifiers_keep_attrs(ty)
}

///|
pub fn struct_size_align(
  ctx : SemContext,
  fields : Array[@ast.Field],
  attrs : @ast.Attributes,
  loc : @source.SrcLoc,
) -> (Int, Int) {
  @sem_core.struct_size_align(ctx, fields, attrs, loc)
}

///|
pub fn try_eval_int_const(ctx : SemContext, expr : @ast.Expr) -> Int? {
  @sem_core.try_eval_int_const(ctx, expr)
}

///|
pub fn type_contains_vla(ty : @ast.CType) -> Bool {
  @sem_core.type_contains_vla(ty)
}

///|
pub fn type_for_sizeof(ctx : SemContext, expr : @ast.Expr) -> @ast.CType {
  @sem_core.type_for_sizeof(ctx, expr)
}

///|
pub fn type_of_expr(ctx : SemContext, expr : @ast.Expr) -> @ast.CType {
  @sem_core.type_of_expr(ctx, expr)
}

///|
pub fn type_of_lvalue(ctx : SemContext, expr : @ast.Expr) -> @ast.CType? {
  @sem_core.type_of_lvalue(ctx, expr)
}

///|
pub fn type_size_align(
  ctx : SemContext,
  ty : @ast.CType,
  loc : @source.SrcLoc,
) -> (Int, Int)? {
  @sem_core.type_size_align(ctx, ty, loc)
}

///|
pub fn union_size_align(
  ctx : SemContext,
  fields : Array[@ast.Field],
  attrs : @ast.Attributes,
  loc : @source.SrcLoc,
) -> (Int, Int) {
  @sem_core.union_size_align(ctx, fields, attrs, loc)
}
