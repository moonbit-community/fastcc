///|
test "intern token hash step" {
  let h0 : UInt = @intern.tok_hash_init
  let code_a : UInt16 = ('a' : UInt16)
  let code_b : UInt16 = ('b' : UInt16)
  let h1 = @intern.tok_hash_step(h0, code_a)
  let expect_h1 = h0 + (h0 << 5) + (h0 >> 27) + code_a.to_uint()
  assert_eq(h1, expect_h1)
  let h2 = @intern.tok_hash_step(h1, code_b)
  let expect_h2 = h1 + (h1 << 5) + (h1 >> 27) + code_b.to_uint()
  assert_eq(h2, expect_h2)
  let h1_again = @intern.tok_hash_step(h0, code_a)
  assert_eq(h1_again, h1)
}
