///|
test "int literal helpers" {
  assert_eq(@int_literals.int_literal_end(""), 0)
  assert_eq(@int_literals.int_literal_base("0x10"), 16)
  assert_eq(@int_literals.int_literal_end("123u"), 3)
  assert_eq(@int_literals.int_literal_end("0x1fU"), 4)
  assert_eq(@int_literals.int_literal_end("0b1010"), 6)
  assert_eq(@int_literals.int_literal_end("0777"), 4)
  assert_eq(@int_literals.int_literal_end("0x"), 2)
  assert_eq(@int_literals.int_literal_end("0b"), 2)
  assert_eq(@int_literals.int_literal_base("123"), 10)
  assert_eq(@int_literals.int_literal_base("0b10"), 2)
  assert_eq(@int_literals.int_literal_base("077"), 8)
  assert_eq(@int_literals.int_literal_base("0"), 10)
  assert_eq(@int_literals.int_literal_base_from("0x1f", 4), 16)
  assert_eq(@int_literals.int_literal_base_from("07", 2), 8)
  assert_eq(@int_literals.parse_uint64_literal("0x10", 16), (16 : UInt64))
  assert_eq(@int_literals.parse_uint64_literal("0xAF", 16), (175 : UInt64))
  assert_eq(@int_literals.parse_uint64_literal("0b101", 2), (5 : UInt64))
  assert_eq(@int_literals.parse_uint64_literal("0", 10), (0 : UInt64))
  assert_eq(@int_literals.parse_uint64_literal("12g", 10), (12 : UInt64))
  assert_eq(@int_literals.parse_uint64_literal("19", 8), (1 : UInt64))
  assert_eq(
    @int_literals.parse_uint64_literal_prefix("0x10zz", 16, 4),
    (16 : UInt64),
  )
  assert_eq(
    @int_literals.parse_uint64_literal_prefix("12g", 10, 3),
    (12 : UInt64),
  )
  assert_eq(@int_literals.parse_uint64_literal_prefix("19", 8, 2), (1 : UInt64))
  assert_eq(@int_literals.parse_int_suffix("llU"), (2, true))
  assert_eq(@int_literals.parse_int_suffix("lllu"), (2, true))
  assert_eq(@int_literals.parse_int_suffix_range("123uLL", 3), (2, true))
  assert_eq(@int_literals.parse_int_suffix_range("123LLLL", 3), (2, false))
  inspect(@int_literals.parse_int_suffix("llu"), content="(2, true)")
}
