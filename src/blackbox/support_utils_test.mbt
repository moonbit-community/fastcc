///|
test "support util literals" {
  assert_eq(@util.int_literal_end(""), 0)
  assert_eq(@util.int_literal_end("123u"), 3)
  assert_eq(@util.int_literal_end("0x1fU"), 4)
  assert_eq(@util.int_literal_end("0b1010"), 6)
  assert_eq(@util.int_literal_end("0777"), 4)

  assert_eq(@util.int_literal_base("123"), 10)
  assert_eq(@util.int_literal_base("0x10"), 16)
  assert_eq(@util.int_literal_base("0b10"), 2)
  assert_eq(@util.int_literal_base("077"), 8)
  assert_eq(@util.int_literal_base_from("0x1f", 4), 16)

  assert_eq(@util.parse_uint64_literal("0x10", 16), (16 : UInt64))
  assert_eq(@util.parse_uint64_literal_prefix("0x10zz", 16, 4), (16 : UInt64))

  assert_eq(@util.parse_int_suffix("llU"), (2, true))
  assert_eq(@util.parse_int_suffix_range("123uLL", 3), (2, true))
}

///|
test "support util strings and intern" {
  assert_eq(@util.slice_string("abc", 0, 3), "abc")
  assert_eq(@util.slice_string("abc", 1, 2), "b")

  assert_eq(@util.hex_digit_value(('F' : UInt16)), Some(15))
  assert_eq(@util.hex_digit_value(('g' : UInt16)), None)

  let interner = @intern.new_string_interner_with_capacity(capacity=0)
  let (value, id) = interner.intern_view_with_id("hello"[:])
  assert_eq(value, "hello")
  assert_eq(interner.get(id), "hello")
  assert_eq(interner.get(0), "")
  assert_eq(interner.get(id + 1), "")
}
