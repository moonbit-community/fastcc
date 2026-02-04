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
pub struct FuncSig {
  return_type : @ast.CType
  params : Array[@ast.CType]
  varargs : Bool
  is_old_style : Bool
  call_conv : @ast.CallConv
} derive(Show, Eq, ToJson)

///|
pub struct RecordDef {
  fields : Array[@ast.Field]
  attrs : @ast.Attributes
}

///|
pub(all) struct FieldAccessInfo {
  offset : Int
  ty : @ast.CType
  bit_offset : Int?
  bit_width : Int?
  bit_unit_size : Int?
}

///|
pub(all) enum BuiltinCallKind {
  ChooseExpr
  Expect
  ConstantP
  Unreachable
  SyncSynchronize
  VaStart
  VaCopy
  VaEnd
  FrameAddress
  ReturnAddress
} derive(Show, Eq, ToJson)

///|
pub struct SemContext {
  diags : @diag.DiagBag
  globals : @util.FastMap[String, @ast.CType]
  globals_by_id : Array[@ast.CType?]
  functions : @util.FastMap[String, FuncSig]
  functions_by_id : Array[FuncSig?]
  builtin_call_ids : Array[BuiltinCallKind?]
  builtin_sig_ids : Array[FuncSig?]
  atomic_template_ids : Array[String?]
  function_defs : @util.FastMap[String, Bool]
  local_scope_ids_by_id : Array[Int]
  local_scope_stack : Array[Int]
  mut next_local_scope_id : Int
  local_values_by_id : Array[@ast.CType?]
  local_overrides : Array[Array[LocalOverride]]
  type_aliases : @util.FastMap[String, @ast.CType]
  struct_defs : @util.FastMap[String, RecordDef]
  struct_defs_by_id : Array[RecordDef?]
  union_defs : @util.FastMap[String, RecordDef]
  union_defs_by_id : Array[RecordDef?]
  struct_member_cache : @util.FastMap[String, @util.FastMap[String, @ast.CType]]
  struct_member_cache_by_id : Array[@util.FastMap[Int, @ast.CType]?]
  union_member_cache : @util.FastMap[String, @util.FastMap[String, @ast.CType]]
  union_member_cache_by_id : Array[@util.FastMap[Int, @ast.CType]?]
  struct_field_access_cache : @util.FastMap[
    String,
    @util.FastMap[String, FieldAccessInfo],
  ]
  struct_field_access_cache_by_id : Array[@util.FastMap[Int, FieldAccessInfo]?]
  union_field_access_cache : @util.FastMap[
    String,
    @util.FastMap[String, FieldAccessInfo],
  ]
  union_field_access_cache_by_id : Array[@util.FastMap[Int, FieldAccessInfo]?]
  struct_field_index_cache : @util.FastMap[String, @util.FastMap[String, Int]]
  struct_field_index_cache_by_id : Array[@util.FastMap[Int, Int]?]
  union_field_index_cache : @util.FastMap[String, @util.FastMap[String, Int]]
  union_field_index_cache_by_id : Array[@util.FastMap[Int, Int]?]
  struct_size_cache : @util.FastMap[String, (Int, Int)]
  struct_size_cache_by_id : Array[(Int, Int)?]
  union_size_cache : @util.FastMap[String, (Int, Int)]
  union_size_cache_by_id : Array[(Int, Int)?]
  func_compound_literals : @util.FastMap[String, Array[Int]]
  func_compound_literals_by_id : Array[Array[Int]?]
  compound_literal_sizes : @util.FastMap[Int, (Int, Int)]
  func_has_compound_literal : @util.FastMap[String, Bool]
  func_has_stmt_expr : @util.FastMap[String, Bool]
  func_has_stmt_expr_by_id : Array[Bool?]
  func_has_static_local : @util.FastMap[String, Bool]
  func_has_static_local_by_id : Array[Bool?]
  func_has_local_decl : @util.FastMap[String, Bool]
  func_has_local_decl_by_id : Array[Bool?]
  enum_defs : @util.FastMap[String, Array[@ast.EnumItem]]
  enum_defs_by_id : Array[Array[@ast.EnumItem]?]
  enum_consts : @util.FastMap[String, Int]
  enum_consts_by_id : Array[Int?]
  enum_types : @util.FastMap[String, @ast.CType]
  enum_types_by_id : Array[@ast.CType?]
  compound_literal_types : @util.FastMap[Int, @ast.CType]
  expr_type_cache : Array[@ast.CType?]
  func_agg_temps : @util.FastMap[String, (Int, Int)]
  func_agg_temps_by_id : Array[(Int, Int)?]
  switch_stack : Array[SwitchInfo]
  mut labels_defined : @util.FastMap[String, Bool]
  mut labels_used : Array[(String, @source.SrcLoc)]
  mut loop_depth : Int
  mut switch_depth : Int
  mut current_func_name : String?
  mut current_func_id : Int
  mut current_agg_temp_size : Int
  mut current_agg_temp_align : Int
  mut record_agg_temps : Bool
}

///|
struct LocalOverride {
  id : Int
  prev_ty : @ast.CType?
  prev_scope : Int
}

///|
struct SwitchInfo {
  cases : Array[(Int, Int, @source.SrcLoc)]
  mut has_default : Bool
}

///|
fn default_type_aliases() -> @util.FastMap[String, @ast.CType] {
  let aliases : @util.FastMap[String, @ast.CType] = @util.fast_map_new()
  aliases.set("__builtin_va_list", Pointer(Void))
  aliases.set(
    "jmp_buf",
    Array(elem=default_int_type(), size=Some(1), size_expr=None),
  )
  aliases.set("FILE", Pointer(Void))
  aliases
}

///|
fn new_sem_context(diags : @diag.DiagBag) -> SemContext {
  let type_aliases = default_type_aliases()
  {
    diags,
    globals: @util.fast_map_new(),
    globals_by_id: [],
    functions: @util.fast_map_new(),
    functions_by_id: [],
    builtin_call_ids: [],
    builtin_sig_ids: [],
    atomic_template_ids: [],
    function_defs: @util.fast_map_new(),
    local_scope_ids_by_id: [],
    local_scope_stack: [],
    next_local_scope_id: 0,
    local_values_by_id: [],
    local_overrides: [],
    type_aliases,
    struct_defs: @util.fast_map_new(),
    struct_defs_by_id: [],
    union_defs: @util.fast_map_new(),
    union_defs_by_id: [],
    struct_member_cache: @util.fast_map_new(),
    struct_member_cache_by_id: [],
    union_member_cache: @util.fast_map_new(),
    union_member_cache_by_id: [],
    struct_field_access_cache: @util.fast_map_new(),
    struct_field_access_cache_by_id: [],
    union_field_access_cache: @util.fast_map_new(),
    union_field_access_cache_by_id: [],
    struct_field_index_cache: @util.fast_map_new(),
    struct_field_index_cache_by_id: [],
    union_field_index_cache: @util.fast_map_new(),
    union_field_index_cache_by_id: [],
    struct_size_cache: @util.fast_map_new(),
    struct_size_cache_by_id: [],
    union_size_cache: @util.fast_map_new(),
    union_size_cache_by_id: [],
    func_compound_literals: @util.fast_map_new(),
    func_compound_literals_by_id: [],
    compound_literal_sizes: @util.fast_map_new(),
    func_has_compound_literal: @util.fast_map_new(),
    func_has_stmt_expr: @util.fast_map_new(),
    func_has_stmt_expr_by_id: [],
    func_has_static_local: @util.fast_map_new(),
    func_has_static_local_by_id: [],
    func_has_local_decl: @util.fast_map_new(),
    func_has_local_decl_by_id: [],
    enum_defs: @util.fast_map_new(),
    enum_defs_by_id: [],
    enum_consts: @util.fast_map_new(),
    enum_consts_by_id: [],
    enum_types: @util.fast_map_new(),
    enum_types_by_id: [],
    compound_literal_types: @util.fast_map_new(),
    expr_type_cache: [],
    func_agg_temps: @util.fast_map_new(),
    func_agg_temps_by_id: [],
    switch_stack: [],
    labels_defined: @util.fast_map_new(),
    labels_used: [],
    loop_depth: 0,
    switch_depth: 0,
    current_func_name: None,
    current_func_id: 0,
    current_agg_temp_size: 0,
    current_agg_temp_align: 1,
    record_agg_temps: true,
  }
}

///|
fn[T] ensure_opt_array_capacity(arr : Array[T?], id : Int) -> Unit {
  if id <= 0 {
    return
  }
  let len = arr.length()
  if len >= id {
    return
  }
  let mut i = len
  while i < id {
    arr.push(None)
    i = i + 1
  }
}

///|
pub fn[T] get_opt_by_id(arr : Array[T?], id : Int) -> T? {
  if id <= 0 || id > arr.length() {
    None
  } else {
    arr[id - 1]
  }
}

///|
pub fn[T] set_opt_by_id(arr : Array[T?], id : Int, value : T) -> Unit {
  if id <= 0 {
    return
  }
  ensure_opt_array_capacity(arr, id)
  arr[id - 1] = Some(value)
}

///|
fn ensure_int_array_capacity(arr : Array[Int], id : Int) -> Unit {
  if id <= 0 {
    return
  }
  let len = arr.length()
  if len >= id {
    return
  }
  let mut i = len
  while i < id {
    arr.push(0)
    i = i + 1
  }
}

///|
pub fn current_local_scope_id(ctx : SemContext) -> Int {
  let len = ctx.local_scope_stack.length()
  if len == 0 {
    0
  } else {
    ctx.local_scope_stack[len - 1]
  }
}

///|
pub fn[T] has_opt_by_id(arr : Array[T?], id : Int) -> Bool {
  get_opt_by_id(arr, id) is Some(_)
}

///|
fn ensure_globals_by_id(ctx : SemContext, id : Int) -> Unit {
  if id <= 0 {
    return
  }
  let len = ctx.globals_by_id.length()
  if len >= id {
    return
  }
  let mut i = len
  while i < id {
    ctx.globals_by_id.push(None)
    i = i + 1
  }
}

///|
fn set_global_by_id(ctx : SemContext, id : Int, ty : @ast.CType) -> Unit {
  if id <= 0 {
    return
  }
  ensure_globals_by_id(ctx, id)
  ctx.globals_by_id[id - 1] = Some(ty)
}

///|
pub fn get_global_by_id(ctx : SemContext, id : Int) -> @ast.CType? {
  get_opt_by_id(ctx.globals_by_id, id)
}

///|
fn has_global_by_id(ctx : SemContext, id : Int) -> Bool {
  get_global_by_id(ctx, id) is Some(_)
}

///|
fn ensure_functions_by_id(ctx : SemContext, id : Int) -> Unit {
  if id <= 0 {
    return
  }
  let len = ctx.functions_by_id.length()
  if len >= id {
    return
  }
  let mut i = len
  while i < id {
    ctx.functions_by_id.push(None)
    i = i + 1
  }
}

///|
fn set_function_by_id(ctx : SemContext, id : Int, sig : FuncSig) -> Unit {
  if id <= 0 {
    return
  }
  ensure_functions_by_id(ctx, id)
  ctx.functions_by_id[id - 1] = Some(sig)
}

///|
pub fn get_function_by_id(ctx : SemContext, id : Int) -> FuncSig? {
  get_opt_by_id(ctx.functions_by_id, id)
}

///|
pub fn has_function_by_id(ctx : SemContext, id : Int) -> Bool {
  get_function_by_id(ctx, id) is Some(_)
}

///|
fn ensure_enum_consts_by_id(ctx : SemContext, id : Int) -> Unit {
  if id <= 0 {
    return
  }
  let len = ctx.enum_consts_by_id.length()
  if len >= id {
    return
  }
  let mut i = len
  while i < id {
    ctx.enum_consts_by_id.push(None)
    i = i + 1
  }
}

///|
fn set_enum_const_by_id(ctx : SemContext, id : Int, value : Int) -> Unit {
  if id <= 0 {
    return
  }
  ensure_enum_consts_by_id(ctx, id)
  ctx.enum_consts_by_id[id - 1] = Some(value)
}

///|
fn get_enum_const_by_id(ctx : SemContext, id : Int) -> Int? {
  get_opt_by_id(ctx.enum_consts_by_id, id)
}

///|
fn has_enum_const_by_id(ctx : SemContext, id : Int) -> Bool {
  get_enum_const_by_id(ctx, id) is Some(_)
}

///|

///|
pub fn attrs_layout_empty(attrs : @ast.Attributes) -> Bool {
  attrs.aligned is None && !attrs.packed
}

///|

///|
let size_t_type_value : @ast.CType = Int(kind=Long, unsigned=true)

///|
let char_type_value : @ast.CType = Int(
  kind=Char,
  unsigned=@util.char_is_unsigned,
)

///|
let void_pointer_type_value : @ast.CType = Pointer(Void)

///|
let char_pointer_type_value : @ast.CType = Pointer(char_type_value)

///|
pub fn default_int_type() -> @ast.CType {
  @ast.default_int_type()
}

///|
fn size_t_type() -> @ast.CType {
  size_t_type_value
}

///|
fn char_type() -> @ast.CType {
  char_type_value
}

///|
fn void_pointer_type() -> @ast.CType {
  void_pointer_type_value
}

///|
fn char_pointer_type() -> @ast.CType {
  char_pointer_type_value
}

///|
fn lookup_local_only(ctx : SemContext, id : Int) -> @ast.CType? {
  get_opt_by_id(ctx.local_values_by_id, id)
}

///|
pub fn enum_const_value(ctx : SemContext, name : String, id : Int) -> Int? {
  if id > 0 {
    get_enum_const_by_id(ctx, id)
  } else {
    ctx.enum_consts.get(name)
  }
}

///|
fn enum_const_exists(ctx : SemContext, name : String, id : Int) -> Bool {
  if id > 0 {
    has_enum_const_by_id(ctx, id)
  } else {
    ctx.enum_consts.contains(name)
  }
}

///|
fn enum_int_type_from_range(min_value : Int, max_value : Int) -> @ast.CType {
  let max_int = 2147483647
  let min_int = -2147483647 - 1
  if min_value >= 0 {
    Int(kind=Int, unsigned=true)
  } else if min_value < min_int || max_value > max_int {
    Int(kind=LongLong, unsigned=false)
  } else {
    Int(kind=Int, unsigned=false)
  }
}

///|
fn enum_type_from_items(
  ctx : SemContext,
  items : Array[@ast.EnumItem],
) -> @ast.CType {
  let mut value = 0
  let mut min_value = 0
  let mut max_value = 0
  let mut has_value = false
  for item in items {
    let current = match item.value {
      None => value
      Some(expr) => eval_const_expr(ctx, expr, item.loc)
    }
    if !has_value {
      min_value = current
      max_value = current
      has_value = true
    } else {
      if current < min_value {
        min_value = current
      }
      if current > max_value {
        max_value = current
      }
    }
    value = current + 1
  }
  if has_value {
    enum_int_type_from_range(min_value, max_value)
  } else {
    default_int_type()
  }
}

///|
pub fn strip_qualifiers(ty : @ast.CType) -> @ast.CType {
  match ty {
    Qualified(base~, ..) => strip_qualifiers(base)
    Attributed(attrs~, base~) => Attributed(attrs~, base=strip_qualifiers(base))
    Pointer(inner) => Pointer(strip_qualifiers(inner))
    Array(elem~, size~, size_expr~) =>
      Array(elem=strip_qualifiers(elem), size~, size_expr~)
    Function(return_type~, params~, varargs~, is_old_style~, call_conv~) =>
      Function(
        return_type=strip_qualifiers(return_type),
        params=params.map(strip_qualifiers),
        varargs~,
        is_old_style~,
        call_conv~,
      )
    _ => ty
  }
}

///|
pub fn strip_qual_attrs(ty : @ast.CType) -> @ast.CType {
  match ty {
    Qualified(base~, ..) => strip_qual_attrs(base)
    Attributed(base~, ..) => strip_qual_attrs(base)
    Pointer(inner) => Pointer(strip_qual_attrs(inner))
    Array(elem~, size~, size_expr~) =>
      Array(elem=strip_qual_attrs(elem), size~, size_expr~)
    Function(return_type~, params~, varargs~, is_old_style~, call_conv~) =>
      Function(
        return_type=strip_qual_attrs(return_type),
        params=params.map(strip_qual_attrs),
        varargs~,
        is_old_style~,
        call_conv~,
      )
    _ => ty
  }
}

///|
pub fn strip_top_qualifiers(ty : @ast.CType) -> @ast.CType {
  let mut current = ty
  while true {
    match current {
      Qualified(base~, ..) => current = base
      Attributed(base~, ..) => current = base
      _ => break
    }
  }
  current
}

///|
pub fn strip_top_qualifiers_keep_attrs(ty : @ast.CType) -> @ast.CType {
  let mut current = ty
  while true {
    match current {
      Qualified(base~, ..) => current = base
      _ => break
    }
  }
  current
}

///|
fn split_top_qual(ty : @ast.CType) -> (@ast.TypeQual, @ast.CType) {
  match ty {
    Qualified(qual~, base~) => (qual, base)
    Attributed(base~, ..) => split_top_qual(base)
    _ => (@ast.empty_qual(), ty)
  }
}

///|
fn is_const_qualified(ty : @ast.CType) -> Bool {
  match ty {
    Qualified(qual~, ..) => qual.is_const
    Attributed(base~, ..) => is_const_qualified(base)
    _ => false
  }
}

///|
fn is_void_type(ty : @ast.CType) -> Bool {
  strip_top_qualifiers(ty) is Void
}

///|
fn int_rank(kind : @ast.CIntKind) -> Int {
  match kind {
    Char => 1
    Short => 2
    Int => 3
    Long => 4
    LongLong => 5
  }
}

///|
fn int_bits(kind : @ast.CIntKind) -> Int {
  match kind {
    Char => 8
    Short => 16
    Int => 32
    Long => 64
    LongLong => 64
  }
}

///|
fn float_rank(kind : @ast.CFloatKind) -> Int {
  match kind {
    Float => 1
    Double => 2
    LongDouble => 3
  }
}

///|
pub fn int_size(kind : @ast.CIntKind) -> Int {
  match kind {
    Char => 1
    Short => 2
    Int => 4
    Long => 8
    LongLong => 8
  }
}

///|
pub fn float_size(kind : @ast.CFloatKind) -> Int {
  match kind {
    Float => 4
    Double => 8
    // AArch64 uses 8-byte long double (same as double)
    LongDouble => 8
  }
}

///|
pub fn align_to(value : Int, align : Int) -> Int {
  if align <= 1 {
    return value
  }
  (value + align - 1) / align * align
}

///|
let max_align = 16

///|
fn is_power_of_two(value : Int) -> Bool {
  value > 0 && (value & (value - 1)) == 0
}

///|
fn resolve_align_spec(
  ctx : SemContext,
  spec : @ast.AlignSpec,
  loc : @source.SrcLoc,
) -> Int? {
  match spec {
    Default => Some(max_align)
    Expr(expr~) =>
      match const_int_from_expr(ctx, expr, loc) {
        None => None
        Some(value) =>
          if !is_power_of_two(value) {
            add_sem_error(ctx, loc, "alignment must be a positive power of two")
            None
          } else {
            Some(value)
          }
      }
  }
}

///|
pub fn attr_align_value(
  ctx : SemContext,
  attrs : @ast.Attributes,
  loc : @source.SrcLoc,
) -> Int? {
  match attrs.aligned {
    None => None
    Some(spec) => resolve_align_spec(ctx, spec, loc)
  }
}

///|
fn is_float_type(ty : @ast.CType) -> Bool {
  match strip_top_qualifiers(ty) {
    Float(..) => true
    _ => false
  }
}

///|
fn enum_type_for_arith(ctx : SemContext, ty : @ast.CType) -> @ast.CType {
  match strip_top_qualifiers(ty) {
    Enum(name~, id~, ..) =>
      if id != 0 {
        match get_opt_by_id(ctx.enum_types_by_id, id) {
          Some(base) => base
          None => default_int_type()
        }
      } else {
        match ctx.enum_types.get(name) {
          Some(base) => base
          None => default_int_type()
        }
      }
    _ => ty
  }
}

///|
fn promote_int_type(ctx : SemContext, ty : @ast.CType) -> @ast.CType {
  match strip_top_qualifiers(ty) {
    Int(kind~, unsigned~) =>
      if int_rank(kind) < int_rank(Int) {
        default_int_type()
      } else {
        Int(kind~, unsigned~)
      }
    Bool => default_int_type()
    Enum(..) => promote_int_type(ctx, enum_type_for_arith(ctx, ty))
    _ => default_int_type()
  }
}

///|
pub fn common_int_type(
  ctx : SemContext,
  lhs : @ast.CType,
  rhs : @ast.CType,
) -> @ast.CType {
  let left = promote_int_type(ctx, lhs)
  let right = promote_int_type(ctx, rhs)
  match (left, right) {
    (
      Int(kind=l_kind, unsigned=l_unsigned),
      Int(kind=r_kind, unsigned=r_unsigned),
    ) => {
      if l_unsigned == r_unsigned {
        let rank = if int_rank(l_kind) >= int_rank(r_kind) {
          l_kind
        } else {
          r_kind
        }
        return Int(kind=rank, unsigned=l_unsigned)
      }
      let (u_kind, u_unsigned, s_kind) = if l_unsigned {
        (l_kind, true, r_kind)
      } else {
        (r_kind, true, l_kind)
      }
      if int_rank(u_kind) >= int_rank(s_kind) {
        return Int(kind=u_kind, unsigned=u_unsigned)
      }
      let u_bits = int_bits(u_kind)
      let s_bits = int_bits(s_kind)
      if s_bits > u_bits {
        Int(kind=s_kind, unsigned=false)
      } else {
        Int(kind=s_kind, unsigned=true)
      }
    }
    _ => default_int_type()
  }
}

///|
fn arithmetic_result_type(
  ctx : SemContext,
  lhs : @ast.CType,
  rhs : @ast.CType,
) -> @ast.CType {
  let left = strip_top_qualifiers(lhs)
  let right = strip_top_qualifiers(rhs)
  match (left, right) {
    (Float(kind=l_kind), Float(kind=r_kind)) =>
      if float_rank(l_kind) >= float_rank(r_kind) {
        Float(kind=l_kind)
      } else {
        Float(kind=r_kind)
      }
    (Float(kind~), _) => Float(kind~)
    (_, Float(kind~)) => Float(kind~)
    _ => common_int_type(ctx, lhs, rhs)
  }
}

///|
fn is_arithmetic(ty : @ast.CType) -> Bool {
  is_int_like(ty) || is_float_type(ty)
}

///|
fn can_assign(dst : @ast.CType, src : @ast.CType) -> Bool {
  let dst_ty = strip_top_qualifiers(dst)
  let src_ty = strip_top_qualifiers(src)
  if is_arithmetic(dst_ty) && is_arithmetic(src_ty) {
    return true
  }
  match (dst_ty, src_ty) {
    (Pointer(inner_a), Pointer(inner_b)) => pointer_compatible(inner_a, inner_b)
    _ => type_eq(dst_ty, src_ty)
  }
}

///|
fn pointer_compatible(a : @ast.CType, b : @ast.CType) -> Bool {
  if type_eq(a, b) || is_void_type(a) || is_void_type(b) {
    return true
  }
  // Match tcc leniency: same-size integer pointer types are compatible.
  match (strip_top_qualifiers(a), strip_top_qualifiers(b)) {
    (
      Int(kind=a_kind, unsigned=a_unsigned),
      Int(kind=b_kind, unsigned=b_unsigned),
    ) => a_unsigned == b_unsigned && int_size(a_kind) == int_size(b_kind)
    _ => false
  }
}

///|
fn check_storage_class(
  ctx : SemContext,
  storage : @ast.StorageClass,
  loc : @source.SrcLoc,
  is_local~ : Bool,
  is_function~ : Bool,
) -> Unit {
  if is_function {
    match storage {
      Auto | Register =>
        add_sem_error(ctx, loc, "invalid storage class for function")
      Static =>
        if is_local {
          add_sem_error(
            ctx, loc, "function without file scope cannot be static",
          )
        }
      _ => ()
    }
  } else if !is_local {
    match storage {
      Auto | Register =>
        add_sem_error(ctx, loc, "invalid storage class for global")
      _ => ()
    }
  }
}

