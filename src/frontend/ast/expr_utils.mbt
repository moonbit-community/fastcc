///|
pub fn expr_is_lvalue_simple(expr : Expr) -> Bool {
  match expr {
    Expr::Ident(..) => true
    Expr::Index(..) => true
    Expr::Member(base~, is_arrow~, ..) =>
      is_arrow || expr_is_lvalue_simple(base)
    Expr::Unary(op=UnaryOp::Deref, ..) => true
    Expr::CompoundLiteral(..) => true
    Expr::StmtExpr(stmts~, ..) => {
      let len = stmts.length()
      if len == 0 {
        false
      } else {
        match stmts[len - 1] {
          Stmt::ExprStmt(expr~, ..) => expr_is_lvalue_simple(expr)
          _ => false
        }
      }
    }
    _ => false
  }
}

///|
pub fn expr_may_call(expr : Expr) -> Bool {
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
pub fn parse_int64_literal(text : String) -> Int64? {
  if text == "" {
    return None
  }

  let len = text.length()

  let zero = 48
  let x_lower = 120
  let x_upper = 88
  let b_lower = 98
  let b_upper = 66
  let underscore = 95

  let mut base = 10
  let mut start = 0
  if len >= 2 && text.code_unit_at(0).to_int() == zero {
    let second = text.code_unit_at(1).to_int()
    if second == x_lower || second == x_upper {
      base = 16
      start = 2
    } else if second == b_lower || second == b_upper {
      base = 2
      start = 2
    } else {
      base = 8
      start = 1
    }
  }

  fn digit_value(base : Int, ch : Int) -> UInt64? {
    let zero = 48
    let nine = 57
    let lower_a = 97
    let lower_f = 102
    let upper_a = 65
    let upper_f = 70
    if ch >= zero && ch <= nine {
      Some((ch - zero).to_uint64())
    } else if base == 16 && ch >= lower_a && ch <= lower_f {
      Some((10 + (ch - lower_a)).to_uint64())
    } else if base == 16 && ch >= upper_a && ch <= upper_f {
      Some((10 + (ch - upper_a)).to_uint64())
    } else {
      None
    }
  }

  if start >= len {
    return Some(0)
  }

  let mut acc : UInt64 = 0
  let base_u64 = base.to_uint64()
  // Leading zero already contributes a digit for octal/decimal zero forms like "0l".
  let mut any_digit = start == 1

  let mut i = start
  while i < len {
    let ch = text.code_unit_at(i).to_int()
    i = i + 1
    if ch == underscore {
      continue
    }
    match digit_value(base, ch) {
      None => break // suffix starts or invalid digit
      Some(d) =>
        if d >= base_u64 {
          return None
        } else {
          any_digit = true
          acc = acc * base_u64 + d
        }
    }
  }
  if !any_digit {
    None
  } else {
    Some(acc.reinterpret_as_int64())
  }
}

///|
pub fn const_i64_from_expr(expr : Expr) -> Int64? {
  match expr {
    Expr::IntLit(value~, ..) => parse_int64_literal(value)
    Expr::Unary(op=UnaryOp::Plus, expr=inner, ..) => const_i64_from_expr(inner)
    Expr::Unary(op=UnaryOp::Minus, expr=inner, ..) =>
      match const_i64_from_expr(inner) {
        None => None
        Some(v) => Some(-v)
      }
    _ => None
  }
}

///|
pub fn expr_loc(expr : Expr) -> @source.SrcLoc {
  match expr {
    Expr::IntLit(loc~, ..) => loc
    Expr::FloatLit(loc~, ..) => loc
    Expr::CharLit(loc~, ..) => loc
    Expr::StringLit(loc~, ..) => loc
    Expr::Ident(loc~, ..) => loc
    Expr::LabelAddr(loc~, ..) => loc
    Expr::BuiltinTypesCompatibleP(loc~, ..) => loc
    Expr::BuiltinOffsetof(loc~, ..) => loc
    Expr::BuiltinVaArg(loc~, ..) => loc
    Expr::Unary(loc~, ..) => loc
    Expr::Cast(loc~, ..) => loc
    Expr::CompoundLiteral(loc~, ..) => loc
    Expr::StmtExpr(loc~, ..) => loc
    Expr::SizeofExpr(loc~, ..) => loc
    Expr::SizeofType(loc~, ..) => loc
    Expr::AlignofExpr(loc~, ..) => loc
    Expr::AlignofType(loc~, ..) => loc
    Expr::Binary(loc~, ..) => loc
    Expr::Conditional(loc~, ..) => loc
    Expr::Call(loc~, ..) => loc
    Expr::Index(loc~, ..) => loc
    Expr::Member(loc~, ..) => loc
  }
}

///|
pub fn expr_node_id(expr : Expr) -> Int {
  match expr {
    Expr::IntLit(node_id~, ..) => node_id
    Expr::FloatLit(node_id~, ..) => node_id
    Expr::CharLit(node_id~, ..) => node_id
    Expr::StringLit(node_id~, ..) => node_id
    Expr::Ident(node_id~, ..) => node_id
    Expr::LabelAddr(node_id~, ..) => node_id
    Expr::BuiltinTypesCompatibleP(node_id~, ..) => node_id
    Expr::BuiltinOffsetof(node_id~, ..) => node_id
    Expr::BuiltinVaArg(node_id~, ..) => node_id
    Expr::Unary(node_id~, ..) => node_id
    Expr::Cast(node_id~, ..) => node_id
    Expr::CompoundLiteral(node_id~, ..) => node_id
    Expr::StmtExpr(node_id~, ..) => node_id
    Expr::SizeofExpr(node_id~, ..) => node_id
    Expr::SizeofType(node_id~, ..) => node_id
    Expr::AlignofExpr(node_id~, ..) => node_id
    Expr::AlignofType(node_id~, ..) => node_id
    Expr::Binary(node_id~, ..) => node_id
    Expr::Conditional(node_id~, ..) => node_id
    Expr::Call(node_id~, ..) => node_id
    Expr::Index(node_id~, ..) => node_id
    Expr::Member(node_id~, ..) => node_id
  }
}

///|
