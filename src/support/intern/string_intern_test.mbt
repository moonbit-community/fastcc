///|
test "string interner basics" {
  let interner = @intern.new_string_interner_with_capacity()
  let (_, id) = interner.intern_view_with_id("hello"[:])
  assert_true(id > 0)
  inspect(interner.get(id), content="hello")
}

///|
test "string interner id stability and capacity edges" {
  let interner = @intern.new_string_interner_with_capacity(capacity=0)
  assert_eq(interner.intern_view("world"[:]), "world")
  let (value, id) = interner.intern_view_with_id("hello"[:])
  assert_eq(value, "hello")
  assert_eq(interner.get(id), "hello")
  assert_eq(interner.get(0), "")
  assert_eq(interner.get(id + 1), "")

  let (value2, id2) = interner.intern_view_with_id("hello"[:])
  assert_eq(value2, "hello")
  assert_eq(id2, id)
  assert_eq(interner.intern_view("hello"[:]), "hello")

  let interner2 = @intern.new_string_interner_with_capacity(capacity=-1)
  let (value3, id3) = interner2.intern_view_with_id("cap"[:])
  assert_eq(value3, "cap")
  assert_eq(interner2.get(id3), "cap")
}
