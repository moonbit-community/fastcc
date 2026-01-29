///|
test "int literal helpers" {
  assert_eq(@int_literals.int_literal_base("0x10"), 16)
  assert_eq(@int_literals.int_literal_end("123u"), 3)
  inspect(@int_literals.parse_int_suffix("llu"), content="(2, true)")
}

///|
test "uint64 literal parsing" {
  assert_eq(@int_literals.parse_uint64_literal("0755", 8), 493)
  assert_eq(@int_literals.parse_uint64_literal("0b1011", 2), 11)
  let text = "0x10ffu"
  let end = @int_literals.int_literal_end(text)
  assert_eq(@int_literals.parse_uint64_literal_prefix(text, 16, end), 4351)
}
