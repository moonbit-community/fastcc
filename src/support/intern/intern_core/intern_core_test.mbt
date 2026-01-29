///|
test "interner core basics" {
  let interner = @intern_core.new_string_interner_with_capacity(capacity=2)
  let (_, id) = interner.intern_view_with_id("world"[:])
  assert_true(id > 0)
  inspect(interner.get(id), content="world")
}
