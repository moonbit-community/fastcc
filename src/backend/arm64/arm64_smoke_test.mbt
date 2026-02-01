///|
fn uses_movi_e64(value : UInt64) -> Bool {
  let m : UInt64 = 0xffff
  if (value & m.lnot()) == 0 {
    return false
  }
  if (value & (m << 16).lnot()) == 0 {
    return false
  }
  if (value & (m << 32).lnot()) == 0 {
    return false
  }
  if (value & (m << 48).lnot()) == 0 {
    return false
  }
  if (value & m.lnot()) == m << 16 {
    return false
  }
  if (value & (m << 16).lnot()) == m {
    return false
  }
  if value.lor(m).lnot() == 0 {
    return false
  }
  if value.lor(m << 16).lnot() == 0 {
    return false
  }
  if value.lor(m << 32).lnot() == 0 {
    return false
  }
  if value.lor(m << 48).lnot() == 0 {
    return false
  }
  if value >> 32 == 0 {
    let e = @arm64.arm64_encode_bimm64(value | (value << 32))
    if e >= 0 {
      return false
    }
  }
  @arm64.arm64_encode_bimm64(value) >= 0
}

///|
test "arm64 emitter helpers" {
  let emitter = @arm64.new_arm64_emitter_with_capacity(0, 2)
  assert_eq(emitter.code.length(), 0)
  assert_eq(emitter.relocs.length(), 0)
  let sym : @arm64.Sym = { id: 1 }
  @arm64.greloc(emitter, sym, 4, @arm64.R_AARCH64_POINTER)
  assert_eq(emitter.relocs.length(), 1)
  assert_eq(emitter.relocs[0].addend, 0)
  let fallback = @arm64.new_arm64_emitter_with_capacity(0, 0)
  assert_eq(fallback.code.length(), 0)
  assert_eq(fallback.relocs.length(), 0)
  emitter.code_len = 3
  assert_eq(@arm64.gind(emitter), 12)
}

///|
test "arm64 emit32 expansion and errors" {
  let emitter = @arm64.new_arm64_emitter_with_capacity(1, 0)
  emitter.code_len = 1
  @arm64.emit32(emitter, 0xd503201f)
  assert_true(emitter.code.length() >= 2)
  assert_eq(emitter.code_len, 2)
  let bad_fill : Result[Unit, Error] = try? @arm64.gen_fill_nops(emitter, 3)
  assert_true(bad_fill is Err(_))
}

///|
test "arm64 movi and bimm64 coverage" {
  ignore(@arm64.arm64_encode_bimm64((0x100000000 : UInt64)))
  assert_eq(@arm64.arm64_type_size(0), 0)
  let candidates : Array[UInt64] = [
    (0x00ff00ff00ff00ff : UInt64),
    (0x0f0f0f0f0f0f0f0f : UInt64),
    (0xf0f0f0f0f0f0f0f0 : UInt64),
    (0x0000ffff0000ffff : UInt64),
    (0x00ff00ff0000ff00 : UInt64),
    (0x0000ff00ff00ff00 : UInt64),
  ]
  let mut found : UInt64? = None
  for value in candidates {
    if uses_movi_e64(value) {
      found = Some(value)
      break
    }
  }
  match found {
    Some(value) => {
      let insn = @arm64.arm64_movi(0, value)
      assert_true(insn != 0)
    }
    None => fail("no movi e64 candidate found")
  }
}

///|
test "arm64 branch range errors" {
  let emitter = @arm64.new_arm64_emitter_with_capacity(2, 0)
  emitter.code_len = 2
  let bad_gsym : Result[Unit, Error] = try? @arm64.gsym_addr(
    emitter, 4, 0x20000000,
  )
  assert_true(bad_gsym is Err(_))
  let bad_jmp : Result[Unit, Error] = try? @arm64.gjmp_addr(emitter, 0x20000000)
  assert_true(bad_jmp is Err(_))
}
