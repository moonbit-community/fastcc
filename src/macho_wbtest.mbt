///|
fn read_u32_le(bytes : Bytes, offset : Int) -> UInt {
  let b0 = bytes[offset].to_uint()
  let b1 = bytes[offset + 1].to_uint() << 8
  let b2 = bytes[offset + 2].to_uint() << 16
  let b3 = bytes[offset + 3].to_uint() << 24
  b0 | b1 | b2 | b3
}

///|
test "macho header has segment and symtab" {
  let sec = new_section(".text")
  sec.data.push((0x14000000 : UInt))
  let symbols = [
    {
      id: 1,
      name: "_main",
      section: Some(".text"),
      value: 0,
      is_external: true,
    },
  ]
  let bytes = encode_macho_object([sec], symbols)
  assert_eq(read_u32_le(bytes, 0), MH_MAGIC_64)
  assert_eq(read_u32_le(bytes, 12), MH_OBJECT)
  assert_eq(read_u32_le(bytes, 16), (4 : UInt))
  assert_eq(read_u32_le(bytes, 32), LC_SEGMENT_64)
  assert_eq(read_u32_le(bytes, 96), (1 : UInt))
}

///|
test "macho section records reloc count" {
  let sec = new_section(".text")
  let reloc_sym = { id: 2 }
  sec.data.push((0x14000000 : UInt))
  sec.relocs.push({
    offset: 0,
    kind: R_AARCH64_ADR_GOT_PAGE,
    sym: reloc_sym,
    addend: 0,
  })
  let symbols = [
    { id: 2, name: "_ext", section: None, value: 0, is_external: true },
  ]
  let bytes = encode_macho_object([sec], symbols)
  assert_eq(read_u32_le(bytes, 164), (1 : UInt))
}

///|
test "macho maps arm64 relocation kinds" {
  assert_eq(macho_reloc_type(R_AARCH64_CALL26), (ARM64_RELOC_BRANCH26, true))
  assert_eq(macho_reloc_type(R_AARCH64_JUMP26), (ARM64_RELOC_BRANCH26, true))
  assert_eq(
    macho_reloc_type(R_AARCH64_ADR_PREL_PG_HI21),
    (ARM64_RELOC_PAGE21, true),
  )
  assert_eq(
    macho_reloc_type(R_AARCH64_ADD_ABS_LO12_NC),
    (ARM64_RELOC_PAGEOFF12, false),
  )
  assert_eq(
    macho_reloc_type(R_AARCH64_LDST8_ABS_LO12_NC),
    (ARM64_RELOC_PAGEOFF12, false),
  )
}
