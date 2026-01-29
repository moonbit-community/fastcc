///|
test "attributes helpers" {
  let base = empty_attrs()
  assert_true(attrs_is_empty(base))
  let incoming = attrs_with(packed=true, weak=true)
  let merged = merge_attrs(base, incoming)
  assert_true(merged.packed)
  assert_true(merged.weak)
}

///|
test "type qualifiers helpers" {
  let base = empty_qual()
  let const_qual = with_const(base)
  let combined = merge_qual(const_qual, with_volatile(empty_qual()))
  let ty = apply_qualifiers(CType::Int(kind=CIntKind::Int, unsigned=false), combined)
  match ty {
    CType::Qualified(qual~, ..) => assert_true(qual.is_const && qual.is_volatile)
    _ => fail("expected qualified type")
  }
}

///|
test "expr helpers" {
  let loc = @source.dummy_loc(0)
  let expr = Expr::IntLit(value="1", node_id=42, loc=loc)
  assert_true(expr_loc(expr) == loc)
  assert_eq(expr_node_id(expr), 42)
  assert_true(parse_int64_literal("0x10") is Some(16))
}