///|
pub fn type_size_align(
  ctx : SemContext,
  ty : @ast.CType,
  loc : @source.SrcLoc,
) -> (Int, Int)? {
  match strip_top_qualifiers_keep_attrs(ty) {
    TypeofExpr(expr~) => type_size_align(ctx, type_for_typeof(ctx, expr), loc)
    Attributed(attrs~, base~) =>
      match type_size_align(ctx, base, loc) {
        None => None
        Some((size, align)) => {
          let mut final_align = if attrs.packed { 1 } else { align }
          if attr_align_value(ctx, attrs, loc) is Some(value) {
            if value > final_align {
              final_align = value
            }
          }
          Some((size, final_align))
        }
      }
    Void => {
      add_sem_error(ctx, loc, "invalid application of sizeof to void")
      None
    }
    Bool => Some((1, 1))
    Int(kind~, ..) => {
      let size = int_size(kind)
      Some((size, size))
    }
    Float(kind~) => {
      let size = float_size(kind)
      Some((size, size))
    }
    Pointer(_) => Some((8, 8))
    Enum(name~, id~, items~) => {
      let enum_ty = if id != 0 {
        match get_opt_by_id(ctx.enum_types_by_id, id) {
          Some(base) => Some(base)
          None =>
            match items {
              None => {
                add_sem_error(ctx, loc, "incomplete enum '\{name}'")
                None
              }
              Some(list) =>
                if list.length() == 0 {
                  add_sem_error(ctx, loc, "incomplete enum '\{name}'")
                  None
                } else {
                  let base = enum_type_from_items(ctx, list)
                  if name != "" {
                    set_opt_by_id(ctx.enum_types_by_id, id, base)
                    ctx.enum_types.set(name, base)
                  }
                  Some(base)
                }
            }
        }
      } else {
        match ctx.enum_types.get(name) {
          Some(base) => Some(base)
          None =>
            match items {
              None => {
                add_sem_error(ctx, loc, "incomplete enum '\{name}'")
                None
              }
              Some(list) =>
                if list.length() == 0 {
                  add_sem_error(ctx, loc, "incomplete enum '\{name}'")
                  None
                } else {
                  let base = enum_type_from_items(ctx, list)
                  if name != "" {
                    ctx.enum_types.set(name, base)
                  }
                  Some(base)
                }
            }
        }
      }
      match enum_ty {
        None => None
        Some(base) => type_size_align(ctx, base, loc)
      }
    }
    Function(..) => Some((8, 8))
    Array(elem~, size~, size_expr~) => {
      let (elem_size, elem_align) = match type_size_align(ctx, elem, loc) {
        None => return None
        Some(v) => v
      }
      match size {
        Some(n) => Some((elem_size * n, elem_align))
        None =>
          match size_expr {
            None => {
              add_sem_error(ctx, loc, "sizeof incomplete array")
              None
            }
            Some(expr) =>
              match const_int_from_expr(ctx, expr, @ast.expr_loc(expr)) {
                None => None
                Some(n) =>
                  if n < 0 {
                    add_sem_error(
                      ctx,
                      @ast.expr_loc(expr),
                      "invalid array size",
                    )
                    None
                  } else {
                    Some((elem_size * n, elem_align))
                  }
              }
          }
      }
    }
    Struct(name=tag, id=tag_id, fields=field_list, attrs=struct_attrs) =>
      match
        ensure_struct_fields(ctx, tag, tag_id, field_list, is_union=false, loc) {
        None => None
        Some(def) => {
          let merged = @ast.merge_attrs(def.attrs, struct_attrs)
          if tag != "" && @ast.attrs_is_empty(struct_attrs) {
            if tag_id != 0 {
              match get_opt_by_id(ctx.struct_size_cache_by_id, tag_id) {
                Some(value) => Some(value)
                None => {
                  let value = struct_size_align(ctx, def.fields, merged, loc)
                  set_opt_by_id(ctx.struct_size_cache_by_id, tag_id, value)
                  Some(value)
                }
              }
            } else {
              match ctx.struct_size_cache.get(tag) {
                Some(value) => Some(value)
                None => {
                  let value = struct_size_align(ctx, def.fields, merged, loc)
                  ctx.struct_size_cache.set(tag, value)
                  Some(value)
                }
              }
            }
          } else {
            Some(struct_size_align(ctx, def.fields, merged, loc))
          }
        }
      }
    Union(name=tag, id=tag_id, fields=field_list, attrs=struct_attrs) =>
      match
        ensure_struct_fields(ctx, tag, tag_id, field_list, is_union=true, loc) {
        None => None
        Some(def) => {
          let merged = @ast.merge_attrs(def.attrs, struct_attrs)
          if tag != "" && @ast.attrs_is_empty(struct_attrs) {
            if tag_id != 0 {
              match get_opt_by_id(ctx.union_size_cache_by_id, tag_id) {
                Some(value) => Some(value)
                None => {
                  let value = union_size_align(ctx, def.fields, merged, loc)
                  set_opt_by_id(ctx.union_size_cache_by_id, tag_id, value)
                  Some(value)
                }
              }
            } else {
              match ctx.union_size_cache.get(tag) {
                Some(value) => Some(value)
                None => {
                  let value = union_size_align(ctx, def.fields, merged, loc)
                  ctx.union_size_cache.set(tag, value)
                  Some(value)
                }
              }
            }
          } else {
            Some(union_size_align(ctx, def.fields, merged, loc))
          }
        }
      }
    Qualified(base~, ..) => type_size_align(ctx, base, loc)
  }
}

///|
fn record_agg_temp_for_type(
  ctx : SemContext,
  ty : @ast.CType,
  loc : @source.SrcLoc,
) -> Unit {
  if ctx.current_func_name is None {
    return
  }
  if !ctx.record_agg_temps {
    return
  }
  match strip_top_qualifiers(ty) {
    Struct(..) | Union(..) =>
      if type_size_align(ctx, ty, loc) is Some((size, align)) {
        if size > 0 {
          if size > ctx.current_agg_temp_size {
            ctx.current_agg_temp_size = size
          }
          if align > ctx.current_agg_temp_align {
            ctx.current_agg_temp_align = align
          }
        }
      }
    _ => ()
  }
}

///|
fn maybe_record_agg_temp_for_expr(
  ctx : SemContext,
  expr : @ast.Expr,
  ty : @ast.CType,
) -> Unit {
  if ctx.current_func_name is None {
    return
  }
  if !ctx.record_agg_temps {
    return
  }
  match strip_top_qualifiers(ty) {
    Struct(..) | Union(..) =>
      if !@ast.expr_is_lvalue_simple(expr) {
        record_agg_temp_for_type(ctx, ty, @ast.expr_loc(expr))
      }
    _ => ()
  }
}

///|
pub fn ensure_struct_fields(
  ctx : SemContext,
  tag : String,
  tag_id : Int,
  fields : Array[@ast.RecordItem]?,
  is_union~ : Bool,
  loc : @source.SrcLoc,
) -> RecordDef? {
  match fields {
    Some(list) =>
      if tag != "" {
        match lookup_struct_def(ctx, tag, tag_id, is_union~) {
          Some(def) => Some(def)
          None =>
            Some({
              fields: record_items_to_fields(list),
              attrs: @ast.empty_attrs(),
            })
        }
      } else {
        Some({ fields: record_items_to_fields(list), attrs: @ast.empty_attrs() })
      }
    None =>
      if is_union {
        if tag_id != 0 {
          match get_opt_by_id(ctx.union_defs_by_id, tag_id) {
            Some(def) if def.fields.length() > 0 => Some(def)
            _ => {
              add_sem_error(ctx, loc, "incomplete union '\{tag}'")
              None
            }
          }
        } else {
          match ctx.union_defs.get(tag) {
            Some(def) if def.fields.length() > 0 => Some(def)
            _ => {
              add_sem_error(ctx, loc, "incomplete union '\{tag}'")
              None
            }
          }
        }
      } else if tag_id != 0 {
        match get_opt_by_id(ctx.struct_defs_by_id, tag_id) {
          Some(def) if def.fields.length() > 0 => Some(def)
          _ => {
            add_sem_error(ctx, loc, "incomplete struct '\{tag}'")
            None
          }
        }
      } else {
        match ctx.struct_defs.get(tag) {
          Some(def) if def.fields.length() > 0 => Some(def)
          _ => {
            add_sem_error(ctx, loc, "incomplete struct '\{tag}'")
            None
          }
        }
      }
  }
}

///|
fn static_assert_message(message : String?) -> String {
  match message {
    Some(value) => value
    None => "_Static_assert fail"
  }
}

///|
fn check_static_assert(ctx : SemContext, item : @ast.StaticAssert) -> Unit {
  let (value, ok) = eval_const_expr_value(ctx, item.expr, item.loc)
  if ok && value == 0 {
    add_sem_error(ctx, item.loc, static_assert_message(item.message))
  }
}

///|
fn record_items_to_fields(items : Array[@ast.RecordItem]) -> Array[@ast.Field] {
  let fields : Array[@ast.Field] = []
  for item in items {
    match item {
      Field(field) => fields.push(field)
      StaticAssert(_) => ()
    }
  }
  fields
}

///|
fn record_items_to_fields_checked(
  ctx : SemContext,
  items : Array[@ast.RecordItem],
) -> Array[@ast.Field] {
  let fields : Array[@ast.Field] = []
  for item in items {
    match item {
      Field(field) => fields.push(field)
      StaticAssert(static_assert) => check_static_assert(ctx, static_assert)
    }
  }
  fields
}

///|
pub fn struct_size_align(
  ctx : SemContext,
  fields : Array[@ast.Field],
  attrs : @ast.Attributes,
  loc : @source.SrcLoc,
) -> (Int, Int) {
  let mut size = 0
  let mut align = 1
  let mut bit_pos = 0
  for i = 0; i < fields.length(); i = i + 1 {
    let field = fields[i]
    let packed = attrs.packed || field.attrs.packed
    let field_align_override = attr_align_value(ctx, field.attrs, field.loc)
    match field.bit_width {
      Some(expr) => {
        let width = const_int_from_expr(ctx, expr, field.loc).unwrap_or(0)
        let base = strip_top_qualifiers_keep_attrs(field.ty)
        let (base_size, base_align) = type_size_align(ctx, base, loc).unwrap_or(
          (0, 1),
        )
        let mut field_align = base_align
        if field_align_override is Some(value) {
          field_align = value
        }
        if width == 0 {
          let used_bytes = (bit_pos + 7) / 8
          size = align_to(size + used_bytes, field_align)
          bit_pos = 0
          continue
        }
        if packed && width != 0 {
          field_align = 1
        }
        if field_align_override is Some(value) {
          field_align = value
        }
        align = if field_align > align { field_align } else { align }
        if field_align_override is Some(_) {
          let used_bytes = (bit_pos + 7) / 8
          size = align_to(size + used_bytes, field_align)
          bit_pos = 0
        } else if !packed {
          let a8 = field_align * 8
          let max_units = if field_align > 0 {
            base_size / field_align
          } else {
            0
          }
          if a8 > 0 {
            let ofs = ((size * 8 + bit_pos) % a8 + width + a8 - 1) / a8
            if ofs > max_units {
              let used_bytes = (bit_pos + 7) / 8
              size = align_to(size + used_bytes, field_align)
              bit_pos = 0
            }
          }
        }
        while bit_pos >= field_align * 8 {
          size = size + field_align
          bit_pos = bit_pos - field_align * 8
        }
        bit_pos = bit_pos + width
      }
      None => {
        if bit_pos != 0 {
          size = size + (bit_pos + 7) / 8
          bit_pos = 0
        }
        let (field_size, field_align) = match
          strip_top_qualifiers_keep_attrs(field.ty) {
          Array(elem~, size=None, size_expr~) =>
            match size_expr {
              None => {
                if i != fields.length() - 1 {
                  add_sem_error(
                    ctx,
                    field.loc,
                    "flexible array member '\{field.name}' not at the end of struct",
                  )
                }
                let (_elem_size, elem_align) = match
                  type_size_align(ctx, elem, field.loc) {
                  None => (0, 1)
                  Some(v) => v
                }
                (0, elem_align)
              }
              Some(_) =>
                match type_size_align(ctx, field.ty, field.loc) {
                  None => {
                    add_sem_error(
                      ctx,
                      field.loc,
                      "variable length array not allowed in struct",
                    )
                    (0, 1)
                  }
                  Some(v) => v
                }
            }
          _ =>
            match type_size_align(ctx, field.ty, loc) {
              None => (0, 1)
              Some(v) => v
            }
        }
        let mut adjusted_align = if packed { 1 } else { field_align }
        if field_align_override is Some(value) {
          adjusted_align = value
        }
        size = align_to(size, adjusted_align)
        size = size + field_size
        align = if adjusted_align > align { adjusted_align } else { align }
      }
    }
  }
  if bit_pos != 0 {
    size = size + (bit_pos + 7) / 8
  }
  let mut final_align = align
  if attr_align_value(ctx, attrs, loc) is Some(value) {
    if value > final_align {
      final_align = value
    }
  }
  size = align_to(size, final_align)
  (size, final_align)
}

///|
pub fn union_size_align(
  ctx : SemContext,
  fields : Array[@ast.Field],
  attrs : @ast.Attributes,
  loc : @source.SrcLoc,
) -> (Int, Int) {
  let mut size = 0
  let mut align = 1
  for field in fields {
    let packed = attrs.packed || field.attrs.packed
    let field_align_override = attr_align_value(ctx, field.attrs, field.loc)
    let base = strip_top_qualifiers_keep_attrs(field.ty)
    let (field_size, field_align) = match field.bit_width {
      Some(expr) => {
        let width = const_int_from_expr(ctx, expr, field.loc).unwrap_or(0)
        let size_bits = if width > 0 { width } else { 0 }
        let size_bytes = (size_bits + 7) / 8
        let (_, base_align) = type_size_align(ctx, base, loc).unwrap_or((0, 1))
        (size_bytes, base_align)
      }
      None =>
        match strip_top_qualifiers_keep_attrs(field.ty) {
          Array(elem=_, size=None, size_expr~) =>
            match size_expr {
              None =>
                match type_size_align(ctx, field.ty, loc) {
                  None => (0, 1)
                  Some(v) => v
                }
              Some(_) =>
                match type_size_align(ctx, field.ty, field.loc) {
                  None => {
                    add_sem_error(
                      ctx,
                      field.loc,
                      "variable length array not allowed in union",
                    )
                    (0, 1)
                  }
                  Some(v) => v
                }
            }
          _ =>
            match type_size_align(ctx, field.ty, loc) {
              None => (0, 1)
              Some(v) => v
            }
        }
    }
    let mut adjusted_align = if packed { 1 } else { field_align }
    if field_align_override is Some(value) {
      adjusted_align = value
    }
    if field_size > size {
      size = field_size
    }
    if adjusted_align > align {
      align = adjusted_align
    }
  }
  let mut final_align = align
  if attr_align_value(ctx, attrs, loc) is Some(value) {
    if value > final_align {
      final_align = value
    }
  }
  size = align_to(size, final_align)
  (size, final_align)
}

///|
pub fn type_for_sizeof(ctx : SemContext, expr : @ast.Expr) -> @ast.CType {
  let prev = ctx.record_agg_temps
  ctx.record_agg_temps = false
  let ty = match expr {
    Ident(name~, id~, loc~, ..) =>
      match lookup_value(ctx, name, id) {
        Some(ty) => ty
        None => {
          add_sem_error(ctx, loc, "use of undeclared identifier '\{name}'")
          default_int_type()
        }
      }
    StringLit(length~, ..) =>
      Array(elem=char_type(), size=Some(length), size_expr=None)
    _ =>
      match type_of_lvalue_optional(ctx, expr) {
        Some(ty) => ty
        None => type_of_expr_impl(ctx, expr)
      }
  }
  ctx.record_agg_temps = prev
  ty
}

///|
fn type_for_typeof(ctx : SemContext, expr : @ast.Expr) -> @ast.CType {
  let prev = ctx.record_agg_temps
  ctx.record_agg_temps = false
  let ty = match expr {
    Ident(name~, id~, loc~, ..) =>
      match lookup_value(ctx, name, id) {
        Some(ty) => ty
        None => {
          add_sem_error(ctx, loc, "use of undeclared identifier '\{name}'")
          default_int_type()
        }
      }
    StringLit(length~, ..) =>
      Array(elem=char_type(), size=Some(length), size_expr=None)
    _ => type_of_expr_impl(ctx, expr)
  }
  ctx.record_agg_temps = prev
  ty
}

///|
pub fn resolve_type(
  ctx : SemContext,
  ty : @ast.CType,
  loc : @source.SrcLoc,
) -> @ast.CType {
  let (resolved, _) = resolve_type_inner(ctx, ty, loc)
  resolved
}

///|
fn resolve_type_inner(
  ctx : SemContext,
  ty : @ast.CType,
  loc : @source.SrcLoc,
) -> (@ast.CType, Bool) {
  match ty {
    Qualified(qual~, base~) => {
      let (resolved_base, changed) = resolve_type_inner(ctx, base, loc)
      if changed {
        (Qualified(qual~, base=resolved_base), true)
      } else {
        (ty, false)
      }
    }
    Attributed(attrs~, base~) => {
      let (resolved_base, changed) = resolve_type_inner(ctx, base, loc)
      if changed {
        (Attributed(attrs~, base=resolved_base), true)
      } else {
        (ty, false)
      }
    }
    Pointer(inner) => {
      let (resolved_inner, changed) = resolve_type_inner(ctx, inner, loc)
      if changed {
        (Pointer(resolved_inner), true)
      } else {
        (ty, false)
      }
    }
    Array(elem~, size~, size_expr~) => {
      let (resolved_elem, changed) = resolve_type_inner(ctx, elem, loc)
      if changed {
        (Array(elem=resolved_elem, size~, size_expr~), true)
      } else {
        (ty, false)
      }
    }
    Function(return_type~, params~, varargs~, is_old_style~, call_conv~) => {
      let (resolved_ret, ret_changed) = resolve_type_inner(
        ctx, return_type, loc,
      )
      let mut any_changed = ret_changed
      let mut out_params : Array[@ast.CType]? = None
      let len = params.length()
      for i = 0; i < len; i = i + 1 {
        let param = params[i]
        let (resolved_param, param_changed) = resolve_type_inner(
          ctx, param, loc,
        )
        if param_changed {
          any_changed = true
          if out_params is None {
            let arr : Array[@ast.CType] = Array::new(capacity=len)
            for j = 0; j < i; j = j + 1 {
              arr.push(params[j])
            }
            out_params = Some(arr)
          }
        }
        if out_params is Some(arr) {
          if param_changed {
            arr.push(resolved_param)
          } else {
            arr.push(param)
          }
        }
      }
      if !any_changed {
        (ty, false)
      } else {
        let resolved_params = match out_params {
          Some(arr) => arr
          None => params
        }
        (
          Function(
            return_type=resolved_ret,
            params=resolved_params,
            varargs~,
            is_old_style~,
            call_conv~,
          ),
          true,
        )
      }
    }
    TypeofExpr(expr~) => {
      let resolved = type_for_typeof(ctx, expr)
      let (final_ty, _) = resolve_type_inner(ctx, resolved, @ast.expr_loc(expr))
      (final_ty, true)
    }
    _ => (ty, false)
  }
}

///|
fn decl_allows_vla(is_local : Bool, storage : @ast.StorageClass) -> Bool {
  if !is_local {
    return false
  }
  match storage {
    Default | Auto | Register => true
    _ => false
  }
}

///|
fn resolve_array_sizes_for_decl(
  ctx : SemContext,
  ty : @ast.CType,
  is_local : Bool,
  storage : @ast.StorageClass,
  loc : @source.SrcLoc,
) -> @ast.CType {
  match ty {
    Qualified(qual~, base~) =>
      Qualified(
        qual~,
        base=resolve_array_sizes_for_decl(ctx, base, is_local, storage, loc),
      )
    Attributed(attrs~, base~) =>
      Attributed(
        attrs~,
        base=resolve_array_sizes_for_decl(ctx, base, is_local, storage, loc),
      )
    Pointer(inner) =>
      Pointer(resolve_array_sizes_for_decl(ctx, inner, is_local, storage, loc))
    Function(return_type~, params~, varargs~, is_old_style~, call_conv~) =>
      Function(
        return_type=resolve_array_sizes_for_decl(
          ctx, return_type, is_local, storage, loc,
        ),
        params=params.map(p => resolve_array_sizes_for_decl(
          ctx, p, is_local, storage, loc,
        )),
        varargs~,
        is_old_style~,
        call_conv~,
      )
    Array(elem~, size~, size_expr~) => {
      let resolved_elem = resolve_array_sizes_for_decl(
        ctx, elem, is_local, storage, loc,
      )
      match size {
        Some(n) =>
          if n < 0 {
            add_sem_error(ctx, loc, "invalid array size")
            Array(elem=resolved_elem, size=None, size_expr~)
          } else {
            Array(elem=resolved_elem, size=Some(n), size_expr~)
          }
        None =>
          match size_expr {
            None => Array(elem=resolved_elem, size=None, size_expr=None)
            Some(expr) =>
              if decl_allows_vla(is_local, storage) {
                if is_constant_expr_for_builtin(ctx, expr) {
                  let (value, ok) = eval_const_expr_value(
                    ctx,
                    expr,
                    @ast.expr_loc(expr),
                  )
                  if !ok {
                    Array(elem=resolved_elem, size=None, size_expr~)
                  } else if value < 0 {
                    add_sem_error(
                      ctx,
                      @ast.expr_loc(expr),
                      "invalid array size",
                    )
                    Array(elem=resolved_elem, size=None, size_expr~)
                  } else {
                    Array(elem=resolved_elem, size=Some(value), size_expr~)
                  }
                } else {
                  let expr_ty = type_of_expr(ctx, expr)
                  if !is_int_like(expr_ty) {
                    add_sem_error(
                      ctx,
                      @ast.expr_loc(expr),
                      "size of variable length array should be an integer",
                    )
                  }
                  Array(elem=resolved_elem, size=None, size_expr~)
                }
              } else {
                match const_int_from_expr(ctx, expr, @ast.expr_loc(expr)) {
                  None => Array(elem=resolved_elem, size=None, size_expr~)
                  Some(value) =>
                    if value < 0 {
                      add_sem_error(
                        ctx,
                        @ast.expr_loc(expr),
                        "invalid array size",
                      )
                      Array(elem=resolved_elem, size=None, size_expr~)
                    } else {
                      Array(elem=resolved_elem, size=Some(value), size_expr~)
                    }
                }
              }
          }
      }
    }
    _ => ty
  }
}

///|
pub fn type_contains_vla(ty : @ast.CType) -> Bool {
  match strip_top_qualifiers(ty) {
    Array(size=None, size_expr=Some(_), ..) => true
    Array(elem~, ..) => type_contains_vla(elem)
    Pointer(inner) => type_contains_vla(inner)
    Function(return_type~, params~, ..) =>
      type_contains_vla(return_type) || params.any(type_contains_vla)
    Qualified(base~, ..) => type_contains_vla(base)
    Attributed(base~, ..) => type_contains_vla(base)
    _ => false
  }
}

///|
fn type_has_vla_object_size(ty : @ast.CType) -> Bool {
  match strip_top_qualifiers(ty) {
    Array(size=None, size_expr=Some(_), ..) => true
    Array(elem~, ..) => type_has_vla_object_size(elem)
    Qualified(base~, ..) => type_has_vla_object_size(base)
    Attributed(base~, ..) => type_has_vla_object_size(base)
    _ => false
  }
}

///|
pub fn check_translation_unit(
  unit : @ast.TranslationUnit,
  diags : @diag.DiagBag,
) -> SemContext {
  let ctx = new_sem_context(diags)
  ensure_expr_type_cache(ctx, unit.expr_id_max)
  for decl in unit.decls {
    check_decl(ctx, decl)
  }
  ctx
}

///|
fn check_decl(ctx : SemContext, decl : @ast.Decl) -> Unit {
  match decl {
    Var(var_decl) => {
      register_type_defs(ctx, var_decl.ty, var_decl.loc)
      check_var_decl(ctx, var_decl, is_local=false)
    }
    FuncDecl(func_decl) => {
      register_type_defs(ctx, func_decl.return_type, func_decl.loc)
      for param in func_decl.params {
        register_type_defs(ctx, param.ty, param.loc)
      }
      check_func_decl(ctx, func_decl)
    }
    FuncDef(func_def) => {
      register_type_defs(ctx, func_def.return_type, func_def.loc)
      for param in func_def.params {
        register_type_defs(ctx, param.ty, param.loc)
      }
      check_func_def(ctx, func_def)
    }
    Typedef(name~, ty~, attrs~, loc~) => {
      register_type_defs(ctx, ty, loc)
      let resolved = resolve_type(ctx, ty, loc)
      let resolved_with_attrs = @ast.apply_type_attrs(
        resolved,
        @ast.type_attrs_from(attrs),
      )
      let final_ty = resolve_array_sizes_for_decl(
        ctx,
        resolved_with_attrs,
        false,
        Default,
        loc,
      )
      ctx.type_aliases.set(name, final_ty)
    }
    TagDef(ty~, loc~) => register_type_defs(ctx, ty, loc)
    StaticAssert(static_assert) => check_static_assert(ctx, static_assert)
    Asm(asm_stmt) => check_asm_stmt(ctx, asm_stmt)
  }
}

///|
fn register_type_defs(
  ctx : SemContext,
  ty : @ast.CType,
  loc : @source.SrcLoc,
) -> Unit {
  match ty {
    Qualified(base~, ..) => register_type_defs(ctx, base, loc)
    Attributed(base~, ..) => register_type_defs(ctx, base, loc)
    Struct(name~, id~, fields~, attrs~) =>
      register_struct_def(ctx, name, id, fields, attrs, is_union=false, loc)
    Union(name~, id~, fields~, attrs~) =>
      register_struct_def(ctx, name, id, fields, attrs, is_union=true, loc)
    Enum(name~, id~, items~) => register_enum_def(ctx, name, id, items, loc)
    Pointer(inner) => register_type_defs(ctx, inner, loc)
    Array(elem~, ..) => register_type_defs(ctx, elem, loc)
    Function(return_type~, params~, ..) => {
      register_type_defs(ctx, return_type, loc)
      for param_ty in params {
        register_type_defs(ctx, param_ty, loc)
      }
    }
    _ => ()
  }
}

