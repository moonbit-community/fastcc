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
}

///|
fn new_sem_context(diags : DiagBag) -> SemContext {
  { diags, globals: {}, functions: {}, function_defs: {}, locals: [] }
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
    Decl::Var(var_decl) => check_var_decl(ctx, var_decl, is_local=false)
    Decl::FuncDecl(func_decl) => check_func_decl(ctx, func_decl)
    Decl::FuncDef(func_def) => check_func_def(ctx, func_def)
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
  push_scope(ctx)
  for param in func_def.params {
    declare_local(ctx, param.name, param.ty, param.loc)
  }
  check_stmt(ctx, func_def.body, func_def.return_type)
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
  if a.return_type != b.return_type {
    return false
  }
  if a.params.length() != b.params.length() {
    return false
  }
  for i = 0; i < a.params.length(); i = i + 1 {
    if a.params[i] != b.params[i] {
      return false
    }
  }
  true
}

///|
fn check_var_decl(ctx : SemContext, decl : VarDecl, is_local~ : Bool) -> Unit {
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
      if init_ty != decl.ty {
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
      check_stmt(ctx, body, return_type)
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
      check_stmt(ctx, body, return_type)
      pop_scope(ctx)
    }
    Stmt::Break(..) => ()
    Stmt::Continue(..) => ()
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
          } else if expr_ty != return_type {
            add_sem_error(
              ctx,
              loc,
              "return type '\{type_to_string(expr_ty)}' does not match '\{type_to_string(return_type)}'",
            )
          }
        }
      }
    Stmt::ExprStmt(expr~, ..) => type_of_expr(ctx, expr) |> ignore
    Stmt::DeclStmt(decl~, ..) => check_var_decl(ctx, decl, is_local=true)
    Stmt::Empty(..) => ()
  }
}

///|
fn check_cond_expr(ctx : SemContext, expr : Expr) -> Unit {
  let ty = type_of_expr(ctx, expr)
  if ty != CType::Int {
    add_sem_error(ctx, expr_loc(expr), "condition expression must be int")
  }
}

///|
fn type_of_expr(ctx : SemContext, expr : Expr) -> CType {
  match expr {
    Expr::IntLit(..) => CType::Int
    Expr::Ident(name~, loc~) =>
      match lookup_value(ctx, name) {
        Some(ty) => ty
        None => {
          add_sem_error(ctx, loc, "use of undeclared identifier '\{name}'")
          CType::Int
        }
      }
    Expr::Unary(expr~, loc~, ..) => {
      let inner = type_of_expr(ctx, expr)
      if inner != CType::Int {
        add_sem_error(ctx, loc, "unary operator expects int")
      }
      CType::Int
    }
    Expr::Binary(op~, left~, right~, loc~) =>
      match op {
        BinaryOp::Assign =>
          match left {
            Expr::Ident(name~, loc~) =>
              match lookup_value(ctx, name) {
                Some(lhs_ty) => {
                  let rhs_ty = type_of_expr(ctx, right)
                  if lhs_ty != rhs_ty {
                    add_sem_error(
                      ctx,
                      loc,
                      "cannot assign '\{type_to_string(rhs_ty)}' to '\{type_to_string(lhs_ty)}'",
                    )
                  }
                  lhs_ty
                }
                None => {
                  add_sem_error(
                    ctx,
                    loc,
                    "assignment to undeclared identifier '\{name}'",
                  )
                  CType::Int
                }
              }
            _ => {
              add_sem_error(ctx, loc, "assignment target must be an identifier")
              CType::Int
            }
          }
        _ => {
          let lhs_ty = type_of_expr(ctx, left)
          let rhs_ty = type_of_expr(ctx, right)
          if lhs_ty != CType::Int || rhs_ty != CType::Int {
            add_sem_error(ctx, loc, "binary operator expects int operands")
          }
          CType::Int
        }
      }
    Expr::Call(callee~, args~, loc~) => {
      let callee_ty = type_of_expr(ctx, callee)
      match callee_ty {
        CType::Function(return_type~, params~) => {
          if params.length() != args.length() {
            add_sem_error(ctx, loc, "argument count mismatch in call")
          } else {
            for i = 0; i < params.length(); i = i + 1 {
              let arg_ty = type_of_expr(ctx, args[i])
              if arg_ty != params[i] {
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
  if ctx.globals.contains(name) {
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
        None => None
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
    CType::Function(return_type~, params~) => {
      let args = params.map(type_to_string).join(", ")
      "fn(\{args}) -> \{type_to_string(return_type)}"
    }
  }
}
