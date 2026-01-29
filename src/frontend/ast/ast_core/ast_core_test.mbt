///|
test "attributes helpers" {
  let base = @ast_core.empty_attrs()
  assert_true(@ast_core.attrs_is_empty(base))
  let incoming = @ast_core.attrs_with(packed=true, weak=true)
  let merged = @ast_core.merge_attrs(base, incoming)
  assert_true(merged.packed)
  assert_true(merged.weak)
}
///|
test "type qualifiers helpers" {
  let base = @ast_core.empty_qual()
  let const_qual = @ast_core.with_const(base)
  let combined = @ast_core.merge_qual(const_qual, @ast_core.with_volatile(@ast_core.empty_qual()))
  let ty = @ast_core.apply_qualifiers(@ast_core.CType::Int(kind=@ast_core.CIntKind::Int, unsigned=false), combined)
  match ty {
    @ast_core.CType::Qualified(qual~, ..) => assert_true(qual.is_const && qual.is_volatile)
    _ => fail("expected qualified type")
  }
}
///|
test "expr helpers" {
  let loc = @source.dummy_loc(0)
  let expr = @ast_core.Expr::IntLit(value="1", node_id=42, loc=loc)
  assert_true(@ast_core.expr_loc(expr) == loc)
  assert_eq(@ast_core.expr_node_id(expr), 42)
  assert_true(@ast_core.parse_int64_literal("0x10") is Some(16))
}

///|
test "expr helper variants" {
  let loc = @source.dummy_loc(1)
  let left = @ast_core.Expr::IntLit(value="2", node_id=7, loc=loc)
  let right = @ast_core.Expr::IntLit(value="3", node_id=8, loc=loc)
  let expr = @ast_core.Expr::Binary(
    op=@ast_core.BinaryOp::Add,
    left=left,
    right=right,
    node_id=99,
    loc=loc,
  )
  assert_true(@ast_core.expr_loc(expr) == loc)
  assert_eq(@ast_core.expr_node_id(expr), 99)
}