///|
fn register_struct_def(
  ctx : SemContext,
  name : String,
  id : Int,
  fields : Array[@ast.RecordItem]?,
  attrs : @ast.Attributes,
  is_union~ : Bool,
  loc : @source.SrcLoc,
) -> Unit {
  if name == "" {
    return
  }
  if is_union {
    if id != 0 {
      if has_opt_by_id(ctx.struct_defs_by_id, id) {
        add_sem_error(ctx, loc, "redefinition of '\{name}'")
        return
      }
    } else if ctx.struct_defs.contains(name) {
      add_sem_error(ctx, loc, "redefinition of '\{name}'")
      return
    }
  } else if id != 0 {
    if has_opt_by_id(ctx.union_defs_by_id, id) {
      add_sem_error(ctx, loc, "redefinition of '\{name}'")
      return
    }
  } else if ctx.union_defs.contains(name) {
    add_sem_error(ctx, loc, "redefinition of '\{name}'")
    return
  }
  let incoming_fields = match fields {
    None => []
    Some(val) => record_items_to_fields_checked(ctx, val)
  }
  let incoming = { fields: incoming_fields, attrs }
  let validate_fields = fn(def : RecordDef) -> Unit {
    if def.fields.length() == 0 {
      return
    }
    if is_union {
      union_size_align(ctx, def.fields, def.attrs, loc) |> ignore
    } else {
      struct_size_align(ctx, def.fields, def.attrs, loc) |> ignore
    }
  }
  if is_union {
    let existing = if id != 0 {
      get_opt_by_id(ctx.union_defs_by_id, id)
    } else {
      ctx.union_defs.get(name)
    }
    match existing {
      None => {
        ctx.union_defs.set(name, incoming)
        if id != 0 {
          set_opt_by_id(ctx.union_defs_by_id, id, incoming)
        }
        validate_fields(incoming)
      }
      Some(existing) =>
        if existing.fields.length() > 0 && incoming.fields.length() > 0 {
          if existing.fields == incoming.fields &&
            existing.attrs == incoming.attrs {
            let merged = {
              fields: existing.fields,
              attrs: @ast.merge_attrs(existing.attrs, incoming.attrs),
            }
            ctx.union_defs.set(name, merged)
            if id != 0 {
              set_opt_by_id(ctx.union_defs_by_id, id, merged)
            }
          } else {
            add_sem_error(ctx, loc, "redefinition of '\{name}'")
          }
        } else if existing.fields.length() == 0 && incoming.fields.length() > 0 {
          let merged = {
            fields: incoming.fields,
            attrs: @ast.merge_attrs(existing.attrs, incoming.attrs),
          }
          ctx.union_defs.set(name, merged)
          if id != 0 {
            set_opt_by_id(ctx.union_defs_by_id, id, merged)
          }
          validate_fields(merged)
        } else {
          let merged = {
            fields: existing.fields,
            attrs: @ast.merge_attrs(existing.attrs, incoming.attrs),
          }
          ctx.union_defs.set(name, merged)
          if id != 0 {
            set_opt_by_id(ctx.union_defs_by_id, id, merged)
          }
        }
    }
  } else {
    let existing = if id != 0 {
      get_opt_by_id(ctx.struct_defs_by_id, id)
    } else {
      ctx.struct_defs.get(name)
    }
    match existing {
      None => {
        ctx.struct_defs.set(name, incoming)
        if id != 0 {
          set_opt_by_id(ctx.struct_defs_by_id, id, incoming)
        }
        validate_fields(incoming)
      }
      Some(existing) =>
        if existing.fields.length() > 0 && incoming.fields.length() > 0 {
          if existing.fields == incoming.fields &&
            existing.attrs == incoming.attrs {
            let merged = {
              fields: existing.fields,
              attrs: @ast.merge_attrs(existing.attrs, incoming.attrs),
            }
            ctx.struct_defs.set(name, merged)
            if id != 0 {
              set_opt_by_id(ctx.struct_defs_by_id, id, merged)
            }
          } else {
            add_sem_error(ctx, loc, "redefinition of '\{name}'")
          }
        } else if existing.fields.length() == 0 && incoming.fields.length() > 0 {
          let merged = {
            fields: incoming.fields,
            attrs: @ast.merge_attrs(existing.attrs, incoming.attrs),
          }
          ctx.struct_defs.set(name, merged)
          if id != 0 {
            set_opt_by_id(ctx.struct_defs_by_id, id, merged)
          }
          validate_fields(merged)
        } else {
          let merged = {
            fields: existing.fields,
            attrs: @ast.merge_attrs(existing.attrs, incoming.attrs),
          }
          ctx.struct_defs.set(name, merged)
          if id != 0 {
            set_opt_by_id(ctx.struct_defs_by_id, id, merged)
          }
        }
    }
  }
  if incoming.fields.length() > 0 {
    for field in incoming.fields {
      register_type_defs(ctx, field.ty, field.loc)
      if field.bit_width is Some(expr) {
        if !is_int_like(field.ty) {
          add_sem_error(ctx, field.loc, "bitfields must have integer type")
        }
        if const_int_from_expr(ctx, expr, field.loc) is Some(width) {
          if width < 0 {
            add_sem_error(ctx, field.loc, "negative width in bit-field")
          }
          if width == 0 && field.name != "" {
            add_sem_error(ctx, field.loc, "zero width for bit-field")
          }
          if width > 0 {
            if type_size_align(ctx, field.ty, field.loc) is Some((size, _align)) {
              if width > size * 8 {
                add_sem_error(
                  ctx,
                  field.loc,
                  "width of '\{field.name}' exceeds its type",
                )
              }
            }
          }
        }
      }
    }
  }
}

///|
fn register_enum_def(
  ctx : SemContext,
  name : String,
  id : Int,
  items : Array[@ast.EnumItem]?,
  loc : @source.SrcLoc,
) -> Unit {
  if name == "" {
    return
  }
  let incoming = match items {
    None => []
    Some(val) => val
  }
  let existing = if id != 0 {
    get_opt_by_id(ctx.enum_defs_by_id, id)
  } else {
    ctx.enum_defs.get(name)
  }
  match existing {
    None => {
      ctx.enum_defs.set(name, incoming)
      if id != 0 {
        set_opt_by_id(ctx.enum_defs_by_id, id, incoming)
      }
    }
    Some(existing) =>
      if existing.length() > 0 && incoming.length() > 0 {
        add_sem_error(ctx, loc, "redefinition of '\{name}'")
      } else if existing.length() == 0 && incoming.length() > 0 {
        ctx.enum_defs.set(name, incoming)
        if id != 0 {
          set_opt_by_id(ctx.enum_defs_by_id, id, incoming)
        }
      }
  }
  if incoming.length() > 0 {
    let mut value = 0
    let mut min_value = 0
    let mut max_value = 0
    let mut has_value = false
    for item in incoming {
      let current = match item.value {
        None => value
        Some(expr) => eval_const_expr(ctx, expr, item.loc)
      }
      define_enum_const(ctx, item.name, item.id, item.loc, current)
      if !has_value {
        min_value = current
        max_value = current
        has_value = true
      } else {
        if current < min_value {
          min_value = current
        }
        if current > max_value {
          max_value = current
        }
      }
      value = current + 1
    }
    if has_value {
      let base = enum_int_type_from_range(min_value, max_value)
      ctx.enum_types.set(name, base)
      if id != 0 {
        set_opt_by_id(ctx.enum_types_by_id, id, base)
      }
    }
  }
}

///|
fn define_enum_const(
  ctx : SemContext,
  name : String,
  id : Int,
  loc : @source.SrcLoc,
  value : Int,
) -> Unit {
  let mut conflict = enum_const_exists(ctx, name, id)
  if !conflict {
    conflict = if id > 0 {
      has_global_by_id(ctx, id)
    } else {
      ctx.globals.contains(name)
    }
  }
  if !conflict {
    conflict = if id > 0 {
      has_function_by_id(ctx, id)
    } else {
      ctx.functions.contains(name)
    }
  }
  if conflict {
    add_sem_error(ctx, loc, "redefinition of '\{name}'")
    return
  }
  ctx.enum_consts.set(name, value)
  if id > 0 {
    set_enum_const_by_id(ctx, id, value)
  }
}

///|
fn parse_int_value(text : String) -> Int {
  parse_uint64_value(text).reinterpret_as_int64().to_int()
}

///|
fn parse_uint64_value(text : String) -> UInt64 {
  let end = int_literal_end(text)
  let base = int_literal_base_from(text, end)
  parse_uint64_literal_prefix(text, base, end)
}

///|
fn trim_int_literal(text : String) -> String {
  let end = int_literal_end(text)
  slice_string_sem(text, 0, end)
}

///|
fn int_literal_type(text : String) -> @ast.CType {
  let end = int_literal_end(text)
  let (long_count, unsigned) = parse_int_suffix_range(text, end)
  let base = int_literal_base_from(text, end)
  if base == 10 && end <= 9 && long_count == 0 && !unsigned {
    return Int(kind=Int, unsigned=false)
  }
  let value = parse_uint64_literal_prefix(text, base, end)
  let (adj_long_count, adj_unsigned) = adjust_int_literal_kind(
    value, base, long_count, unsigned,
  )
  let kind = if adj_long_count >= 2 {
    @ast.CIntKind::LongLong
  } else if adj_long_count == 1 {
    Long
  } else {
    Int
  }
  Int(kind~, unsigned=adj_unsigned)
}

///|
fn int_literal_end(text : String) -> Int {
  let len = text.length()
  if len == 0 {
    return 0
  }
  let first = text[0]
  if first == 48 {
    if len >= 2 {
      let next = text[1]
      if next == 120 || next == 88 {
        return scan_digits(text, 2, is_hex_digit_code)
      }
      if next == 98 || next == 66 {
        return scan_digits(text, 2, is_bin_digit_code)
      }
      return scan_digits(text, 1, is_oct_digit_code)
    }
    return 1
  }
  scan_digits(text, 0, is_dec_digit_code)
}

///|
fn scan_digits(text : String, start : Int, accept : (UInt16) -> Bool) -> Int {
  let mut i = start
  while i < text.length() {
    if !accept(text[i]) {
      break
    }
    i = i + 1
  }
  i
}

///|
fn slice_string_sem(text : String, start : Int, end : Int) -> String {
  text.view(start_offset=start, end_offset=end).to_string()
}

///|
fn is_dec_digit_code(code : UInt16) -> Bool {
  code >= 48 && code <= 57
}

///|
fn is_oct_digit_code(code : UInt16) -> Bool {
  code >= 48 && code <= 55
}

///|
fn is_bin_digit_code(code : UInt16) -> Bool {
  code == 48 || code == 49
}

///|
fn is_hex_digit_code(code : UInt16) -> Bool {
  is_dec_digit_code(code) ||
  (code >= 65 && code <= 70) ||
  (code >= 97 && code <= 102)
}

///|
fn _parse_uint64_literal(text : String, base : Int) -> UInt64 {
  let mut value : UInt64 = 0
  let mut i = 0
  if base == 16 &&
    text.length() >= 2 &&
    text[0] == 48 &&
    (text[1] == 120 || text[1] == 88) {
    i = 2
  } else if base == 2 &&
    text.length() >= 2 &&
    text[0] == 48 &&
    (text[1] == 98 || text[1] == 66) {
    i = 2
  } else if base == 8 && text.length() > 1 && text[0] == 48 {
    i = 1
  }
  while i < text.length() {
    let code = text[i]
    let digit = match digit_value(code) {
      None => break
      Some(v) => v
    }
    if digit >= base {
      break
    }
    value = value * base.to_uint64() + digit.to_uint64()
    i = i + 1
  }
  value
}

///|
fn parse_uint64_literal_prefix(text : String, base : Int, end : Int) -> UInt64 {
  let mut value : UInt64 = 0
  let mut i = 0
  if base == 16 &&
    end >= 2 &&
    text[0] == 48 &&
    (text[1] == 120 || text[1] == 88) {
    i = 2
  } else if base == 2 &&
    end >= 2 &&
    text[0] == 48 &&
    (text[1] == 98 || text[1] == 66) {
    i = 2
  } else if base == 8 && end > 1 && text[0] == 48 {
    i = 1
  }
  while i < end {
    let code = text[i]
    let digit = match digit_value(code) {
      None => break
      Some(v) => v
    }
    if digit >= base {
      break
    }
    value = value * base.to_uint64() + digit.to_uint64()
    i = i + 1
  }
  value
}

///|
fn digit_value(code : UInt16) -> Int? {
  if is_dec_digit_code(code) {
    Some(code.to_int() - 48)
  } else if code >= 65 && code <= 70 {
    Some(code.to_int() - 65 + 10)
  } else if code >= 97 && code <= 102 {
    Some(code.to_int() - 97 + 10)
  } else {
    None
  }
}

///|
fn _int_literal_base(text : String) -> Int {
  let trimmed = trim_int_literal(text)
  if trimmed.length() >= 2 && trimmed[0] == 48 {
    let next = trimmed[1]
    if next == 120 || next == 88 {
      return 16
    }
    if next == 98 || next == 66 {
      return 2
    }
    return 8
  }
  10
}

///|
fn int_literal_base_from(text : String, end : Int) -> Int {
  if end >= 2 && text[0] == 48 {
    let next = text[1]
    if next == 120 || next == 88 {
      return 16
    }
    if next == 98 || next == 66 {
      return 2
    }
    return 8
  }
  10
}

///|
fn _parse_int_suffix(suffix : String) -> (Int, Bool) {
  let mut long_count = 0
  let mut unsigned = false
  for code in suffix.to_lower() {
    if code == 'l' {
      long_count = long_count + 1
    } else if code == 'u' {
      unsigned = true
    }
  }
  if long_count > 2 {
    long_count = 2
  }
  (long_count, unsigned)
}

///|
fn parse_int_suffix_range(text : String, start : Int) -> (Int, Bool) {
  let mut long_count = 0
  let mut unsigned = false
  let len = text.length()
  let mut i = start
  while i < len {
    let code = text[i]
    if code == 108 || code == 76 {
      long_count = long_count + 1
    } else if code == 117 || code == 85 {
      unsigned = true
    }
    i = i + 1
  }
  if long_count > 2 {
    long_count = 2
  }
  (long_count, unsigned)
}

///|
fn adjust_int_literal_kind(
  value : UInt64,
  base : Int,
  long_count : Int,
  unsigned : Bool,
) -> (Int, Bool) {
  let mut lcount = long_count
  let mut ucount = unsigned
  if !ucount && base == 10 {
    if lcount <= 0 {
      if value >= 0x80000000 {
        lcount = 1
      }
    }
    if value >= 0x8000000000000000 {
      ucount = true
    }
  } else {
    if lcount <= 0 {
      if value >= 0x100000000 {
        lcount = 1
      } else if value >= 0x80000000 {
        ucount = true
      }
    }
    if value >= 0x8000000000000000 {
      ucount = true
    }
  }
  (lcount, ucount)
}

///|
fn float_type_from_literal(lit : String) -> @ast.CType {
  let len = lit.length()
  if len == 0 {
    return Float(kind=Double)
  }
  let last = lit[len - 1]
  if last == 102 || last == 70 {
    Float(kind=Float)
  } else if last == 108 || last == 76 {
    Float(kind=LongDouble)
  } else {
    Float(kind=Double)
  }
}

///|
fn eval_const_expr_value(
  ctx : SemContext,
  expr : @ast.Expr,
  loc : @source.SrcLoc,
) -> (Int, Bool) {
  match expr {
    IntLit(value~, ..) => (parse_int_value(value), true)
    CharLit(value~, ..) => (value, true)
    FloatLit(..) => {
      add_sem_error(ctx, loc, "invalid constant expression")
      (0, false)
    }
    StringLit(..) => {
      add_sem_error(ctx, loc, "invalid constant expression")
      (0, false)
    }
    Ident(name~, id~, ..) =>
      match enum_const_value(ctx, name, id) {
        Some(v) => (v, true)
        None => {
          add_sem_error(ctx, loc, "invalid constant expression")
          (0, false)
        }
      }
    BuiltinTypesCompatibleP(a~, b~, loc=type_loc, ..) => {
      register_type_defs(ctx, a, type_loc)
      register_type_defs(ctx, b, type_loc)
      let lhs = resolve_type(ctx, a, type_loc)
      let rhs = resolve_type(ctx, b, type_loc)
      (if types_compatible_for_decl(lhs, rhs) { 1 } else { 0 }, true)
    }
    BuiltinOffsetof(ty~, path~, loc=type_loc, ..) => {
      register_type_defs(ctx, ty, type_loc)
      match eval_builtin_offsetof(ctx, ty, path, type_loc) {
        None => (0, false)
        Some(v) => (v, true)
      }
    }
    BuiltinVaArg(..) => {
      add_sem_error(ctx, loc, "invalid constant expression")
      (0, false)
    }
    Unary(op~, expr~, ..) => {
      let (v, ok) = eval_const_expr_value(ctx, expr, loc)
      if !ok {
        return (0, false)
      }
      match op {
        Plus => (v, true)
        Minus => (0 - v, true)
        BitNot => (v ^ -1, true)
        Not => (if v == 0 { 1 } else { 0 }, true)
        _ => {
          add_sem_error(ctx, loc, "invalid constant expression")
          (0, false)
        }
      }
    }
    Binary(op~, left~, right~, ..) => {
      let (lhs, ok_lhs) = eval_const_expr_value(ctx, left, loc)
      let (rhs, ok_rhs) = eval_const_expr_value(ctx, right, loc)
      if !ok_lhs || !ok_rhs {
        return (0, false)
      }
      match op {
        Add => (lhs + rhs, true)
        Sub => (lhs - rhs, true)
        Mul => (lhs * rhs, true)
        Div =>
          if rhs == 0 {
            add_sem_error(ctx, loc, "division by zero in constant expression")
            (0, false)
          } else {
            (lhs / rhs, true)
          }
        Mod =>
          if rhs == 0 {
            add_sem_error(ctx, loc, "division by zero in constant expression")
            (0, false)
          } else {
            (lhs % rhs, true)
          }
        Shl => (lhs << rhs, true)
        Shr => (lhs >> rhs, true)
        BitAnd => (lhs & rhs, true)
        BitOr => (lhs | rhs, true)
        BitXor => (lhs ^ rhs, true)
        Eq => (if lhs == rhs { 1 } else { 0 }, true)
        Ne => (if lhs != rhs { 1 } else { 0 }, true)
        Lt => (if lhs < rhs { 1 } else { 0 }, true)
        Le => (if lhs <= rhs { 1 } else { 0 }, true)
        Gt => (if lhs > rhs { 1 } else { 0 }, true)
        Ge => (if lhs >= rhs { 1 } else { 0 }, true)
        LogAnd => (if lhs != 0 && rhs != 0 { 1 } else { 0 }, true)
        LogOr => (if lhs != 0 || rhs != 0 { 1 } else { 0 }, true)
        Comma => (rhs, true)
        _ => {
          add_sem_error(ctx, loc, "invalid constant expression")
          (0, false)
        }
      }
    }
    Conditional(cond~, then_expr~, else_expr~, ..) => {
      let (cond_val, ok) = eval_const_expr_value(ctx, cond, loc)
      if !ok {
        return (0, false)
      }
      if cond_val != 0 {
        eval_const_expr_value(ctx, then_expr, loc)
      } else {
        eval_const_expr_value(ctx, else_expr, loc)
      }
    }
    Cast(ty~, expr~, ..) => {
      let (v, ok) = eval_const_expr_value(ctx, expr, loc)
      if !ok {
        return (0, false)
      }
      let (casted, ok_cast) = cast_const_int64_value(ctx, v.to_int64(), ty, loc)
      (casted.to_int(), ok_cast)
    }
    SizeofExpr(expr~, loc~, ..) => {
      let ty = type_for_sizeof(ctx, expr)
      match strip_top_qualifiers(ty) {
        Array(size=None, size_expr=Some(_), ..) => (0, false)
        _ =>
          match type_size_align(ctx, ty, loc) {
            None => (0, false)
            Some((size, _)) => (size, true)
          }
      }
    }
    SizeofType(ty~, loc~, ..) => {
      register_type_defs(ctx, ty, loc)
      match strip_top_qualifiers(resolve_type(ctx, ty, loc)) {
        Array(size=None, size_expr=Some(_), ..) => (0, false)
        _ =>
          match type_size_align(ctx, ty, loc) {
            None => (0, false)
            Some((size, _)) => (size, true)
          }
      }
    }
    AlignofExpr(expr~, loc~, ..) => {
      let ty = type_for_sizeof(ctx, expr)
      match type_size_align(ctx, ty, loc) {
        None => (0, false)
        Some((_, align)) => (align, true)
      }
    }
    AlignofType(ty~, loc~, ..) => {
      register_type_defs(ctx, ty, loc)
      match type_size_align(ctx, ty, loc) {
        None => (0, false)
        Some((_, align)) => (align, true)
      }
    }
    Call(callee=Ident(name~, id~, ..), args~, loc=call_loc, ..) =>
      match builtin_call_kind(ctx, name, id) {
        Some(ChooseExpr) if args.length() == 3 => {
          let (cond_val, ok) = eval_const_expr_value(ctx, args[0], call_loc)
          if !ok {
            return (0, false)
          }
          if cond_val != 0 {
            eval_const_expr_value(ctx, args[1], call_loc)
          } else {
            eval_const_expr_value(ctx, args[2], call_loc)
          }
        }
        Some(Expect) if args.length() == 2 =>
          eval_const_expr_value(ctx, args[0], call_loc)
        Some(ConstantP) if args.length() == 1 =>
          (if is_constant_expr_for_builtin(ctx, args[0]) { 1 } else { 0 }, true)
        _ => {
          add_sem_error(ctx, loc, "invalid constant expression")
          (0, false)
        }
      }
    _ => {
      add_sem_error(ctx, loc, "invalid constant expression")
      (0, false)
    }
  }
}

///|
fn cast_const_int64_value(
  ctx : SemContext,
  value : Int64,
  ty : @ast.CType,
  loc : @source.SrcLoc,
) -> (Int64, Bool) {
  let resolved = resolve_type(ctx, ty, loc)
  let base = strip_top_qualifiers_keep_attrs(resolved)
  match base {
    Bool => (if value == 0 { 0 } else { 1 }, true)
    Enum(..) =>
      cast_const_int64_value(ctx, value, enum_type_for_arith(ctx, base), loc)
    Pointer(_) => (value.reinterpret_as_uint64().reinterpret_as_int64(), true)
    Int(kind~, unsigned~) => {
      let bits = int_size(kind) * 8
      let mask : UInt64 = if bits >= 64 {
        (0 : UInt64).lnot()
      } else {
        ((1 : UInt64) << bits) - (1 : UInt64)
      }
      let u = value.reinterpret_as_uint64() & mask
      if unsigned || bits >= 64 {
        (u.reinterpret_as_int64(), true)
      } else {
        let sign_bit = (1 : UInt64) << (bits - 1)
        let signed_u = if (u & sign_bit) != 0 { u | mask.lnot() } else { u }
        (signed_u.reinterpret_as_int64(), true)
      }
    }
    _ => {
      add_sem_error(ctx, loc, "invalid constant expression")
      (0, false)
    }
  }
}

