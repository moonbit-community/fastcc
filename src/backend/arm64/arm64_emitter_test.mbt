///|
test "arm64 register helpers (extra)" {
  assert_eq(@arm64.treg_r(3), 3)
  assert_eq(@arm64.treg_f(0), @arm64.TREG_F0)
  assert_eq(@arm64.treg_f(7), @arm64.TREG_F7)
  assert_true(@arm64.is_freg(@arm64.TREG_F0))
  assert_true(!@arm64.is_freg(@arm64.TREG_R30))
  assert_eq(@arm64.fltr(@arm64.treg_f(3)), 3)
  assert_eq(@arm64.intr(@arm64.TREG_R30), 30)
}

///|
test "arm64 mask helper" {
  assert_eq(@arm64.u64_mask(0), 0UL)
  assert_eq(@arm64.u64_mask(-1), 0UL)
  assert_eq(@arm64.u64_mask(1), 1UL)
  assert_eq(@arm64.u64_mask(4), 15UL)
}

///|
test "arm64 emitter basics" {
  let emitter = @arm64.new_arm64_emitter()
  assert_eq(emitter.code_len, 0)
  @arm64.emit32(emitter, 0x12345678)
  @arm64.emit32(emitter, 0x9abcdef0)
  assert_eq(emitter.code_len, 2)
  assert_eq(@arm64.emitter_pc(emitter), 8)
  assert_eq(emitter.code[0], 0x12345678)
  assert_eq(emitter.code[1], 0x9abcdef0)

  let sec = @arm64.section_from_emitter(".text", emitter)
  assert_eq(sec.name, ".text")
  assert_eq(sec.align, 4)
  assert_eq(sec.size_bytes, 8)
  assert_eq(sec.data.length(), 2)
  assert_eq(sec.data[0], 0x12345678)
  assert_eq(sec.data[1], 0x9abcdef0)
  assert_eq(sec.relocs.length(), 0)
}

///|
test "arm64 emitter take section" {
  let emitter = @arm64.new_arm64_emitter_with_capacity(2, 0)
  @arm64.emit32(emitter, 0x0)
  @arm64.emit32(emitter, 0xffffffff)
  let sec = @arm64.section_from_emitter_take(".text", emitter)
  assert_eq(sec.size_bytes, 8)
  assert_eq(sec.data.length(), 2)
  assert_eq(sec.data[0], 0x0)
  assert_eq(sec.data[1], 0xffffffff)
}
