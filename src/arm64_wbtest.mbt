///|
test "arm64 encode bitmask immediates" {
  let v0 : UInt64 = 0
  let v1 : UInt64 = 1
  let v3 : UInt64 = 3
  let v16 : UInt64 = 0xffff
  let v32 : UInt64 = 0x80000000
  let v_high : UInt64 = 0xffff0000
  let v_mix : UInt64 = 0xffffffff0000ffff
  assert_eq(arm64_encode_bimm64(v0), -1)
  assert_eq(arm64_encode_bimm64(v1), 0x1000)
  assert_eq(arm64_encode_bimm64(v3), 0x1001)
  assert_eq(arm64_encode_bimm64(v16), 0x100f)
  assert_eq(arm64_encode_bimm64(v32), 0x1840)
  assert_eq(arm64_encode_bimm64(v_high), 0x1c0f)
  assert_eq(arm64_encode_bimm64(v_mix), 0x182f)
}

///|
test "arm64 movi encodings" {
  let reg : UInt = 0
  let v0 : UInt64 = 0x1234
  let v1 : UInt64 = 0x12340000
  let v2 : UInt64 = 0x123400000000
  let v3 : UInt64 = 0x1234000000000000
  let v4 : UInt64 = 0xffff0001
  let v5 : UInt64 = 0x00ff00ff
  assert_eq(arm64_movi(reg, v0), (0x52824680 : UInt))
  assert_eq(arm64_movi(reg, v1), (0x52a24680 : UInt))
  assert_eq(arm64_movi(reg, v2), (0xd2c24680 : UInt))
  assert_eq(arm64_movi(reg, v3), (0xd2e24680 : UInt))
  assert_eq(arm64_movi(reg, v4), (0x129fffc0 : UInt))
  assert_eq(arm64_movi(reg, v5), (0x32009fe0 : UInt))
}

///|
test "arm64 movimm emits movk sequence" {
  let emitter = new_arm64_emitter()
  let v0 : UInt64 = 0x12345678
  arm64_movimm(emitter, 0, v0)
  assert_eq(emitter.code.length(), 2)
  assert_eq(emitter.code[0], (0xd28acf00 : UInt))
  assert_eq(emitter.code[1], (0xf2a24680 : UInt))
}

///|
test "arm64 movimm uses movn when beneficial" {
  let emitter = new_arm64_emitter()
  let v0 : UInt64 = 0xffff1234ffff5678
  arm64_movimm(emitter, 0, v0)
  assert_eq(emitter.code.length(), 4)
  assert_eq(emitter.code[0], (0x929530e0 : UInt))
  assert_eq(emitter.code[1], (0xf2bfffe0 : UInt))
  assert_eq(emitter.code[2], (0xf2c24680 : UInt))
  assert_eq(emitter.code[3], (0xf2ffffe0 : UInt))
}