///|
fn eval_const_expr_value_i64(
  ctx : SemContext,
  expr : @ast.Expr,
  loc : @source.SrcLoc,
) -> (Int64, Bool) {
  match expr {
    IntLit(value~, ..) =>
      (parse_uint64_value(value).reinterpret_as_int64(), true)
    CharLit(value~, ..) => (value.to_int64(), true)
    FloatLit(..) => {
      add_sem_error(ctx, loc, "invalid constant expression")
      (0, false)
    }
    StringLit(..) => {
      add_sem_error(ctx, loc, "invalid constant expression")
      (0, false)
    }
    Ident(name~, id~, ..) =>
      match enum_const_value(ctx, name, id) {
        Some(v) => (v.to_int64(), true)
        None => {
          add_sem_error(ctx, loc, "invalid constant expression")
          (0, false)
        }
      }
    BuiltinTypesCompatibleP(a~, b~, loc=type_loc, ..) => {
      register_type_defs(ctx, a, type_loc)
      register_type_defs(ctx, b, type_loc)
      let lhs = resolve_type(ctx, a, type_loc)
      let rhs = resolve_type(ctx, b, type_loc)
      (if types_compatible_for_decl(lhs, rhs) { 1 } else { 0 }, true)
    }
    BuiltinOffsetof(ty~, path~, loc=type_loc, ..) => {
      register_type_defs(ctx, ty, type_loc)
      match eval_builtin_offsetof(ctx, ty, path, type_loc) {
        None => (0, false)
        Some(v) => (v.to_int64(), true)
      }
    }
    BuiltinVaArg(..) => {
      add_sem_error(ctx, loc, "invalid constant expression")
      (0, false)
    }
    Unary(op~, expr~, ..) => {
      let (v, ok) = eval_const_expr_value_i64(ctx, expr, loc)
      if !ok {
        return (0, false)
      }
      match op {
        Plus => (v, true)
        Minus => (0 - v, true)
        BitNot => (v ^ (-1 : Int64), true)
        Not => (if v == 0 { 1 } else { 0 }, true)
        _ => {
          add_sem_error(ctx, loc, "invalid constant expression")
          (0, false)
        }
      }
    }
    Binary(op~, left~, right~, ..) => {
      let (lhs, ok_lhs) = eval_const_expr_value_i64(ctx, left, loc)
      let (rhs, ok_rhs) = eval_const_expr_value_i64(ctx, right, loc)
      if !ok_lhs || !ok_rhs {
        return (0, false)
      }
      match op {
        Add => (lhs + rhs, true)
        Sub => (lhs - rhs, true)
        Mul => (lhs * rhs, true)
        Div =>
          if rhs == 0 {
            add_sem_error(ctx, loc, "division by zero in constant expression")
            (0, false)
          } else {
            (lhs / rhs, true)
          }
        Mod =>
          if rhs == 0 {
            add_sem_error(ctx, loc, "division by zero in constant expression")
            (0, false)
          } else {
            (lhs % rhs, true)
          }
        Shl => (lhs << rhs.to_int(), true)
        Shr => (lhs >> rhs.to_int(), true)
        BitAnd => (lhs & rhs, true)
        BitOr => (lhs | rhs, true)
        BitXor => (lhs ^ rhs, true)
        Eq => (if lhs == rhs { 1 } else { 0 }, true)
        Ne => (if lhs != rhs { 1 } else { 0 }, true)
        Lt => (if lhs < rhs { 1 } else { 0 }, true)
        Le => (if lhs <= rhs { 1 } else { 0 }, true)
        Gt => (if lhs > rhs { 1 } else { 0 }, true)
        Ge => (if lhs >= rhs { 1 } else { 0 }, true)
        LogAnd => (if lhs != 0 && rhs != 0 { 1 } else { 0 }, true)
        LogOr => (if lhs != 0 || rhs != 0 { 1 } else { 0 }, true)
        Comma => (rhs, true)
        _ => {
          add_sem_error(ctx, loc, "invalid constant expression")
          (0, false)
        }
      }
    }
    Conditional(cond~, then_expr~, else_expr~, ..) => {
      let (cond_val, ok) = eval_const_expr_value_i64(ctx, cond, loc)
      if !ok {
        return (0, false)
      }
      if cond_val != 0 {
        eval_const_expr_value_i64(ctx, then_expr, loc)
      } else {
        eval_const_expr_value_i64(ctx, else_expr, loc)
      }
    }
    Cast(ty~, expr~, ..) => {
      let (v, ok) = eval_const_expr_value_i64(ctx, expr, loc)
      if !ok {
        return (0, false)
      }
      cast_const_int64_value(ctx, v, ty, loc)
    }
    SizeofExpr(expr~, loc~, ..) => {
      let ty = type_for_sizeof(ctx, expr)
      match strip_top_qualifiers(ty) {
        Array(size=None, size_expr=Some(_), ..) => (0, false)
        _ =>
          match type_size_align(ctx, ty, loc) {
            None => (0, false)
            Some((size, _)) => (size.to_int64(), true)
          }
      }
    }
    SizeofType(ty~, loc~, ..) => {
      register_type_defs(ctx, ty, loc)
      match strip_top_qualifiers(resolve_type(ctx, ty, loc)) {
        Array(size=None, size_expr=Some(_), ..) => (0, false)
        _ =>
          match type_size_align(ctx, ty, loc) {
            None => (0, false)
            Some((size, _)) => (size.to_int64(), true)
          }
      }
    }
    AlignofExpr(expr~, loc~, ..) => {
      let ty = type_for_sizeof(ctx, expr)
      match type_size_align(ctx, ty, loc) {
        None => (0, false)
        Some((_, align)) => (align.to_int64(), true)
      }
    }
    AlignofType(ty~, loc~, ..) => {
      register_type_defs(ctx, ty, loc)
      match type_size_align(ctx, ty, loc) {
        None => (0, false)
        Some((_, align)) => (align.to_int64(), true)
      }
    }
    Call(callee=Ident(name~, id~, ..), args~, loc=call_loc, ..) =>
      match builtin_call_kind(ctx, name, id) {
        Some(ChooseExpr) if args.length() == 3 => {
          let (cond_val, ok) = eval_const_expr_value_i64(ctx, args[0], call_loc)
          if !ok {
            return (0, false)
          }
          if cond_val != 0 {
            eval_const_expr_value_i64(ctx, args[1], call_loc)
          } else {
            eval_const_expr_value_i64(ctx, args[2], call_loc)
          }
        }
        Some(Expect) if args.length() == 2 =>
          eval_const_expr_value_i64(ctx, args[0], call_loc)
        Some(ConstantP) if args.length() == 1 =>
          (if is_constant_expr_for_builtin(ctx, args[0]) { 1 } else { 0 }, true)
        _ => {
          add_sem_error(ctx, loc, "invalid constant expression")
          (0, false)
        }
      }
    _ => {
      add_sem_error(ctx, loc, "invalid constant expression")
      (0, false)
    }
  }
}

///|
fn eval_const_expr(
  ctx : SemContext,
  expr : @ast.Expr,
  loc : @source.SrcLoc,
) -> Int {
  let (value, _) = eval_const_expr_value(ctx, expr, loc)
  value
}

///|
pub fn eval_builtin_offsetof(
  ctx : SemContext,
  ty : @ast.CType,
  path : Array[String],
  loc : @source.SrcLoc,
) -> Int? {
  match eval_builtin_offsetof_and_type(ctx, ty, path, loc, false) {
    None => None
    Some((off, _, _)) => Some(off)
  }
}

///|
fn eval_builtin_offsetof_and_type(
  ctx : SemContext,
  ty : @ast.CType,
  path : Array[String],
  loc : @source.SrcLoc,
  suppress_error : Bool,
) -> (Int, @ast.CType, Bool)? {
  if path.length() == 0 {
    add_sem_error(ctx, loc, "__builtin_offsetof expects member designator")
    return None
  }
  let mut current = resolve_type(ctx, ty, loc) |> strip_top_qualifiers
  let mut offset = 0
  for name in path {
    match strip_top_qualifiers(current) {
      Struct(name=tag, id=tag_id, fields=field_list, attrs~) =>
        match
          ensure_struct_fields(
            ctx,
            tag,
            tag_id,
            field_list,
            is_union=false,
            loc,
          ) {
          None => return None
          Some(def) =>
            match struct_field_offset_and_type(ctx, def, attrs, name, loc) {
              None =>
                if suppress_error {
                  return None
                } else {
                  add_sem_error(
                    ctx,
                    loc,
                    "unknown field '\{name}' in __builtin_offsetof",
                  )
                  return None
                }
              Some((field_off, field_ty, is_bitfield)) => {
                if is_bitfield {
                  if !suppress_error {
                    add_sem_error(
                      ctx, loc, "__builtin_offsetof does not allow bitfields",
                    )
                  }
                  return None
                }
                offset = offset + field_off
                current = resolve_type(ctx, field_ty, loc)
                  |> strip_top_qualifiers
              }
            }
        }
      Union(name=tag, id=tag_id, fields=field_list, attrs~) =>
        match
          ensure_struct_fields(ctx, tag, tag_id, field_list, is_union=true, loc) {
          None => return None
          Some(def) =>
            match union_field_offset_and_type(ctx, def, attrs, name, loc) {
              None =>
                if suppress_error {
                  return None
                } else {
                  add_sem_error(
                    ctx,
                    loc,
                    "unknown field '\{name}' in __builtin_offsetof",
                  )
                  return None
                }
              Some((field_off, field_ty, is_bitfield)) => {
                if is_bitfield {
                  if !suppress_error {
                    add_sem_error(
                      ctx, loc, "__builtin_offsetof does not allow bitfields",
                    )
                  }
                  return None
                }
                offset = offset + field_off
                current = resolve_type(ctx, field_ty, loc)
                  |> strip_top_qualifiers
              }
            }
        }
      _ => {
        if !suppress_error {
          add_sem_error(
            ctx, loc, "__builtin_offsetof expects struct/union type",
          )
        }
        return None
      }
    }
  }
  Some((offset, current, false))
}

///|
fn struct_field_offset_and_type(
  ctx : SemContext,
  def : RecordDef,
  struct_attrs : @ast.Attributes,
  name : String,
  loc : @source.SrcLoc,
) -> (Int, @ast.CType, Bool)? {
  let fields = def.fields
  let attrs = @ast.merge_attrs(def.attrs, struct_attrs)
  let mut size = 0
  let mut bit_pos = 0
  for i = 0; i < fields.length(); i = i + 1 {
    let field = fields[i]
    let packed = attrs.packed || field.attrs.packed
    let field_align_override = attr_align_value(ctx, field.attrs, field.loc)
    match field.bit_width {
      Some(expr) => {
        let width = match const_int_from_expr(ctx, expr, field.loc) {
          Some(v) => v
          None => 0
        }
        let base = strip_top_qualifiers_keep_attrs(field.ty)
        let (base_size, base_align) = match type_size_align(ctx, base, loc) {
          None => (0, 1)
          Some(v) => v
        }
        let mut field_align = base_align
        if field_align_override is Some(value) {
          field_align = value
        }
        if width == 0 {
          let used_bytes = (bit_pos + 7) / 8
          size = align_to(size + used_bytes, field_align)
          bit_pos = 0
          continue
        }
        if packed && width != 0 {
          field_align = 1
        }
        if field_align_override is Some(value) {
          field_align = value
        }
        if field_align_override is Some(_) {
          let used_bytes = (bit_pos + 7) / 8
          size = align_to(size + used_bytes, field_align)
          bit_pos = 0
        } else if !packed {
          let a8 = field_align * 8
          let max_units = if field_align > 0 {
            base_size / field_align
          } else {
            0
          }
          if a8 > 0 {
            let ofs = ((size * 8 + bit_pos) % a8 + width + a8 - 1) / a8
            if ofs > max_units {
              let used_bytes = (bit_pos + 7) / 8
              size = align_to(size + used_bytes, field_align)
              bit_pos = 0
            }
          }
        }
        while bit_pos >= field_align * 8 {
          size = size + field_align
          bit_pos = bit_pos - field_align * 8
        }
        if field.name == name {
          return Some((size, field.ty, true))
        }
        bit_pos = bit_pos + width
      }
      None => {
        if bit_pos != 0 {
          size = size + (bit_pos + 7) / 8
          bit_pos = 0
        }
        let (field_size, field_align) = match
          strip_top_qualifiers_keep_attrs(field.ty) {
          Array(elem~, size=None, size_expr~) =>
            match size_expr {
              None => {
                let (_elem_size, elem_align) = match
                  type_size_align(ctx, elem, field.loc) {
                  None => (0, 1)
                  Some(v) => v
                }
                (0, elem_align)
              }
              Some(_) =>
                match type_size_align(ctx, field.ty, field.loc) {
                  None => {
                    add_sem_error(
                      ctx,
                      field.loc,
                      "variable length array not allowed in struct",
                    )
                    (0, 1)
                  }
                  Some(v) => v
                }
            }
          _ =>
            match type_size_align(ctx, field.ty, loc) {
              None => (0, 1)
              Some(v) => v
            }
        }
        let mut adjusted_align = if packed { 1 } else { field_align }
        if field_align_override is Some(value) {
          adjusted_align = value
        }
        size = align_to(size, adjusted_align)
        if field.name == name {
          return Some((size, field.ty, false))
        }
        if field.name == "" {
          match strip_top_qualifiers(field.ty) {
            Struct(..) | Union(..) =>
              if eval_builtin_offsetof_and_type(
                  ctx,
                  field.ty,
                  [name],
                  loc,
                  true,
                )
                is Some((inner_off, inner_ty, _)) {
                return Some((size + inner_off, inner_ty, false))
              }
            _ => ()
          }
        }
        size = size + field_size
      }
    }
  }
  None
}

///|
fn union_field_offset_and_type(
  ctx : SemContext,
  def : RecordDef,
  union_attrs : @ast.Attributes,
  name : String,
  loc : @source.SrcLoc,
) -> (Int, @ast.CType, Bool)? {
  let fields = def.fields
  let _attrs = @ast.merge_attrs(def.attrs, union_attrs)
  for field in fields {
    if field.name == name {
      if field.bit_width is Some(_) {
        return Some((0, field.ty, true))
      }
      return Some((0, field.ty, false))
    }
    if field.name == "" {
      match strip_top_qualifiers(field.ty) {
        Struct(..) | Union(..) =>
          if eval_builtin_offsetof_and_type(ctx, field.ty, [name], loc, true)
            is Some((inner_off, inner_ty, _)) {
            return Some((inner_off, inner_ty, false))
          }
        _ => ()
      }
    }
  }
  None
}

///|
fn is_constant_expr_for_builtin(ctx : SemContext, expr : @ast.Expr) -> Bool {
  match expr {
    IntLit(..) | CharLit(..) => true
    Ident(name~, id~, ..) => enum_const_exists(ctx, name, id)
    Unary(op~, expr=inner, ..) =>
      match op {
        Plus | Minus | BitNot | Not => is_constant_expr_for_builtin(ctx, inner)
        _ => false
      }
    Binary(op~, left~, right~, ..) => {
      if !is_constant_expr_for_builtin(ctx, left) ||
        !is_constant_expr_for_builtin(ctx, right) {
        return false
      }
      match op {
        Div | Mod =>
          match try_eval_int_const(ctx, right) {
            Some(v) => v != 0
            None => false
          }
        _ => true
      }
    }
    Conditional(cond~, then_expr~, else_expr~, ..) =>
      match try_eval_int_const(ctx, cond) {
        Some(v) =>
          if v != 0 {
            is_constant_expr_for_builtin(ctx, then_expr)
          } else {
            is_constant_expr_for_builtin(ctx, else_expr)
          }
        None => false
      }
    Cast(expr=inner, ..) => is_constant_expr_for_builtin(ctx, inner)
    SizeofExpr(expr=inner, loc~, ..) =>
      match strip_top_qualifiers(type_for_sizeof(ctx, inner)) {
        Array(size=None, size_expr=Some(_), ..) => false
        _ => type_size_align(ctx, type_for_sizeof(ctx, inner), loc) is Some(_)
      }
    SizeofType(ty~, loc~, ..) =>
      match strip_top_qualifiers(resolve_type(ctx, ty, loc)) {
        Array(size=None, size_expr=Some(_), ..) => false
        _ => type_size_align(ctx, ty, loc) is Some(_)
      }
    AlignofExpr(expr=inner, loc~, ..) =>
      type_size_align(ctx, type_for_sizeof(ctx, inner), loc) is Some(_)
    AlignofType(ty~, loc~, ..) => type_size_align(ctx, ty, loc) is Some(_)
    BuiltinTypesCompatibleP(..) => true
    BuiltinOffsetof(..) => true
    Call(callee=Ident(name~, id~, ..), args~, ..) =>
      match builtin_call_kind(ctx, name, id) {
        Some(ChooseExpr) if args.length() == 3 =>
          match try_eval_int_const(ctx, args[0]) {
            Some(v) =>
              if v != 0 {
                is_constant_expr_for_builtin(ctx, args[1])
              } else {
                is_constant_expr_for_builtin(ctx, args[2])
              }
            None => false
          }
        Some(Expect) if args.length() == 2 =>
          is_constant_expr_for_builtin(ctx, args[0])
        Some(ConstantP) if args.length() == 1 => true
        _ => false
      }
    _ => false
  }
}

///|
pub fn try_eval_int_const(ctx : SemContext, expr : @ast.Expr) -> Int? {
  match expr {
    IntLit(value~, ..) => Some(parse_int_value(value))
    CharLit(value~, ..) => Some(value)
    Ident(name~, id~, ..) => enum_const_value(ctx, name, id)
    Unary(op~, expr~, ..) =>
      match op {
        Plus =>
          match try_eval_int_const(ctx, expr) {
            Some(v) => Some(v)
            None => None
          }
        Minus =>
          match try_eval_int_const(ctx, expr) {
            Some(v) => Some(0 - v)
            None => None
          }
        _ => None
      }
    Cast(ty~, expr~, ..) =>
      if is_pointer_type(ty) || is_int_like(ty) {
        try_eval_int_const(ctx, expr)
      } else {
        None
      }
    _ => None
  }
}

///|
fn is_null_pointer_expr(ctx : SemContext, expr : @ast.Expr) -> Bool {
  match try_eval_int_const(ctx, expr) {
    Some(v) => v == 0
    None => false
  }
}

///|
fn check_func_decl(ctx : SemContext, func_decl : @ast.FuncDecl) -> Unit {
  check_storage_class(
    ctx,
    func_decl.storage,
    func_decl.loc,
    is_local=false,
    is_function=true,
  )
  let call_conv = @ast.normalize_call_conv(func_decl.attrs.call_conv)
  let resolved_return = resolve_type(ctx, func_decl.return_type, func_decl.loc)
  let params = func_decl.params.map(param => @ast.Param::{
    name: param.name,
    id: param.id,
    ty: resolve_type(ctx, param.ty, param.loc),
    loc: param.loc,
  })
  for param in params {
    if is_void_type(param.ty) {
      add_sem_error(ctx, param.loc, "parameter declared as void")
    }
  }
  let sig = func_sig_from_params(
    resolved_return,
    params,
    func_decl.varargs,
    func_decl.is_old_style,
    call_conv,
  )
  add_function_sig(
    ctx,
    func_decl.name,
    func_decl.id,
    sig,
    func_decl.loc,
    is_def=false,
  )
}

///|
fn check_func_def(ctx : SemContext, func_def : @ast.FuncDef) -> Unit {
  check_storage_class(
    ctx,
    func_def.storage,
    func_def.loc,
    is_local=false,
    is_function=true,
  )
  let call_conv = @ast.normalize_call_conv(func_def.attrs.call_conv)
  let resolved_return = resolve_type(ctx, func_def.return_type, func_def.loc)
  let resolved_params = func_def.params.map(param => @ast.Param::{
    name: param.name,
    id: param.id,
    ty: resolve_type(ctx, param.ty, param.loc),
    loc: param.loc,
  })
  let params = if func_def.is_old_style {
    promote_old_style_params(resolved_params)
  } else {
    resolved_params
  }
  let sig = func_sig_from_params(
    resolved_return,
    params,
    func_def.varargs,
    func_def.is_old_style,
    call_conv,
  )
  add_function_sig(
    ctx,
    func_def.name,
    func_def.id,
    sig,
    func_def.loc,
    is_def=true,
  )
  let prev_func = ctx.current_func_name
  let prev_func_id = ctx.current_func_id
  let prev_agg_size = ctx.current_agg_temp_size
  let prev_agg_align = ctx.current_agg_temp_align
  ctx.current_func_name = Some(func_def.name)
  ctx.current_func_id = func_def.id
  ctx.current_agg_temp_size = 0
  ctx.current_agg_temp_align = 1
  ctx.labels_defined = @util.fast_map_new()
  ctx.labels_used = []
  ctx.loop_depth = 0
  ctx.switch_depth = 0
  push_scope(ctx)
  let func_name_ty = @ast.CType::Array(
    elem=@ast.apply_qualifiers(char_type(), @ast.with_const(@ast.empty_qual())),
    size=Some(func_def.name.length() + 1),
    size_expr=None,
  )
  declare_local(ctx, "__func__", 0, func_name_ty, func_def.loc)
  declare_local(ctx, "__FUNCTION__", 0, func_name_ty, func_def.loc)
  declare_local(ctx, "__PRETTY_FUNCTION__", 0, func_name_ty, func_def.loc)
  for param in params {
    if param.name == "" {
      add_sem_error(ctx, param.loc, "parameter name missing in definition")
    } else if is_void_type(param.ty) {
      add_sem_error(ctx, param.loc, "parameter declared as void")
    } else {
      let param_ty = adjust_param_type_for_local(param.ty)
      declare_local(ctx, param.name, param.id, param_ty, param.loc)
    }
  }
  check_stmt(ctx, func_def.body, resolved_return)
  check_label_uses(ctx)
  if func_def.id > 0 {
    set_opt_by_id(
      ctx.func_agg_temps_by_id,
      func_def.id,
      (ctx.current_agg_temp_size, ctx.current_agg_temp_align),
    )
  } else {
    ctx.func_agg_temps.set(
      func_def.name,
      (ctx.current_agg_temp_size, ctx.current_agg_temp_align),
    )
  }
  ctx.current_agg_temp_size = prev_agg_size
  ctx.current_agg_temp_align = prev_agg_align
  ctx.current_func_name = prev_func
  ctx.current_func_id = prev_func_id
  pop_scope(ctx)
}

///|
fn func_sig_from_params(
  return_type : @ast.CType,
  params : Array[@ast.Param],
  varargs : Bool,
  is_old_style : Bool,
  call_conv : @ast.CallConv,
) -> FuncSig {
  let param_types = params.map(p => adjust_param_type_for_sig(p.ty))
  { return_type, params: param_types, varargs, is_old_style, call_conv }
}

///|
fn add_function_sig(
  ctx : SemContext,
  name : String,
  id : Int,
  sig : FuncSig,
  loc : @source.SrcLoc,
  is_def~ : Bool,
) -> Unit {
  if enum_const_exists(ctx, name, id) {
    add_sem_error(ctx, loc, "redefinition of '\{name}'")
  }
  let mut updated : FuncSig? = None
  let existing = if id > 0 {
    get_function_by_id(ctx, id)
  } else {
    ctx.functions.get(name)
  }
  match existing {
    Some(existing) =>
      if !func_sig_eq(existing, sig) {
        add_sem_error(
          ctx,
          loc,
          "conflicting function declaration for '\{name}'",
        )
      } else if existing.is_old_style && !sig.is_old_style {
        ctx.functions.set(name, sig)
        updated = Some(sig)
      } else {
        updated = Some(existing)
      }
    None => {
      ctx.functions.set(name, sig)
      updated = Some(sig)
    }
  }
  if id > 0 {
    if updated is Some(resolved) {
      set_function_by_id(ctx, id, resolved)
    }
  }
  if is_def {
    if ctx.function_defs.contains(name) {
      add_sem_error(ctx, loc, "redefinition of function '\{name}'")
    } else {
      ctx.function_defs.set(name, true)
    }
  }
}

///|
fn func_sig_eq(a : FuncSig, b : FuncSig) -> Bool {
  if !types_compatible_for_decl(a.return_type, b.return_type) {
    return false
  }
  if a.call_conv != b.call_conv {
    return false
  }
  if a.is_old_style || b.is_old_style {
    return true
  }
  if a.varargs != b.varargs {
    return false
  }
  if a.params.length() != b.params.length() {
    return false
  }
  for i = 0; i < a.params.length(); i = i + 1 {
    if !types_compatible_for_decl(a.params[i], b.params[i]) {
      return false
    }
  }
  true
}

///|
pub fn apply_inferred_array_size(ty : @ast.CType, size : Int) -> @ast.CType {
  match ty {
    Qualified(qual~, base~) => {
      let updated = apply_inferred_array_size(base, size)
      Qualified(qual~, base=updated)
    }
    Array(elem~, size=arr_size, size_expr~) =>
      match (arr_size, size_expr) {
        (None, None) => Array(elem~, size=Some(size), size_expr=None)
        _ => ty
      }
    _ => ty
  }
}

///|
pub fn compound_literal_key(node_id : Int) -> Int {
  node_id
}

///|
pub fn compound_literal_type(
  ctx : SemContext,
  ty : @ast.CType,
  init : @ast.Initializer,
  loc : @source.SrcLoc,
  node_id : Int,
) -> @ast.CType {
  let key = compound_literal_key(node_id)
  match ctx.compound_literal_types.get(key) {
    Some(resolved) => resolved
    None => {
      register_type_defs(ctx, ty, loc)
      let resolved = resolve_type(ctx, ty, loc)
      let mut final_ty = resolved
      if check_initializer(ctx, resolved, init, loc) is Some(size) {
        final_ty = apply_inferred_array_size(final_ty, size)
      }
      require_complete_object_type(ctx, final_ty, loc)
      ctx.compound_literal_types.set(key, final_ty)
      final_ty
    }
  }
}

///|
fn update_decl_type(
  ctx : SemContext,
  name : String,
  id : Int,
  ty : @ast.CType,
  is_local~ : Bool,
) -> Unit {
  if is_local {
    let scope_id = current_local_scope_id(ctx)
    if scope_id == 0 || id <= 0 {
      return
    }
    if id <= ctx.local_scope_ids_by_id.length() &&
      ctx.local_scope_ids_by_id[id - 1] == scope_id {
      set_opt_by_id(ctx.local_values_by_id, id, ty)
    }
  } else if id > 0 {
    if has_global_by_id(ctx, id) {
      ctx.globals.set(name, ty)
      set_global_by_id(ctx, id, ty)
    } else if ctx.globals.contains(name) {
      ctx.globals.set(name, ty)
    }
  } else if ctx.globals.contains(name) {
    ctx.globals.set(name, ty)
  }
}

