///|
fn parse_int64_literal(text : String) -> Int64? {
  if text == "" {
    return None
  }

  // Strip common C integer suffixes (U/L/UL/LL/etc).
  let mut end = text.length()
  while end > 0 {
    let ch = text.code_unit_at(end - 1).to_int()
    let is_suffix = (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)
    if !is_suffix {
      break
    }
    end = end - 1
  }
  if end == 0 {
    return None
  }

  let base = if end >= 2 &&
      text.code_unit_at(0).to_int() == 48 &&
      (text.code_unit_at(1).to_int() == 120 || text.code_unit_at(1).to_int() == 88) {
    16
  } else if end >= 2 && text.code_unit_at(0).to_int() == 48 {
    8
  } else {
    10
  }
  let start = if base == 16 { 2 } else if base == 8 { 1 } else { 0 }
  if start >= end {
    return Some(0)
  }

  let mut acc : UInt64 = 0
  let base_u64 = base.to_uint64()
  let zero = 48
  let nine = 57
  let lower_a = 97
  let lower_f = 102
  let upper_a = 65
  let upper_f = 70
  let underscore = 95

  let mut i = start
  while i < end {
    let ch = text.code_unit_at(i).to_int()
    i = i + 1
    if ch == underscore {
      continue
    }
    let d : UInt64 =
      if ch >= zero && ch <= nine {
        (ch - zero).to_uint64()
      } else if ch >= lower_a && ch <= lower_f {
        (10 + (ch - lower_a)).to_uint64()
      } else if ch >= upper_a && ch <= upper_f {
        (10 + (ch - upper_a)).to_uint64()
      } else {
        return None
      }
    if d >= base_u64 {
      return None
    }
    acc = acc * base_u64 + d
  }
  Some(acc.to_int64())
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
fn const_u32_from_initializer(init : Initializer) -> UInt? {
  match init {
    Initializer::Expr(expr~, ..) =>
      match const_i64_from_expr(expr) {
        None => None
        Some(value) =>
          Some((value.to_uint64() & (0xffff_ffff : UInt64)).to_uint())
      }
    _ => None
  }
}

///|
fn codegen_arm64_object_bytes(unit : TranslationUnit, bag : DiagBag) -> Bytes? {
  codegen_arm64_object_bytes_from_ast(unit, bag)
}
