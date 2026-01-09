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
  let sig = func_sig_from_params(func_decl.return_type, func_decl.params)
  add_function_sig(ctx, func_decl.name, sig, func_decl.loc, is_def=false)
}

///|
fn check_func_def(ctx : SemContext, func_def : FuncDef) -> Unit {
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
  match decl.ty {
    CType::Function(return_type~, params~) => {
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
  if decl.ty == CType::Void {
    add_sem_error(ctx, decl.loc, "variable '\{decl.name}' has void type")
  }
  if is_local {
    declare_local(ctx, decl.name, decl.ty, decl.loc)
  } else {
    declare_global(ctx, decl.name, decl.ty, decl.loc)
  }
  match decl.init {
    None => ()
    Some(expr) => {
      let init_ty = type_of_expr(ctx, expr)
      if !type_eq(init_ty, decl.ty) {
        add_sem_error(
          ctx,
          decl.loc,
          "cannot assign '\{type_to_string(init_ty)}' to '\{type_to_string(decl.ty)}'",
        )
      }
    }
  }
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
          if return_type != CType::Void {
            add_sem_error(ctx, loc, "non-void function must return a value")
          }
        Some(expr) => {
          let expr_ty = type_of_expr(ctx, expr)
          if return_type == CType::Void {
            add_sem_error(ctx, loc, "void function should not return a value")
          } else if !type_eq(expr_ty, return_type) {
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
    add_sem_error(ctx, expr_loc(expr), "condition expression must be int")
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
  match (a, b) {
    (CType::Void, CType::Void) => true
    (CType::Int, CType::Int) => true
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
  match ty {
    CType::Int => true
    CType::Enum(..) => true
    _ => false
  }
}

///|
fn is_scalar(ty : CType) -> Bool {
  if is_int_like(ty) {
    return true
  }
  match ty {
    CType::Pointer(_) => true
    _ => false
  }
}

///|
fn decay_type(ty : CType) -> CType {
  match ty {
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
    match base_ty {
      CType::Pointer(inner) => inner
      _ => {
        add_sem_error(ctx, loc, "arrow operator requires pointer")
        return None
      }
    }
  } else {
    base_ty
  }
  match obj_ty {
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
  match base_ty {
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
      match inner_ty {
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
    Expr::IntLit(..) => CType::Int
    Expr::Ident(name~, loc~) =>
      match lookup_value(ctx, name) {
        Some(ty) => decay_type(ty)
        None => {
          add_sem_error(ctx, loc, "use of undeclared identifier '\{name}'")
          CType::Int
        }
      }
    Expr::Unary(op~, expr~, loc~) =>
      match op {
        UnaryOp::Addr =>
          match type_of_lvalue(ctx, expr) {
            Some(ty) => CType::Pointer(ty)
            None => CType::Int
          }
        UnaryOp::Deref => {
          let inner = type_of_expr(ctx, expr)
          match inner {
            CType::Pointer(pointee) => pointee
            _ => {
              add_sem_error(ctx, loc, "cannot dereference non-pointer")
              CType::Int
            }
          }
        }
        UnaryOp::Not => {
          let inner = type_of_expr(ctx, expr)
          if !is_scalar(inner) {
            add_sem_error(ctx, loc, "unary operator expects scalar")
          }
          CType::Int
        }
        UnaryOp::Plus | UnaryOp::Minus | UnaryOp::BitNot => {
          let inner = type_of_expr(ctx, expr)
          if !is_int_like(inner) {
            add_sem_error(ctx, loc, "unary operator expects int")
          }
          CType::Int
        }
        UnaryOp::PreInc
        | UnaryOp::PreDec
        | UnaryOp::PostInc
        | UnaryOp::PostDec =>
          match type_of_lvalue(ctx, expr) {
            None => CType::Int
            Some(ty) => {
              let mut result = ty
              match ty {
                CType::Array(_) | CType::Function(..) => {
                  add_sem_error(ctx, loc, "invalid operand to increment")
                  result = CType::Int
                }
                _ => ()
              }
              if !is_int_like(ty) {
                match ty {
                  CType::Pointer(_) => ()
                  _ => add_sem_error(ctx, loc, "invalid operand to increment")
                }
              }
              result
            }
          }
      }
    Expr::Cast(ty~, expr~, loc~) => {
      register_type_defs(ctx, ty, loc)
      type_of_expr(ctx, expr) |> ignore
      ty
    }
    Expr::SizeofExpr(expr~, ..) => {
      type_of_expr(ctx, expr) |> ignore
      CType::Int
    }
    Expr::SizeofType(ty~, loc~) => {
      register_type_defs(ctx, ty, loc)
      CType::Int
    }
    Expr::Binary(op~, left~, right~, loc~) =>
      match op {
        BinaryOp::Assign =>
          match type_of_lvalue(ctx, left) {
            Some(lhs_ty) => {
              match lhs_ty {
                CType::Array(_) | CType::Function(..) => {
                  add_sem_error(ctx, loc, "assignment to non-modifiable lvalue")
                  return CType::Int
                }
                _ => ()
              }
              let rhs_ty = type_of_expr(ctx, right)
              if !type_eq(lhs_ty, rhs_ty) {
                add_sem_error(
                  ctx,
                  loc,
                  "cannot assign '\{type_to_string(rhs_ty)}' to '\{type_to_string(lhs_ty)}'",
                )
              }
              lhs_ty
            }
            None => CType::Int
          }
        BinaryOp::Comma => {
          type_of_expr(ctx, left) |> ignore
          type_of_expr(ctx, right)
        }
        BinaryOp::Add => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          match lhs_ty {
            CType::Pointer(pointee) =>
              if is_int_like(rhs_ty) {
                return CType::Pointer(pointee)
              } else {
                add_sem_error(ctx, loc, "invalid operands to '+'")
                return CType::Int
              }
            _ => ()
          }
          match rhs_ty {
            CType::Pointer(pointee) =>
              if is_int_like(lhs_ty) {
                return CType::Pointer(pointee)
              } else {
                add_sem_error(ctx, loc, "invalid operands to '+'")
                return CType::Int
              }
            _ => ()
          }
          if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
            add_sem_error(ctx, loc, "binary operator expects int operands")
          }
          CType::Int
        }
        BinaryOp::Sub => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          match lhs_ty {
            CType::Pointer(pointee) =>
              match rhs_ty {
                CType::Pointer(other) => {
                  if !type_eq(pointee, other) {
                    add_sem_error(ctx, loc, "pointer subtraction type mismatch")
                  }
                  return CType::Int
                }
                _ =>
                  if is_int_like(rhs_ty) {
                    return CType::Pointer(pointee)
                  } else {
                    add_sem_error(ctx, loc, "invalid operands to '-'")
                    return CType::Int
                  }
              }
            _ => ()
          }
          if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
            add_sem_error(ctx, loc, "binary operator expects int operands")
          }
          CType::Int
        }
        BinaryOp::Eq
        | BinaryOp::Ne
        | BinaryOp::Lt
        | BinaryOp::Le
        | BinaryOp::Gt
        | BinaryOp::Ge => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          match lhs_ty {
            CType::Pointer(pointee) =>
              match rhs_ty {
                CType::Pointer(other) => {
                  if !type_eq(pointee, other) {
                    add_sem_error(ctx, loc, "pointer comparison type mismatch")
                  }
                  return CType::Int
                }
                _ => ()
              }
            _ => ()
          }
          if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
            add_sem_error(ctx, loc, "binary operator expects int operands")
          }
          CType::Int
        }
        BinaryOp::LogAnd | BinaryOp::LogOr => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          if !is_scalar(lhs_ty) || !is_scalar(rhs_ty) {
            add_sem_error(ctx, loc, "binary operator expects scalar operands")
          }
          CType::Int
        }
        _ => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          if !is_int_like(lhs_ty) || !is_int_like(rhs_ty) {
            add_sem_error(ctx, loc, "binary operator expects int operands")
          }
          CType::Int
        }
      }
    Expr::Conditional(cond~, then_expr~, else_expr~, loc~) => {
      check_cond_expr(ctx, cond)
      let then_ty = type_of_expr(ctx, then_expr)
      let else_ty = type_of_expr(ctx, else_expr)
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
        None => CType::Int
      }
    Expr::Member(base~, name~, is_arrow~, loc~) =>
      match
        member_access_type(ctx, type_of_expr(ctx, base), name, is_arrow~, loc) {
        Some(ty) => decay_type(ty)
        None => CType::Int
      }
    Expr::Call(callee~, args~, loc~) => {
      let callee_ty = type_of_expr(ctx, callee)
      let fn_ty = match callee_ty {
        CType::Function(..) => Some(callee_ty)
        CType::Pointer(inner) =>
          match inner {
            CType::Function(..) => Some(inner)
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
              if !type_eq(arg_ty, params[i]) {
                add_sem_error(ctx, loc, "argument type mismatch in call")
                break
              }
            }
          }
          return_type
        }
        _ => {
          add_sem_error(ctx, loc, "call target is not a function")
          CType::Int
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
            Some(CType::Int)
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
fn type_to_string(ty : CType) -> String {
  match ty {
    CType::Void => "void"
    CType::Int => "int"
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
