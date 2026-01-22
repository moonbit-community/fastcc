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
  assert_eq(emitter.code_len, 2)
  assert_eq(emitter.code[0], (0xd28acf00 : UInt))
  assert_eq(emitter.code[1], (0xf2a24680 : UInt))
}

///|
test "arm64 movimm uses movn when beneficial" {
  let emitter = new_arm64_emitter()
  let v0 : UInt64 = 0xffff1234ffff5678
  arm64_movimm(emitter, 0, v0)
  assert_eq(emitter.code_len, 4)
  assert_eq(emitter.code[0], (0x929530e0 : UInt))
  assert_eq(emitter.code[1], (0xf2bfffe0 : UInt))
  assert_eq(emitter.code[2], (0xf2c24680 : UInt))
  assert_eq(emitter.code[3], (0xf2ffffe0 : UInt))
}

///|
test "arm64 gsym_addr patches branches" {
  let emitter = new_arm64_emitter()
  emit32(emitter, 0)
  emit32(emitter, (8 : UInt))
  emit32(emitter, 0)
  gsym_addr(emitter, 4, 12) catch {
    err => fail("unexpected gsym_addr error: \{err.to_string()}")
  }
  assert_eq(emitter.code[1], (0x14000002 : UInt))
  assert_eq(emitter.code[2], (0xd503201f : UInt))
}

///|
test "arm64 gjmp helpers build and append chains" {
  let emitter = new_arm64_emitter()
  emit32(emitter, 0)
  let t1 = gjmp(emitter, 0)
  let t2 = gjmp(emitter, 0)
  let merged = gjmp_append(emitter, t1, t2)
  assert_eq(merged, t1)
  assert_eq(emitter.code[1], t2.reinterpret_as_uint())
  assert_eq(emitter.code[2], (0 : UInt))
}

///|
test "arm64 gjmp_addr emits branch encoding" {
  let emitter = new_arm64_emitter()
  emit32(emitter, 0)
  gjmp_addr(emitter, 12) catch {
    err => fail("unexpected gjmp_addr error: \{err.to_string()}")
  }
  assert_eq(emitter.code[1], (0x14000002 : UInt))
}

///|
fn push_sv(type_t : Int, r : Int, c_i : Int64) -> Int {
  vstack.push({
    type_t,
    r,
    r2: VT_CONST,
    jtrue: 0,
    jfalse: 0,
    c_i,
    sym: None,
    cmp_op: 0,
    cmp_r: 0,
  })
  vstack.length() - 1
}

///|
test "arm64 iconst sign extension" {
  vstack.clear()
  let idx = push_sv(VT_INT, VT_CONST, (0x80000000 : Int64))
  let val = arm64_iconst(idx)
  guard val is Some(v) else { fail("expected value") }
  assert_eq(v, (0xffffffff80000000 : UInt64))
}

///|
test "arm64 iconst unsigned truncation" {
  vstack.clear()
  let idx = push_sv(VT_INT | VT_UNSIGNED, VT_CONST, (0x80000000 : Int64))
  let val = arm64_iconst(idx)
  guard val is Some(v) else { fail("expected value") }
  assert_eq(v, (0x80000000 : UInt64))
}

///|
test "arm64 iconst non-const returns none" {
  vstack.clear()
  let idx = push_sv(VT_INT, VT_LOCAL, 0)
  assert_eq(arm64_iconst(idx), None)
}

///|
test "arm64 gen opic add immediate" {
  let emitter = new_arm64_emitter()
  let ok = arm64_gen_opic(emitter, TOK_ADD, 0, true, 5, 1, 2)
  assert_true(ok)
  assert_eq(emitter.code_len, 1)
  assert_eq(emitter.code[0], (0x11001441 : UInt))
}

///|
test "arm64 sym emits relocations" {
  let emitter = new_arm64_emitter()
  let sym = { id: 7 }
  arm64_sym(emitter, 0, sym, 0)
  assert_eq(emitter.code_len, 2)
  assert_eq(emitter.code[0], (0x90000000 : UInt))
  assert_eq(emitter.code[1], (0xf9400000 : UInt))
  assert_eq(emitter.relocs.length(), 2)
  assert_eq(emitter.relocs[0].offset, 0)
  assert_eq(emitter.relocs[0].kind, R_AARCH64_ADR_GOT_PAGE)
  assert_eq(emitter.relocs[0].sym.id, 7)
  assert_eq(emitter.relocs[1].offset, 4)
  assert_eq(emitter.relocs[1].kind, R_AARCH64_LD64_GOT_LO12_NC)
}

///|
test "section_from_emitter copies code and relocs" {
  let emitter = new_arm64_emitter()
  let sym = { id: 3 }
  emit32(emitter, (0x14000000 : UInt))
  greloca(emitter, sym, 0, R_AARCH64_ADR_GOT_PAGE, 0)
  let sec = section_from_emitter(".text", emitter)
  assert_eq(sec.name, ".text")
  assert_eq(sec.data.length(), 1)
  assert_eq(sec.data[0], (0x14000000 : UInt))
  assert_eq(sec.relocs.length(), 1)
  assert_eq(sec.relocs[0].sym.id, 3)
  assert_eq(sec.relocs[0].kind, R_AARCH64_ADR_GOT_PAGE)
}