///|
pub fn record_local_binding(
  ctx : SemContext,
  id : Int,
  ty : @ast.CType,
) -> Unit {
  let scope_id = current_local_scope_id(ctx)
  if scope_id == 0 || id <= 0 {
    return
  }
  let idx = ctx.local_overrides.length() - 1
  let overrides = ctx.local_overrides[idx]
  let prev_scope = if id <= ctx.local_scope_ids_by_id.length() {
    ctx.local_scope_ids_by_id[id - 1]
  } else {
    0
  }
  overrides.push({
    id,
    prev_ty: get_opt_by_id(ctx.local_values_by_id, id),
    prev_scope,
  })
  ctx.local_overrides[idx] = overrides
  set_opt_by_id(ctx.local_values_by_id, id, ty)
  ensure_int_array_capacity(ctx.local_scope_ids_by_id, id)
  ctx.local_scope_ids_by_id[id - 1] = scope_id
}

///|
fn record_stmt_expr(ctx : SemContext) -> Unit {
  let id = ctx.current_func_id
  if id > 0 {
    set_opt_by_id(ctx.func_has_stmt_expr_by_id, id, true)
    return
  }
  if ctx.current_func_name is Some(name) {
    ctx.func_has_stmt_expr.set(name, true)
  }
}

///|
fn record_static_local(ctx : SemContext) -> Unit {
  let id = ctx.current_func_id
  if id > 0 {
    set_opt_by_id(ctx.func_has_static_local_by_id, id, true)
    return
  }
  if ctx.current_func_name is Some(name) {
    ctx.func_has_static_local.set(name, true)
  }
}

///|
fn record_local_decl(ctx : SemContext) -> Unit {
  let id = ctx.current_func_id
  if id > 0 {
    set_opt_by_id(ctx.func_has_local_decl_by_id, id, true)
    return
  }
  if ctx.current_func_name is Some(name) {
    ctx.func_has_local_decl.set(name, true)
  }
}

///|
fn record_compound_literal(
  ctx : SemContext,
  loc : @source.SrcLoc,
  node_id : Int,
  ty : @ast.CType,
) -> Unit {
  if !ctx.record_agg_temps {
    return
  }
  let key = compound_literal_key(node_id)
  let id = ctx.current_func_id
  if id > 0 {
    let keys = match get_opt_by_id(ctx.func_compound_literals_by_id, id) {
      None => []
      Some(list) => list
    }
    let mut has_key = false
    for existing in keys {
      if existing == key {
        has_key = true
      }
    }
    if !has_key {
      keys.push(key)
      set_opt_by_id(ctx.func_compound_literals_by_id, id, keys)
    }
  } else if ctx.current_func_name is Some(name) {
    ctx.func_has_compound_literal.set(name, true)
    let keys = match ctx.func_compound_literals.get(name) {
      None => []
      Some(list) => list
    }
    let mut has_key = false
    for existing in keys {
      if existing == key {
        has_key = true
      }
    }
    if !has_key {
      keys.push(key)
      ctx.func_compound_literals.set(name, keys)
    }
  }
  if !ctx.compound_literal_sizes.contains(key) {
    if type_size_align(ctx, ty, loc) is Some((size, align)) {
      if size > 0 {
        ctx.compound_literal_sizes.set(key, (size, align))
      }
    }
  }
}

///|
fn require_complete_object_type(
  ctx : SemContext,
  ty : @ast.CType,
  loc : @source.SrcLoc,
  allow_incomplete_array? : Bool = false,
) -> Unit {
  match strip_top_qualifiers(ty) {
    Array(elem~, size~, size_expr~) => {
      if size is None && size_expr is None && !allow_incomplete_array {
        add_sem_error(ctx, loc, "incomplete array type")
      }
      require_complete_object_type(ctx, elem, loc)
    }
    Struct(name=tag, id=tag_id, fields=field_list, attrs=_) =>
      ensure_struct_fields(ctx, tag, tag_id, field_list, is_union=false, loc)
      |> ignore
    Union(name=tag, id=tag_id, fields=field_list, attrs=_) =>
      ensure_struct_fields(ctx, tag, tag_id, field_list, is_union=true, loc)
      |> ignore
    Enum(name=tag, id=tag_id, items~) =>
      match items {
        Some(list) =>
          if list.length() == 0 {
            add_sem_error(ctx, loc, "incomplete enum '\{tag}'")
          } else {
            let base = enum_type_from_items(ctx, list)
            if tag != "" {
              if tag_id != 0 {
                set_opt_by_id(ctx.enum_types_by_id, tag_id, base)
              } else {
                ctx.enum_types.set(tag, base)
              }
            }
          }
        None =>
          if tag_id != 0 {
            if !has_opt_by_id(ctx.enum_types_by_id, tag_id) {
              add_sem_error(ctx, loc, "incomplete enum '\{tag}'")
            }
          } else if !ctx.enum_types.contains(tag) {
            add_sem_error(ctx, loc, "incomplete enum '\{tag}'")
          }
      }
    _ => ()
  }
}

///|
fn check_var_decl(
  ctx : SemContext,
  decl : @ast.VarDecl,
  is_local~ : Bool,
) -> Unit {
  register_type_defs(ctx, decl.ty, decl.loc)
  let resolved = resolve_type(ctx, decl.ty, decl.loc)
  let is_local = is_local && decl.storage != Extern
  if is_local {
    record_local_decl(ctx)
    if decl.storage == Static {
      record_static_local(ctx)
    }
  }
  let resolved_with_attrs = @ast.apply_type_attrs(
    resolved,
    @ast.type_attrs_from(decl.attrs),
  )
  let resolved_with_sizes = resolve_array_sizes_for_decl(
    ctx,
    resolved_with_attrs,
    is_local,
    decl.storage,
    decl.loc,
  )
  let mut final_ty = resolved_with_sizes
  match strip_top_qualifiers(resolved) {
    Function(return_type~, params~, varargs~, is_old_style~, call_conv~) => {
      check_storage_class(
        ctx,
        decl.storage,
        decl.loc,
        is_local~,
        is_function=true,
      )
      if decl.init is Some(_) {
        add_sem_error(
          ctx,
          decl.loc,
          "function declaration cannot have initializer",
        )
      }
      let sig = { return_type, params, varargs, is_old_style, call_conv }
      add_function_sig(ctx, decl.name, decl.id, sig, decl.loc, is_def=false)
      return
    }
    _ => ()
  }
  check_storage_class(ctx, decl.storage, decl.loc, is_local~, is_function=false)
  if is_void_type(final_ty) {
    add_sem_error(ctx, decl.loc, "variable '\{decl.name}' has void type")
  }
  if is_local {
    declare_local(ctx, decl.name, decl.id, final_ty, decl.loc)
  } else {
    declare_global(ctx, decl.name, decl.id, final_ty, decl.loc)
  }
  if type_has_vla_object_size(final_ty) && decl.init is Some(_) {
    add_sem_error(ctx, decl.loc, "variable length array cannot be initialized")
  } else if decl.init is Some(init) {
    if check_initializer(ctx, final_ty, init, decl.loc) is Some(size) {
      let updated = apply_inferred_array_size(final_ty, size)
      final_ty = updated
      update_decl_type(ctx, decl.name, decl.id, updated, is_local~)
    }
  }
  if decl.storage != Extern || decl.init is Some(_) {
    let allow_incomplete_array = !is_local && decl.init is None
    require_complete_object_type(
      ctx,
      final_ty,
      decl.loc,
      allow_incomplete_array~,
    )
  }
}

///|
fn check_initializer(
  ctx : SemContext,
  ty : @ast.CType,
  init : @ast.Initializer,
  loc : @source.SrcLoc,
) -> Int? {
  match init {
    Expr(expr~, ..) =>
      if is_zero_aggregate_init(ctx, ty, expr) {
        None
      } else {
        match expr {
          StringLit(length~, ..) =>
            match strip_top_qualifiers(ty) {
              Array(elem~, size~, ..) => {
                let elem_sz = match type_size_align(ctx, elem, loc) {
                  Some((sz, _)) => sz
                  None => -1
                }
                if elem_sz == 1 {
                  match size {
                    None => Some(length)
                    Some(n) => {
                      if length > n + 1 {
                        add_sem_error(
                          ctx, loc, "string literal too long for array",
                        )
                      }
                      None
                    }
                  }
                } else {
                  let init_ty = type_of_expr(ctx, expr)
                  if !can_assign(ty, init_ty) &&
                    !(is_pointer_type(ty) && is_null_pointer_expr(ctx, expr)) {
                    add_sem_error(
                      ctx,
                      loc,
                      "cannot assign '\{type_to_string(init_ty)}' to '\{type_to_string(ty)}'",
                    )
                  }
                  None
                }
              }
              _ => {
                let init_ty = type_of_expr(ctx, expr)
                if !can_assign(ty, init_ty) &&
                  !(is_pointer_type(ty) && is_null_pointer_expr(ctx, expr)) {
                  add_sem_error(
                    ctx,
                    loc,
                    "cannot assign '\{type_to_string(init_ty)}' to '\{type_to_string(ty)}'",
                  )
                }
                None
              }
            }
          _ => {
            let init_ty = type_of_expr(ctx, expr)
            if !can_assign(ty, init_ty) &&
              !(is_pointer_type(ty) && is_null_pointer_expr(ctx, expr)) {
              add_sem_error(
                ctx,
                loc,
                "cannot assign '\{type_to_string(init_ty)}' to '\{type_to_string(ty)}'",
              )
            }
            None
          }
        }
      }
    List(items~, ..) => check_initializer_list(ctx, ty, items, loc)
  }
}

///|
fn is_zero_aggregate_init(
  ctx : SemContext,
  ty : @ast.CType,
  expr : @ast.Expr,
) -> Bool {
  match try_eval_int_const(ctx, expr) {
    Some(v) if v == 0 =>
      match strip_top_qualifiers(ty) {
        Struct(..) | Union(..) | Array(..) => true
        _ => false
      }
    _ => false
  }
}

///|
fn check_initializer_list(
  ctx : SemContext,
  ty : @ast.CType,
  items : Array[@ast.InitItem],
  loc : @source.SrcLoc,
) -> Int? {
  match strip_top_qualifiers(ty) {
    Array(elem~, size~, ..) => {
      let mut next_index = 0
      let mut max_index = -1
      for item in items {
        let mut index = next_index
        let mut has_index = false
        let mut range_end : Int? = None
        let target = if item.designators.length() > 0 {
          match item.designators[0] {
            Index(expr~, loc=des_loc) =>
              if const_int_from_expr(ctx, expr, des_loc) is Some(v) {
                index = v
                has_index = true
              }
            IndexRange(start~, end~, loc=des_loc) => {
              let start_val = const_int_from_expr(ctx, start, des_loc)
              let end_val = const_int_from_expr(ctx, end, des_loc)
              match (start_val, end_val) {
                (Some(start_idx), Some(end_idx)) => {
                  index = start_idx
                  has_index = true
                  range_end = Some(end_idx)
                  if end_idx < start_idx {
                    add_sem_error(
                      ctx, des_loc, "array designator range is empty",
                    )
                  }
                }
                _ => ()
              }
            }
            _ => ()
          }
          resolve_designator_type(ctx, ty, item.designators, item.loc)
        } else {
          Some(elem)
        }
        if target is Some(target_ty) {
          check_initializer(ctx, target_ty, item.value, item.loc) |> ignore
        }
        if has_index {
          if size is None && index < 0 {
            add_sem_error(ctx, item.loc, "array designator out of bounds")
          } else if size is Some(n) {
            let end_idx = range_end.unwrap_or(index)
            if index < 0 || end_idx < 0 || index >= n || end_idx >= n {
              // TCC accepts excess array initializers and truncates them.
              ()
            }
          }
        } else if size is Some(n) {
          if index >= n {
            // TCC accepts excess array initializers and truncates them.
            ()
          }
        }
        let range_last = range_end.unwrap_or(index)
        if range_last >= 0 && range_last > max_index {
          max_index = range_last
        }
        if has_index {
          if range_last >= 0 {
            next_index = range_last + 1
          }
        } else {
          next_index = next_index + 1
        }
      }
      match size {
        None => if max_index < 0 { Some(0) } else { Some(max_index + 1) }
        Some(_) => None
      }
    }
    Struct(name=tag, id=tag_id, fields=field_list, attrs=_) => {
      let fields = resolve_struct_fields(
        ctx,
        tag,
        tag_id,
        field_list,
        is_union=false,
      )
      match fields {
        None => add_sem_error(ctx, loc, "incomplete struct '\{tag}'")
        Some(list) =>
          check_struct_initializer(ctx, ty, list, items, is_union=false, loc)
      }
      None
    }
    Union(name=tag, id=tag_id, fields=field_list, attrs=_) => {
      let fields = resolve_struct_fields(
        ctx,
        tag,
        tag_id,
        field_list,
        is_union=true,
      )
      match fields {
        None => add_sem_error(ctx, loc, "incomplete union '\{tag}'")
        Some(list) =>
          check_struct_initializer(ctx, ty, list, items, is_union=true, loc)
      }
      None
    }
    _ => {
      add_sem_error(ctx, loc, "initializer list for non-aggregate")
      None
    }
  }
}

///|
fn check_struct_initializer(
  ctx : SemContext,
  ty : @ast.CType,
  fields : Array[@ast.Field],
  items : Array[@ast.InitItem],
  is_union~ : Bool,
  loc : @source.SrcLoc,
) -> Unit {
  let mut index = 0
  let mut saw = 0
  let mut item_index = 0
  while item_index < items.length() {
    let item = items[item_index]
    if item.designators.length() > 0 {
      match item.designators[0] {
        Field(name~, id~, ..) =>
          if find_field_index_cached(ctx, ty, name, id, item.loc) is Some(idx) {
            index = idx + 1
          }
        _ => ()
      }
      if resolve_designator_type(ctx, ty, item.designators, item.loc)
        is Some(target_ty) {
        check_initializer(ctx, target_ty, item.value, item.loc) |> ignore
      }
      if is_union {
        saw = saw + 1
        if saw > 1 {
          add_sem_error(ctx, item.loc, "too many initializers for union")
        }
      }
      item_index = item_index + 1
    } else {
      match next_init_field(fields, index) {
        None => {
          add_sem_error(ctx, item.loc, "too many initializers for aggregate")
          item_index = item_index + 1
        }
        Some((field, next_index)) => {
          let mut consumed = 1
          let mut used_elision = false
          match (strip_top_qualifiers(field.ty), item.value) {
            (Array(size~, ..), Expr(expr~, ..)) =>
              match expr {
                StringLit(..) => ()
                _ => {
                  let (elided_items, count) = collect_elided_array_items(
                    items, item_index, size,
                  )
                  let init = @ast.Initializer::List(
                    items=elided_items,
                    loc=item.loc,
                  )
                  check_initializer(ctx, field.ty, init, item.loc) |> ignore
                  consumed = count
                  used_elision = true
                }
              }
            (Struct(..) | Union(..), Expr(..)) =>
              if has_single_init_field(ctx, field.ty) {
                let init = @ast.Initializer::List(
                  items=[{ designators: [], value: item.value, loc: item.loc }],
                  loc=item.loc,
                )
                check_initializer(ctx, field.ty, init, item.loc) |> ignore
                used_elision = true
              }
            _ => ()
          }
          if !used_elision {
            check_initializer(ctx, field.ty, item.value, item.loc) |> ignore
          }
          index = next_index
          if is_union {
            saw = saw + 1
            if saw > 1 {
              add_sem_error(ctx, item.loc, "too many initializers for union")
            }
          }
          item_index = item_index + consumed
        }
      }
    }
  }
  if is_union && items.length() == 0 && fields.length() == 0 {
    add_sem_error(ctx, loc, "incomplete union")
  }
}

///|
fn collect_elided_array_items(
  items : Array[@ast.InitItem],
  start : Int,
  max_count : Int?,
) -> (Array[@ast.InitItem], Int) {
  let collected : Array[@ast.InitItem] = []
  let mut idx = start
  let limit = match max_count {
    None => items.length()
    Some(n) => if n < 0 { 0 } else { start + n }
  }
  while idx < items.length() && idx < limit {
    let item = items[idx]
    if item.designators.length() > 0 {
      break
    }
    collected.push({ designators: [], value: item.value, loc: item.loc })
    idx = idx + 1
  }
  (collected, idx - start)
}

///|
fn has_single_init_field(ctx : SemContext, ty : @ast.CType) -> Bool {
  match strip_top_qualifiers(ty) {
    Struct(name=tag, id=tag_id, fields=field_list, attrs=_) => {
      let fields = resolve_struct_fields(
        ctx,
        tag,
        tag_id,
        field_list,
        is_union=false,
      )
      match fields {
        None => false
        Some(list) =>
          match next_init_field(list, 0) {
            None => false
            Some((_, next_idx)) => next_init_field(list, next_idx) is None
          }
      }
    }
    Union(name=tag, id=tag_id, fields=field_list, attrs=_) => {
      let fields = resolve_struct_fields(
        ctx,
        tag,
        tag_id,
        field_list,
        is_union=true,
      )
      match fields {
        None => false
        Some(list) =>
          match next_init_field(list, 0) {
            None => false
            Some((_, next_idx)) => next_init_field(list, next_idx) is None
          }
      }
    }
    _ => false
  }
}

///|
pub fn next_init_field(
  fields : Array[@ast.Field],
  start : Int,
) -> (@ast.Field, Int)? {
  let mut i = start
  while i < fields.length() {
    let field = fields[i]
    if field.name == "" && field.bit_width is Some(_) {
      i = i + 1
      continue
    }
    return Some((field, i + 1))
  }
  None
}

///|
pub fn const_int_from_expr(
  ctx : SemContext,
  expr : @ast.Expr,
  loc : @source.SrcLoc,
) -> Int? {
  let (value, ok) = eval_const_expr_value(ctx, expr, loc)
  if ok {
    Some(value)
  } else {
    None
  }
}

///|
pub fn const_int64_from_expr(
  ctx : SemContext,
  expr : @ast.Expr,
  loc : @source.SrcLoc,
) -> Int64? {
  let (value, ok) = eval_const_expr_value_i64(ctx, expr, loc)
  if ok {
    Some(value)
  } else {
    None
  }
}

///|
fn resolve_designator_type(
  ctx : SemContext,
  ty : @ast.CType,
  designators : Array[@ast.InitDesignator],
  loc : @source.SrcLoc,
) -> @ast.CType? {
  let mut current = strip_top_qualifiers(ty)
  for des in designators {
    match des {
      Index(expr~, loc=des_loc) =>
        match strip_top_qualifiers(current) {
          Array(elem~, size~, ..) => {
            if size is Some(n) {
              if const_int_from_expr(ctx, expr, des_loc) is Some(v) {
                if v < 0 || v >= n {
                  add_sem_error(ctx, loc, "array designator out of bounds")
                }
              }
            }
            current = elem
          }
          _ => {
            add_sem_error(ctx, loc, "array designator on non-array type")
            return None
          }
        }
      IndexRange(start~, end~, loc=des_loc) =>
        match strip_top_qualifiers(current) {
          Array(elem~, size~, ..) => {
            let start_val = const_int_from_expr(ctx, start, des_loc)
            let end_val = const_int_from_expr(ctx, end, des_loc)
            match (start_val, end_val) {
              (Some(start_idx), Some(end_idx)) =>
                if end_idx < start_idx {
                  add_sem_error(ctx, loc, "array designator range is empty")
                }
              _ => ()
            }
            if size is Some(n) {
              match (start_val, end_val) {
                (Some(start_idx), Some(end_idx)) =>
                  if start_idx < 0 ||
                    end_idx < 0 ||
                    start_idx >= n ||
                    end_idx >= n {
                    add_sem_error(ctx, loc, "array designator out of bounds")
                  }
                _ => ()
              }
            }
            current = elem
          }
          _ => {
            add_sem_error(ctx, loc, "array designator on non-array type")
            return None
          }
        }
      Field(name~, id~, ..) =>
        match strip_top_qualifiers(current) {
          Struct(name=tag, id=tag_id, fields=field_list, attrs=_) => {
            let fields = resolve_struct_fields(
              ctx,
              tag,
              tag_id,
              field_list,
              is_union=false,
            )
            match fields {
              None => {
                add_sem_error(ctx, loc, "incomplete struct '\{tag}'")
                return None
              }
              Some(list) =>
                match find_field(ctx, list, name, id) {
                  Some(field) => current = field.ty
                  None => {
                    add_sem_error(ctx, loc, "unknown field '\{name}'")
                    return None
                  }
                }
            }
          }
          Union(name=tag, id=tag_id, fields=field_list, attrs=_) => {
            let fields = resolve_struct_fields(
              ctx,
              tag,
              tag_id,
              field_list,
              is_union=true,
            )
            match fields {
              None => {
                add_sem_error(ctx, loc, "incomplete union '\{tag}'")
                return None
              }
              Some(list) =>
                match find_field(ctx, list, name, id) {
                  Some(field) => current = field.ty
                  None => {
                    add_sem_error(ctx, loc, "unknown field '\{name}'")
                    return None
                  }
                }
            }
          }
          _ => {
            add_sem_error(ctx, loc, "field designator on non-aggregate")
            return None
          }
        }
    }
  }
  Some(current)
}

///|
fn check_stmt(
  ctx : SemContext,
  stmt : @ast.Stmt,
  return_type : @ast.CType,
) -> Unit {
  match stmt {
    Compound(stmts~, ..) => {
      let mut scope_open = false
      for item in stmts {
        if !scope_open {
          match item {
            DeclStmt(..) => {
              push_scope(ctx)
              scope_open = true
            }
            _ => ()
          }
        }
        check_stmt(ctx, item, return_type)
      }
      if scope_open {
        pop_scope(ctx)
      }
    }
    If(cond~, then_branch~, else_branch~, ..) => {
      check_cond_expr(ctx, cond)
      check_stmt(ctx, then_branch, return_type)
      if else_branch is Some(stmt) {
        check_stmt(ctx, stmt, return_type)
      }
    }
    While(cond~, body~, ..) => {
      check_cond_expr(ctx, cond)
      with_loop(ctx, () => check_stmt(ctx, body, return_type))
    }
    DoWhile(cond~, body~, ..) => {
      with_loop(ctx, () => check_stmt(ctx, body, return_type))
      check_cond_expr(ctx, cond)
    }
    For(init~, cond~, step~, body~, ..) => {
      let needs_scope = init is Some(DeclStmt(..))
      if needs_scope {
        push_scope(ctx)
      }
      if init is Some(stmt) {
        check_stmt(ctx, stmt, return_type)
      }
      if cond is Some(expr) {
        check_cond_expr(ctx, expr)
      }
      if step is Some(expr) {
        type_of_expr(ctx, expr) |> ignore
      }
      with_loop(ctx, () => check_stmt(ctx, body, return_type))
      if needs_scope {
        pop_scope(ctx)
      }
    }
    Switch(cond~, body~, loc~) => {
      let cond_ty = type_of_expr(ctx, cond)
      if !is_int_like(cond_ty) {
        add_sem_error(ctx, loc, "switch expression must have integer type")
      }
      with_switch(ctx, () => check_stmt(ctx, body, return_type))
    }
    Case(expr~, end_expr~, body~, ..) => {
      if ctx.switch_depth == 0 {
        add_sem_error(ctx, @ast.expr_loc(expr), "case outside of switch")
      }
      let start = const_int_from_expr(ctx, expr, @ast.expr_loc(expr))
      if start is None {
        add_sem_error(ctx, @ast.expr_loc(expr), "case label is not constant")
      }
      let end = match end_expr {
        None => start
        Some(end_value) => {
          let end_val = const_int_from_expr(
            ctx,
            end_value,
            @ast.expr_loc(end_value),
          )
          if end_val is None {
            add_sem_error(
              ctx,
              @ast.expr_loc(end_value),
              "case label is not constant",
            )
          }
          end_val
        }
      }
      match (start, end) {
        (Some(v1), Some(v2)) =>
          register_case_range(ctx, v1, v2, @ast.expr_loc(expr))
        _ => ()
      }
      check_stmt(ctx, body, return_type)
    }
    Default(body~, loc~) => {
      if ctx.switch_depth == 0 {
        add_sem_error(ctx, loc, "default outside of switch")
      }
      if ctx.switch_stack.length() > 0 {
        let idx = ctx.switch_stack.length() - 1
        let info = ctx.switch_stack[idx]
        if info.has_default {
          add_sem_error(ctx, loc, "too many 'default'")
        } else {
          info.has_default = true
          ctx.switch_stack[idx] = info
        }
      }
      check_stmt(ctx, body, return_type)
    }
    Label(name~, body~, loc~) => {
      if ctx.labels_defined.contains(name) {
        add_sem_error(ctx, loc, "duplicate label '\{name}'")
      } else {
        ctx.labels_defined.set(name, true)
      }
      check_stmt(ctx, body, return_type)
    }
    Goto(name~, loc~) => ctx.labels_used.push((name, loc))
    GotoExpr(expr~, loc~) => {
      let expr_ty = type_of_expr(ctx, expr)
      if !is_pointer_type(expr_ty) {
        add_sem_error(ctx, loc, "computed goto expects pointer")
      }
    }
    Break(loc~) =>
      if ctx.loop_depth == 0 && ctx.switch_depth == 0 {
        add_sem_error(ctx, loc, "cannot break outside of loop or switch")
      }
    Continue(loc~) =>
      if ctx.loop_depth == 0 {
        add_sem_error(ctx, loc, "cannot continue outside of loop")
      }
    Return(value~, loc~) =>
      match value {
        None =>
          if !is_void_type(return_type) {
            add_sem_error(ctx, loc, "non-void function must return a value")
          }
        Some(expr) => {
          let expr_ty = type_of_expr(ctx, expr)
          if is_void_type(return_type) {
            add_sem_error(ctx, loc, "void function should not return a value")
          } else if !can_assign(return_type, expr_ty) &&
            !(is_pointer_type(return_type) && is_null_pointer_expr(ctx, expr)) {
            add_sem_error(
              ctx,
              loc,
              "return type '\{type_to_string(expr_ty)}' does not match '\{type_to_string(return_type)}'",
            )
          }
        }
      }
    Asm(asm_stmt) => check_asm_stmt(ctx, asm_stmt)
    ExprStmt(expr~, ..) => type_of_expr(ctx, expr) |> ignore
    DeclStmt(decls~, ..) =>
      for decl in decls {
        check_var_decl(ctx, decl, is_local=true)
      }
    TagDef(ty~, loc~) => register_type_defs(ctx, ty, loc)
    StaticAssert(static_assert) => check_static_assert(ctx, static_assert)
    Empty(..) => ()
  }
}

