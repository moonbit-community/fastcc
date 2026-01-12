///|
struct FuncSig {
  return_type : CType
  params : Array[CType]
  varargs : Bool
  is_old_style : Bool
  call_conv : CallConv
} derive(Show, Eq, ToJson)

///|
struct RecordDef {
  fields : Array[Field]
  attrs : Attributes
}

///|
struct SemContext {
  diags : DiagBag
  globals : Map[String, CType]
  functions : Map[String, FuncSig]
  function_defs : Map[String, Bool]
  locals : Array[Map[String, CType]]
  type_aliases : Map[String, CType]
  struct_defs : Map[String, RecordDef]
  union_defs : Map[String, RecordDef]
  enum_defs : Map[String, Array[EnumItem]]
  enum_consts : Map[String, Int]
  enum_types : Map[String, CType]
  switch_stack : Array[SwitchInfo]
  mut labels_defined : Map[String, Bool]
  mut labels_used : Array[(String, SrcLoc)]
  mut loop_depth : Int
  mut switch_depth : Int
}

///|
struct SwitchInfo {
  cases : Array[(Int, Int, SrcLoc)]
  mut has_default : Bool
}

///|
fn new_sem_context(diags : DiagBag) -> SemContext {
  {
    diags,
    globals: {},
    functions: {},
    function_defs: {},
    locals: [],
    type_aliases: {},
    struct_defs: {},
    union_defs: {},
    enum_defs: {},
    enum_consts: {},
    enum_types: {},
    switch_stack: [],
    labels_defined: {},
    labels_used: [],
    loop_depth: 0,
    switch_depth: 0,
  }
}

///|
fn default_int_type() -> CType {
  CType::Int(kind=CIntKind::Int, unsigned=false)
}

///|
fn char_type() -> CType {
  CType::Int(kind=CIntKind::Char, unsigned=false)
}

///|
fn enum_int_type_from_range(min_value : Int, max_value : Int) -> CType {
  let max_int = 2147483647
  let min_int = -2147483647 - 1
  if min_value >= 0 {
    CType::Int(kind=CIntKind::Int, unsigned=true)
  } else if min_value < min_int || max_value > max_int {
    CType::Int(kind=CIntKind::LongLong, unsigned=false)
  } else {
    CType::Int(kind=CIntKind::Int, unsigned=false)
  }
}

