///|
fn parse_int64_literal(text : String) -> Int64? {
  let value = try @strconv.parse_int(text, base=0) catch {
    _ => None
  } noraise {
    v => Some(v.to_int64())
  }
  value
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
