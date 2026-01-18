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
