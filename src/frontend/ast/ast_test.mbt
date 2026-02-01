///|
test "attributes helpers" {
  let base = @ast.empty_attrs()
  assert_true(@ast.attrs_is_empty(base))
  let incoming = @ast.attrs_with(packed=true, weak=true)
  let merged = @ast.merge_attrs(base, incoming)
  assert_true(merged.packed)
  assert_true(merged.weak)
}

///|
test "type qualifiers helpers" {
  let base = @ast.empty_qual()
  let const_qual = @ast.with_const(base)
  let combined = @ast.merge_qual(
    const_qual,
    @ast.with_volatile(@ast.empty_qual()),
  )
  let ty = @ast.apply_qualifiers(
    @ast.CType::Int(kind=@ast.CIntKind::Int, unsigned=false),
    combined,
  )
  match ty {
    @ast.CType::Qualified(qual~, ..) =>
      assert_true(qual.is_const && qual.is_volatile)
    _ => fail("expected qualified type")
  }
}

///|
test "expr helpers" {
  let loc = @source.dummy_loc(0)
  let expr = @ast.Expr::IntLit(value="1", node_id=42, loc~)
  assert_true(@ast.expr_loc(expr) == loc)
  assert_eq(@ast.expr_node_id(expr), 42)
  assert_true(@ast.parse_int64_literal("0x10") is Some(16))
}
