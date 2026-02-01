///|
type SemContext = @sem.SemContext

///|
type FieldAccessInfo = @sem.FieldAccessInfo

///|
type RecordDef = @sem.RecordDef

///|
type BuiltinCallKind = @sem.BuiltinCallKind

///|
let add_sem_error = @sem.add_sem_error

///|
let adjust_param_type_for_local = @sem.adjust_param_type_for_local

///|
let align_to = @sem.align_to

///|
let apply_inferred_array_size = @sem.apply_inferred_array_size

///|
let atomic_builtin_return_type = @sem.atomic_builtin_return_type

///|
let atomic_builtin_template_from_ident = @sem.atomic_builtin_template_from_ident

///|
let attr_align_value = @sem.attr_align_value

///|
let attrs_layout_empty = @sem.attrs_layout_empty

///|
let builtin_call_kind = @sem.builtin_call_kind

///|
let check_translation_unit = @sem.check_translation_unit

///|
let common_int_type = @sem.common_int_type

///|
let compound_literal_key = @sem.compound_literal_key

///|
let compound_literal_type = @sem.compound_literal_type

///|
let const_int_from_expr = @sem.const_int_from_expr

///|
let const_int64_from_expr = @sem.const_int64_from_expr

///|
let current_local_scope_id = @sem.current_local_scope_id

///|
let decay_type = @sem.decay_type

///|
let default_int_type = @sem.default_int_type

///|
fn ensure_struct_fields(
  ctx : SemContext,
  tag : String,
  tag_id : Int,
  fields : Array[@ast.RecordItem]?,
  is_union~ : Bool,
  loc : @source.SrcLoc,
) -> RecordDef? {
  @sem.ensure_struct_fields(
    ctx,
    tag,
    tag_id,
    fields,
    is_union=is_union,
    loc,
  )
}

///|
let enum_const_value = @sem.enum_const_value

///|
let eval_builtin_offsetof = @sem.eval_builtin_offsetof

///|
let find_field_index_cached = @sem.find_field_index_cached

///|
fn[T] get_opt_by_id(arr : Array[T?], id : Int) -> T? {
  @sem.get_opt_by_id(arr, id)
}

///|
let float_size = @sem.float_size

///|
let get_function_by_id = @sem.get_function_by_id

///|
let get_global_by_id = @sem.get_global_by_id

///|
let has_function_by_id = @sem.has_function_by_id

///|
let int_size = @sem.int_size

///|
let is_char_type = @sem.is_char_type

///|
let is_int_like = @sem.is_int_like

///|
let next_init_field = @sem.next_init_field

///|
let pop_scope = @sem.pop_scope

///|
let push_scope = @sem.push_scope

///|
fn[T] set_opt_by_id(arr : Array[T?], id : Int, value : T) -> Unit {
  @sem.set_opt_by_id(arr, id, value)
}

///|
let record_local_binding = @sem.record_local_binding

///|
fn resolve_struct_fields(
  ctx : SemContext,
  tag : String,
  tag_id : Int,
  fields : Array[@ast.RecordItem]?,
  is_union~ : Bool,
) -> Array[@ast.Field]? {
  @sem.resolve_struct_fields(ctx, tag, tag_id, fields, is_union=is_union)
}

///|
let resolve_type = @sem.resolve_type

///|
let strip_top_qualifiers = @sem.strip_top_qualifiers

///|
let strip_top_qualifiers_keep_attrs = @sem.strip_top_qualifiers_keep_attrs

///|
fn[T] has_opt_by_id(arr : Array[T?], id : Int) -> Bool {
  @sem.has_opt_by_id(arr, id)
}

///|
let struct_size_align = @sem.struct_size_align

///|
let try_eval_int_const = @sem.try_eval_int_const

///|
let type_for_sizeof = @sem.type_for_sizeof

///|
let type_of_expr = @sem.type_of_expr

///|
let type_of_lvalue = @sem.type_of_lvalue

///|
let type_size_align = @sem.type_size_align

///|
let union_size_align = @sem.union_size_align
