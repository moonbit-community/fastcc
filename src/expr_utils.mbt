///|
fn expr_is_lvalue_simple(expr : Expr) -> Bool {
  match expr {
    Expr::Ident(..) => true
    Expr::Index(..) => true
    Expr::Member(base~, is_arrow~, ..) =>
      if is_arrow { true } else { expr_is_lvalue_simple(base) }
    Expr::Unary(op=UnaryOp::Deref, ..) => true
    Expr::CompoundLiteral(..) => true
    Expr::StmtExpr(stmts~, ..) => {
      if stmts.length() == 0 {
        false
      } else {
        match stmts[stmts.length() - 1] {
          Stmt::ExprStmt(expr~, ..) => expr_is_lvalue_simple(expr)
          _ => false
        }
      }
    }
    _ => false
  }
}

///|
fn expr_may_call(expr : Expr) -> Bool {
  match expr {
    Expr::Call(..) => true
    Expr::Unary(expr=inner, ..) | Expr::Cast(expr=inner, ..) => expr_may_call(inner)
    Expr::SizeofExpr(..) | Expr::AlignofExpr(..) => false
    Expr::Binary(left~, right~, ..) =>
      expr_may_call(left) || expr_may_call(right)
    Expr::Conditional(cond~, then_expr~, else_expr~, ..) =>
      expr_may_call(cond) || expr_may_call(then_expr) || expr_may_call(else_expr)
    Expr::Index(base~, index~, ..) =>
      expr_may_call(base) || expr_may_call(index)
    Expr::Member(base~, ..) => expr_may_call(base)
    Expr::BuiltinVaArg(list~, ..) => expr_may_call(list)
    Expr::StmtExpr(..) => true
    _ => false
  }
}

///|
