///|
test "string interner basics" {
  let interner = @intern.new_string_interner_with_capacity()
  let (_, id) = interner.intern_view_with_id("hello"[:])
  assert_true(id > 0)
  inspect(interner.get(id), content="hello")
}