///|
fn check_cond_expr(ctx : SemContext, expr : @ast.Expr) -> Unit {
  let ty = type_of_expr(ctx, expr)
  if !is_scalar(ty) {
    add_sem_error(
      ctx,
      @ast.expr_loc(expr),
      "condition expression must be scalar",
    )
  }
}

///|
fn register_case_range(
  ctx : SemContext,
  start : Int,
  end : Int,
  loc : @source.SrcLoc,
) -> Unit {
  if ctx.switch_stack.length() == 0 {
    return
  }
  if start > end {
    return
  }
  let idx = ctx.switch_stack.length() - 1
  let info = ctx.switch_stack[idx]
  info.cases.push((start, end, loc))
  ctx.switch_stack[idx] = info
}

///|
fn with_loop(ctx : SemContext, f : () -> Unit) -> Unit {
  ctx.loop_depth = ctx.loop_depth + 1
  f()
  ctx.loop_depth = ctx.loop_depth - 1
}

///|
fn with_switch(ctx : SemContext, f : () -> Unit) -> Unit {
  ctx.switch_depth = ctx.switch_depth + 1
  ctx.switch_stack.push({ cases: [], has_default: false })
  f()
  if ctx.switch_stack.pop() is Some(info) {
    check_switch_cases(ctx, info)
  }
  ctx.switch_depth = ctx.switch_depth - 1
}

///|
fn check_switch_cases(ctx : SemContext, info : SwitchInfo) -> Unit {
  let cases = info.cases
  if cases.length() < 2 {
    return
  }
  cases.sort_by((a, b) => {
    let (a_start, a_end, _) = a
    let (b_start, b_end, _) = b
    if a_start < b_start {
      -1
    } else if a_start > b_start {
      1
    } else if a_end < b_end {
      -1
    } else if a_end > b_end {
      1
    } else {
      0
    }
  })
  let (_, first_end, _) = cases[0]
  let mut prev_end = first_end
  let mut i = 1
  while i < cases.length() {
    let (start, end, loc) = cases[i]
    if prev_end >= start {
      add_sem_error(ctx, loc, "duplicate case value")
    }
    if end > prev_end {
      prev_end = end
    }
    i = i + 1
  }
}

///|
fn check_label_uses(ctx : SemContext) -> Unit {
  for item in ctx.labels_used {
    let (name, loc) = item
    if !ctx.labels_defined.contains(name) {
      add_sem_error(ctx, loc, "undefined label '\{name}'")
    }
  }
}

///|
fn check_asm_stmt(ctx : SemContext, asm_stmt : @ast.AsmStmt) -> Unit {
  for op in asm_stmt.outputs {
    type_of_lvalue(ctx, op.expr) |> ignore
  }
  for op in asm_stmt.inputs {
    type_of_expr(ctx, op.expr) |> ignore
  }
  for label in asm_stmt.labels {
    ctx.labels_used.push((label, asm_stmt.loc))
  }
}

///|
fn type_eq(a : @ast.CType, b : @ast.CType) -> Bool {
  match (a, b) {
    (Qualified(base~, ..), _) => type_eq(base, b)
    (Attributed(base~, ..), _) => type_eq(base, b)
    (_, Qualified(base~, ..)) => type_eq(a, base)
    (_, Attributed(base~, ..)) => type_eq(a, base)
    (Void, Void) => true
    (Bool, Bool) => true
    (
      Int(kind=a_kind, unsigned=a_unsigned),
      Int(kind=b_kind, unsigned=b_unsigned),
    ) => a_kind == b_kind && a_unsigned == b_unsigned
    (Float(kind=a_kind), Float(kind=b_kind)) => a_kind == b_kind
    (Pointer(inner_a), Pointer(inner_b)) => type_eq(inner_a, inner_b)
    (Array(elem=elem_a, size=size_a, ..), Array(elem=elem_b, size=size_b, ..)) =>
      match (size_a, size_b) {
        (Some(sa), Some(sb)) => sa == sb && type_eq(elem_a, elem_b)
        _ => type_eq(elem_a, elem_b)
      }
    (
      Function(
        return_type=a_ret,
        params=a_params,
        varargs=a_varargs,
        is_old_style=a_old,
        call_conv=a_call
      ),
      Function(
        return_type=b_ret,
        params=b_params,
        varargs=b_varargs,
        is_old_style=b_old,
        call_conv=b_call
      ),
    ) => {
      if !type_eq(a_ret, b_ret) {
        return false
      }
      if a_call != b_call {
        return false
      }
      if a_old || b_old {
        return true
      }
      if a_varargs != b_varargs {
        return false
      }
      if a_params.length() != b_params.length() {
        return false
      }
      for i = 0; i < a_params.length(); i = i + 1 {
        if !type_eq(a_params[i], b_params[i]) {
          return false
        }
      }
      true
    }
    (Struct(name=a_name, id=a_id, ..), Struct(name=b_name, id=b_id, ..)) =>
      if a_id != 0 && b_id != 0 {
        a_id == b_id
      } else {
        a_name == b_name
      }
    (Union(name=a_name, id=a_id, ..), Union(name=b_name, id=b_id, ..)) =>
      if a_id != 0 && b_id != 0 {
        a_id == b_id
      } else {
        a_name == b_name
      }
    (Enum(name=a_name, id=a_id, ..), Enum(name=b_name, id=b_id, ..)) =>
      if a_id != 0 && b_id != 0 {
        a_id == b_id
      } else {
        a_name == b_name
      }
    _ => false
  }
}

///|
fn types_compatible_for_decl(a : @ast.CType, b : @ast.CType) -> Bool {
  match (a, b) {
    (Qualified(base~, ..), _) => types_compatible_for_decl(base, b)
    (Attributed(base~, ..), _) => types_compatible_for_decl(base, b)
    (_, Qualified(base~, ..)) => types_compatible_for_decl(a, base)
    (_, Attributed(base~, ..)) => types_compatible_for_decl(a, base)
    (Array(elem=elem_a, size=size_a, ..), Array(elem=elem_b, size=size_b, ..)) =>
      match (size_a, size_b) {
        (Some(sa), Some(sb)) =>
          sa == sb && types_compatible_for_decl(elem_a, elem_b)
        _ => types_compatible_for_decl(elem_a, elem_b)
      }
    (Pointer(inner_a), Pointer(inner_b)) =>
      types_compatible_for_decl(inner_a, inner_b)
    (
      Function(
        return_type=a_ret,
        params=a_params,
        varargs=a_varargs,
        is_old_style=a_old,
        call_conv=a_call
      ),
      Function(
        return_type=b_ret,
        params=b_params,
        varargs=b_varargs,
        is_old_style=b_old,
        call_conv=b_call
      ),
    ) => {
      if !types_compatible_for_decl(a_ret, b_ret) {
        return false
      }
      if a_call != b_call {
        return false
      }
      if a_old || b_old {
        return true
      }
      if a_varargs != b_varargs {
        return false
      }
      if a_params.length() != b_params.length() {
        return false
      }
      for i = 0; i < a_params.length(); i = i + 1 {
        if !types_compatible_for_decl(a_params[i], b_params[i]) {
          return false
        }
      }
      true
    }
    _ => type_eq(a, b)
  }
}

///|
pub fn is_int_like(ty : @ast.CType) -> Bool {
  match strip_top_qualifiers(ty) {
    Int(..) => true
    Bool => true
    Enum(..) => true
    _ => false
  }
}

///|
pub fn is_char_type(ty : @ast.CType) -> Bool {
  match strip_top_qualifiers(ty) {
    Int(kind=Char, ..) => true
    _ => false
  }
}

///|
fn is_scalar(ty : @ast.CType) -> Bool {
  if is_int_like(ty) || is_float_type(ty) {
    return true
  }
  match strip_top_qualifiers(ty) {
    Pointer(_) => true
    _ => false
  }
}

///|
fn is_pointer_type(ty : @ast.CType) -> Bool {
  match strip_top_qualifiers(ty) {
    Pointer(_) => true
    _ => false
  }
}

///|
fn is_void_pointer_type(ty : @ast.CType) -> Bool {
  match strip_top_qualifiers(ty) {
    Pointer(inner) => is_void_type(inner)
    _ => false
  }
}

///|
pub fn decay_type(ty : @ast.CType) -> @ast.CType {
  match strip_top_qualifiers(ty) {
    Array(elem~, ..) => Pointer(elem)
    Function(..) => Pointer(ty)
    _ => ty
  }
}

///|
pub fn adjust_param_type_for_local(ty : @ast.CType) -> @ast.CType {
  match ty {
    Qualified(qual~, base~) => {
      let adjusted = adjust_param_type_for_local(base)
      Qualified(qual~, base=adjusted)
    }
    Attributed(attrs~, base~) =>
      Attributed(attrs~, base=adjust_param_type_for_local(base))
    Array(elem~, ..) => Pointer(elem)
    Function(..) => Pointer(ty)
    _ => ty
  }
}

///|
fn adjust_param_type_for_sig(ty : @ast.CType) -> @ast.CType {
  let adjusted = adjust_param_type_for_local(ty)
  strip_top_qualifiers(adjusted)
}

///|
fn promote_old_style_param_type(ty : @ast.CType) -> @ast.CType {
  match ty {
    Qualified(qual~, base~) => {
      let updated = promote_old_style_param_type(base)
      Qualified(qual~, base=updated)
    }
    Attributed(attrs~, base~) =>
      Attributed(attrs~, base=promote_old_style_param_type(base))
    Float(kind=Float) => Float(kind=Double)
    _ => ty
  }
}

///|
fn promote_old_style_params(params : Array[@ast.Param]) -> Array[@ast.Param] {
  params.map(param => {
    name: param.name,
    id: param.id,
    ty: promote_old_style_param_type(param.ty),
    loc: param.loc,
  })
}

///|
fn lookup_struct_fields(
  ctx : SemContext,
  name : String,
  id : Int,
  is_union~ : Bool,
) -> Array[@ast.Field]? {
  match lookup_struct_def(ctx, name, id, is_union~) {
    Some(def) => Some(def.fields)
    None => None
  }
}

///|
fn lookup_struct_def(
  ctx : SemContext,
  name : String,
  id : Int,
  is_union~ : Bool,
) -> RecordDef? {
  if id != 0 {
    let def = if is_union {
      get_opt_by_id(ctx.union_defs_by_id, id)
    } else {
      get_opt_by_id(ctx.struct_defs_by_id, id)
    }
    match def {
      None => None
      Some(def) => if def.fields.length() == 0 { None } else { Some(def) }
    }
  } else {
    let defs = if is_union { ctx.union_defs } else { ctx.struct_defs }
    match defs.get(name) {
      None => None
      Some(def) => if def.fields.length() == 0 { None } else { Some(def) }
    }
  }
}

///|
pub fn resolve_struct_fields(
  ctx : SemContext,
  tag : String,
  tag_id : Int,
  fields : Array[@ast.RecordItem]?,
  is_union~ : Bool,
) -> Array[@ast.Field]? {
  if tag != "" {
    if lookup_struct_fields(ctx, tag, tag_id, is_union~) is Some(list) {
      return Some(list)
    }
  }
  match fields {
    Some(list) => Some(record_items_to_fields(list))
    None => None
  }
}

///|
fn find_field(
  ctx : SemContext,
  fields : Array[@ast.Field],
  name : String,
  id : Int,
) -> @ast.Field? {
  for field in fields {
    if (id > 0 && field.id == id) || field.name == name {
      return Some(field)
    }
    if field.name == "" {
      match strip_top_qualifiers(field.ty) {
        Struct(name=tag, id=tag_id, fields=field_list, attrs=_) => {
          let nested = resolve_struct_fields(
            ctx,
            tag,
            tag_id,
            field_list,
            is_union=false,
          )
          if nested is Some(list) {
            if find_field(ctx, list, name, id) is Some(found) {
              return Some(found)
            }
          }
        }
        Union(name=tag, id=tag_id, fields=field_list, attrs=_) => {
          let nested = resolve_struct_fields(
            ctx,
            tag,
            tag_id,
            field_list,
            is_union=true,
          )
          if nested is Some(list) {
            if find_field(ctx, list, name, id) is Some(found) {
              return Some(found)
            }
          }
        }
        _ => ()
      }
    }
  }
  None
}

///|
fn find_field_index(
  ctx : SemContext,
  fields : Array[@ast.Field],
  name : String,
  id : Int,
) -> Int? {
  for i = 0; i < fields.length(); i = i + 1 {
    if (id > 0 && fields[i].id == id) || fields[i].name == name {
      return Some(i)
    }
    if fields[i].name == "" {
      match strip_top_qualifiers(fields[i].ty) {
        Struct(name=tag, id=tag_id, fields=field_list, attrs=_) => {
          let nested = resolve_struct_fields(
            ctx,
            tag,
            tag_id,
            field_list,
            is_union=false,
          )
          if nested is Some(list) {
            if find_field(ctx, list, name, id) is Some(_) {
              return Some(i)
            }
          }
        }
        Union(name=tag, id=tag_id, fields=field_list, attrs=_) => {
          let nested = resolve_struct_fields(
            ctx,
            tag,
            tag_id,
            field_list,
            is_union=true,
          )
          if nested is Some(list) {
            if find_field(ctx, list, name, id) is Some(_) {
              return Some(i)
            }
          }
        }
        _ => ()
      }
    }
  }
  None
}

///|
fn collect_field_index_cache_from_field(
  ctx : SemContext,
  field : @ast.Field,
  top_index : Int,
  loc : @source.SrcLoc,
  cache_by_name : @util.FastMap[String, Int],
  cache_by_id : @util.FastMap[Int, Int],
) -> Unit {
  if field.name != "" {
    if !cache_by_name.contains(field.name) {
      cache_by_name.set(field.name, top_index)
    }
    if field.id > 0 && !cache_by_id.contains(field.id) {
      cache_by_id.set(field.id, top_index)
    }
    return
  }
  match strip_top_qualifiers(field.ty) {
    Struct(name=tag, id=tag_id, fields=field_list, attrs=_) => {
      let nested = ensure_struct_fields(
        ctx,
        tag,
        tag_id,
        field_list,
        is_union=false,
        loc,
      )
      if nested is Some(def) {
        for nested_field in def.fields {
          collect_field_index_cache_from_field(
            ctx, nested_field, top_index, loc, cache_by_name, cache_by_id,
          )
        }
      }
    }
    Union(name=tag, id=tag_id, fields=field_list, attrs=_) => {
      let nested = ensure_struct_fields(
        ctx,
        tag,
        tag_id,
        field_list,
        is_union=true,
        loc,
      )
      if nested is Some(def) {
        for nested_field in def.fields {
          collect_field_index_cache_from_field(
            ctx, nested_field, top_index, loc, cache_by_name, cache_by_id,
          )
        }
      }
    }
    _ => ()
  }
}

///|
fn build_field_index_caches(
  ctx : SemContext,
  fields : Array[@ast.Field],
  loc : @source.SrcLoc,
) -> (@util.FastMap[String, Int], @util.FastMap[Int, Int]) {
  let cache_by_name : @util.FastMap[String, Int] = @util.fast_map_new()
  let cache_by_id : @util.FastMap[Int, Int] = @util.fast_map_new()
  for i = 0; i < fields.length(); i = i + 1 {
    collect_field_index_cache_from_field(
      ctx,
      fields[i],
      i,
      loc,
      cache_by_name,
      cache_by_id,
    )
  }
  (cache_by_name, cache_by_id)
}

///|
pub fn find_field_index_cached(
  ctx : SemContext,
  record_ty : @ast.CType,
  name : String,
  id : Int,
  loc : @source.SrcLoc,
) -> Int? {
  let resolved = resolve_type(ctx, record_ty, loc) |> strip_top_qualifiers
  match resolved {
    Struct(name=tag, id=tag_id, fields=field_list, attrs=_) =>
      match
        ensure_struct_fields(ctx, tag, tag_id, field_list, is_union=false, loc) {
        None => None
        Some(def) =>
          if tag != "" &&
            (if tag_id != 0 {
              has_opt_by_id(ctx.struct_defs_by_id, tag_id)
            } else {
              ctx.struct_defs.contains(tag)
            }) {
            if id > 0 && tag_id != 0 {
              let cache = match
                get_opt_by_id(ctx.struct_field_index_cache_by_id, tag_id) {
                Some(existing) => existing
                None => {
                  let (built_name, built_id) = build_field_index_caches(
                    ctx,
                    def.fields,
                    loc,
                  )
                  set_opt_by_id(
                    ctx.struct_field_index_cache_by_id,
                    tag_id,
                    built_id,
                  )
                  ctx.struct_field_index_cache.set(tag, built_name)
                  built_id
                }
              }
              match cache.get(id) {
                Some(idx) => Some(idx)
                None =>
                  if name == "" {
                    None
                  } else {
                    match ctx.struct_field_index_cache.get(tag) {
                      Some(by_name) => by_name.get(name)
                      None => None
                    }
                  }
              }
            } else {
              let cache = match ctx.struct_field_index_cache.get(tag) {
                Some(existing) => existing
                None => {
                  let (built_name, built_id) = build_field_index_caches(
                    ctx,
                    def.fields,
                    loc,
                  )
                  ctx.struct_field_index_cache.set(tag, built_name)
                  if tag_id != 0 {
                    set_opt_by_id(
                      ctx.struct_field_index_cache_by_id,
                      tag_id,
                      built_id,
                    )
                  }
                  built_name
                }
              }
              cache.get(name)
            }
          } else {
            find_field_index(ctx, def.fields, name, id)
          }
      }
    Union(name=tag, id=tag_id, fields=field_list, attrs=_) =>
      match
        ensure_struct_fields(ctx, tag, tag_id, field_list, is_union=true, loc) {
        None => None
        Some(def) =>
          if tag != "" &&
            (if tag_id != 0 {
              has_opt_by_id(ctx.union_defs_by_id, tag_id)
            } else {
              ctx.union_defs.contains(tag)
            }) {
            if id > 0 && tag_id != 0 {
              let cache = match
                get_opt_by_id(ctx.union_field_index_cache_by_id, tag_id) {
                Some(existing) => existing
                None => {
                  let (built_name, built_id) = build_field_index_caches(
                    ctx,
                    def.fields,
                    loc,
                  )
                  set_opt_by_id(
                    ctx.union_field_index_cache_by_id,
                    tag_id,
                    built_id,
                  )
                  ctx.union_field_index_cache.set(tag, built_name)
                  built_id
                }
              }
              match cache.get(id) {
                Some(idx) => Some(idx)
                None =>
                  if name == "" {
                    None
                  } else {
                    match ctx.union_field_index_cache.get(tag) {
                      Some(by_name) => by_name.get(name)
                      None => None
                    }
                  }
              }
            } else {
              let cache = match ctx.union_field_index_cache.get(tag) {
                Some(existing) => existing
                None => {
                  let (built_name, built_id) = build_field_index_caches(
                    ctx,
                    def.fields,
                    loc,
                  )
                  ctx.union_field_index_cache.set(tag, built_name)
                  if tag_id != 0 {
                    set_opt_by_id(
                      ctx.union_field_index_cache_by_id,
                      tag_id,
                      built_id,
                    )
                  }
                  built_name
                }
              }
              cache.get(name)
            }
          } else {
            find_field_index(ctx, def.fields, name, id)
          }
      }
    _ => None
  }
}

///|
fn collect_member_cache_from_fields(
  ctx : SemContext,
  fields : Array[@ast.Field],
  qual : @ast.TypeQual,
  loc : @source.SrcLoc,
  cache_by_name : @util.FastMap[String, @ast.CType],
  cache_by_id : @util.FastMap[Int, @ast.CType],
) -> Unit {
  for field in fields {
    let (field_qual, _) = split_top_qual(field.ty)
    let combined = @ast.merge_qual(qual, field_qual)
    if field.name != "" {
      if !cache_by_name.contains(field.name) {
        cache_by_name.set(field.name, @ast.apply_qualifiers(field.ty, qual))
      }
      if field.id > 0 && !cache_by_id.contains(field.id) {
        cache_by_id.set(field.id, @ast.apply_qualifiers(field.ty, qual))
      }
      continue
    }
    match strip_top_qualifiers(field.ty) {
      Struct(name=tag, id=tag_id, fields=field_list, attrs=_) => {
        let def = ensure_struct_fields(
          ctx,
          tag,
          tag_id,
          field_list,
          is_union=false,
          loc,
        )
        if def is Some(def_val) {
          collect_member_cache_from_fields(
            ctx,
            def_val.fields,
            combined,
            loc,
            cache_by_name,
            cache_by_id,
          )
        }
      }
      Union(name=tag, id=tag_id, fields=field_list, attrs=_) => {
        let def = ensure_struct_fields(
          ctx,
          tag,
          tag_id,
          field_list,
          is_union=true,
          loc,
        )
        if def is Some(def_val) {
          collect_member_cache_from_fields(
            ctx,
            def_val.fields,
            combined,
            loc,
            cache_by_name,
            cache_by_id,
          )
        }
      }
      _ => ()
    }
  }
}

///|
fn build_member_caches(
  ctx : SemContext,
  fields : Array[@ast.Field],
  loc : @source.SrcLoc,
) -> (@util.FastMap[String, @ast.CType], @util.FastMap[Int, @ast.CType]) {
  let cache_by_name : @util.FastMap[String, @ast.CType] = @util.fast_map_new()
  let cache_by_id : @util.FastMap[Int, @ast.CType] = @util.fast_map_new()
  collect_member_cache_from_fields(
    ctx,
    fields,
    @ast.empty_qual(),
    loc,
    cache_by_name,
    cache_by_id,
  )
  (cache_by_name, cache_by_id)
}

///|
fn member_access_search(
  ctx : SemContext,
  ty : @ast.CType,
  qual : @ast.TypeQual,
  name : String,
  id : Int,
  loc : @source.SrcLoc,
) -> @ast.CType? {
  match strip_top_qualifiers(ty) {
    Struct(name=tag, id=tag_id, fields=field_list, attrs=_) => {
      let def = ensure_struct_fields(
        ctx,
        tag,
        tag_id,
        field_list,
        is_union=false,
        loc,
      )
      match def {
        None => None
        Some(def_val) => {
          for field in def_val.fields {
            let (field_qual, _) = split_top_qual(field.ty)
            let combined = @ast.merge_qual(qual, field_qual)
            if (id > 0 && field.id == id) || field.name == name {
              return Some(@ast.apply_qualifiers(field.ty, qual))
            }
            if field.name == "" {
              if member_access_search(ctx, field.ty, combined, name, id, loc)
                is Some(found) {
                return Some(found)
              }
            }
          }
          None
        }
      }
    }
    Union(name=tag, id=tag_id, fields=field_list, attrs=_) => {
      let def = ensure_struct_fields(
        ctx,
        tag,
        tag_id,
        field_list,
        is_union=true,
        loc,
      )
      match def {
        None => None
        Some(def_val) => {
          for field in def_val.fields {
            let (field_qual, _) = split_top_qual(field.ty)
            let combined = @ast.merge_qual(qual, field_qual)
            if (id > 0 && field.id == id) || field.name == name {
              return Some(@ast.apply_qualifiers(field.ty, qual))
            }
            if field.name == "" {
              if member_access_search(ctx, field.ty, combined, name, id, loc)
                is Some(found) {
                return Some(found)
              }
            }
          }
          None
        }
      }
    }
    _ => None
  }
}