///|
fn enum_type_from_items(ctx : SemContext, items : Array[EnumItem]) -> CType {
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
fn strip_qualifiers(ty : CType) -> CType {
  match ty {
    CType::Qualified(base~, ..) => strip_qualifiers(base)
    CType::Attributed(attrs~, base~) =>
      CType::Attributed(attrs~, base=strip_qualifiers(base))
    CType::Pointer(inner) => CType::Pointer(strip_qualifiers(inner))
    CType::Array(elem~, size~) =>
      CType::Array(elem=strip_qualifiers(elem), size~)
    CType::Function(return_type~, params~, varargs~, is_old_style~, call_conv~) =>
      CType::Function(
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
fn strip_attrs(ty : CType) -> CType {
  match ty {
    CType::Attributed(base~, ..) => strip_attrs(base)
    CType::Qualified(qual~, base~) =>
      CType::Qualified(qual~, base=strip_attrs(base))
    CType::Pointer(inner) => CType::Pointer(strip_attrs(inner))
    CType::Array(elem~, size~) => CType::Array(elem=strip_attrs(elem), size~)
    CType::Function(return_type~, params~, varargs~, is_old_style~, call_conv~) =>
      CType::Function(
        return_type=strip_attrs(return_type),
        params=params.map(strip_attrs),
        varargs~,
        is_old_style~,
        call_conv~,
      )
    _ => ty
  }
}

///|
fn strip_qual_attrs(ty : CType) -> CType {
  strip_attrs(strip_qualifiers(ty))
}

///|
fn strip_top_qualifiers(ty : CType) -> CType {
  match ty {
    CType::Qualified(base~, ..) => strip_top_qualifiers(base)
    CType::Attributed(base~, ..) => strip_top_qualifiers(base)
    _ => ty
  }
}

///|
fn split_top_qual(ty : CType) -> (TypeQual, CType) {
  match ty {
    CType::Qualified(qual~, base~) => (qual, base)
    CType::Attributed(base~, ..) => split_top_qual(base)
    _ => (empty_qual(), ty)
  }
}

///|
fn is_const_qualified(ty : CType) -> Bool {
  match ty {
    CType::Qualified(qual~, ..) => qual.is_const
    CType::Attributed(base~, ..) => is_const_qualified(base)
    _ => false
  }
}

///|
fn is_void_type(ty : CType) -> Bool {
  strip_qual_attrs(ty) is CType::Void
}

///|
fn int_rank(kind : CIntKind) -> Int {
  match kind {
    CIntKind::Char => 1
    CIntKind::Short => 2
    CIntKind::Int => 3
    CIntKind::Long => 4
    CIntKind::LongLong => 5
  }
}

///|
fn int_bits(kind : CIntKind) -> Int {
  match kind {
    CIntKind::Char => 8
    CIntKind::Short => 16
    CIntKind::Int => 32
    CIntKind::Long => 64
    CIntKind::LongLong => 64
  }
}

///|
fn float_rank(kind : CFloatKind) -> Int {
  match kind {
    CFloatKind::Float => 1
    CFloatKind::Double => 2
    CFloatKind::LongDouble => 3
  }
}

///|
fn int_size(kind : CIntKind) -> Int {
  match kind {
    CIntKind::Char => 1
    CIntKind::Short => 2
    CIntKind::Int => 4
    CIntKind::Long => 8
    CIntKind::LongLong => 8
  }
}

///|
fn float_size(kind : CFloatKind) -> Int {
  match kind {
    CFloatKind::Float => 4
    CFloatKind::Double => 8
    CFloatKind::LongDouble => 16
  }
}

///|
fn align_to(value : Int, align : Int) -> Int {
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
fn resolve_align_spec(ctx : SemContext, spec : AlignSpec, loc : SrcLoc) -> Int? {
  match spec {
    AlignSpec::Default => Some(max_align)
    AlignSpec::Expr(expr~) =>
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
fn attr_align_value(ctx : SemContext, attrs : Attributes, loc : SrcLoc) -> Int? {
  match attrs.aligned {
    None => None
    Some(spec) => resolve_align_spec(ctx, spec, loc)
  }
}

///|
fn is_float_type(ty : CType) -> Bool {
  match strip_qual_attrs(ty) {
    CType::Float(..) => true
    _ => false
  }
}

///|
fn enum_type_for_arith(ctx : SemContext, ty : CType) -> CType {
  match strip_qual_attrs(ty) {
    CType::Enum(name~, ..) =>
      match ctx.enum_types.get(name) {
        Some(base) => base
        None => default_int_type()
      }
    _ => ty
  }
}

///|
fn promote_int_type(ctx : SemContext, ty : CType) -> CType {
  match strip_qual_attrs(ty) {
    CType::Int(kind~, unsigned~) =>
      if int_rank(kind) < int_rank(CIntKind::Int) {
        default_int_type()
      } else {
        CType::Int(kind~, unsigned~)
      }
    CType::Bool => default_int_type()
    CType::Enum(..) => promote_int_type(ctx, enum_type_for_arith(ctx, ty))
    _ => default_int_type()
  }
}

///|
fn common_int_type(ctx : SemContext, lhs : CType, rhs : CType) -> CType {
  let left = promote_int_type(ctx, lhs)
  let right = promote_int_type(ctx, rhs)
  match (left, right) {
    (
      CType::Int(kind=l_kind, unsigned=l_unsigned),
      CType::Int(kind=r_kind, unsigned=r_unsigned),
    ) => {
      if l_unsigned == r_unsigned {
        let rank = if int_rank(l_kind) >= int_rank(r_kind) {
          l_kind
        } else {
          r_kind
        }
        return CType::Int(kind=rank, unsigned=l_unsigned)
      }
      let (u_kind, u_unsigned, s_kind) = if l_unsigned {
        (l_kind, true, r_kind)
      } else {
        (r_kind, true, l_kind)
      }
      if int_rank(u_kind) >= int_rank(s_kind) {
        return CType::Int(kind=u_kind, unsigned=u_unsigned)
      }
      let u_bits = int_bits(u_kind)
      let s_bits = int_bits(s_kind)
      if s_bits > u_bits {
        CType::Int(kind=s_kind, unsigned=false)
      } else {
        CType::Int(kind=s_kind, unsigned=true)
      }
    }
    _ => default_int_type()
  }
}

///|
fn arithmetic_result_type(ctx : SemContext, lhs : CType, rhs : CType) -> CType {
  let left = strip_qual_attrs(lhs)
  let right = strip_qual_attrs(rhs)
  match (left, right) {
    (CType::Float(kind=l_kind), CType::Float(kind=r_kind)) =>
      if float_rank(l_kind) >= float_rank(r_kind) {
        CType::Float(kind=l_kind)
      } else {
        CType::Float(kind=r_kind)
      }
    (CType::Float(kind~), _) => CType::Float(kind~)
    (_, CType::Float(kind~)) => CType::Float(kind~)
    _ => common_int_type(ctx, lhs, rhs)
  }
}

///|
fn is_arithmetic(ty : CType) -> Bool {
  is_int_like(ty) || is_float_type(ty)
}

///|
fn can_assign(dst : CType, src : CType) -> Bool {
  let dst_ty = strip_qual_attrs(dst)
  let src_ty = strip_qual_attrs(src)
  if is_arithmetic(dst_ty) && is_arithmetic(src_ty) {
    return true
  }
  match (dst_ty, src_ty) {
    (CType::Pointer(inner_a), CType::Pointer(inner_b)) =>
      pointer_compatible(inner_a, inner_b)
    _ => type_eq(dst_ty, src_ty)
  }
}

///|
fn pointer_compatible(a : CType, b : CType) -> Bool {
  type_eq(a, b) || is_void_type(a) || is_void_type(b)
}

///|
fn check_storage_class(
  ctx : SemContext,
  storage : StorageClass,
  loc : SrcLoc,
  is_local~ : Bool,
  is_function~ : Bool,
) -> Unit {
  if is_function {
    match storage {
      StorageClass::Auto | StorageClass::Register =>
        add_sem_error(ctx, loc, "invalid storage class for function")
      StorageClass::Static =>
        if is_local {
          add_sem_error(
            ctx, loc, "function without file scope cannot be static",
          )
        }
      _ => ()
    }
  } else if !is_local {
    match storage {
      StorageClass::Auto | StorageClass::Register =>
        add_sem_error(ctx, loc, "invalid storage class for global")
      _ => ()
    }
  }
}

///|
fn type_size_align(ctx : SemContext, ty : CType, loc : SrcLoc) -> (Int, Int)? {
  let resolved = resolve_type(ctx, ty, loc)
  match strip_qualifiers(resolved) {
    CType::TypeofExpr(expr~) =>
      type_size_align(ctx, type_for_typeof(ctx, expr), loc)
    CType::Attributed(attrs~, base~) =>
      match type_size_align(ctx, base, loc) {
        None => None
        Some((size, align)) => {
          let mut final_align = if attrs.packed { 1 } else { align }
          match attr_align_value(ctx, attrs, loc) {
            None => ()
            Some(value) => if value > final_align { final_align = value }
          }
          Some((size, final_align))
        }
      }
    CType::Void => {
      add_sem_error(ctx, loc, "invalid application of sizeof to void")
      None
    }
    CType::Bool => Some((1, 1))
    CType::Int(kind~, ..) => {
      let size = int_size(kind)
      Some((size, size))
    }
    CType::Float(kind~) => {
      let size = float_size(kind)
      Some((size, size))
    }
    CType::Pointer(_) => Some((8, 8))
    CType::Enum(name~, items~) => {
      let enum_ty = match ctx.enum_types.get(name) {
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
      match enum_ty {
        None => None
        Some(base) => type_size_align(ctx, base, loc)
      }
    }
    CType::Function(..) => {
      add_sem_error(ctx, loc, "invalid application of sizeof to function")
      None
    }
    CType::Array(elem~, size~) => {
      let (elem_size, elem_align) = match type_size_align(ctx, elem, loc) {
        None => return None
        Some(v) => v
      }
      match size {
        None => {
          add_sem_error(ctx, loc, "sizeof incomplete array")
          None
        }
        Some(n) => Some((elem_size * n, elem_align))
      }
    }
    CType::Struct(name=tag, fields=field_list, attrs=struct_attrs) =>
      match ensure_struct_fields(ctx, tag, field_list, is_union=false, loc) {
        None => None
        Some(def) => {
          let merged = merge_attrs(def.attrs, struct_attrs)
          Some(struct_size_align(ctx, def.fields, merged, loc))
        }
      }
    CType::Union(name=tag, fields=field_list, attrs=struct_attrs) =>
      match ensure_struct_fields(ctx, tag, field_list, is_union=true, loc) {
        None => None
        Some(def) => {
          let merged = merge_attrs(def.attrs, struct_attrs)
          Some(union_size_align(ctx, def.fields, merged, loc))
        }
      }
    CType::Qualified(base~, ..) => type_size_align(ctx, base, loc)
  }
}

///|
fn ensure_struct_fields(
  ctx : SemContext,
  tag : String,
  fields : Array[RecordItem]?,
  is_union~ : Bool,
  loc : SrcLoc,
) -> RecordDef? {
  match fields {
    Some(list) =>
      Some({ fields: record_items_to_fields(list), attrs: empty_attrs() })
    None =>
      if is_union {
        match ctx.union_defs.get(tag) {
          Some(def) if def.fields.length() > 0 => Some(def)
          _ => {
            add_sem_error(ctx, loc, "incomplete union '\{tag}'")
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
fn check_static_assert(ctx : SemContext, item : StaticAssert) -> Unit {
  let (value, ok) = eval_const_expr_value(ctx, item.expr, item.loc)
  if ok && value == 0 {
    add_sem_error(ctx, item.loc, static_assert_message(item.message))
  }
}

///|
fn record_items_to_fields(items : Array[RecordItem]) -> Array[Field] {
  let fields : Array[Field] = []
  for item in items {
    match item {
      RecordItem::Field(field) => fields.push(field)
      RecordItem::StaticAssert(_) => ()
    }
  }
  fields
}

///|
fn record_items_to_fields_checked(
  ctx : SemContext,
  items : Array[RecordItem],
) -> Array[Field] {
  let fields : Array[Field] = []
  for item in items {
    match item {
      RecordItem::Field(field) => fields.push(field)
      RecordItem::StaticAssert(static_assert) =>
        check_static_assert(ctx, static_assert)
    }
  }
  fields
}

///|
fn struct_size_align(
  ctx : SemContext,
  fields : Array[Field],
  attrs : Attributes,
  loc : SrcLoc,
) -> (Int, Int) {
  let mut size = 0
  let mut align = 1
  let mut bit_unit_bits = 0
  let mut bit_offset = 0
  let mut bit_unit_size = 0
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
        let base = strip_qualifiers(field.ty)
        let (base_size, base_align) = match type_size_align(ctx, base, loc) {
          None => (0, 1)
          Some(v) => v
        }
        let unit_bits = base_size * 8
        let mut field_align = if packed { 1 } else { base_align }
        match field_align_override {
          None => ()
          Some(value) => field_align = value
        }
        align = if field_align > align { field_align } else { align }
        if width == 0 {
          size = align_to(size, field_align)
          bit_unit_bits = 0
          bit_offset = 0
          bit_unit_size = 0
          continue
        }
        if bit_unit_bits == 0 ||
          bit_unit_bits != unit_bits ||
          width > unit_bits - bit_offset {
          size = align_to(size, field_align)
          bit_unit_bits = unit_bits
          bit_unit_size = base_size
          bit_offset = 0
        }
        bit_offset = bit_offset + width
        if bit_offset == bit_unit_bits {
          size = size + bit_unit_size
          bit_unit_bits = 0
          bit_unit_size = 0
          bit_offset = 0
        }
      }
      None => {
        if bit_unit_bits != 0 {
          size = size + bit_unit_size
          bit_unit_bits = 0
          bit_unit_size = 0
          bit_offset = 0
        }
        let (field_size, field_align) = match strip_qualifiers(field.ty) {
          CType::Array(elem~, size=None) => {
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
          _ =>
            match type_size_align(ctx, field.ty, loc) {
              None => (0, 1)
              Some(v) => v
            }
        }
        let mut adjusted_align = if packed { 1 } else { field_align }
        match field_align_override {
          None => ()
          Some(value) => adjusted_align = value
        }
        size = align_to(size, adjusted_align)
        size = size + field_size
        align = if adjusted_align > align { adjusted_align } else { align }
      }
    }
  }
  if bit_unit_bits != 0 {
    size = size + bit_unit_size
  }
  let mut final_align = align
  match attr_align_value(ctx, attrs, loc) {
    None => ()
    Some(value) => if value > final_align { final_align = value }
  }
  size = align_to(size, final_align)
  (size, final_align)
}

///|
fn union_size_align(
  ctx : SemContext,
  fields : Array[Field],
  attrs : Attributes,
  loc : SrcLoc,
) -> (Int, Int) {
  let mut size = 0
  let mut align = 1
  for field in fields {
    let packed = attrs.packed || field.attrs.packed
    let field_align_override = attr_align_value(ctx, field.attrs, field.loc)
    let base = strip_qualifiers(field.ty)
    let (field_size, field_align) = match field.bit_width {
      Some(_) =>
        match type_size_align(ctx, base, loc) {
          None => (0, 1)
          Some(v) => v
        }
      None =>
        match type_size_align(ctx, field.ty, loc) {
          None => (0, 1)
          Some(v) => v
        }
    }
    let mut adjusted_align = if packed { 1 } else { field_align }
    match field_align_override {
      None => ()
      Some(value) => adjusted_align = value
    }
    if field_size > size {
      size = field_size
    }
    if adjusted_align > align {
      align = adjusted_align
    }
  }
  let mut final_align = align
  match attr_align_value(ctx, attrs, loc) {
    None => ()
    Some(value) => if value > final_align { final_align = value }
  }
  size = align_to(size, final_align)
  (size, final_align)
}

///|
fn type_for_sizeof(ctx : SemContext, expr : Expr) -> CType {
  match expr {
    Expr::Ident(name~, loc~) =>
      match lookup_value(ctx, name) {
        Some(ty) => ty
        None => {
          add_sem_error(ctx, loc, "use of undeclared identifier '\{name}'")
          default_int_type()
        }
      }
    Expr::StringLit(length~, ..) =>
      CType::Array(elem=char_type(), size=Some(length))
    _ => type_of_expr(ctx, expr)
  }
}

///|
fn type_for_typeof(ctx : SemContext, expr : Expr) -> CType {
  match expr {
    Expr::Ident(name~, loc~) =>
      match lookup_value(ctx, name) {
        Some(ty) => ty
        None => {
          add_sem_error(ctx, loc, "use of undeclared identifier '\{name}'")
          default_int_type()
        }
      }
    Expr::StringLit(length~, ..) =>
      CType::Array(elem=char_type(), size=Some(length))
    _ => type_of_expr(ctx, expr)
  }
}

///|
fn resolve_type(ctx : SemContext, ty : CType, loc : SrcLoc) -> CType {
  match ty {
    CType::Qualified(qual~, base~) =>
      CType::Qualified(qual~, base=resolve_type(ctx, base, loc))
    CType::Attributed(attrs~, base~) =>
      CType::Attributed(attrs~, base=resolve_type(ctx, base, loc))
    CType::Pointer(inner) => CType::Pointer(resolve_type(ctx, inner, loc))
    CType::Array(elem~, size~) =>
      CType::Array(elem=resolve_type(ctx, elem, loc), size~)
    CType::Function(return_type~, params~, varargs~, is_old_style~, call_conv~) =>
      CType::Function(
        return_type=resolve_type(ctx, return_type, loc),
        params=params.map(param => resolve_type(ctx, param, loc)),
        varargs~,
        is_old_style~,
        call_conv~,
      )
    CType::TypeofExpr(expr~) =>
      resolve_type(ctx, type_for_typeof(ctx, expr), expr_loc(expr))
    _ => ty
  }
}

///|
fn check_translation_unit(unit : TranslationUnit, diags : DiagBag) -> Unit {
  let ctx = new_sem_context(diags)
  for decl in unit.decls {
    check_decl(ctx, decl)
  }
}

///|
fn check_decl(ctx : SemContext, decl : Decl) -> Unit {
  match decl {
    Decl::Var(var_decl) => {
      register_type_defs(ctx, var_decl.ty, var_decl.loc)
      check_var_decl(ctx, var_decl, is_local=false)
    }
    Decl::FuncDecl(func_decl) => {
      register_type_defs(ctx, func_decl.return_type, func_decl.loc)
      for param in func_decl.params {
        register_type_defs(ctx, param.ty, param.loc)
      }
      check_func_decl(ctx, func_decl)
    }
    Decl::FuncDef(func_def) => {
      register_type_defs(ctx, func_def.return_type, func_def.loc)
      for param in func_def.params {
        register_type_defs(ctx, param.ty, param.loc)
      }
      check_func_def(ctx, func_def)
    }
    Decl::Typedef(name~, ty~, attrs=_, loc~) => {
      register_type_defs(ctx, ty, loc)
      let resolved = resolve_type(ctx, ty, loc)
      ctx.type_aliases.set(name, resolved)
    }
    Decl::TagDef(ty~, loc~) => register_type_defs(ctx, ty, loc)
    Decl::StaticAssert(static_assert) => check_static_assert(ctx, static_assert)
    Decl::Asm(asm_stmt) => check_asm_stmt(ctx, asm_stmt)
  }
}

///|
fn register_type_defs(ctx : SemContext, ty : CType, loc : SrcLoc) -> Unit {
  match ty {
    CType::Qualified(base~, ..) => register_type_defs(ctx, base, loc)
    CType::Attributed(base~, ..) => register_type_defs(ctx, base, loc)
    CType::Struct(name~, fields~, attrs~) =>
      register_struct_def(ctx, name, fields, attrs, is_union=false, loc)
    CType::Union(name~, fields~, attrs~) =>
      register_struct_def(ctx, name, fields, attrs, is_union=true, loc)
    CType::Enum(name~, items~) => register_enum_def(ctx, name, items, loc)
    CType::Pointer(inner) => register_type_defs(ctx, inner, loc)
    CType::Array(elem~, ..) => register_type_defs(ctx, elem, loc)
    CType::Function(return_type~, params~, ..) => {
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
  fields : Array[RecordItem]?,
  attrs : Attributes,
  is_union~ : Bool,
  loc : SrcLoc,
) -> Unit {
  if name == "" {
    return
  }
  if is_union {
    if ctx.struct_defs.contains(name) {
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
    match ctx.union_defs.get(name) {
      None => {
        ctx.union_defs.set(name, incoming)
        validate_fields(incoming)
      }
      Some(existing) =>
        if existing.fields.length() > 0 && incoming.fields.length() > 0 {
          add_sem_error(ctx, loc, "redefinition of '\{name}'")
        } else if existing.fields.length() == 0 && incoming.fields.length() > 0 {
          let merged = {
            fields: incoming.fields,
            attrs: merge_attrs(existing.attrs, incoming.attrs),
          }
          ctx.union_defs.set(name, merged)
          validate_fields(merged)
        } else {
          let merged = {
            fields: existing.fields,
            attrs: merge_attrs(existing.attrs, incoming.attrs),
          }
          ctx.union_defs.set(name, merged)
        }
    }
  } else {
    match ctx.struct_defs.get(name) {
      None => {
        ctx.struct_defs.set(name, incoming)
        validate_fields(incoming)
      }
      Some(existing) =>
        if existing.fields.length() > 0 && incoming.fields.length() > 0 {
          add_sem_error(ctx, loc, "redefinition of '\{name}'")
        } else if existing.fields.length() == 0 && incoming.fields.length() > 0 {
          let merged = {
            fields: incoming.fields,
            attrs: merge_attrs(existing.attrs, incoming.attrs),
          }
          ctx.struct_defs.set(name, merged)
          validate_fields(merged)
        } else {
          let merged = {
            fields: existing.fields,
            attrs: merge_attrs(existing.attrs, incoming.attrs),
          }
          ctx.struct_defs.set(name, merged)
        }
    }
  }
  if incoming.fields.length() > 0 {
    for field in incoming.fields {
      register_type_defs(ctx, field.ty, field.loc)
      match field.bit_width {
        None => ()
        Some(expr) => {
          if !is_int_like(field.ty) {
            add_sem_error(ctx, field.loc, "bitfields must have integer type")
          }
          match const_int_from_expr(ctx, expr, field.loc) {
            None => ()
            Some(width) => {
              if width < 0 {
                add_sem_error(ctx, field.loc, "negative width in bit-field")
              }
              if width == 0 && field.name != "" {
                add_sem_error(ctx, field.loc, "zero width for bit-field")
              }
              if width > 0 {
                match type_size_align(ctx, field.ty, field.loc) {
                  None => ()
                  Some((size, _align)) =>
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
  }
}

///|
fn register_enum_def(
  ctx : SemContext,
  name : String,
  items : Array[EnumItem]?,
  loc : SrcLoc,
) -> Unit {
  if name == "" {
    return
  }
  let incoming = match items {
    None => []
    Some(val) => val
  }
  match ctx.enum_defs.get(name) {
    None => ctx.enum_defs.set(name, incoming)
    Some(existing) =>
      if existing.length() > 0 && incoming.length() > 0 {
        add_sem_error(ctx, loc, "redefinition of '\{name}'")
      } else if existing.length() == 0 && incoming.length() > 0 {
        ctx.enum_defs.set(name, incoming)
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
      define_enum_const(ctx, item.name, item.loc, current)
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
      ctx.enum_types.set(name, enum_int_type_from_range(min_value, max_value))
    }
  }
}

///|
fn define_enum_const(
  ctx : SemContext,
  name : String,
  loc : SrcLoc,
  value : Int,
) -> Unit {
  let mut conflict = ctx.enum_consts.contains(name)
  if !conflict && ctx.globals.contains(name) {
    conflict = true
  }
  if !conflict && ctx.functions.contains(name) {
    conflict = true
  }
  if conflict {
    add_sem_error(ctx, loc, "redefinition of '\{name}'")
    return
  }
  ctx.enum_consts.set(name, value)
}

///|
fn parse_int_value(text : String) -> Int {
  let trimmed = trim_int_literal(text)
  try @strconv.parse_int(trimmed, base=0) catch {
    _ => 0
  } noraise {
    v => v
  }
}

///|
fn parse_uint64_value(text : String) -> UInt64 {
  let trimmed = trim_int_literal(text)
  parse_uint64_literal(trimmed, int_literal_base(text))
}

///|
fn trim_int_literal(text : String) -> String {
  let end = int_literal_end(text)
  slice_string_sem(text, 0, end)
}

///|
fn int_literal_type(text : String) -> CType {
  let end = int_literal_end(text)
  let suffix = if end >= text.length() {
    ""
  } else {
    slice_string_sem(text, end, text.length())
  }
  let (long_count, unsigned) = parse_int_suffix(suffix)
  let value = parse_uint64_value(text)
  let base = int_literal_base(text)
  let (adj_long_count, adj_unsigned) = adjust_int_literal_kind(
    value, base, long_count, unsigned,
  )
  let kind = if adj_long_count >= 2 {
    CIntKind::LongLong
  } else if adj_long_count == 1 {
    CIntKind::Long
  } else {
    CIntKind::Int
  }
  CType::Int(kind~, unsigned=adj_unsigned)
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
  try text[start:end] catch {
    _ => ""
  } noraise {
    view => view.to_string()
  }
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
fn parse_uint64_literal(text : String, base : Int) -> UInt64 {
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
fn int_literal_base(text : String) -> Int {
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
fn parse_int_suffix(suffix : String) -> (Int, Bool) {
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
fn float_type_from_literal(lit : String) -> CType {
  let len = lit.length()
  if len == 0 {
    return CType::Float(kind=CFloatKind::Double)
  }
  let last = lit[len - 1]
  if last == 102 || last == 70 {
    CType::Float(kind=CFloatKind::Float)
  } else if last == 108 || last == 76 {
    CType::Float(kind=CFloatKind::LongDouble)
  } else {
    CType::Float(kind=CFloatKind::Double)
  }
}

///|
fn eval_const_expr_value(
  ctx : SemContext,
  expr : Expr,
  loc : SrcLoc,
) -> (Int, Bool) {
  match expr {
    Expr::IntLit(value~, ..) => (parse_int_value(value), true)
    Expr::CharLit(value~, ..) => (value, true)
    Expr::FloatLit(..) => {
      add_sem_error(ctx, loc, "invalid constant expression")
      (0, false)
    }
    Expr::StringLit(..) => {
      add_sem_error(ctx, loc, "invalid constant expression")
      (0, false)
    }
    Expr::Ident(name~, ..) =>
      match ctx.enum_consts.get(name) {
        Some(v) => (v, true)
        None => {
          add_sem_error(ctx, loc, "invalid constant expression")
          (0, false)
        }
      }
    Expr::Unary(op~, expr~, ..) => {
      let (v, ok) = eval_const_expr_value(ctx, expr, loc)
      if !ok {
        return (0, false)
      }
      match op {
        UnaryOp::Plus => (v, true)
        UnaryOp::Minus => (0 - v, true)
        UnaryOp::BitNot => (v ^ -1, true)
        UnaryOp::Not => (if v == 0 { 1 } else { 0 }, true)
        _ => {
          add_sem_error(ctx, loc, "invalid constant expression")
          (0, false)
        }
      }
    }
    Expr::Binary(op~, left~, right~, ..) => {
      let (lhs, ok_lhs) = eval_const_expr_value(ctx, left, loc)
      let (rhs, ok_rhs) = eval_const_expr_value(ctx, right, loc)
      if !ok_lhs || !ok_rhs {
        return (0, false)
      }
      match op {
        BinaryOp::Add => (lhs + rhs, true)
        BinaryOp::Sub => (lhs - rhs, true)
        BinaryOp::Mul => (lhs * rhs, true)
        BinaryOp::Div =>
          if rhs == 0 {
            add_sem_error(ctx, loc, "division by zero in constant expression")
            (0, false)
          } else {
            (lhs / rhs, true)
          }
        BinaryOp::Mod =>
          if rhs == 0 {
            add_sem_error(ctx, loc, "division by zero in constant expression")
            (0, false)
          } else {
            (lhs % rhs, true)
          }
        BinaryOp::Shl => (lhs << rhs, true)
        BinaryOp::Shr => (lhs >> rhs, true)
        BinaryOp::BitAnd => (lhs & rhs, true)
        BinaryOp::BitOr => (lhs | rhs, true)
        BinaryOp::BitXor => (lhs ^ rhs, true)
        BinaryOp::Eq => (if lhs == rhs { 1 } else { 0 }, true)
        BinaryOp::Ne => (if lhs != rhs { 1 } else { 0 }, true)
        BinaryOp::Lt => (if lhs < rhs { 1 } else { 0 }, true)
        BinaryOp::Le => (if lhs <= rhs { 1 } else { 0 }, true)
        BinaryOp::Gt => (if lhs > rhs { 1 } else { 0 }, true)
        BinaryOp::Ge => (if lhs >= rhs { 1 } else { 0 }, true)
        BinaryOp::LogAnd => (if lhs != 0 && rhs != 0 { 1 } else { 0 }, true)
        BinaryOp::LogOr => (if lhs != 0 || rhs != 0 { 1 } else { 0 }, true)
        BinaryOp::Comma => (rhs, true)
        _ => {
          add_sem_error(ctx, loc, "invalid constant expression")
          (0, false)
        }
      }
    }
    Expr::Conditional(cond~, then_expr~, else_expr~, ..) => {
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
    Expr::Cast(expr~, ..) => eval_const_expr_value(ctx, expr, loc)
    Expr::SizeofExpr(expr~, loc~) => {
      let ty = type_for_sizeof(ctx, expr)
      match type_size_align(ctx, ty, loc) {
        None => (0, false)
        Some((size, _)) => (size, true)
      }
    }
    Expr::SizeofType(ty~, loc~) => {
      register_type_defs(ctx, ty, loc)
      match type_size_align(ctx, ty, loc) {
        None => (0, false)
        Some((size, _)) => (size, true)
      }
    }
    _ => {
      add_sem_error(ctx, loc, "invalid constant expression")
      (0, false)
    }
  }
}

///|
fn eval_const_expr(ctx : SemContext, expr : Expr, loc : SrcLoc) -> Int {
  let (value, _) = eval_const_expr_value(ctx, expr, loc)
  value
}

///|
fn try_eval_int_const(ctx : SemContext, expr : Expr) -> Int? {
  match expr {
    Expr::IntLit(value~, ..) => Some(parse_int_value(value))
    Expr::CharLit(value~, ..) => Some(value)
    Expr::Ident(name~, ..) => ctx.enum_consts.get(name)
    Expr::Unary(op~, expr~, ..) =>
      match op {
        UnaryOp::Plus =>
          match try_eval_int_const(ctx, expr) {
            Some(v) => Some(v)
            None => None
          }
        UnaryOp::Minus =>
          match try_eval_int_const(ctx, expr) {
            Some(v) => Some(0 - v)
            None => None
          }
        _ => None
      }
    Expr::Cast(ty~, expr~, ..) =>
      if is_pointer_type(ty) || is_int_like(ty) {
        try_eval_int_const(ctx, expr)
      } else {
        None
      }
    _ => None
  }
}

///|
fn is_null_pointer_expr(ctx : SemContext, expr : Expr) -> Bool {
  match try_eval_int_const(ctx, expr) {
    Some(v) => v == 0
    None => false
  }
}

///|
fn check_func_decl(ctx : SemContext, func_decl : FuncDecl) -> Unit {
  check_storage_class(
    ctx,
    func_decl.storage,
    func_decl.loc,
    is_local=false,
    is_function=true,
  )
  let call_conv = normalize_call_conv(func_decl.attrs.call_conv)
  let resolved_return = resolve_type(ctx, func_decl.return_type, func_decl.loc)
  let params = func_decl.params.map(param => {
    name: param.name,
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
  add_function_sig(ctx, func_decl.name, sig, func_decl.loc, is_def=false)
}

///|
fn check_func_def(ctx : SemContext, func_def : FuncDef) -> Unit {
  check_storage_class(
    ctx,
    func_def.storage,
    func_def.loc,
    is_local=false,
    is_function=true,
  )
  let call_conv = normalize_call_conv(func_def.attrs.call_conv)
  let resolved_return = resolve_type(ctx, func_def.return_type, func_def.loc)
  let resolved_params = func_def.params.map(param => {
    name: param.name,
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
  add_function_sig(ctx, func_def.name, sig, func_def.loc, is_def=true)
  ctx.labels_defined = {}
  ctx.labels_used = []
  ctx.loop_depth = 0
  ctx.switch_depth = 0
  push_scope(ctx)
  for param in params {
    if param.name == "" {
      add_sem_error(ctx, param.loc, "parameter name missing in definition")
    } else if is_void_type(param.ty) {
      add_sem_error(ctx, param.loc, "parameter declared as void")
    } else {
      let param_ty = adjust_param_type_for_local(param.ty)
      declare_local(ctx, param.name, param_ty, param.loc)
    }
  }
  check_stmt(ctx, func_def.body, resolved_return)
  check_label_uses(ctx)
  pop_scope(ctx)
}

///|
fn func_sig_from_params(
  return_type : CType,
  params : Array[Param],
  varargs : Bool,
  is_old_style : Bool,
  call_conv : CallConv,
) -> FuncSig {
  let param_types = params.map(p => adjust_param_type_for_sig(p.ty))
  { return_type, params: param_types, varargs, is_old_style, call_conv }
}

///|
fn add_function_sig(
  ctx : SemContext,
  name : String,
  sig : FuncSig,
  loc : SrcLoc,
  is_def~ : Bool,
) -> Unit {
  if ctx.enum_consts.contains(name) {
    add_sem_error(ctx, loc, "redefinition of '\{name}'")
  }
  if ctx.functions.contains(name) {
    match ctx.functions.get(name) {
      Some(existing) =>
        if !func_sig_eq(existing, sig) {
          add_sem_error(
            ctx,
            loc,
            "conflicting function declaration for '\{name}'",
          )
        } else if existing.is_old_style && !sig.is_old_style {
          ctx.functions.set(name, sig)
        }
      None => ()
    }
  } else {
    ctx.functions.set(name, sig)
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
fn apply_inferred_array_size(ty : CType, size : Int) -> CType {
  match ty {
    CType::Qualified(qual~, base~) => {
      let updated = apply_inferred_array_size(base, size)
      CType::Qualified(qual~, base=updated)
    }
    CType::Array(elem~, size=arr_size) =>
      match arr_size {
        None => CType::Array(elem~, size=Some(size))
        Some(_) => ty
      }
    _ => ty
  }
}

///|
fn update_decl_type(
  ctx : SemContext,
  name : String,
  ty : CType,
  is_local~ : Bool,
) -> Unit {
  if is_local {
    if ctx.locals.length() == 0 {
      return
    }
    let idx = ctx.locals.length() - 1
    let scope = ctx.locals[idx]
    if scope.contains(name) {
      scope.set(name, ty)
      ctx.locals[idx] = scope
    }
  } else if ctx.globals.contains(name) {
    ctx.globals.set(name, ty)
  }
}

///|
fn require_complete_object_type(
  ctx : SemContext,
  ty : CType,
  loc : SrcLoc,
  allow_incomplete_array? : Bool = false,
) -> Unit {
  match strip_qual_attrs(ty) {
    CType::Array(elem~, size~) =>
      match size {
        None => {
          if !allow_incomplete_array {
            add_sem_error(ctx, loc, "incomplete array type")
          }
          require_complete_object_type(ctx, elem, loc)
        }
        Some(_) => require_complete_object_type(ctx, elem, loc)
      }
    CType::Struct(name=tag, fields=field_list, attrs=_) =>
      ensure_struct_fields(ctx, tag, field_list, is_union=false, loc) |> ignore
    CType::Union(name=tag, fields=field_list, attrs=_) =>
      ensure_struct_fields(ctx, tag, field_list, is_union=true, loc) |> ignore
    CType::Enum(name=tag, items~) =>
      match items {
        Some(list) =>
          if list.length() == 0 {
            add_sem_error(ctx, loc, "incomplete enum '\{tag}'")
          } else {
            let base = enum_type_from_items(ctx, list)
            if tag != "" {
              ctx.enum_types.set(tag, base)
            }
          }
        None =>
          if !ctx.enum_types.contains(tag) {
            add_sem_error(ctx, loc, "incomplete enum '\{tag}'")
          }
      }
    _ => ()
  }
}

///|
fn check_var_decl(ctx : SemContext, decl : VarDecl, is_local~ : Bool) -> Unit {
  register_type_defs(ctx, decl.ty, decl.loc)
  let resolved = resolve_type(ctx, decl.ty, decl.loc)
  let mut final_ty = resolved
  match strip_qual_attrs(resolved) {
    CType::Function(return_type~, params~, varargs~, is_old_style~, call_conv~) => {
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
      add_function_sig(ctx, decl.name, sig, decl.loc, is_def=false)
      return
    }
    _ => ()
  }
  check_storage_class(ctx, decl.storage, decl.loc, is_local~, is_function=false)
  if is_void_type(resolved) {
    add_sem_error(ctx, decl.loc, "variable '\{decl.name}' has void type")
  }
  if is_local {
    declare_local(ctx, decl.name, resolved, decl.loc)
  } else {
    declare_global(ctx, decl.name, resolved, decl.loc)
  }
  match decl.init {
    None => ()
    Some(init) =>
      match check_initializer(ctx, resolved, init, decl.loc) {
        None => ()
        Some(size) => {
          let updated = apply_inferred_array_size(resolved, size)
          final_ty = updated
          update_decl_type(ctx, decl.name, updated, is_local~)
        }
      }
  }
  if decl.storage != StorageClass::Extern || decl.init is Some(_) {
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
  ty : CType,
  init : Initializer,
  loc : SrcLoc,
) -> Int? {
  match init {
    Initializer::Expr(expr~, ..) =>
      match expr {
        Expr::StringLit(length~, ..) =>
          match strip_qual_attrs(ty) {
            CType::Array(elem~, size~) =>
              if is_char_type(elem) {
                match size {
                  None => Some(length)
                  Some(n) => {
                    if length > n {
                      add_sem_error(
                        ctx, loc, "string initializer too long for array",
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
          if !can_assign(ty, init_ty) {
            add_sem_error(
              ctx,
              loc,
              "cannot assign '\{type_to_string(init_ty)}' to '\{type_to_string(ty)}'",
            )
          }
          None
        }
      }
    Initializer::List(items~, ..) => check_initializer_list(ctx, ty, items, loc)
  }
}

///|
fn check_initializer_list(
  ctx : SemContext,
  ty : CType,
  items : Array[InitItem],
  loc : SrcLoc,
) -> Int? {
  match strip_qual_attrs(ty) {
    CType::Array(elem~, size~) => {
      let mut next_index = 0
      let mut max_index = -1
      for item in items {
        let mut index = next_index
        let mut has_index = false
        let target = if item.designators.length() > 0 {
          match item.designators[0] {
            InitDesignator::Index(expr~, loc=des_loc) =>
              match const_int_from_expr(ctx, expr, des_loc) {
                None => ()
                Some(v) => {
                  index = v
                  has_index = true
                }
              }
            _ => ()
          }
          resolve_designator_type(ctx, ty, item.designators, item.loc)
        } else {
          Some(elem)
        }
        match target {
          None => ()
          Some(target_ty) =>
            check_initializer(ctx, target_ty, item.value, item.loc) |> ignore
        }
        if has_index {
          if size is None && index < 0 {
            add_sem_error(ctx, item.loc, "array designator out of bounds")
          }
        } else {
          match size {
            None => ()
            Some(n) =>
              if index >= n {
                add_sem_error(ctx, item.loc, "too many initializers for array")
              }
          }
        }
        if index >= 0 && index > max_index {
          max_index = index
        }
        if has_index {
          if index >= 0 {
            next_index = index + 1
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
    CType::Struct(name=tag, fields=field_list, attrs=_) => {
      let fields = match field_list {
        Some(list) => Some(record_items_to_fields(list))
        None => lookup_struct_fields(ctx, tag, is_union=false)
      }
      match fields {
        None => add_sem_error(ctx, loc, "incomplete struct '\{tag}'")
        Some(list) =>
          check_struct_initializer(ctx, ty, list, items, is_union=false, loc)
      }
      None
    }
    CType::Union(name=tag, fields=field_list, attrs=_) => {
      let fields = match field_list {
        Some(list) => Some(record_items_to_fields(list))
        None => lookup_struct_fields(ctx, tag, is_union=true)
      }
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
  ty : CType,
  fields : Array[Field],
  items : Array[InitItem],
  is_union~ : Bool,
  loc : SrcLoc,
) -> Unit {
  let mut index = 0
  let mut saw = 0
  for item in items {
    if item.designators.length() > 0 {
      match item.designators[0] {
        InitDesignator::Field(name~, ..) =>
          match find_field_index(fields, name) {
            None => ()
            Some(idx) => index = idx + 1
          }
        _ => ()
      }
      match resolve_designator_type(ctx, ty, item.designators, item.loc) {
        None => ()
        Some(target_ty) =>
          check_initializer(ctx, target_ty, item.value, item.loc) |> ignore
      }
      if is_union {
        saw = saw + 1
        if saw > 1 {
          add_sem_error(ctx, item.loc, "too many initializers for union")
        }
      }
    } else {
      match next_init_field(fields, index) {
        None =>
          add_sem_error(ctx, item.loc, "too many initializers for aggregate")
        Some((field, next_index)) => {
          check_initializer(ctx, field.ty, item.value, item.loc) |> ignore
          index = next_index
          if is_union {
            saw = saw + 1
            if saw > 1 {
              add_sem_error(ctx, item.loc, "too many initializers for union")
            }
          }
        }
      }
    }
  }
  if is_union && items.length() == 0 && fields.length() == 0 {
    add_sem_error(ctx, loc, "incomplete union")
  }
}

///|
fn next_init_field(fields : Array[Field], start : Int) -> (Field, Int)? {
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
fn const_int_from_expr(ctx : SemContext, expr : Expr, loc : SrcLoc) -> Int? {
  let (value, ok) = eval_const_expr_value(ctx, expr, loc)
  if ok {
    Some(value)
  } else {
    None
  }
}

///|
fn resolve_designator_type(
  ctx : SemContext,
  ty : CType,
  designators : Array[InitDesignator],
  loc : SrcLoc,
) -> CType? {
  let mut current = strip_qual_attrs(ty)
  for des in designators {
    match des {
      InitDesignator::Index(expr~, loc=des_loc) =>
        match strip_qual_attrs(current) {
          CType::Array(elem~, size~) => {
            match size {
              None => ()
              Some(n) =>
                match const_int_from_expr(ctx, expr, des_loc) {
                  None => ()
                  Some(v) =>
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
      InitDesignator::Field(name~, ..) =>
        match strip_qual_attrs(current) {
          CType::Struct(name=tag, fields=field_list, attrs=_) => {
            let fields = match field_list {
              Some(list) => Some(record_items_to_fields(list))
              None => lookup_struct_fields(ctx, tag, is_union=false)
            }
            match fields {
              None => {
                add_sem_error(ctx, loc, "incomplete struct '\{tag}'")
                return None
              }
              Some(list) =>
                match find_field(list, name) {
                  Some(field) => current = field.ty
                  None => {
                    add_sem_error(ctx, loc, "unknown field '\{name}'")
                    return None
                  }
                }
            }
          }
          CType::Union(name=tag, fields=field_list, attrs=_) => {
            let fields = match field_list {
              Some(list) => Some(record_items_to_fields(list))
              None => lookup_struct_fields(ctx, tag, is_union=true)
            }
            match fields {
              None => {
                add_sem_error(ctx, loc, "incomplete union '\{tag}'")
                return None
              }
              Some(list) =>
                match find_field(list, name) {
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
fn check_stmt(ctx : SemContext, stmt : Stmt, return_type : CType) -> Unit {
  match stmt {
    Stmt::Compound(stmts~, ..) => {
      push_scope(ctx)
      for item in stmts {
        check_stmt(ctx, item, return_type)
      }
      pop_scope(ctx)
    }
    Stmt::If(cond~, then_branch~, else_branch~, ..) => {
      check_cond_expr(ctx, cond)
      check_stmt(ctx, then_branch, return_type)
      match else_branch {
        None => ()
        Some(stmt) => check_stmt(ctx, stmt, return_type)
      }
    }
    Stmt::While(cond~, body~, ..) => {
      check_cond_expr(ctx, cond)
      with_loop(ctx, () => check_stmt(ctx, body, return_type))
    }
    Stmt::DoWhile(cond~, body~, ..) => {
      with_loop(ctx, () => check_stmt(ctx, body, return_type))
      check_cond_expr(ctx, cond)
    }
    Stmt::For(init~, cond~, step~, body~, ..) => {
      push_scope(ctx)
      match init {
        None => ()
        Some(stmt) => check_stmt(ctx, stmt, return_type)
      }
      match cond {
        None => ()
        Some(expr) => check_cond_expr(ctx, expr)
      }
      match step {
        None => ()
        Some(expr) => type_of_expr(ctx, expr) |> ignore
      }
      with_loop(ctx, () => check_stmt(ctx, body, return_type))
      pop_scope(ctx)
    }
    Stmt::Switch(cond~, body~, loc~) => {
      let cond_ty = type_of_expr(ctx, cond)
      if !is_int_like(cond_ty) {
        add_sem_error(ctx, loc, "switch expression must have integer type")
      }
      with_switch(ctx, () => check_stmt(ctx, body, return_type))
    }
    Stmt::Case(expr~, end_expr~, body~, ..) => {
      if ctx.switch_depth == 0 {
        add_sem_error(ctx, expr_loc(expr), "case outside of switch")
      }
      let start = const_int_from_expr(ctx, expr, expr_loc(expr))
      if start is None {
        add_sem_error(ctx, expr_loc(expr), "case label is not constant")
      }
      let end = match end_expr {
        None => start
        Some(end_value) => {
          let end_val = const_int_from_expr(ctx, end_value, expr_loc(end_value))
          if end_val is None {
            add_sem_error(
              ctx,
              expr_loc(end_value),
              "case label is not constant",
            )
          }
          end_val
        }
      }
      match (start, end) {
        (Some(v1), Some(v2)) => register_case_range(ctx, v1, v2, expr_loc(expr))
        _ => ()
      }
      check_stmt(ctx, body, return_type)
    }
    Stmt::Default(body~, loc~) => {
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
    Stmt::Label(name~, body~, loc~) => {
      if ctx.labels_defined.contains(name) {
        add_sem_error(ctx, loc, "duplicate label '\{name}'")
      } else {
        ctx.labels_defined.set(name, true)
      }
      check_stmt(ctx, body, return_type)
    }
    Stmt::Goto(name~, loc~) => ctx.labels_used.push((name, loc))
    Stmt::Break(loc~) =>
      if ctx.loop_depth == 0 && ctx.switch_depth == 0 {
        add_sem_error(ctx, loc, "cannot break outside of loop or switch")
      }
    Stmt::Continue(loc~) =>
      if ctx.loop_depth == 0 {
        add_sem_error(ctx, loc, "cannot continue outside of loop")
      }
    Stmt::Return(value~, loc~) =>
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
    Stmt::Asm(asm_stmt) => check_asm_stmt(ctx, asm_stmt)
    Stmt::ExprStmt(expr~, ..) => type_of_expr(ctx, expr) |> ignore
    Stmt::DeclStmt(decls~, ..) =>
      for decl in decls {
        check_var_decl(ctx, decl, is_local=true)
      }
    Stmt::TagDef(ty~, loc~) => register_type_defs(ctx, ty, loc)
    Stmt::StaticAssert(static_assert) => check_static_assert(ctx, static_assert)
    Stmt::Empty(..) => ()
  }
}

///|
fn check_cond_expr(ctx : SemContext, expr : Expr) -> Unit {
  let ty = type_of_expr(ctx, expr)
  if !is_scalar(ty) {
    add_sem_error(ctx, expr_loc(expr), "condition expression must be scalar")
  }
}

///|
fn register_case_range(
  ctx : SemContext,
  start : Int,
  end : Int,
  loc : SrcLoc,
) -> Unit {
  if ctx.switch_stack.length() == 0 {
    return
  }
  if start > end {
    return
  }
  let idx = ctx.switch_stack.length() - 1
  let info = ctx.switch_stack[idx]
  for item in info.cases {
    let (existing_start, existing_end, _) = item
    if start <= existing_end && existing_start <= end {
      add_sem_error(ctx, loc, "duplicate case value")
      return
    }
  }
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
  ignore(ctx.switch_stack.pop())
  ctx.switch_depth = ctx.switch_depth - 1
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
fn check_asm_stmt(ctx : SemContext, asm_stmt : AsmStmt) -> Unit {
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
fn type_eq(a : CType, b : CType) -> Bool {
  let lhs = strip_qual_attrs(a)
  let rhs = strip_qual_attrs(b)
  match (lhs, rhs) {
    (CType::Void, CType::Void) => true
    (CType::Bool, CType::Bool) => true
    (
      CType::Int(kind=a_kind, unsigned=a_unsigned),
      CType::Int(kind=b_kind, unsigned=b_unsigned),
    ) => a_kind == b_kind && a_unsigned == b_unsigned
    (CType::Float(kind=a_kind), CType::Float(kind=b_kind)) => a_kind == b_kind
    (CType::Pointer(inner_a), CType::Pointer(inner_b)) =>
      type_eq(inner_a, inner_b)
    (
      CType::Array(elem=elem_a, size=size_a),
      CType::Array(elem=elem_b, size=size_b),
    ) =>
      match (size_a, size_b) {
        (Some(sa), Some(sb)) => sa == sb && type_eq(elem_a, elem_b)
        _ => type_eq(elem_a, elem_b)
      }
    (
      CType::Function(
        return_type=a_ret,
        params=a_params,
        varargs=a_varargs,
        is_old_style=a_old,
        call_conv=a_call
      ),
      CType::Function(
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
    (CType::Struct(name=a_name, ..), CType::Struct(name=b_name, ..)) =>
      a_name == b_name
    (CType::Union(name=a_name, ..), CType::Union(name=b_name, ..)) =>
      a_name == b_name
    (CType::Enum(name=a_name, ..), CType::Enum(name=b_name, ..)) =>
      a_name == b_name
    _ => false
  }
}

///|
fn types_compatible_for_decl(a : CType, b : CType) -> Bool {
  let lhs = strip_qual_attrs(a)
  let rhs = strip_qual_attrs(b)
  match (lhs, rhs) {
    (
      CType::Array(elem=elem_a, size=size_a),
      CType::Array(elem=elem_b, size=size_b),
    ) =>
      match (size_a, size_b) {
        (Some(sa), Some(sb)) =>
          sa == sb && types_compatible_for_decl(elem_a, elem_b)
        _ => types_compatible_for_decl(elem_a, elem_b)
      }
    (CType::Pointer(inner_a), CType::Pointer(inner_b)) =>
      types_compatible_for_decl(inner_a, inner_b)
    (
      CType::Function(
        return_type=a_ret,
        params=a_params,
        varargs=a_varargs,
        is_old_style=a_old,
        call_conv=a_call
      ),
      CType::Function(
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
    _ => type_eq(lhs, rhs)
  }
}

///|
fn is_int_like(ty : CType) -> Bool {
  match strip_qual_attrs(ty) {
    CType::Int(..) => true
    CType::Bool => true
    CType::Enum(..) => true
    _ => false
  }
}

///|
fn is_char_type(ty : CType) -> Bool {
  match strip_qual_attrs(ty) {
    CType::Int(kind=CIntKind::Char, ..) => true
    _ => false
  }
}

///|
fn is_scalar(ty : CType) -> Bool {
  if is_int_like(ty) || is_float_type(ty) {
    return true
  }
  match strip_qual_attrs(ty) {
    CType::Pointer(_) => true
    _ => false
  }
}

///|
fn is_pointer_type(ty : CType) -> Bool {
  match strip_qual_attrs(ty) {
    CType::Pointer(_) => true
    _ => false
  }
}

///|
fn is_void_pointer_type(ty : CType) -> Bool {
  match strip_qual_attrs(ty) {
    CType::Pointer(inner) => is_void_type(inner)
    _ => false
  }
}

///|
fn decay_type(ty : CType) -> CType {
  match strip_qual_attrs(ty) {
    CType::Array(elem~, ..) => CType::Pointer(elem)
    CType::Function(..) => CType::Pointer(ty)
    _ => ty
  }
}

///|
fn adjust_param_type_for_local(ty : CType) -> CType {
  match ty {
    CType::Qualified(qual~, base~) => {
      let adjusted = adjust_param_type_for_local(base)
      CType::Qualified(qual~, base=adjusted)
    }
    CType::Attributed(attrs~, base~) =>
      CType::Attributed(attrs~, base=adjust_param_type_for_local(base))
    CType::Array(elem~, ..) => CType::Pointer(elem)
    CType::Function(..) => CType::Pointer(ty)
    _ => ty
  }
}

///|
fn adjust_param_type_for_sig(ty : CType) -> CType {
  let adjusted = adjust_param_type_for_local(ty)
  strip_top_qualifiers(adjusted)
}

///|
fn promote_old_style_param_type(ty : CType) -> CType {
  match ty {
    CType::Qualified(qual~, base~) => {
      let updated = promote_old_style_param_type(base)
      CType::Qualified(qual~, base=updated)
    }
    CType::Attributed(attrs~, base~) =>
      CType::Attributed(attrs~, base=promote_old_style_param_type(base))
    CType::Float(kind=CFloatKind::Float) =>
      CType::Float(kind=CFloatKind::Double)
    _ => ty
  }
}

///|
fn promote_old_style_params(params : Array[Param]) -> Array[Param] {
  params.map(param => {
    name: param.name,
    ty: promote_old_style_param_type(param.ty),
    loc: param.loc,
  })
}

///|
fn lookup_struct_fields(
  ctx : SemContext,
  name : String,
  is_union~ : Bool,
) -> Array[Field]? {
  let defs = if is_union { ctx.union_defs } else { ctx.struct_defs }
  match defs.get(name) {
    None => None
    Some(def) => if def.fields.length() == 0 { None } else { Some(def.fields) }
  }
}

///|
fn find_field(fields : Array[Field], name : String) -> Field? {
  for field in fields {
    if field.name == name {
      return Some(field)
    }
  }
  None
}

///|
fn find_field_index(fields : Array[Field], name : String) -> Int? {
  for i = 0; i < fields.length(); i = i + 1 {
    if fields[i].name == name {
      return Some(i)
    }
  }
  None
}

///|
fn member_access_type(
  ctx : SemContext,
  base_ty : CType,
  name : String,
  is_arrow~ : Bool,
  loc : SrcLoc,
) -> CType? {
  let obj_ty = if is_arrow {
    match strip_top_qualifiers(base_ty) {
      CType::Pointer(inner) => inner
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
    CType::Struct(name=tag, fields=field_list, ..) => {
      let fields = match field_list {
        Some(vals) => Some(record_items_to_fields(vals))
        None => lookup_struct_fields(ctx, tag, is_union=false)
      }
      match fields {
        None => {
          add_sem_error(ctx, loc, "incomplete struct '\{tag}'")
          None
        }
        Some(list) =>
          match find_field(list, name) {
            Some(field) => Some(apply_qualifiers(field.ty, obj_qual))
            None => {
              add_sem_error(ctx, loc, "unknown field '\{name}'")
              None
            }
          }
      }
    }
    CType::Union(name=tag, fields=field_list, ..) => {
      let fields = match field_list {
        Some(vals) => Some(record_items_to_fields(vals))
        None => lookup_struct_fields(ctx, tag, is_union=true)
      }
      match fields {
        None => {
          add_sem_error(ctx, loc, "incomplete union '\{tag}'")
          None
        }
        Some(list) =>
          match find_field(list, name) {
            Some(field) => Some(apply_qualifiers(field.ty, obj_qual))
            None => {
              add_sem_error(ctx, loc, "unknown field '\{name}'")
              None
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
  base_ty : CType,
  index_ty : CType,
  loc : SrcLoc,
) -> CType? {
  if is_int_like(index_ty) {
    match strip_top_qualifiers(base_ty) {
      CType::Pointer(elem) => Some(elem)
      CType::Array(elem~, ..) => Some(elem)
      _ => {
        add_sem_error(ctx, loc, "subscripted value is not an array")
        None
      }
    }
  } else if is_int_like(base_ty) {
    match strip_top_qualifiers(index_ty) {
      CType::Pointer(elem) => Some(elem)
      CType::Array(elem~, ..) => Some(elem)
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
fn type_of_lvalue(ctx : SemContext, expr : Expr) -> CType? {
  match expr {
    Expr::Ident(name~, loc~) =>
      if ctx.enum_consts.contains(name) {
        add_sem_error(ctx, loc, "expression is not assignable")
        None
      } else {
        match lookup_value(ctx, name) {
          Some(ty) => Some(ty)
          None => {
            add_sem_error(ctx, loc, "use of undeclared identifier '\{name}'")
            None
          }
        }
      }
    Expr::Index(base~, index~, loc~) =>
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
    Expr::Member(base~, name~, is_arrow~, loc~) =>
      member_access_type(ctx, type_of_expr(ctx, base), name, is_arrow~, loc)
    Expr::Unary(op=UnaryOp::Deref, expr=inner, loc~) => {
      let inner_ty = type_of_expr(ctx, inner)
      match strip_top_qualifiers(inner_ty) {
        CType::Pointer(pointee) => Some(pointee)
        _ => {
          add_sem_error(ctx, loc, "cannot dereference non-pointer")
          None
        }
      }
    }
    _ => {
      add_sem_error(ctx, expr_loc(expr), "expression is not assignable")
      None
    }
  }
}

///|
fn type_of_expr(ctx : SemContext, expr : Expr) -> CType {
  match expr {
    Expr::IntLit(value~, ..) => int_literal_type(value)
    Expr::FloatLit(value~, ..) => float_type_from_literal(value)
    Expr::CharLit(..) => default_int_type()
    Expr::StringLit(..) => CType::Pointer(char_type())
    Expr::Ident(name~, loc~) =>
      match lookup_value(ctx, name) {
        Some(ty) => decay_type(ty)
        None => {
          add_sem_error(ctx, loc, "use of undeclared identifier '\{name}'")
          default_int_type()
        }
      }
    Expr::Unary(op~, expr~, loc~) =>
      match op {
        UnaryOp::Addr =>
          match type_of_lvalue(ctx, expr) {
            Some(ty) => CType::Pointer(ty)
            None => default_int_type()
          }
        UnaryOp::Deref => {
          let inner = type_of_expr(ctx, expr)
          match strip_qual_attrs(inner) {
            CType::Pointer(pointee) => pointee
            _ => {
              add_sem_error(ctx, loc, "cannot dereference non-pointer")
              default_int_type()
            }
          }
        }
        UnaryOp::Not => {
          let inner = type_of_expr(ctx, expr)
          if !is_scalar(inner) {
            add_sem_error(ctx, loc, "unary operator expects scalar")
          }
          default_int_type()
        }
        UnaryOp::Plus | UnaryOp::Minus => {
          let inner = type_of_expr(ctx, expr)
          if !is_arithmetic(inner) {
            add_sem_error(ctx, loc, "unary operator expects arithmetic")
          }
          if is_float_type(inner) {
            strip_qual_attrs(inner)
          } else {
            common_int_type(ctx, inner, inner)
          }
        }
        UnaryOp::BitNot => {
          let inner = type_of_expr(ctx, expr)
          if !is_int_like(inner) {
            add_sem_error(ctx, loc, "unary operator expects int")
          }
          common_int_type(ctx, inner, inner)
        }
        UnaryOp::PreInc
        | UnaryOp::PreDec
        | UnaryOp::PostInc
        | UnaryOp::PostDec =>
          match type_of_lvalue(ctx, expr) {
            None => default_int_type()
            Some(ty) => {
              if is_const_qualified(ty) {
                add_sem_error(ctx, loc, "increment of read-only location")
                return default_int_type()
              }
              match strip_qual_attrs(ty) {
                CType::Array(_) | CType::Function(..) => {
                  add_sem_error(ctx, loc, "invalid operand to increment")
                  return default_int_type()
                }
                _ => ()
              }
              if !is_arithmetic(ty) {
                match strip_qual_attrs(ty) {
                  CType::Pointer(_) => ()
                  _ => add_sem_error(ctx, loc, "invalid operand to increment")
                }
              }
              ty
            }
          }
      }
    Expr::Cast(ty~, expr~, loc~) => {
      register_type_defs(ctx, ty, loc)
      let resolved = resolve_type(ctx, ty, loc)
      type_of_expr(ctx, expr) |> ignore
      resolved
    }
    Expr::SizeofExpr(expr~, ..) => {
      let ty = type_for_sizeof(ctx, expr)
      type_size_align(ctx, ty, expr_loc(expr)) |> ignore
      default_int_type()
    }
    Expr::SizeofType(ty~, loc~) => {
      register_type_defs(ctx, ty, loc)
      let resolved = resolve_type(ctx, ty, loc)
      type_size_align(ctx, resolved, loc) |> ignore
      default_int_type()
    }
    Expr::Binary(op~, left~, right~, loc~) =>
      match op {
        BinaryOp::Assign =>
          match type_of_lvalue(ctx, left) {
            Some(lhs_ty) => {
              if is_const_qualified(lhs_ty) {
                add_sem_error(ctx, loc, "assignment to read-only location")
                return default_int_type()
              }
              match strip_qual_attrs(lhs_ty) {
                CType::Array(_) | CType::Function(..) => {
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
        BinaryOp::AddAssign
        | BinaryOp::SubAssign
        | BinaryOp::MulAssign
        | BinaryOp::DivAssign
        | BinaryOp::ModAssign
        | BinaryOp::ShlAssign
        | BinaryOp::ShrAssign
        | BinaryOp::BitAndAssign
        | BinaryOp::BitXorAssign
        | BinaryOp::BitOrAssign =>
          type_of_compound_assign(ctx, op, left, right, loc)
        BinaryOp::Comma => {
          type_of_expr(ctx, left) |> ignore
          type_of_expr(ctx, right)
        }
        BinaryOp::Add => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          match strip_qual_attrs(lhs_ty) {
            CType::Pointer(pointee) =>
              if is_int_like(rhs_ty) {
                return CType::Pointer(pointee)
              } else {
                add_sem_error(ctx, loc, "invalid operands to '+'")
                return default_int_type()
              }
            _ => ()
          }
          match strip_qual_attrs(rhs_ty) {
            CType::Pointer(pointee) =>
              if is_int_like(lhs_ty) {
                return CType::Pointer(pointee)
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
        BinaryOp::Sub => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          match strip_qual_attrs(lhs_ty) {
            CType::Pointer(pointee) =>
              match strip_qual_attrs(rhs_ty) {
                CType::Pointer(other) => {
                  if !pointer_compatible(pointee, other) {
                    add_sem_error(ctx, loc, "pointer subtraction type mismatch")
                  }
                  return default_int_type()
                }
                _ =>
                  if is_int_like(rhs_ty) {
                    return CType::Pointer(pointee)
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
        BinaryOp::Eq
        | BinaryOp::Ne
        | BinaryOp::Lt
        | BinaryOp::Le
        | BinaryOp::Gt
        | BinaryOp::Ge => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          match strip_qual_attrs(lhs_ty) {
            CType::Pointer(pointee) =>
              match strip_qual_attrs(rhs_ty) {
                CType::Pointer(other) => {
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
          match strip_qual_attrs(rhs_ty) {
            CType::Pointer(_) =>
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
        BinaryOp::LogAnd | BinaryOp::LogOr => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          if !is_scalar(lhs_ty) || !is_scalar(rhs_ty) {
            add_sem_error(ctx, loc, "binary operator expects scalar operands")
          }
          default_int_type()
        }
        BinaryOp::Mul | BinaryOp::Div => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          if !is_arithmetic(lhs_ty) || !is_arithmetic(rhs_ty) {
            add_sem_error(
              ctx, loc, "binary operator expects arithmetic operands",
            )
          }
          arithmetic_result_type(ctx, lhs_ty, rhs_ty)
        }
        BinaryOp::Mod
        | BinaryOp::Shl
        | BinaryOp::Shr
        | BinaryOp::BitAnd
        | BinaryOp::BitXor
        | BinaryOp::BitOr => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
            add_sem_error(ctx, loc, "binary operator expects int operands")
          }
          common_int_type(ctx, lhs_ty, rhs_ty)
        }
      }
    Expr::Conditional(cond~, then_expr~, else_expr~, loc~) => {
      check_cond_expr(ctx, cond)
      let then_ty = type_of_expr(ctx, then_expr)
      let else_ty = type_of_expr(ctx, else_expr)
      match (strip_qual_attrs(then_ty), strip_qual_attrs(else_ty)) {
        (CType::Pointer(a), CType::Pointer(b)) => {
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
        (CType::Pointer(_), _) =>
          if is_int_like(else_ty) && is_null_pointer_expr(ctx, else_expr) {
            return then_ty
          }
        (_, CType::Pointer(_)) =>
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
    Expr::Index(base~, index~, loc~) =>
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
    Expr::Member(base~, name~, is_arrow~, loc~) =>
      match
        member_access_type(ctx, type_of_expr(ctx, base), name, is_arrow~, loc) {
        Some(ty) => decay_type(ty)
        None => default_int_type()
      }
    Expr::Call(callee~, args~, loc~) => {
      let callee_ty = type_of_expr(ctx, callee)
      let fn_ty = match strip_qual_attrs(callee_ty) {
        CType::Function(..) => Some(strip_qual_attrs(callee_ty))
        CType::Pointer(inner) =>
          match strip_qual_attrs(inner) {
            CType::Function(..) => Some(strip_qual_attrs(inner))
            _ => None
          }
        _ => None
      }
      match fn_ty {
        Some(
          CType::Function(return_type~, params~, varargs~, is_old_style~, ..)
        ) => {
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
            let arg_ty = type_of_expr(ctx, args[i])
            if !is_old_style && i < params.length() {
              if !can_assign(params[i], arg_ty) &&
                !(is_pointer_type(params[i]) &&
                is_null_pointer_expr(ctx, args[i])) {
                add_sem_error(ctx, loc, "argument type mismatch in call")
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
fn type_of_compound_assign(
  ctx : SemContext,
  op : BinaryOp,
  left : Expr,
  right : Expr,
  loc : SrcLoc,
) -> CType {
  let lhs_ty = match type_of_lvalue(ctx, left) {
    None => return default_int_type()
    Some(ty) => ty
  }
  match strip_qual_attrs(lhs_ty) {
    CType::Array(_) | CType::Function(..) => {
      add_sem_error(ctx, loc, "assignment to non-modifiable lvalue")
      return default_int_type()
    }
    _ => ()
  }
  let rhs_ty = type_of_expr(ctx, right)
  let result_ty = match op {
    BinaryOp::AddAssign =>
      match strip_qual_attrs(lhs_ty) {
        CType::Pointer(pointee) =>
          if is_int_like(rhs_ty) {
            CType::Pointer(pointee)
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
    BinaryOp::SubAssign =>
      match strip_qual_attrs(lhs_ty) {
        CType::Pointer(pointee) =>
          if is_int_like(rhs_ty) {
            CType::Pointer(pointee)
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
    BinaryOp::MulAssign => {
      if !is_arithmetic(lhs_ty) || !is_arithmetic(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '*='")
      }
      arithmetic_result_type(ctx, lhs_ty, rhs_ty)
    }
    BinaryOp::DivAssign => {
      if !is_arithmetic(lhs_ty) || !is_arithmetic(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '/='")
      }
      arithmetic_result_type(ctx, lhs_ty, rhs_ty)
    }
    BinaryOp::ModAssign => {
      if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '%='")
      }
      common_int_type(ctx, lhs_ty, rhs_ty)
    }
    BinaryOp::ShlAssign => {
      if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '<<='")
      }
      common_int_type(ctx, lhs_ty, rhs_ty)
    }
    BinaryOp::ShrAssign => {
      if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '>>='")
      }
      common_int_type(ctx, lhs_ty, rhs_ty)
    }
    BinaryOp::BitAndAssign => {
      if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '&='")
      }
      common_int_type(ctx, lhs_ty, rhs_ty)
    }
    BinaryOp::BitXorAssign => {
      if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
        add_sem_error(ctx, loc, "invalid operands to '^='")
      }
      common_int_type(ctx, lhs_ty, rhs_ty)
    }
    BinaryOp::BitOrAssign => {
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
  ty : CType,
  loc : SrcLoc,
) -> Unit {
  if ctx.locals.length() == 0 {
    return
  }
  let idx = ctx.locals.length() - 1
  let scope = ctx.locals[idx]
  if scope.contains(name) {
    add_sem_error(ctx, loc, "redefinition of '\{name}'")
  } else {
    scope.set(name, ty)
    ctx.locals[idx] = scope
  }
}

///|
fn declare_global(
  ctx : SemContext,
  name : String,
  ty : CType,
  loc : SrcLoc,
) -> Unit {
  if ctx.enum_consts.contains(name) || ctx.globals.contains(name) {
    if ctx.enum_consts.contains(name) {
      add_sem_error(ctx, loc, "redefinition of global '\{name}'")
      return
    }
    match ctx.globals.get(name) {
      None => ctx.globals.set(name, ty)
      Some(existing) =>
        if !types_compatible_for_decl(existing, ty) {
          add_sem_error(ctx, loc, "redefinition of global '\{name}'")
        } else {
          let merged = merge_global_decl_type(existing, ty)
          ctx.globals.set(name, merged)
        }
    }
  } else {
    ctx.globals.set(name, ty)
  }
}

///|
fn merge_global_decl_type(existing : CType, incoming : CType) -> CType {
  match (existing, incoming) {
    (CType::Qualified(qual~, base~), _) => {
      let merged = merge_global_decl_type(base, incoming)
      CType::Qualified(qual~, base=merged)
    }
    (_, CType::Qualified(qual~, base~)) => {
      let merged = merge_global_decl_type(existing, base)
      CType::Qualified(qual~, base=merged)
    }
    (
      CType::Attributed(attrs=attrs_a, base=base_a),
      CType::Attributed(attrs=attrs_b, base=base_b),
    ) => {
      let merged_base = merge_global_decl_type(base_a, base_b)
      CType::Attributed(attrs=merge_attrs(attrs_a, attrs_b), base=merged_base)
    }
    (CType::Attributed(attrs=attrs_a, base=base_a), _) => {
      let merged = merge_global_decl_type(base_a, incoming)
      CType::Attributed(attrs=attrs_a, base=merged)
    }
    (_, CType::Attributed(attrs=attrs_b, base=base_b)) => {
      let merged = merge_global_decl_type(existing, base_b)
      CType::Attributed(attrs=attrs_b, base=merged)
    }
    (
      CType::Array(elem=elem_a, size=size_a),
      CType::Array(elem=elem_b, size=size_b),
    ) => {
      let merged_elem = merge_global_decl_type(elem_a, elem_b)
      let merged_size = match size_a {
        Some(_) => size_a
        None => size_b
      }
      CType::Array(elem=merged_elem, size=merged_size)
    }
    (CType::Pointer(inner_a), CType::Pointer(inner_b)) =>
      CType::Pointer(merge_global_decl_type(inner_a, inner_b))
    _ => existing
  }
}

///|
fn lookup_value(ctx : SemContext, name : String) -> CType? {
  let mut i = ctx.locals.length()
  while i > 0 {
    i = i - 1
    let scope = ctx.locals[i]
    if scope.contains(name) {
      return scope.get(name)
    }
  }
  match ctx.globals.get(name) {
    Some(ty) => Some(ty)
    None =>
      match ctx.functions.get(name) {
        Some(sig) =>
          Some(
            CType::Function(
              return_type=sig.return_type,
              params=sig.params,
              varargs=sig.varargs,
              is_old_style=sig.is_old_style,
              call_conv=sig.call_conv,
            ),
          )
        None =>
          if ctx.enum_consts.contains(name) {
            Some(default_int_type())
          } else {
            None
          }
      }
  }
}

///|
fn push_scope(ctx : SemContext) -> Unit {
  ctx.locals.push({})
}

///|
fn pop_scope(ctx : SemContext) -> Unit {
  ignore(ctx.locals.pop())
}

///|
fn add_sem_error(ctx : SemContext, loc : SrcLoc, message : String) -> Unit {
  add_error(ctx.diags, loc, message)
}

///|
fn int_kind_to_string(kind : CIntKind) -> String {
  match kind {
    CIntKind::Char => "char"
    CIntKind::Short => "short"
    CIntKind::Int => "int"
    CIntKind::Long => "long"
    CIntKind::LongLong => "long long"
  }
}

///|
fn float_kind_to_string(kind : CFloatKind) -> String {
  match kind {
    CFloatKind::Float => "float"
    CFloatKind::Double => "double"
    CFloatKind::LongDouble => "long double"
  }
}

///|
fn qual_to_string(qual : TypeQual) -> String {
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
  if parts.length() == 0 {
    ""
  } else {
    parts.join(" ") + " "
  }
}

///|
fn type_to_string(ty : CType) -> String {
  match ty {
    CType::Qualified(qual~, base~) =>
      qual_to_string(qual) + type_to_string(base)
    CType::Attributed(base~, ..) => type_to_string(base)
    CType::Void => "void"
    CType::Bool => "_Bool"
    CType::Int(kind~, unsigned~) => {
      let base = int_kind_to_string(kind)
      if unsigned {
        "unsigned " + base
      } else {
        base
      }
    }
    CType::Float(kind~) => float_kind_to_string(kind)
    CType::Pointer(inner) => type_to_string(inner) + "*"
    CType::Array(elem~, size~) =>
      match size {
        None => type_to_string(elem) + "[]"
        Some(n) => type_to_string(elem) + "[\{n}]"
      }
    CType::Struct(name~, ..) => "struct " + name
    CType::Union(name~, ..) => "union " + name
    CType::Enum(name~, ..) => "enum " + name
    CType::TypeofExpr(..) => "typeof"
    CType::Function(return_type~, params~, varargs~, is_old_style~, ..) => {
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
