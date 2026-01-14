///|
fn parse_int64_literal(text : String) -> Int64? {
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
fn const_i64_from_expr(expr : Expr) -> Int64? {
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
fn codegen_arm64_object_bytes(unit : TranslationUnit, bag : DiagBag) -> Bytes? {
  codegen_arm64_object_bytes_from_ast(unit, bag)
}