///|
fn member_access_type(
  ctx : SemContext,
  base_ty : @ast.CType,
  name : String,
  id : Int,
  is_arrow~ : Bool,
  loc : @source.SrcLoc,
) -> @ast.CType? {
  let obj_ty = if is_arrow {
    match strip_top_qualifiers(base_ty) {
      Pointer(inner) => inner
      _ => {
        add_sem_error(ctx, loc, "arrow operator requires pointer")
        return None
      }
    }
  } else {
    base_ty
  }
  let (obj_qual, obj_base) = split_top_qual(obj_ty)
  match strip_top_qualifiers(obj_base) {
    Struct(name=tag, id=tag_id, fields=field_list, attrs=_) => {
      let def = ensure_struct_fields(
        ctx,
        tag,
        tag_id,
        field_list,
        is_union=false,
        loc,
      )
      match def {
        None => None
        Some(def_val) =>
          if tag != "" {
            if id > 0 && tag_id != 0 {
              let cache = match
                get_opt_by_id(ctx.struct_member_cache_by_id, tag_id) {
                Some(existing) => existing
                None => {
                  let (built_name, built_id) = build_member_caches(
                    ctx,
                    def_val.fields,
                    loc,
                  )
                  set_opt_by_id(ctx.struct_member_cache_by_id, tag_id, built_id)
                  ctx.struct_member_cache.set(tag, built_name)
                  built_id
                }
              }
              match cache.get(id) {
                Some(ty) => Some(@ast.apply_qualifiers(ty, obj_qual))
                None => {
                  let msg = "unknown field '\{name}' in \{type_to_string(obj_base)}"
                  add_sem_error(ctx, loc, msg)
                  None
                }
              }
            } else {
              let cache = match ctx.struct_member_cache.get(tag) {
                Some(existing) => existing
                None => {
                  let (built_name, built_id) = build_member_caches(
                    ctx,
                    def_val.fields,
                    loc,
                  )
                  ctx.struct_member_cache.set(tag, built_name)
                  if tag_id != 0 {
                    set_opt_by_id(
                      ctx.struct_member_cache_by_id,
                      tag_id,
                      built_id,
                    )
                  }
                  built_name
                }
              }
              match cache.get(name) {
                Some(ty) => Some(@ast.apply_qualifiers(ty, obj_qual))
                None => {
                  let msg = "unknown field '\{name}' in \{type_to_string(obj_base)}"
                  add_sem_error(ctx, loc, msg)
                  None
                }
              }
            }
          } else {
            match member_access_search(ctx, obj_base, obj_qual, name, id, loc) {
              Some(ty) => Some(ty)
              None => {
                let msg = "unknown field '\{name}' in \{type_to_string(obj_base)}"
                add_sem_error(ctx, loc, msg)
                None
              }
            }
          }
      }
    }
    Union(name=tag, id=tag_id, fields=field_list, attrs=_) => {
      let def = ensure_struct_fields(
        ctx,
        tag,
        tag_id,
        field_list,
        is_union=true,
        loc,
      )
      match def {
        None => None
        Some(def_val) =>
          if tag != "" {
            if id > 0 && tag_id != 0 {
              let cache = match
                get_opt_by_id(ctx.union_member_cache_by_id, tag_id) {
                Some(existing) => existing
                None => {
                  let (built_name, built_id) = build_member_caches(
                    ctx,
                    def_val.fields,
                    loc,
                  )
                  set_opt_by_id(ctx.union_member_cache_by_id, tag_id, built_id)
                  ctx.union_member_cache.set(tag, built_name)
                  built_id
                }
              }
              match cache.get(id) {
                Some(ty) => Some(@ast.apply_qualifiers(ty, obj_qual))
                None => {
                  let msg = "unknown field '\{name}' in \{type_to_string(obj_base)}"
                  add_sem_error(ctx, loc, msg)
                  None
                }
              }
            } else {
              let cache = match ctx.union_member_cache.get(tag) {
                Some(existing) => existing
                None => {
                  let (built_name, built_id) = build_member_caches(
                    ctx,
                    def_val.fields,
                    loc,
                  )
                  ctx.union_member_cache.set(tag, built_name)
                  if tag_id != 0 {
                    set_opt_by_id(
                      ctx.union_member_cache_by_id,
                      tag_id,
                      built_id,
                    )
                  }
                  built_name
                }
              }
              match cache.get(name) {
                Some(ty) => Some(@ast.apply_qualifiers(ty, obj_qual))
                None => {
                  let msg = "unknown field '\{name}' in \{type_to_string(obj_base)}"
                  add_sem_error(ctx, loc, msg)
                  None
                }
              }
            }
          } else {
            match member_access_search(ctx, obj_base, obj_qual, name, id, loc) {
              Some(ty) => Some(ty)
              None => {
                let msg = "unknown field '\{name}' in \{type_to_string(obj_base)}"
                add_sem_error(ctx, loc, msg)
                None
              }
            }
          }
      }
    }
    _ => {
      add_sem_error(ctx, loc, "member access on non-aggregate")
      None
    }
  }
}

///|
fn index_access_type(
  ctx : SemContext,
  base_ty : @ast.CType,
  index_ty : @ast.CType,
  loc : @source.SrcLoc,
) -> @ast.CType? {
  if is_int_like(index_ty) {
    match strip_top_qualifiers(base_ty) {
      Pointer(elem) => Some(elem)
      Array(elem~, ..) => Some(elem)
      _ => {
        add_sem_error(ctx, loc, "subscripted value is not an array")
        None
      }
    }
  } else if is_int_like(base_ty) {
    match strip_top_qualifiers(index_ty) {
      Pointer(elem) => Some(elem)
      Array(elem~, ..) => Some(elem)
      _ => {
        add_sem_error(ctx, loc, "array index must be int")
        None
      }
    }
  } else {
    add_sem_error(ctx, loc, "array index must be int")
    None
  }
}

///|
pub fn type_of_lvalue(ctx : SemContext, expr : @ast.Expr) -> @ast.CType? {
  match expr {
    Ident(name~, id~, loc~, ..) =>
      if enum_const_exists(ctx, name, id) {
        add_sem_error(ctx, loc, "expression is not assignable")
        None
      } else {
        match lookup_value(ctx, name, id) {
          Some(ty) => Some(ty)
          None => {
            add_sem_error(ctx, loc, "use of undeclared identifier '\{name}'")
            None
          }
        }
      }
    Index(base~, index~, loc~, ..) =>
      match
        index_access_type(
          ctx,
          type_of_expr(ctx, base),
          type_of_expr(ctx, index),
          loc,
        ) {
        Some(ty) => Some(ty)
        None => None
      }
    Member(base~, name~, id~, is_arrow~, loc~, ..) =>
      member_access_type(ctx, type_of_expr(ctx, base), name, id, is_arrow~, loc)
    Unary(op=Deref, expr=inner, loc~, ..) => {
      let inner_ty = type_of_expr(ctx, inner)
      match strip_top_qualifiers(inner_ty) {
        Pointer(pointee) => Some(pointee)
        _ => {
          add_sem_error(ctx, loc, "cannot dereference non-pointer")
          None
        }
      }
    }
    CompoundLiteral(ty~, init~, node_id~, loc~) => {
      let resolved = compound_literal_type(ctx, ty, init, loc, node_id)
      record_compound_literal(ctx, loc, node_id, resolved)
      Some(resolved)
    }
    StmtExpr(stmts~, loc~, ..) => stmt_expr_lvalue_type(ctx, stmts, loc)
    _ => {
      add_sem_error(ctx, @ast.expr_loc(expr), "expression is not assignable")
      None
    }
  }
}

///|
fn type_of_lvalue_optional(ctx : SemContext, expr : @ast.Expr) -> @ast.CType? {
  match expr {
    Ident(name~, id~, ..) =>
      if enum_const_exists(ctx, name, id) {
        None
      } else {
        match lookup_value(ctx, name, id) {
          Some(ty) => Some(ty)
          None => None
        }
      }
    Index(base~, index~, loc~, ..) =>
      match
        index_access_type(
          ctx,
          type_of_expr_impl(ctx, base),
          type_of_expr_impl(ctx, index),
          loc,
        ) {
        Some(ty) => Some(ty)
        None => None
      }
    Member(base~, name~, id~, is_arrow~, loc~, ..) =>
      member_access_type(
        ctx,
        type_of_expr_impl(ctx, base),
        name,
        id,
        is_arrow~,
        loc,
      )
    Unary(op=Deref, expr=inner, loc~, ..) => {
      let inner_ty = type_of_expr_impl(ctx, inner)
      match strip_top_qualifiers(inner_ty) {
        Pointer(pointee) => Some(pointee)
        _ => {
          add_sem_error(ctx, loc, "cannot dereference non-pointer")
          None
        }
      }
    }
    CompoundLiteral(ty~, init~, node_id~, loc~) => {
      let resolved = compound_literal_type(ctx, ty, init, loc, node_id)
      record_compound_literal(ctx, loc, node_id, resolved)
      Some(resolved)
    }
    StmtExpr(stmts~, loc~, ..) => stmt_expr_lvalue_type(ctx, stmts, loc)
    _ => None
  }
}

///|
fn current_return_type(ctx : SemContext) -> @ast.CType {
  match ctx.current_func_name {
    None => Void
    Some(name) =>
      match ctx.functions.get(name) {
        Some(sig) => sig.return_type
        None => Void
      }
  }
}

///|
fn stmt_expr_result_type(
  ctx : SemContext,
  stmts : Array[@ast.Stmt],
  _loc : @source.SrcLoc,
) -> @ast.CType {
  record_stmt_expr(ctx)
  let return_type = current_return_type(ctx)
  push_scope(ctx)
  let mut result = @ast.CType::Void
  let len = stmts.length()
  if len == 0 {
    pop_scope(ctx)
    return result
  }
  for i = 0; i < len; i = i + 1 {
    let stmt = stmts[i]
    if i + 1 == len {
      match stmt {
        ExprStmt(expr~, ..) => result = type_of_expr(ctx, expr)
        _ => {
          check_stmt(ctx, stmt, return_type)
          result = Void
        }
      }
    } else {
      check_stmt(ctx, stmt, return_type)
    }
  }
  pop_scope(ctx)
  result
}

///|
fn stmt_expr_lvalue_type(
  ctx : SemContext,
  stmts : Array[@ast.Stmt],
  loc : @source.SrcLoc,
) -> @ast.CType? {
  record_stmt_expr(ctx)
  let return_type = current_return_type(ctx)
  push_scope(ctx)
  let mut result : @ast.CType? = None
  let len = stmts.length()
  if len == 0 {
    pop_scope(ctx)
    add_sem_error(ctx, loc, "statement expression is not assignable")
    return None
  }
  for i = 0; i < len; i = i + 1 {
    let stmt = stmts[i]
    if i + 1 == len {
      match stmt {
        ExprStmt(expr~, ..) => result = type_of_lvalue(ctx, expr)
        _ => {
          check_stmt(ctx, stmt, return_type)
          add_sem_error(ctx, loc, "statement expression is not assignable")
          result = None
        }
      }
    } else {
      check_stmt(ctx, stmt, return_type)
    }
  }
  pop_scope(ctx)
  result
}

///|
fn ensure_expr_type_cache(ctx : SemContext, id : Int) -> Unit {
  if id <= 0 {
    return
  }
  let cache_len = ctx.expr_type_cache.length()
  if cache_len >= id {
    return
  }
  let mut i = cache_len
  while i < id {
    ctx.expr_type_cache.push(None)
    i = i + 1
  }
}

///|

///|
pub fn type_of_expr(ctx : SemContext, expr : @ast.Expr) -> @ast.CType {
  let id = @ast.expr_node_id(expr)
  let ty = if id > 0 {
    let idx = id - 1
    let cache_len = ctx.expr_type_cache.length()
    if idx < cache_len {
      match ctx.expr_type_cache[idx] {
        Some(found) => found
        None => {
          let computed = type_of_expr_impl(ctx, expr)
          ctx.expr_type_cache[idx] = Some(computed)
          computed
        }
      }
    } else {
      let computed = type_of_expr_impl(ctx, expr)
      ensure_expr_type_cache(ctx, id)
      ctx.expr_type_cache[idx] = Some(computed)
      computed
    }
  } else {
    type_of_expr_impl(ctx, expr)
  }
  if ctx.record_agg_temps {
    if ctx.current_func_name is Some(_) {
      maybe_record_agg_temp_for_expr(ctx, expr, ty)
    }
  }
  ty
}

///|
fn type_of_expr_impl(ctx : SemContext, expr : @ast.Expr) -> @ast.CType {
  match expr {
    IntLit(value~, ..) => int_literal_type(value)
    FloatLit(value~, ..) => float_type_from_literal(value)
    CharLit(..) => default_int_type()
    StringLit(..) => Pointer(char_type())
    Ident(name~, id~, loc~, ..) =>
      match lookup_value(ctx, name, id) {
        Some(ty) => decay_type(ty)
        None => {
          add_sem_error(ctx, loc, "use of undeclared identifier '\{name}'")
          default_int_type()
        }
      }
    LabelAddr(name~, loc~, ..) => {
      if ctx.current_func_name is None {
        add_sem_error(ctx, loc, "label address used outside of function")
      }
      ctx.labels_used.push((name, loc))
      void_pointer_type()
    }
    BuiltinTypesCompatibleP(a~, b~, loc~, ..) => {
      register_type_defs(ctx, a, loc)
      register_type_defs(ctx, b, loc)
      default_int_type()
    }
    BuiltinOffsetof(ty~, path~, loc~, ..) => {
      register_type_defs(ctx, ty, loc)
      ignore(eval_builtin_offsetof(ctx, ty, path, loc))
      size_t_type()
    }
    BuiltinVaArg(list~, ty~, loc~, ..) => {
      ignore(type_of_expr(ctx, list))
      register_type_defs(ctx, ty, loc)
      resolve_type(ctx, ty, loc)
    }
    CompoundLiteral(ty~, init~, node_id~, loc~) => {
      let resolved = compound_literal_type(ctx, ty, init, loc, node_id)
      record_compound_literal(ctx, loc, node_id, resolved)
      decay_type(resolved)
    }
    StmtExpr(stmts~, loc~, ..) => stmt_expr_result_type(ctx, stmts, loc)
    Unary(op~, expr~, loc~, ..) =>
      match op {
        Addr =>
          match type_of_lvalue(ctx, expr) {
            Some(ty) => Pointer(ty)
            None => default_int_type()
          }
        Deref => {
          let inner = type_of_expr(ctx, expr)
          match strip_top_qualifiers(inner) {
            Pointer(pointee) => pointee
            _ => {
              add_sem_error(ctx, loc, "cannot dereference non-pointer")
              default_int_type()
            }
          }
        }
        Not => {
          let inner = type_of_expr(ctx, expr)
          if !is_scalar(inner) {
            add_sem_error(ctx, loc, "unary operator expects scalar")
          }
          default_int_type()
        }
        Plus | Minus => {
          let inner = type_of_expr(ctx, expr)
          if !is_arithmetic(inner) {
            add_sem_error(ctx, loc, "unary operator expects arithmetic")
          }
          if is_float_type(inner) {
            strip_top_qualifiers(inner)
          } else {
            common_int_type(ctx, inner, inner)
          }
        }
        BitNot => {
          let inner = type_of_expr(ctx, expr)
          if !is_int_like(inner) {
            add_sem_error(ctx, loc, "unary operator expects int")
          }
          common_int_type(ctx, inner, inner)
        }
        PreInc | PreDec | PostInc | PostDec =>
          match type_of_lvalue(ctx, expr) {
            None => default_int_type()
            Some(ty) => {
              if is_const_qualified(ty) {
                add_sem_error(ctx, loc, "increment of read-only location")
                return default_int_type()
              }
              match strip_top_qualifiers(ty) {
                Array(..) | Function(..) => {
                  add_sem_error(ctx, loc, "invalid operand to increment")
                  return default_int_type()
                }
                _ => ()
              }
              if !is_arithmetic(ty) {
                match strip_top_qualifiers(ty) {
                  Pointer(_) => ()
                  _ => add_sem_error(ctx, loc, "invalid operand to increment")
                }
              }
              ty
            }
          }
      }
    Cast(ty~, expr~, loc~, ..) => {
      register_type_defs(ctx, ty, loc)
      let resolved = resolve_type(ctx, ty, loc)
      type_of_expr(ctx, expr) |> ignore
      resolved
    }
    SizeofExpr(expr~, ..) => {
      let ty = type_for_sizeof(ctx, expr)
      match strip_top_qualifiers(ty) {
        Array(size=None, size_expr=Some(_), ..) => ()
        _ => type_size_align(ctx, ty, @ast.expr_loc(expr)) |> ignore
      }
      default_int_type()
    }
    SizeofType(ty~, loc~, ..) => {
      register_type_defs(ctx, ty, loc)
      let resolved = resolve_type(ctx, ty, loc)
      match strip_top_qualifiers(resolved) {
        Array(size=None, size_expr=Some(_), ..) => ()
        _ => type_size_align(ctx, resolved, loc) |> ignore
      }
      default_int_type()
    }
    AlignofExpr(expr~, loc~, ..) => {
      let ty = type_for_sizeof(ctx, expr)
      type_size_align(ctx, ty, loc) |> ignore
      default_int_type()
    }
    AlignofType(ty~, loc~, ..) => {
      register_type_defs(ctx, ty, loc)
      let resolved = resolve_type(ctx, ty, loc)
      type_size_align(ctx, resolved, loc) |> ignore
      default_int_type()
    }
    Binary(op~, left~, right~, loc~, ..) =>
      match op {
        Assign =>
          match type_of_lvalue(ctx, left) {
            Some(lhs_ty) => {
              if is_const_qualified(lhs_ty) {
                add_sem_error(ctx, loc, "assignment to read-only location")
                return default_int_type()
              }
              match strip_top_qualifiers(lhs_ty) {
                Array(..) | Function(..) => {
                  add_sem_error(ctx, loc, "assignment to non-modifiable lvalue")
                  return default_int_type()
                }
                _ => ()
              }
              let rhs_ty = type_of_expr(ctx, right)
              if !can_assign(lhs_ty, rhs_ty) &&
                !(is_pointer_type(lhs_ty) && is_null_pointer_expr(ctx, right)) {
                add_sem_error(
                  ctx,
                  loc,
                  "cannot assign '\{type_to_string(rhs_ty)}' to '\{type_to_string(lhs_ty)}'",
                )
              }
              lhs_ty
            }
            None => default_int_type()
          }
        AddAssign
        | SubAssign
        | MulAssign
        | DivAssign
        | ModAssign
        | ShlAssign
        | ShrAssign
        | BitAndAssign
        | BitXorAssign
        | BitOrAssign => type_of_compound_assign(ctx, op, left, right, loc)
        Comma => {
          type_of_expr(ctx, left) |> ignore
          type_of_expr(ctx, right)
        }
        Add => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          match strip_top_qualifiers(lhs_ty) {
            Pointer(pointee) =>
              if is_int_like(rhs_ty) {
                return Pointer(pointee)
              } else {
                add_sem_error(ctx, loc, "invalid operands to '+'")
                return default_int_type()
              }
            _ => ()
          }
          match strip_top_qualifiers(rhs_ty) {
            Pointer(pointee) =>
              if is_int_like(lhs_ty) {
                return Pointer(pointee)
              } else {
                add_sem_error(ctx, loc, "invalid operands to '+'")
                return default_int_type()
              }
            _ => ()
          }
          if !is_arithmetic(lhs_ty) || !is_arithmetic(rhs_ty) {
            add_sem_error(
              ctx, loc, "binary operator expects arithmetic operands",
            )
          }
          arithmetic_result_type(ctx, lhs_ty, rhs_ty)
        }
        Sub => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          match strip_top_qualifiers(lhs_ty) {
            Pointer(pointee) =>
              match strip_top_qualifiers(rhs_ty) {
                Pointer(other) => {
                  if !pointer_compatible(pointee, other) {
                    add_sem_error(ctx, loc, "pointer subtraction type mismatch")
                  }
                  return default_int_type()
                }
                _ =>
                  if is_int_like(rhs_ty) {
                    return Pointer(pointee)
                  } else {
                    add_sem_error(ctx, loc, "invalid operands to '-'")
                    return default_int_type()
                  }
              }
            _ => ()
          }
          if !is_arithmetic(lhs_ty) || !is_arithmetic(rhs_ty) {
            add_sem_error(
              ctx, loc, "binary operator expects arithmetic operands",
            )
          }
          arithmetic_result_type(ctx, lhs_ty, rhs_ty)
        }
        Eq | Ne | Lt | Le | Gt | Ge => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          match strip_top_qualifiers(lhs_ty) {
            Pointer(pointee) =>
              match strip_top_qualifiers(rhs_ty) {
                Pointer(other) => {
                  if !pointer_compatible(pointee, other) {
                    add_sem_error(ctx, loc, "pointer comparison type mismatch")
                  }
                  return default_int_type()
                }
                _ =>
                  if is_int_like(rhs_ty) && is_null_pointer_expr(ctx, right) {
                    return default_int_type()
                  }
              }
            _ => ()
          }
          match strip_top_qualifiers(rhs_ty) {
            Pointer(_) =>
              if is_int_like(lhs_ty) && is_null_pointer_expr(ctx, left) {
                return default_int_type()
              }
            _ => ()
          }
          if !is_arithmetic(lhs_ty) || !is_arithmetic(rhs_ty) {
            add_sem_error(
              ctx, loc, "binary operator expects arithmetic operands",
            )
          }
          default_int_type()
        }
        LogAnd | LogOr => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          if !is_scalar(lhs_ty) || !is_scalar(rhs_ty) {
            add_sem_error(ctx, loc, "binary operator expects scalar operands")
          }
          default_int_type()
        }
        Mul | Div => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          if !is_arithmetic(lhs_ty) || !is_arithmetic(rhs_ty) {
            add_sem_error(
              ctx, loc, "binary operator expects arithmetic operands",
            )
          }
          arithmetic_result_type(ctx, lhs_ty, rhs_ty)
        }
        Shl | Shr => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
            add_sem_error(ctx, loc, "binary operator expects int operands")
          }
          promote_int_type(ctx, lhs_ty)
        }
        Mod | BitAnd | BitXor | BitOr => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
            add_sem_error(ctx, loc, "binary operator expects int operands")
          }
          common_int_type(ctx, lhs_ty, rhs_ty)
        }
      }
    Conditional(cond~, then_expr~, else_expr~, loc~, ..) => {
      check_cond_expr(ctx, cond)
      let then_ty = type_of_expr(ctx, then_expr)
      let else_ty = type_of_expr(ctx, else_expr)
      match (strip_top_qualifiers(then_ty), strip_top_qualifiers(else_ty)) {
        (Pointer(a), Pointer(b)) => {
          if !pointer_compatible(a, b) {
            add_sem_error(ctx, loc, "conditional operator type mismatch")
          }
          if is_void_pointer_type(then_ty) {
            return then_ty
          }
          if is_void_pointer_type(else_ty) {
            return else_ty
          }
          return then_ty
        }
        (Pointer(_), _) =>
          if is_int_like(else_ty) && is_null_pointer_expr(ctx, else_expr) {
            return then_ty
          }
        (_, Pointer(_)) =>
          if is_int_like(then_ty) && is_null_pointer_expr(ctx, then_expr) {
            return else_ty
          }
        _ => ()
      }
      if is_arithmetic(then_ty) && is_arithmetic(else_ty) {
        return arithmetic_result_type(ctx, then_ty, else_ty)
      }
      if !type_eq(then_ty, else_ty) {
        add_sem_error(ctx, loc, "conditional operator type mismatch")
      }
      then_ty
    }
    Index(base~, index~, loc~, ..) =>
      match
        index_access_type(
          ctx,
          type_of_expr(ctx, base),
          type_of_expr(ctx, index),
          loc,
        ) {
        Some(ty) => decay_type(ty)
        None => default_int_type()
      }
    Member(base~, name~, id~, is_arrow~, loc~, ..) => {
      let base_ty = type_of_expr(ctx, base)
      if !is_arrow && !@ast.expr_is_lvalue_simple(base) {
        record_agg_temp_for_type(ctx, base_ty, loc)
      }
      match member_access_type(ctx, base_ty, name, id, is_arrow~, loc) {
        Some(ty) => decay_type(ty)
        None => default_int_type()
      }
    }
    Call(callee~, args~, loc~, ..) => {
      if callee is Ident(name~, id~, ..) {
        match builtin_call_kind(ctx, name, id) {
          Some(ChooseExpr) => {
            if args.length() != 3 {
              add_sem_error(
                ctx, loc, "__builtin_choose_expr expects 3 arguments",
              )
              return default_int_type()
            }
            let cond = eval_const_expr(ctx, args[0], loc)
            if cond != 0 {
              return type_of_expr(ctx, args[1])
            }
            return type_of_expr(ctx, args[2])
          }
          Some(Expect) => {
            if args.length() != 2 {
              add_sem_error(ctx, loc, "__builtin_expect expects 2 arguments")
              return default_int_type()
            }
            ignore(type_of_expr(ctx, args[1]))
            return type_of_expr(ctx, args[0])
          }
          Some(ConstantP) => {
            if args.length() != 1 {
              add_sem_error(ctx, loc, "__builtin_constant_p expects 1 argument")
              return default_int_type()
            }
            ignore(type_of_expr(ctx, args[0]))
            return default_int_type()
          }
          Some(Unreachable) => {
            if args.length() != 0 {
              add_sem_error(ctx, loc, "__builtin_unreachable expects no args")
            }
            return Void
          }
          Some(SyncSynchronize) => {
            if args.length() != 0 {
              add_sem_error(ctx, loc, "__sync_synchronize expects no args")
            }
            return Void
          }
          Some(VaStart) => {
            if args.length() != 2 {
              add_sem_error(ctx, loc, "__builtin_va_start expects 2 arguments")
            }
            if args.length() >= 1 {
              match args[0] {
                Ident(name=_, id=ap_id, loc=ap_loc, ..) =>
                  match lookup_local_only(ctx, ap_id) {
                    None =>
                      add_sem_error(
                        ctx, ap_loc, "__builtin_va_start expects a local variable",
                      )
                    Some(_) => ()
                  }
                _ =>
                  add_sem_error(
                    ctx,
                    @ast.expr_loc(args[0]),
                    "__builtin_va_start expects a local variable",
                  )
              }
            }
            for arg in args {
              ignore(type_of_expr(ctx, arg))
            }
            return Void
          }
          Some(FrameAddress) | Some(ReturnAddress) => {
            if args.length() != 1 {
              add_sem_error(ctx, loc, "\{name} expects 1 argument")
            } else {
              let level = eval_const_expr(ctx, args[0], loc)
              if level < 0 {
                add_sem_error(
                  ctx,
                  loc,
                  "\{name} only takes non-negative integers",
                )
              }
            }
            return void_pointer_type()
          }
          _ => ()
        }
        if atomic_builtin_return_type(ctx, name, id, args, loc) is Some(ret) {
          return ret
        }
      }
      let callee_ty = match callee {
        Ident(name~, id~, loc=ident_loc, ..) =>
          match lookup_value(ctx, name, id) {
            Some(ty) => ty
            None =>
              match builtin_func_sig_from_ident(ctx, name, id) {
                Some(sig) => {
                  add_function_sig(ctx, name, id, sig, ident_loc, is_def=false)
                  Function(
                    return_type=sig.return_type,
                    params=sig.params,
                    varargs=sig.varargs,
                    is_old_style=sig.is_old_style,
                    call_conv=sig.call_conv,
                  )
                }
                None => {
                  let sig : FuncSig = {
                    return_type: default_int_type(),
                    params: [],
                    varargs: false,
                    is_old_style: true,
                    call_conv: Default,
                  }
                  add_function_sig(ctx, name, id, sig, ident_loc, is_def=false)
                  Function(
                    return_type=sig.return_type,
                    params=sig.params,
                    varargs=sig.varargs,
                    is_old_style=sig.is_old_style,
                    call_conv=sig.call_conv,
                  )
                }
              }
          }
        _ => type_of_expr(ctx, callee)
      }
      let callee_unqual = strip_top_qualifiers(callee_ty)
      let fn_ty = match callee_unqual {
        Function(..) => Some(callee_unqual)
        Pointer(inner) =>
          match strip_top_qualifiers(inner) {
            Function(..) => Some(strip_top_qualifiers(inner))
            _ => None
          }
        _ => None
      }
      match fn_ty {
        Some(Function(return_type~, params~, varargs~, is_old_style~, ..)) => {
          if !is_old_style {
            if varargs {
              if args.length() < params.length() {
                add_sem_error(ctx, loc, "argument count mismatch in call")
              }
            } else if params.length() != args.length() {
              add_sem_error(ctx, loc, "argument count mismatch in call")
            }
          }
          for i = 0; i < args.length(); i = i + 1 {
            let arg_ty = decay_type(type_of_expr(ctx, args[i]))
            if !is_old_style && i < params.length() {
              if !can_assign(params[i], arg_ty) &&
                !(is_pointer_type(params[i]) &&
                is_null_pointer_expr(ctx, args[i])) {
                let call_name = match callee {
                  Ident(name~, ..) => name
                  _ => "<call>"
                }
                add_sem_error(
                  ctx,
                  loc,
                  "argument type mismatch in call to \{call_name}: expected '\{type_to_string(params[i])}', got '\{type_to_string(arg_ty)}'",
                )
                break
              }
            }
          }
          return_type
        }
        _ => {
          add_sem_error(ctx, loc, "call target is not a function")
          default_int_type()
        }
      }
    }
  }
}

