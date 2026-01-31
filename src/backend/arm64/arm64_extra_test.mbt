///|
test "arm64 register helpers" {
  assert_eq(@arm64.treg_r(5), 5)
  assert_eq(@arm64.treg_f(0), @arm64.TREG_F0)
  assert_eq(@arm64.fltr(@arm64.TREG_F0 + 2), 2)
  assert_true(@arm64.is_freg(@arm64.TREG_F0))
  assert_eq(@arm64.intr(5), 5)
  assert_eq(@arm64.intr(@arm64.TREG_R30 + 1), 30)
}

///|
test "arm64 masks and encodings" {
  assert_eq(@arm64.u64_mask(0), 0UL)
  assert_eq(@arm64.u64_mask(4), 15UL)
  assert_eq(@arm64.arm64_encode_bimm64(0UL), -1)
  assert_true(@arm64.arm64_encode_bimm64(0x5555555555555555UL) >= 0)
  assert_true(@arm64.arm64_encode_bimm64(0x1111111111111111UL) >= 0)
  assert_true(@arm64.arm64_encode_bimm64(0x0101010101010101UL) >= 0)
  assert_true(@arm64.arm64_encode_bimm64(0x00ff00ff00ff00ffUL) >= 0)
  assert_true(@arm64.arm64_encode_bimm64(0x8000000000000001UL) >= 0)
}

///|
test "arm64 movi patterns" {
  let reg : UInt = 1
  let value0 : UInt64 = 0x1234
  let expected0 = (0x52800000 : UInt64)
    .lor(reg.to_uint64())
    .lor(value0 << 5)
    .to_uint()
  assert_eq(@arm64.arm64_movi(reg, value0), expected0)

  let value1 : UInt64 = 0x1234_0000
  let expected1 = (0x52a00000 : UInt64)
    .lor(reg.to_uint64())
    .lor(value1 >> 11)
    .to_uint()
  assert_eq(@arm64.arm64_movi(reg, value1), expected1)

  let value2 : UInt64 = 0x1234_0000_0000
  let expected2 = (0xd2c00000 : UInt64)
    .lor(reg.to_uint64())
    .lor(value2 >> 27)
    .to_uint()
  assert_eq(@arm64.arm64_movi(reg, value2), expected2)
}

///|
test "arm64 movi complement patterns" {
  let reg : UInt = 2
  let value3 : UInt64 = 0x00000000_ffff0001
  let expected3 = (0x12800000 : UInt64)
    .lor(reg.to_uint64())
    .lor((value3.lnot() << 5) & 0x1fffe0)
    .to_uint()
  assert_eq(@arm64.arm64_movi(reg, value3), expected3)

  let value4 : UInt64 = 0x00000000_1234ffff
  let expected4 = (0x12a00000 : UInt64)
    .lor(reg.to_uint64())
    .lor((value4.lnot() >> 11) & 0x1fffe0)
    .to_uint()
  assert_eq(@arm64.arm64_movi(reg, value4), expected4)

  let value5 : UInt64 = 0xffff_ffff_ffff0000
  let expected5 = (0x92800000 : UInt64)
    .lor(reg.to_uint64())
    .lor((value5.lnot() << 5) & 0x1fffe0)
    .to_uint()
  assert_eq(@arm64.arm64_movi(reg, value5), expected5)

  let value6 : UInt64 = 0xffff_ffff_0000ffff
  let expected6 = (0x92a00000 : UInt64)
    .lor(reg.to_uint64())
    .lor((value6.lnot() >> 11) & 0x1fffe0)
    .to_uint()
  assert_eq(@arm64.arm64_movi(reg, value6), expected6)

  let value7 : UInt64 = 0xffff_0000_ffff_ffff
  let expected7 = (0x92c00000 : UInt64)
    .lor(reg.to_uint64())
    .lor((value7.lnot() >> 27) & 0x1fffe0)
    .to_uint()
  assert_eq(@arm64.arm64_movi(reg, value7), expected7)

  let value8 : UInt64 = 0x0000_ffff_ffff_ffff
  let expected8 = (0x92e00000 : UInt64)
    .lor(reg.to_uint64())
    .lor((value8.lnot() >> 43) & 0x1fffe0)
    .to_uint()
  assert_eq(@arm64.arm64_movi(reg, value8), expected8)
}

///|
test "arm64 emitter growth" {
  let emitter = @arm64.new_arm64_emitter_with_capacity(1, 0)
  @arm64.emit32(emitter, 0x11111111)
  @arm64.emit32(emitter, 0x22222222)
  assert_eq(emitter.code_len, 2)
  assert_true(emitter.code.length() >= 2)
  assert_eq(@arm64.emitter_pc(emitter), 8)
}

///|
test "arm64 emitter zero capacity" {
  let emitter = @arm64.new_arm64_emitter_with_capacity(0, 0)
  assert_eq(emitter.code_len, 0)
  assert_eq(emitter.code.length(), 0)
  assert_eq(emitter.relocs.length(), 0)
}

///|
test "arm64 fill nops" {
  let emitter = @arm64.new_arm64_emitter()
  @arm64.gen_fill_nops(emitter, 8)
  assert_eq(emitter.code_len, 2)
  assert_eq(emitter.code[0], 0xd503201f)
  assert_eq(emitter.code[1], 0xd503201f)
}

///|
test "panic arm64 fill nops alignment" {
  let emitter = @arm64.new_arm64_emitter()
  @arm64.gen_fill_nops(emitter, 6)
}

///|
test "arm64 section helpers" {
  let emitter = @arm64.new_arm64_emitter()
  @arm64.emit32(emitter, 0xdeadbeef)
  let section = @arm64.section_from_emitter("text", emitter)
  assert_eq(section.size_bytes, 4)
  assert_eq(section.align, 4)
}
