///|
test "attributes helpers" {
  let base = empty_attrs()
  assert_true(attrs_is_empty(base))
  let incoming = attrs_with(packed=true, weak=true)
  let merged = merge_attrs(base, incoming)
  assert_true(merged.packed)
  assert_true(merged.weak)
}
