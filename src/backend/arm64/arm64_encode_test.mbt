///|
test "arm64 encode bimm64 basics" {
  assert_eq(@arm64.arm64_encode_bimm64(0UL), -1)
  assert_eq(@arm64.arm64_encode_bimm64(0xffffffffffffffffUL), -1)
  let ok_lo = @arm64.arm64_encode_bimm64(0x00000000000000ffUL)
  assert_true(ok_lo != -1)
  let ok_rep = @arm64.arm64_encode_bimm64(0x00ff00ff00ff00ffUL)
  assert_true(ok_rep != -1)
}

///|
test "arm64 movi immediate encodings" {
  let reg : UInt = 3
  let imm0 : UInt64 = 0x1234
  let insn0 = @arm64.arm64_movi(reg, imm0)
  let expect0 = (0x52800000 : UInt64)
    .lor(reg.to_uint64())
    .lor(imm0 << 5)
    .to_uint()
  assert_eq(insn0, expect0)
  let imm1 : UInt64 = 0xabcdUL << 16
  let insn1 = @arm64.arm64_movi(reg, imm1)
  let expect1 = (0x52a00000 : UInt64)
    .lor(reg.to_uint64())
    .lor(imm1 >> 11)
    .to_uint()
  assert_eq(insn1, expect1)
  let imm2 : UInt64 = 0xbeefUL << 32
  let insn2 = @arm64.arm64_movi(reg, imm2)
  let expect2 = (0xd2c00000 : UInt64)
    .lor(reg.to_uint64())
    .lor(imm2 >> 27)
    .to_uint()
  assert_eq(insn2, expect2)
  let imm3 : UInt64 = 0x1111UL << 48
  let insn3 = @arm64.arm64_movi(reg, imm3)
  let expect3 = (0xd2e00000 : UInt64)
    .lor(reg.to_uint64())
    .lor(imm3 >> 43)
    .to_uint()
  assert_eq(insn3, expect3)
}
