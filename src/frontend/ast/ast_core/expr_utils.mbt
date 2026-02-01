///|
pub fn expr_is_lvalue_simple(expr : Expr) -> Bool {
  match expr {
    Ident(..) => true
    Index(..) => true
    Member(base~, is_arrow~, ..) => is_arrow || expr_is_lvalue_simple(base)
    Unary(op=Deref, ..) => true
    CompoundLiteral(..) => true
    StmtExpr(stmts~, ..) => {
      let len = stmts.length()
      if len == 0 {
        false
      } else {
        match stmts[len - 1] {
          ExprStmt(expr~, ..) => expr_is_lvalue_simple(expr)
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
    Call(..) => true
    Unary(expr=inner, ..) | Cast(expr=inner, ..) => expr_may_call(inner)
    SizeofExpr(..) | AlignofExpr(..) => false
    Binary(left~, right~, ..) => expr_may_call(left) || expr_may_call(right)
    Conditional(cond~, then_expr~, else_expr~, ..) =>
      expr_may_call(cond) ||
      expr_may_call(then_expr) ||
      expr_may_call(else_expr)
    Index(base~, index~, ..) => expr_may_call(base) || expr_may_call(index)
    Member(base~, ..) => expr_may_call(base)
    BuiltinVaArg(list~, ..) => expr_may_call(list)
    StmtExpr(..) => true
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
    IntLit(value~, ..) => parse_int64_literal(value)
    Unary(op=Plus, expr=inner, ..) => const_i64_from_expr(inner)
    Unary(op=Minus, expr=inner, ..) =>
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
    IntLit(loc~, ..) => loc
    FloatLit(loc~, ..) => loc
    CharLit(loc~, ..) => loc
    StringLit(loc~, ..) => loc
    Ident(loc~, ..) => loc
    LabelAddr(loc~, ..) => loc
    BuiltinTypesCompatibleP(loc~, ..) => loc
    BuiltinOffsetof(loc~, ..) => loc
    BuiltinVaArg(loc~, ..) => loc
    Unary(loc~, ..) => loc
    Cast(loc~, ..) => loc
    CompoundLiteral(loc~, ..) => loc
    StmtExpr(loc~, ..) => loc
    SizeofExpr(loc~, ..) => loc
    SizeofType(loc~, ..) => loc
    AlignofExpr(loc~, ..) => loc
    AlignofType(loc~, ..) => loc
    Binary(loc~, ..) => loc
    Conditional(loc~, ..) => loc
    Call(loc~, ..) => loc
    Index(loc~, ..) => loc
    Member(loc~, ..) => loc
  }
}

///|
pub fn expr_node_id(expr : Expr) -> Int {
  match expr {
    IntLit(node_id~, ..) => node_id
    FloatLit(node_id~, ..) => node_id
    CharLit(node_id~, ..) => node_id
    StringLit(node_id~, ..) => node_id
    Ident(node_id~, ..) => node_id
    LabelAddr(node_id~, ..) => node_id
    BuiltinTypesCompatibleP(node_id~, ..) => node_id
    BuiltinOffsetof(node_id~, ..) => node_id
    BuiltinVaArg(node_id~, ..) => node_id
    Unary(node_id~, ..) => node_id
    Cast(node_id~, ..) => node_id
    CompoundLiteral(node_id~, ..) => node_id
    StmtExpr(node_id~, ..) => node_id
    SizeofExpr(node_id~, ..) => node_id
    SizeofType(node_id~, ..) => node_id
    AlignofExpr(node_id~, ..) => node_id
    AlignofType(node_id~, ..) => node_id
    Binary(node_id~, ..) => node_id
    Conditional(node_id~, ..) => node_id
    Call(node_id~, ..) => node_id
    Index(node_id~, ..) => node_id
    Member(node_id~, ..) => node_id
  }
}

///|
