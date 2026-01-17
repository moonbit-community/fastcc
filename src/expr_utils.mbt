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
fn expr_may_be_aggregate(expr : Expr) -> Bool {
  match expr {
    Expr::IntLit(..)
    | Expr::FloatLit(..)
    | Expr::CharLit(..)
    | Expr::StringLit(..)
    | Expr::BuiltinTypesCompatibleP(..)
    | Expr::BuiltinOffsetof(..)
    | Expr::SizeofExpr(..)
    | Expr::SizeofType(..)
    | Expr::AlignofExpr(..)
    | Expr::AlignofType(..) => false
    Expr::Unary(op~, ..) =>
      match op {
        UnaryOp::Not
        | UnaryOp::Plus
        | UnaryOp::Minus
        | UnaryOp::BitNot
        | UnaryOp::Addr
        | UnaryOp::PreInc
        | UnaryOp::PreDec
        | UnaryOp::PostInc
        | UnaryOp::PostDec => false
        UnaryOp::Deref => true
      }
    Expr::Binary(op~, ..) =>
      match op {
        BinaryOp::Assign | BinaryOp::Comma => true
        _ => false
      }
    Expr::Conditional(..)
    | Expr::Call(..)
    | Expr::Cast(..)
    | Expr::CompoundLiteral(..)
    | Expr::StmtExpr(..)
    | Expr::BuiltinVaArg(..)
    | Expr::Member(..)
    | Expr::Index(..)
    | Expr::Ident(..) => true
  }
}