///|
fn has_builtin_prefix(name : String) -> Bool {
  name.has_prefix("__builtin_")
}

///|
fn has_atomic_prefix(name : String) -> Bool {
  name.has_prefix("__atomic_")
}

///|
pub fn builtin_call_kind(
  ctx : SemContext,
  name : String,
  id : Int,
) -> BuiltinCallKind? {
  if id != 0 {
    if get_opt_by_id(ctx.builtin_call_ids, id) is Some(kind) {
      return Some(kind)
    }
  }
  let kind = if name == "__sync_synchronize" {
    Some(BuiltinCallKind::SyncSynchronize)
  } else if !has_builtin_prefix(name) {
    None
  } else {
    match name {
      "__builtin_choose_expr" => Some(ChooseExpr)
      "__builtin_expect" => Some(Expect)
      "__builtin_constant_p" => Some(ConstantP)
      "__builtin_unreachable" => Some(Unreachable)
      "__builtin_va_start" => Some(VaStart)
      "__builtin_va_copy" => Some(VaCopy)
      "__builtin_va_end" => Some(VaEnd)
      "__builtin_frame_address" => Some(FrameAddress)
      "__builtin_return_address" => Some(ReturnAddress)
      _ => None
    }
  }
  match kind {
    Some(value) => {
      if id != 0 {
        set_opt_by_id(ctx.builtin_call_ids, id, value)
      }
      Some(value)
    }
    None => None
  }
}

///|
fn builtin_func_sig_from_ident(
  ctx : SemContext,
  name : String,
  id : Int,
) -> FuncSig? {
  if id != 0 {
    if get_opt_by_id(ctx.builtin_sig_ids, id) is Some(sig) {
      return Some(sig)
    }
  }
  if !has_builtin_prefix(name) {
    return None
  }
  let sig = builtin_func_sig_by_name(name)
  match sig {
    Some(value) => {
      if id != 0 {
        set_opt_by_id(ctx.builtin_sig_ids, id, value)
      }
      Some(value)
    }
    None => None
  }
}

///|
pub fn atomic_builtin_template_from_ident(
  ctx : SemContext,
  name : String,
  id : Int,
) -> String? {
  if id != 0 {
    if get_opt_by_id(ctx.atomic_template_ids, id) is Some(template) {
      return Some(template)
    }
  }
  if !has_atomic_prefix(name) {
    return None
  }
  let template = atomic_builtin_template_by_name(name)
  match template {
    Some(value) => {
      if id != 0 {
        set_opt_by_id(ctx.atomic_template_ids, id, value)
      }
      Some(value)
    }
    None => None
  }
}

///|
fn builtin_func_sig_by_name(name : String) -> FuncSig? {
  let voidp = void_pointer_type()
  let charp = char_pointer_type()
  let size_t = size_t_type()
  let int_ty = default_int_type()
  let sig = match name {
    "__builtin_abort" =>
      Some({
        return_type: Void,
        params: [],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_free" =>
      Some({
        return_type: Void,
        params: [voidp],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_malloc" =>
      Some({
        return_type: voidp,
        params: [size_t],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_calloc" =>
      Some({
        return_type: voidp,
        params: [size_t, size_t],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_realloc" =>
      Some({
        return_type: voidp,
        params: [voidp, size_t],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_alloca" =>
      Some({
        return_type: voidp,
        params: [size_t],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_memcpy" | "__builtin_memmove" =>
      Some({
        return_type: voidp,
        params: [voidp, voidp, size_t],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_memset" =>
      Some({
        return_type: voidp,
        params: [voidp, int_ty, size_t],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_memcmp" =>
      Some({
        return_type: int_ty,
        params: [voidp, voidp, size_t],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_va_start" =>
      Some({
        return_type: Void,
        params: [voidp, int_ty],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_va_copy" =>
      Some({
        return_type: Void,
        params: [voidp, voidp],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_va_end" =>
      Some({
        return_type: Void,
        params: [voidp],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_strlen" =>
      Some({
        return_type: size_t,
        params: [charp],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_strcpy"
    | "__builtin_strncpy"
    | "__builtin_strcat"
    | "__builtin_strncat" =>
      Some({
        return_type: charp,
        params: if name == "__builtin_strncpy" || name == "__builtin_strncat" {
          [charp, charp, size_t]
        } else {
          [charp, charp]
        },
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_strcmp" =>
      Some({
        return_type: int_ty,
        params: [charp, charp],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_strncmp" =>
      Some({
        return_type: int_ty,
        params: [charp, charp, size_t],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_strchr" | "__builtin_strrchr" =>
      Some({
        return_type: charp,
        params: [charp, int_ty],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    "__builtin_strdup" =>
      Some({
        return_type: charp,
        params: [charp],
        varargs: false,
        is_old_style: false,
        call_conv: Default,
      })
    _ => None
  }
  sig
}

///|
fn atomic_builtin_template_by_name(name : String) -> String? {
  match name {
    "__atomic_store" => Some("alm.?")
    "__atomic_load" => Some("Asm.v")
    "__atomic_exchange" => Some("alsm.v")
    "__atomic_compare_exchange" => Some("aplbmm.b")
    "__atomic_fetch_add" => Some("avm.v")
    "__atomic_fetch_sub" => Some("avm.v")
    "__atomic_fetch_or" => Some("avm.v")
    "__atomic_fetch_xor" => Some("avm.v")
    "__atomic_fetch_and" => Some("avm.v")
    "__atomic_fetch_nand" => Some("avm.v")
    "__atomic_add_fetch" => Some("avm.v")
    "__atomic_sub_fetch" => Some("avm.v")
    "__atomic_or_fetch" => Some("avm.v")
    "__atomic_xor_fetch" => Some("avm.v")
    "__atomic_and_fetch" => Some("avm.v")
    "__atomic_nand_fetch" => Some("avm.v")
    _ => None
  }
}

///|
fn is_pow2_int(x : Int) -> Bool {
  x > 0 && (x & (x - 1)) == 0
}

///|
pub fn atomic_builtin_return_type(
  ctx : SemContext,
  name : String,
  id : Int,
  args : Array[@ast.Expr],
  loc : @source.SrcLoc,
) -> @ast.CType? {
  let template = match atomic_builtin_template_from_ident(ctx, name, id) {
    None => return None
    Some(v) => v
  }
  let mut dot_index = 0
  while dot_index < template.length() && template[dot_index] != '.' {
    dot_index = dot_index + 1
  }
  if dot_index >= template.length() - 1 {
    return None
  }
  let arg_spec_len = dot_index
  if args.length() != arg_spec_len {
    add_sem_error(ctx, loc, "\{name} expects \{arg_spec_len} arguments")
  }
  let mut atom_type : @ast.CType? = None
  let mut atom_size = 0
  let allow_pointer_target = name == "__atomic_store" ||
    name == "__atomic_load" ||
    name == "__atomic_exchange" ||
    name == "__atomic_compare_exchange"
  for i = 0; i < arg_spec_len && i < args.length(); i = i + 1 {
    let spec = template[i]
    match spec {
      'a' | 'A' => {
        let ptr_ty = type_of_expr(ctx, args[i])
        match strip_top_qualifiers(ptr_ty) {
          Pointer(pointee) => {
            atom_type = Some(pointee)
            match type_size_align(ctx, pointee, loc) {
              None => atom_size = 0
              Some((size, _)) => {
                atom_size = size
                if size > 8 || !is_pow2_int(size) {
                  add_sem_error(
                    ctx,
                    loc,
                    "\{name} expects 1/2/4/8-byte atomic type",
                  )
                }
              }
            }
            if !allow_pointer_target {
              match strip_top_qualifiers(pointee) {
                Pointer(_) =>
                  add_sem_error(
                    ctx,
                    loc,
                    "\{name} expects integral atomic target type",
                  )
                _ =>
                  if !is_int_like(pointee) {
                    add_sem_error(
                      ctx,
                      loc,
                      "\{name} expects integral atomic target type",
                    )
                  }
              }
            }
          }
          _ => add_sem_error(ctx, loc, "\{name} expects pointer argument")
        }
      }
      'p' | 'l' | 's' => {
        let ptr_ty = type_of_expr(ctx, args[i])
        match strip_top_qualifiers(ptr_ty) {
          Pointer(pointee) => {
            if atom_size > 0 {
              if type_size_align(ctx, pointee, loc) is Some((size, _)) {
                if size != atom_size {
                  add_sem_error(
                    ctx,
                    loc,
                    "\{name} pointer target type mismatch in argument \{i + 1}",
                  )
                }
              }
            }
            if spec == 'l' {
              if atom_type is Some(at) {
                if !can_assign(at, pointee) {
                  add_sem_error(
                    ctx,
                    loc,
                    "\{name} type mismatch in argument \{i + 1}",
                  )
                }
              }
            }
          }
          _ => add_sem_error(ctx, loc, "\{name} expects pointer argument")
        }
      }
      'v' => {
        let v_ty = type_of_expr(ctx, args[i])
        if atom_type is Some(at) {
          if !can_assign(at, v_ty) &&
            !(is_pointer_type(at) && is_null_pointer_expr(ctx, args[i])) {
            add_sem_error(
              ctx,
              loc,
              "\{name} type mismatch in argument \{i + 1}",
            )
          }
        }
      }
      'm' => {
        let m_ty = type_of_expr(ctx, args[i])
        if !is_int_like(m_ty) {
          add_sem_error(ctx, loc, "\{name} expects int memory model")
        }
      }
      'b' => {
        let b_ty = type_of_expr(ctx, args[i])
        if !is_scalar(b_ty) {
          add_sem_error(ctx, loc, "\{name} expects scalar boolean argument")
        }
      }
      _ => ()
    }
  }
  let ret = template[dot_index + 1]
  match ret {
    '?' => Some(Void)
    'b' => Some(Bool)
    'v' =>
      match atom_type {
        None => Some(default_int_type())
        Some(at) => Some(at)
      }
    _ => None
  }
}

///|
fn type_of_compound_assign(
  ctx : SemContext,
  op : @ast.BinaryOp,
  left : @ast.Expr,
  right : @ast.Expr,
  loc : @source.SrcLoc,
) -> @ast.CType {
  let lhs_ty = match type_of_lvalue(ctx, left) {
    None => return default_int_type()
    Some(ty) => ty
  }
  match strip_top_qualifiers(lhs_ty) {
    Array(..) | Function(..) => {
      add_sem_error(ctx, loc, "assignment to non-modifiable lvalue")
      return default_int_type()
    }
    _ => ()
  }
  let rhs_ty = type_of_expr(ctx, right)
  let result_ty = match op {
    AddAssign =>
      match strip_top_qualifiers(lhs_ty) {
        Pointer(pointee) =>
          if is_int_like(rhs_ty) {
            @ast.CType::Pointer(pointee)
          } else {
            add_sem_error(ctx, loc, "invalid operands to '+='")
            default_int_type()
          }
        _ =>
          if is_arithmetic(lhs_ty) && is_arithmetic(rhs_ty) {
            arithmetic_result_type(ctx, lhs_ty, rhs_ty)
          } else {
            add_sem_error(ctx, loc, "invalid operands to '+='")
            default_int_type()
          }
      }
    SubAssign =>
      match strip_top_qualifiers(lhs_ty) {
        Pointer(pointee) =>
          if is_int_like(rhs_ty) {
            Pointer(pointee)
          } else {
            add_sem_error(ctx, loc, "invalid operands to '-='")
            default_int_type()
          }
        _ =>
          if is_arithmetic(lhs_ty) && is_arithmetic(rhs_ty) {
            arithmetic_result_type(ctx, lhs_ty, rhs_ty)
          } else {
            add_sem_error(ctx, loc, "invalid operands to '-='")
            default_int_type()
          }
      }
    MulAssign => {
      if !is_arithmetic(lhs_ty) || !is_arithmetic(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '*='")
      }
      arithmetic_result_type(ctx, lhs_ty, rhs_ty)
    }
    DivAssign => {
      if !is_arithmetic(lhs_ty) || !is_arithmetic(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '/='")
      }
      arithmetic_result_type(ctx, lhs_ty, rhs_ty)
    }
    ModAssign => {
      if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '%='")
      }
      common_int_type(ctx, lhs_ty, rhs_ty)
    }
    ShlAssign => {
      if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '<<='")
      }
      common_int_type(ctx, lhs_ty, rhs_ty)
    }
    ShrAssign => {
      if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '>>='")
      }
      common_int_type(ctx, lhs_ty, rhs_ty)
    }
    BitAndAssign => {
      if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '&='")
      }
      common_int_type(ctx, lhs_ty, rhs_ty)
    }
    BitXorAssign => {
      if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '^='")
      }
      common_int_type(ctx, lhs_ty, rhs_ty)
    }
    BitOrAssign => {
      if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '|='")
      }
      common_int_type(ctx, lhs_ty, rhs_ty)
    }
    _ => default_int_type()
  }
  if is_const_qualified(lhs_ty) {
    add_sem_error(ctx, loc, "assignment to read-only location")
  }
  if !can_assign(lhs_ty, result_ty) {
    add_sem_error(
      ctx,
      loc,
      "cannot assign '\{type_to_string(result_ty)}' to '\{type_to_string(lhs_ty)}'",
    )
  }
  lhs_ty
}

///|
fn declare_local(
  ctx : SemContext,
  name : String,
  id : Int,
  ty : @ast.CType,
  loc : @source.SrcLoc,
) -> Unit {
  let scope_id = current_local_scope_id(ctx)
  if scope_id == 0 || id <= 0 {
    return
  }
  let prev_scope = if id <= ctx.local_scope_ids_by_id.length() {
    ctx.local_scope_ids_by_id[id - 1]
  } else {
    0
  }
  if prev_scope == scope_id {
    add_sem_error(ctx, loc, "redefinition of '\{name}'")
  } else {
    record_local_binding(ctx, id, ty)
  }
}

///|
fn declare_global(
  ctx : SemContext,
  name : String,
  id : Int,
  ty : @ast.CType,
  loc : @source.SrcLoc,
) -> Unit {
  if enum_const_exists(ctx, name, id) {
    add_sem_error(ctx, loc, "redefinition of global '\{name}'")
    return
  }
  let mut updated : @ast.CType? = None
  let existing = if id > 0 {
    get_global_by_id(ctx, id)
  } else {
    ctx.globals.get(name)
  }
  match existing {
    None => {
      ctx.globals.set(name, ty)
      updated = Some(ty)
    }
    Some(existing) =>
      if !types_compatible_for_decl(existing, ty) {
        add_sem_error(ctx, loc, "redefinition of global '\{name}'")
      } else {
        let merged = merge_global_decl_type(existing, ty)
        ctx.globals.set(name, merged)
        updated = Some(merged)
      }
  }
  if id > 0 {
    if updated is Some(resolved) {
      set_global_by_id(ctx, id, resolved)
    }
  }
}

///|
fn merge_global_decl_type(
  existing : @ast.CType,
  incoming : @ast.CType,
) -> @ast.CType {
  match (existing, incoming) {
    (Qualified(qual~, base~), _) => {
      let merged = merge_global_decl_type(base, incoming)
      Qualified(qual~, base=merged)
    }
    (_, Qualified(qual~, base~)) => {
      let merged = merge_global_decl_type(existing, base)
      Qualified(qual~, base=merged)
    }
    (
      Attributed(attrs=attrs_a, base=base_a),
      Attributed(attrs=attrs_b, base=base_b),
    ) => {
      let merged_base = merge_global_decl_type(base_a, base_b)
      Attributed(attrs=@ast.merge_attrs(attrs_a, attrs_b), base=merged_base)
    }
    (Attributed(attrs=attrs_a, base=base_a), _) => {
      let merged = merge_global_decl_type(base_a, incoming)
      Attributed(attrs=attrs_a, base=merged)
    }
    (_, Attributed(attrs=attrs_b, base=base_b)) => {
      let merged = merge_global_decl_type(existing, base_b)
      Attributed(attrs=attrs_b, base=merged)
    }
    (
      Array(elem=elem_a, size=size_a, size_expr=size_expr_a),
      Array(elem=elem_b, size=size_b, size_expr=size_expr_b),
    ) => {
      let merged_elem = merge_global_decl_type(elem_a, elem_b)
      let merged_size = match size_a {
        Some(_) => size_a
        None => size_b
      }
      let merged_size_expr = match size_expr_a {
        Some(_) => size_expr_a
        None => size_expr_b
      }
      Array(elem=merged_elem, size=merged_size, size_expr=merged_size_expr)
    }
    (Pointer(inner_a), Pointer(inner_b)) =>
      Pointer(merge_global_decl_type(inner_a, inner_b))
    _ => existing
  }
}

///|
fn lookup_value(ctx : SemContext, name : String, id : Int) -> @ast.CType? {
  let mut found = if id > 0 {
    get_opt_by_id(ctx.local_values_by_id, id)
  } else {
    None
  }
  if found is None {
    found = if id > 0 {
      get_global_by_id(ctx, id)
    } else {
      ctx.globals.get(name)
    }
  }
  if found is None {
    let sig = if id > 0 {
      get_function_by_id(ctx, id)
    } else {
      ctx.functions.get(name)
    }
    if sig is Some(value) {
      found = Some(
        Function(
          return_type=value.return_type,
          params=value.params,
          varargs=value.varargs,
          is_old_style=value.is_old_style,
          call_conv=value.call_conv,
        ),
      )
    }
  }
  if found is None {
    if enum_const_exists(ctx, name, id) {
      found = Some(default_int_type())
    } else if name == "__func__" {
      let elem = @ast.apply_qualifiers(
        char_type(),
        @ast.with_const(@ast.empty_qual()),
      )
      let len = match ctx.current_func_name {
        None => 1
        Some(func) => func.length() + 1
      }
      found = Some(Array(elem~, size=Some(len), size_expr=None))
    } else if name == "__FUNCTION__" || name == "__PRETTY_FUNCTION__" {
      let elem = @ast.apply_qualifiers(
        char_type(),
        @ast.with_const(@ast.empty_qual()),
      )
      let len = match ctx.current_func_name {
        None => 1
        Some(func) => func.length() + 1
      }
      found = Some(Array(elem~, size=Some(len), size_expr=None))
    }
  }
  found
}

///|
pub fn push_scope(ctx : SemContext) -> Unit {
  ctx.next_local_scope_id = ctx.next_local_scope_id + 1
  ctx.local_scope_stack.push(ctx.next_local_scope_id)
  ctx.local_overrides.push([])
}

///|
pub fn pop_scope(ctx : SemContext) -> Unit {
  if ctx.local_overrides.pop() is Some(overrides) {
    let mut i = overrides.length()
    while i > 0 {
      i = i - 1
      let entry = overrides[i]
      let id = entry.id
      if id <= 0 {
        continue
      }
      match entry.prev_ty {
        Some(ty) => set_opt_by_id(ctx.local_values_by_id, id, ty)
        None =>
          if id <= ctx.local_values_by_id.length() {
            ctx.local_values_by_id[id - 1] = None
          }
      }
      ensure_int_array_capacity(ctx.local_scope_ids_by_id, id)
      ctx.local_scope_ids_by_id[id - 1] = entry.prev_scope
    }
  }
  ignore(ctx.local_scope_stack.pop())
}

///|
pub fn add_sem_error(
  ctx : SemContext,
  loc : @source.SrcLoc,
  message : String,
) -> Unit {
  @diag.add_error(ctx.diags, loc, message)
}

///|
fn int_kind_to_string(kind : @ast.CIntKind) -> String {
  match kind {
    Char => "char"
    Short => "short"
    Int => "int"
    Long => "long"
    LongLong => "long long"
  }
}

///|
fn float_kind_to_string(kind : @ast.CFloatKind) -> String {
  match kind {
    Float => "float"
    Double => "double"
    LongDouble => "long double"
  }
}

///|
fn qual_to_string(qual : @ast.TypeQual) -> String {
  let parts : Array[String] = []
  if qual.is_const {
    parts.push("const")
  }
  if qual.is_volatile {
    parts.push("volatile")
  }
  if qual.is_restrict {
    parts.push("restrict")
  }
  if qual.is_atomic {
    parts.push("_Atomic")
  }
  if parts.length() == 0 {
    ""
  } else {
    parts.join(" ") + " "
  }
}

///|
fn type_to_string(ty : @ast.CType) -> String {
  match ty {
    Qualified(qual~, base~) => qual_to_string(qual) + type_to_string(base)
    Attributed(base~, ..) => type_to_string(base)
    Void => "void"
    Bool => "_Bool"
    Int(kind~, unsigned~) => {
      let base = int_kind_to_string(kind)
      if unsigned {
        "unsigned " + base
      } else {
        base
      }
    }
    Float(kind~) => float_kind_to_string(kind)
    Pointer(inner) => type_to_string(inner) + "*"
    Array(elem~, size~, ..) =>
      match size {
        None => type_to_string(elem) + "[]"
        Some(n) => type_to_string(elem) + "[\{n}]"
      }
    Struct(name~, ..) => "struct " + name
    Union(name~, ..) => "union " + name
    Enum(name~, ..) => "enum " + name
    TypeofExpr(..) => "typeof"
    Function(return_type~, params~, varargs~, is_old_style~, ..) => {
      let args = params.map(type_to_string).join(", ")
      let rendered = if is_old_style {
        ""
      } else if varargs {
        if args == "" {
          "..."
        } else {
          "\{args}, ..."
        }
      } else {
        args
      }
      "fn(\{rendered}) -> \{type_to_string(return_type)}"
    }
  }
}
