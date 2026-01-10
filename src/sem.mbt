///|
struct FuncSig {
  return_type : CType
  params : Array[CType]
} derive(Show, Eq, ToJson)

///|
struct SemContext {
  diags : DiagBag
  globals : Map[String, CType]
  functions : Map[String, FuncSig]
  function_defs : Map[String, Bool]
  locals : Array[Map[String, CType]]
  type_aliases : Map[String, CType]
  struct_defs : Map[String, Array[Field]]
  union_defs : Map[String, Array[Field]]
  enum_defs : Map[String, Array[EnumItem]]
  enum_consts : Map[String, Int]
  mut labels_defined : Map[String, Bool]
  mut labels_used : Array[(String, SrcLoc)]
  mut loop_depth : Int
  mut switch_depth : Int
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
fn strip_qualifiers(ty : CType) -> CType {
  match ty {
    CType::Qualified(base~, ..) => strip_qualifiers(base)
    CType::Pointer(inner) => CType::Pointer(strip_qualifiers(inner))
    CType::Array(elem~, size~) =>
      CType::Array(elem=strip_qualifiers(elem), size~)
    CType::Function(return_type~, params~) =>
      CType::Function(
        return_type=strip_qualifiers(return_type),
        params=params.map(strip_qualifiers),
      )
    _ => ty
  }
}

///|
fn is_void_type(ty : CType) -> Bool {
  strip_qualifiers(ty) is CType::Void
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
fn is_float_type(ty : CType) -> Bool {
  match strip_qualifiers(ty) {
    CType::Float(..) => true
    _ => false
  }
}

///|
fn promote_int_type(ty : CType) -> CType {
  match strip_qualifiers(ty) {
    CType::Int(kind~, unsigned~) =>
      if int_rank(kind) < int_rank(CIntKind::Int) {
        default_int_type()
      } else {
        CType::Int(kind~, unsigned~)
      }
    CType::Bool => default_int_type()
    CType::Enum(..) => default_int_type()
    _ => default_int_type()
  }
}

///|
fn common_int_type(lhs : CType, rhs : CType) -> CType {
  let left = promote_int_type(lhs)
  let right = promote_int_type(rhs)
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
fn arithmetic_result_type(lhs : CType, rhs : CType) -> CType {
  let left = strip_qualifiers(lhs)
  let right = strip_qualifiers(rhs)
  match (left, right) {
    (CType::Float(kind=l_kind), CType::Float(kind=r_kind)) =>
      if float_rank(l_kind) >= float_rank(r_kind) {
        CType::Float(kind=l_kind)
      } else {
        CType::Float(kind=r_kind)
      }
    (CType::Float(kind~), _) => CType::Float(kind~)
    (_, CType::Float(kind~)) => CType::Float(kind~)
    _ => common_int_type(lhs, rhs)
  }
}

///|
fn is_arithmetic(ty : CType) -> Bool {
  is_int_like(ty) || is_float_type(ty)
}

///|
fn can_assign(dst : CType, src : CType) -> Bool {
  let dst_ty = strip_qualifiers(dst)
  let src_ty = strip_qualifiers(src)
  if is_arithmetic(dst_ty) && is_arithmetic(src_ty) {
    return true
  }
  match (dst_ty, src_ty) {
    (CType::Pointer(inner_a), CType::Pointer(inner_b)) =>
      type_eq(inner_a, inner_b)
    _ => type_eq(dst_ty, src_ty)
  }
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
  match strip_qualifiers(ty) {
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
    CType::Enum(..) => Some((4, 4))
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
    CType::Struct(name=tag, fields=field_list) =>
      match ensure_struct_fields(ctx, tag, field_list, is_union=false, loc) {
        None => None
        Some(fields) => Some(struct_size_align(ctx, fields, loc))
      }
    CType::Union(name=tag, fields=field_list) =>
      match ensure_struct_fields(ctx, tag, field_list, is_union=true, loc) {
        None => None
        Some(fields) => Some(union_size_align(ctx, fields, loc))
      }
    CType::Qualified(base~, ..) => type_size_align(ctx, base, loc)
  }
}

///|
fn ensure_struct_fields(
  ctx : SemContext,
  tag : String,
  fields : Array[Field]?,
  is_union~ : Bool,
  loc : SrcLoc,
) -> Array[Field]? {
  match fields {
    Some(list) => Some(list)
    None =>
      if is_union {
        match ctx.union_defs.get(tag) {
          Some(list) if list.length() > 0 => Some(list)
          _ => {
            add_sem_error(ctx, loc, "incomplete union '\{tag}'")
            None
          }
        }
      } else {
        match ctx.struct_defs.get(tag) {
          Some(list) if list.length() > 0 => Some(list)
          _ => {
            add_sem_error(ctx, loc, "incomplete struct '\{tag}'")
            None
          }
        }
      }
  }
}

///|
fn struct_size_align(
  ctx : SemContext,
  fields : Array[Field],
  loc : SrcLoc,
) -> (Int, Int) {
  let mut size = 0
  let mut align = 1
  let mut bit_unit_bits = 0
  let mut bit_offset = 0
  let mut bit_unit_size = 0
  for field in fields {
    match field.bit_width {
      Some(expr) => {
        let width = match const_int_from_expr(expr) {
          Some(v) => v
          None => 0
        }
        let base = strip_qualifiers(field.ty)
        let (base_size, base_align) = match type_size_align(ctx, base, loc) {
          None => (0, 1)
          Some(v) => v
        }
        let unit_bits = base_size * 8
        align = if base_align > align { base_align } else { align }
        if width == 0 {
          size = align_to(size, base_align)
          bit_unit_bits = 0
          bit_offset = 0
          bit_unit_size = 0
          continue
        }
        if bit_unit_bits == 0 ||
          bit_unit_bits != unit_bits ||
          width > unit_bits - bit_offset {
          size = align_to(size, base_align)
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
        let (field_size, field_align) = match
          type_size_align(ctx, field.ty, loc) {
          None => (0, 1)
          Some(v) => v
        }
        size = align_to(size, field_align)
        size = size + field_size
        align = if field_align > align { field_align } else { align }
      }
    }
  }
  if bit_unit_bits != 0 {
    size = size + bit_unit_size
  }
  size = align_to(size, align)
  (size, align)
}

///|
fn union_size_align(
  ctx : SemContext,
  fields : Array[Field],
  loc : SrcLoc,
) -> (Int, Int) {
  let mut size = 0
  let mut align = 1
  for field in fields {
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
    if field_size > size {
      size = field_size
    }
    if field_align > align {
      align = field_align
    }
  }
  size = align_to(size, align)
  (size, align)
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
    _ => type_of_expr(ctx, expr)
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
    Decl::Typedef(name~, ty~, loc~) => {
      register_type_defs(ctx, ty, loc)
      ctx.type_aliases.set(name, ty)
    }
    Decl::TagDef(ty~, loc~) => register_type_defs(ctx, ty, loc)
  }
}

///|
fn register_type_defs(ctx : SemContext, ty : CType, loc : SrcLoc) -> Unit {
  match ty {
    CType::Qualified(base~, ..) => register_type_defs(ctx, base, loc)
    CType::Struct(name~, fields~) =>
      register_struct_def(ctx, name, fields, is_union=false, loc)
    CType::Union(name~, fields~) =>
      register_struct_def(ctx, name, fields, is_union=true, loc)
    CType::Enum(name~, items~) => register_enum_def(ctx, name, items, loc)
    CType::Pointer(inner) => register_type_defs(ctx, inner, loc)
    CType::Array(elem~, ..) => register_type_defs(ctx, elem, loc)
    CType::Function(return_type~, params~) => {
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
  fields : Array[Field]?,
  is_union~ : Bool,
  loc : SrcLoc,
) -> Unit {
  if name == "" {
    return
  }
  let incoming = match fields {
    None => []
    Some(val) => val
  }
  if is_union {
    match ctx.union_defs.get(name) {
      None => ctx.union_defs.set(name, incoming)
      Some(existing) =>
        if existing.length() > 0 && incoming.length() > 0 {
          add_sem_error(ctx, loc, "redefinition of '\{name}'")
        } else if existing.length() == 0 && incoming.length() > 0 {
          ctx.union_defs.set(name, incoming)
        }
    }
  } else {
    match ctx.struct_defs.get(name) {
      None => ctx.struct_defs.set(name, incoming)
      Some(existing) =>
        if existing.length() > 0 && incoming.length() > 0 {
          add_sem_error(ctx, loc, "redefinition of '\{name}'")
        } else if existing.length() == 0 && incoming.length() > 0 {
          ctx.struct_defs.set(name, incoming)
        }
    }
  }
  if incoming.length() > 0 {
    for field in incoming {
      register_type_defs(ctx, field.ty, field.loc)
      match field.bit_width {
        None => ()
        Some(expr) => {
          if !is_int_like(field.ty) {
            add_sem_error(ctx, field.loc, "bitfields must have integer type")
          }
          match const_int_from_expr(expr) {
            None =>
              add_sem_error(ctx, field.loc, "bitfield width must be constant")
            Some(width) => {
              if width < 0 {
                add_sem_error(ctx, field.loc, "negative width in bit-field")
              }
              if width == 0 && field.name != "" {
                add_sem_error(ctx, field.loc, "zero width for bit-field")
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
    for item in incoming {
      let current = match item.value {
        None => value
        Some(expr) => eval_const_expr(ctx, expr, item.loc)
      }
      define_enum_const(ctx, item.name, item.loc, current)
      value = current + 1
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
  try @strconv.parse_int(text, base=0) catch {
    _ => 0
  } noraise {
    v => v
  }
}

///|
fn eval_const_expr(ctx : SemContext, expr : Expr, loc : SrcLoc) -> Int {
  match expr {
    Expr::IntLit(value~, ..) => parse_int_value(value)
    Expr::Ident(name~, ..) =>
      match ctx.enum_consts.get(name) {
        Some(v) => v
        None => {
          add_sem_error(ctx, loc, "invalid enum constant expression")
          0
        }
      }
    Expr::Unary(op~, expr~, ..) => {
      let v = eval_const_expr(ctx, expr, loc)
      match op {
        UnaryOp::Plus => v
        UnaryOp::Minus => 0 - v
        UnaryOp::BitNot => v ^ -1
        UnaryOp::Not => if v == 0 { 1 } else { 0 }
        _ => {
          add_sem_error(ctx, loc, "invalid enum constant expression")
          0
        }
      }
    }
    Expr::Binary(op~, left~, right~, ..) => {
      let lhs = eval_const_expr(ctx, left, loc)
      let rhs = eval_const_expr(ctx, right, loc)
      match op {
        BinaryOp::Add => lhs + rhs
        BinaryOp::Sub => lhs - rhs
        BinaryOp::Mul => lhs * rhs
        BinaryOp::Div =>
          if rhs == 0 {
            add_sem_error(ctx, loc, "division by zero in enum constant")
            0
          } else {
            lhs / rhs
          }
        BinaryOp::Mod =>
          if rhs == 0 {
            add_sem_error(ctx, loc, "division by zero in enum constant")
            0
          } else {
            lhs % rhs
          }
        BinaryOp::Shl => lhs << rhs
        BinaryOp::Shr => lhs >> rhs
        BinaryOp::BitAnd => lhs & rhs
        BinaryOp::BitOr => lhs | rhs
        BinaryOp::BitXor => lhs ^ rhs
        BinaryOp::Eq => if lhs == rhs { 1 } else { 0 }
        BinaryOp::Ne => if lhs != rhs { 1 } else { 0 }
        BinaryOp::Lt => if lhs < rhs { 1 } else { 0 }
        BinaryOp::Le => if lhs <= rhs { 1 } else { 0 }
        BinaryOp::Gt => if lhs > rhs { 1 } else { 0 }
        BinaryOp::Ge => if lhs >= rhs { 1 } else { 0 }
        BinaryOp::LogAnd => if lhs != 0 && rhs != 0 { 1 } else { 0 }
        BinaryOp::LogOr => if lhs != 0 || rhs != 0 { 1 } else { 0 }
        BinaryOp::Comma => rhs
        _ => {
          add_sem_error(ctx, loc, "invalid enum constant expression")
          0
        }
      }
    }
    Expr::Conditional(cond~, then_expr~, else_expr~, ..) =>
      if eval_const_expr(ctx, cond, loc) != 0 {
        eval_const_expr(ctx, then_expr, loc)
      } else {
        eval_const_expr(ctx, else_expr, loc)
      }
    Expr::Cast(expr~, ..) => eval_const_expr(ctx, expr, loc)
    Expr::SizeofExpr(..) => {
      add_sem_error(ctx, loc, "sizeof not supported in enum constant")
      0
    }
    Expr::SizeofType(..) => {
      add_sem_error(ctx, loc, "sizeof not supported in enum constant")
      0
    }
    _ => {
      add_sem_error(ctx, loc, "invalid enum constant expression")
      0
    }
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
  let sig = func_sig_from_params(func_decl.return_type, func_decl.params)
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
  let sig = func_sig_from_params(func_def.return_type, func_def.params)
  add_function_sig(ctx, func_def.name, sig, func_def.loc, is_def=true)
  ctx.labels_defined = {}
  ctx.labels_used = []
  ctx.loop_depth = 0
  ctx.switch_depth = 0
  push_scope(ctx)
  for param in func_def.params {
    if param.name == "" {
      add_sem_error(ctx, param.loc, "parameter name missing in definition")
    } else {
      declare_local(ctx, param.name, param.ty, param.loc)
    }
  }
  check_stmt(ctx, func_def.body, func_def.return_type)
  check_label_uses(ctx)
  pop_scope(ctx)
}

///|
fn func_sig_from_params(return_type : CType, params : Array[Param]) -> FuncSig {
  let param_types = params.map(p => p.ty)
  { return_type, params: param_types }
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
  if !type_eq(a.return_type, b.return_type) {
    return false
  }
  if a.params.length() != b.params.length() {
    return false
  }
  for i = 0; i < a.params.length(); i = i + 1 {
    if !type_eq(a.params[i], b.params[i]) {
      return false
    }
  }
  true
}

///|
fn check_var_decl(ctx : SemContext, decl : VarDecl, is_local~ : Bool) -> Unit {
  register_type_defs(ctx, decl.ty, decl.loc)
  match strip_qualifiers(decl.ty) {
    CType::Function(return_type~, params~) => {
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
      let sig = { return_type, params }
      add_function_sig(ctx, decl.name, sig, decl.loc, is_def=false)
      return
    }
    _ => ()
  }
  check_storage_class(ctx, decl.storage, decl.loc, is_local~, is_function=false)
  if is_void_type(decl.ty) {
    add_sem_error(ctx, decl.loc, "variable '\{decl.name}' has void type")
  }
  if is_local {
    declare_local(ctx, decl.name, decl.ty, decl.loc)
  } else {
    declare_global(ctx, decl.name, decl.ty, decl.loc)
  }
  match decl.init {
    None => ()
    Some(init) => check_initializer(ctx, decl.ty, init, decl.loc)
  }
}

///|
fn check_initializer(
  ctx : SemContext,
  ty : CType,
  init : Initializer,
  loc : SrcLoc,
) -> Unit {
  match init {
    Initializer::Expr(expr~, ..) => {
      let init_ty = type_of_expr(ctx, expr)
      if !can_assign(ty, init_ty) {
        add_sem_error(
          ctx,
          loc,
          "cannot assign '\{type_to_string(init_ty)}' to '\{type_to_string(ty)}'",
        )
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
) -> Unit {
  match strip_qualifiers(ty) {
    CType::Array(elem~, size~) => {
      let mut count = 0
      for item in items {
        let target = if item.designators.length() > 0 {
          resolve_designator_type(ctx, ty, item.designators, item.loc)
        } else {
          Some(elem)
        }
        match target {
          None => ()
          Some(target_ty) =>
            check_initializer(ctx, target_ty, item.value, item.loc)
        }
        if item.designators.length() == 0 {
          count = count + 1
        }
      }
      match size {
        None => ()
        Some(n) =>
          if count > n {
            add_sem_error(ctx, loc, "too many initializers for array")
          }
      }
    }
    CType::Struct(name=tag, fields=field_list) => {
      let fields = match field_list {
        Some(list) => Some(list)
        None => lookup_struct_fields(ctx, tag, is_union=false)
      }
      match fields {
        None => add_sem_error(ctx, loc, "incomplete struct '\{tag}'")
        Some(list) =>
          check_struct_initializer(ctx, ty, list, items, is_union=false, loc)
      }
    }
    CType::Union(name=tag, fields=field_list) => {
      let fields = match field_list {
        Some(list) => Some(list)
        None => lookup_struct_fields(ctx, tag, is_union=true)
      }
      match fields {
        None => add_sem_error(ctx, loc, "incomplete union '\{tag}'")
        Some(list) =>
          check_struct_initializer(ctx, ty, list, items, is_union=true, loc)
      }
    }
    _ => add_sem_error(ctx, loc, "initializer list for non-aggregate")
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
      match resolve_designator_type(ctx, ty, item.designators, item.loc) {
        None => ()
        Some(target_ty) =>
          check_initializer(ctx, target_ty, item.value, item.loc)
      }
    } else {
      match next_init_field(fields, index) {
        None =>
          add_sem_error(ctx, item.loc, "too many initializers for aggregate")
        Some((field, next_index)) => {
          check_initializer(ctx, field.ty, item.value, item.loc)
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
fn const_int_from_expr(expr : Expr) -> Int? {
  match expr {
    Expr::IntLit(value~, ..) => Some(parse_int_value(value))
    _ => None
  }
}

///|
fn resolve_designator_type(
  ctx : SemContext,
  ty : CType,
  designators : Array[InitDesignator],
  loc : SrcLoc,
) -> CType? {
  let mut current = strip_qualifiers(ty)
  for des in designators {
    match des {
      InitDesignator::Index(expr~, ..) =>
        match strip_qualifiers(current) {
          CType::Array(elem~, size~) => {
            match size {
              None => ()
              Some(n) =>
                match const_int_from_expr(expr) {
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
        match strip_qualifiers(current) {
          CType::Struct(name=tag, fields=field_list) => {
            let fields = match field_list {
              Some(list) => Some(list)
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
          CType::Union(name=tag, fields=field_list) => {
            let fields = match field_list {
              Some(list) => Some(list)
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
    Stmt::Switch(cond~, body~, ..) => {
      check_cond_expr(ctx, cond)
      with_switch(ctx, () => check_stmt(ctx, body, return_type))
    }
    Stmt::Case(expr~, end_expr~, body~, ..) => {
      if ctx.switch_depth == 0 {
        add_sem_error(ctx, expr_loc(expr), "case outside of switch")
      }
      check_cond_expr(ctx, expr)
      match end_expr {
        None => ()
        Some(end_value) => check_cond_expr(ctx, end_value)
      }
      check_stmt(ctx, body, return_type)
    }
    Stmt::Default(body~, loc~) => {
      if ctx.switch_depth == 0 {
        add_sem_error(ctx, loc, "default outside of switch")
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
          } else if !can_assign(return_type, expr_ty) {
            add_sem_error(
              ctx,
              loc,
              "return type '\{type_to_string(expr_ty)}' does not match '\{type_to_string(return_type)}'",
            )
          }
        }
      }
    Stmt::ExprStmt(expr~, ..) => type_of_expr(ctx, expr) |> ignore
    Stmt::DeclStmt(decls~, ..) =>
      for decl in decls {
        check_var_decl(ctx, decl, is_local=true)
      }
    Stmt::TagDef(ty~, loc~) => register_type_defs(ctx, ty, loc)
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
fn with_loop(ctx : SemContext, f : () -> Unit) -> Unit {
  ctx.loop_depth = ctx.loop_depth + 1
  f()
  ctx.loop_depth = ctx.loop_depth - 1
}

///|
fn with_switch(ctx : SemContext, f : () -> Unit) -> Unit {
  ctx.switch_depth = ctx.switch_depth + 1
  f()
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
fn type_eq(a : CType, b : CType) -> Bool {
  let lhs = strip_qualifiers(a)
  let rhs = strip_qualifiers(b)
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
    ) => size_a == size_b && type_eq(elem_a, elem_b)
    (
      CType::Function(return_type=a_ret, params=a_params),
      CType::Function(return_type=b_ret, params=b_params),
    ) => {
      if !type_eq(a_ret, b_ret) {
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
fn is_int_like(ty : CType) -> Bool {
  match strip_qualifiers(ty) {
    CType::Int(..) => true
    CType::Bool => true
    CType::Enum(..) => true
    _ => false
  }
}

///|
fn is_scalar(ty : CType) -> Bool {
  if is_int_like(ty) || is_float_type(ty) {
    return true
  }
  match strip_qualifiers(ty) {
    CType::Pointer(_) => true
    _ => false
  }
}

///|
fn decay_type(ty : CType) -> CType {
  match strip_qualifiers(ty) {
    CType::Array(elem~, ..) => CType::Pointer(elem)
    CType::Function(..) => CType::Pointer(ty)
    _ => ty
  }
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
    Some(fields) => if fields.length() == 0 { None } else { Some(fields) }
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
fn member_access_type(
  ctx : SemContext,
  base_ty : CType,
  name : String,
  is_arrow~ : Bool,
  loc : SrcLoc,
) -> CType? {
  let obj_ty = if is_arrow {
    match strip_qualifiers(base_ty) {
      CType::Pointer(inner) => inner
      _ => {
        add_sem_error(ctx, loc, "arrow operator requires pointer")
        return None
      }
    }
  } else {
    base_ty
  }
  match strip_qualifiers(obj_ty) {
    CType::Struct(name=tag, fields=field_list) => {
      let fields = match field_list {
        Some(vals) => Some(vals)
        None => lookup_struct_fields(ctx, tag, is_union=false)
      }
      match fields {
        None => {
          add_sem_error(ctx, loc, "incomplete struct '\{tag}'")
          None
        }
        Some(list) =>
          match find_field(list, name) {
            Some(field) => Some(field.ty)
            None => {
              add_sem_error(ctx, loc, "unknown field '\{name}'")
              None
            }
          }
      }
    }
    CType::Union(name=tag, fields=field_list) => {
      let fields = match field_list {
        Some(vals) => Some(vals)
        None => lookup_struct_fields(ctx, tag, is_union=true)
      }
      match fields {
        None => {
          add_sem_error(ctx, loc, "incomplete union '\{tag}'")
          None
        }
        Some(list) =>
          match find_field(list, name) {
            Some(field) => Some(field.ty)
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
  if !is_int_like(index_ty) {
    add_sem_error(ctx, loc, "array index must be int")
  }
  match strip_qualifiers(base_ty) {
    CType::Pointer(elem) => Some(elem)
    CType::Array(elem~, ..) => Some(elem)
    _ => {
      add_sem_error(ctx, loc, "subscripted value is not an array")
      None
    }
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
      match strip_qualifiers(inner_ty) {
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
    Expr::IntLit(..) => default_int_type()
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
          match strip_qualifiers(inner) {
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
            strip_qualifiers(inner)
          } else {
            common_int_type(inner, inner)
          }
        }
        UnaryOp::BitNot => {
          let inner = type_of_expr(ctx, expr)
          if !is_int_like(inner) {
            add_sem_error(ctx, loc, "unary operator expects int")
          }
          common_int_type(inner, inner)
        }
        UnaryOp::PreInc
        | UnaryOp::PreDec
        | UnaryOp::PostInc
        | UnaryOp::PostDec =>
          match type_of_lvalue(ctx, expr) {
            None => default_int_type()
            Some(ty) => {
              match strip_qualifiers(ty) {
                CType::Array(_) | CType::Function(..) => {
                  add_sem_error(ctx, loc, "invalid operand to increment")
                  return default_int_type()
                }
                _ => ()
              }
              if !is_arithmetic(ty) {
                match strip_qualifiers(ty) {
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
      type_of_expr(ctx, expr) |> ignore
      ty
    }
    Expr::SizeofExpr(expr~, ..) => {
      let ty = type_for_sizeof(ctx, expr)
      type_size_align(ctx, ty, expr_loc(expr)) |> ignore
      default_int_type()
    }
    Expr::SizeofType(ty~, loc~) => {
      register_type_defs(ctx, ty, loc)
      type_size_align(ctx, ty, loc) |> ignore
      default_int_type()
    }
    Expr::Binary(op~, left~, right~, loc~) =>
      match op {
        BinaryOp::Assign =>
          match type_of_lvalue(ctx, left) {
            Some(lhs_ty) => {
              match strip_qualifiers(lhs_ty) {
                CType::Array(_) | CType::Function(..) => {
                  add_sem_error(ctx, loc, "assignment to non-modifiable lvalue")
                  return default_int_type()
                }
                _ => ()
              }
              let rhs_ty = type_of_expr(ctx, right)
              if !can_assign(lhs_ty, rhs_ty) {
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
        BinaryOp::Comma => {
          type_of_expr(ctx, left) |> ignore
          type_of_expr(ctx, right)
        }
        BinaryOp::Add => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          match strip_qualifiers(lhs_ty) {
            CType::Pointer(pointee) =>
              if is_int_like(rhs_ty) {
                return CType::Pointer(pointee)
              } else {
                add_sem_error(ctx, loc, "invalid operands to '+'")
                return default_int_type()
              }
            _ => ()
          }
          match strip_qualifiers(rhs_ty) {
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
          arithmetic_result_type(lhs_ty, rhs_ty)
        }
        BinaryOp::Sub => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          match strip_qualifiers(lhs_ty) {
            CType::Pointer(pointee) =>
              match strip_qualifiers(rhs_ty) {
                CType::Pointer(other) => {
                  if !type_eq(pointee, other) {
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
          arithmetic_result_type(lhs_ty, rhs_ty)
        }
        BinaryOp::Eq
        | BinaryOp::Ne
        | BinaryOp::Lt
        | BinaryOp::Le
        | BinaryOp::Gt
        | BinaryOp::Ge => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          match strip_qualifiers(lhs_ty) {
            CType::Pointer(pointee) =>
              match strip_qualifiers(rhs_ty) {
                CType::Pointer(other) => {
                  if !type_eq(pointee, other) {
                    add_sem_error(ctx, loc, "pointer comparison type mismatch")
                  }
                  return default_int_type()
                }
                _ => ()
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
          arithmetic_result_type(lhs_ty, rhs_ty)
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
          common_int_type(lhs_ty, rhs_ty)
        }
      }
    Expr::Conditional(cond~, then_expr~, else_expr~, loc~) => {
      check_cond_expr(ctx, cond)
      let then_ty = type_of_expr(ctx, then_expr)
      let else_ty = type_of_expr(ctx, else_expr)
      if is_arithmetic(then_ty) && is_arithmetic(else_ty) {
        return arithmetic_result_type(then_ty, else_ty)
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
      let fn_ty = match strip_qualifiers(callee_ty) {
        CType::Function(..) => Some(strip_qualifiers(callee_ty))
        CType::Pointer(inner) =>
          match strip_qualifiers(inner) {
            CType::Function(..) => Some(strip_qualifiers(inner))
            _ => None
          }
        _ => None
      }
      match fn_ty {
        Some(CType::Function(return_type~, params~)) => {
          if params.length() != args.length() {
            add_sem_error(ctx, loc, "argument count mismatch in call")
          } else {
            for i = 0; i < params.length(); i = i + 1 {
              let arg_ty = type_of_expr(ctx, args[i])
              if !can_assign(params[i], arg_ty) {
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
    add_sem_error(ctx, loc, "redefinition of global '\{name}'")
  } else {
    ctx.globals.set(name, ty)
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
          Some(CType::Function(return_type=sig.return_type, params=sig.params))
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
    CType::Function(return_type~, params~) => {
      let args = params.map(type_to_string).join(", ")
      "fn(\{args}) -> \{type_to_string(return_type)}"
    }
  }
}
