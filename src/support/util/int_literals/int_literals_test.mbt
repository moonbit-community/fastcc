///|
test "int literal helpers" {
  assert_eq(@int_literals.int_literal_base("0x10"), 16)
  assert_eq(@int_literals.int_literal_end("123u"), 3)
  inspect(@int_literals.parse_int_suffix("llu"), content="(2, true)")
}
