///|
fn read_u32_le(bytes : Bytes, offset : Int) -> UInt {
  let b0 = bytes[offset].to_uint()
  let b1 = bytes[offset + 1].to_uint() << 8
  let b2 = bytes[offset + 2].to_uint() << 16
  let b3 = bytes[offset + 3].to_uint() << 24
  b0 | b1 | b2 | b3
}

///|
fn decode_reloc_info(info : UInt) -> (Int, Bool, Int, Bool, Int) {
  let symbolnum = (info & 0x00ff_ffff).reinterpret_as_int()
  let pcrel = ((info >> 24) & 1) == 1
  let length = ((info >> 25) & 3).reinterpret_as_int()
  let is_extern = ((info >> 27) & 1) == 1
  let r_type = ((info >> 28) & 0xf).reinterpret_as_int()
  (symbolnum, pcrel, length, is_extern, r_type)
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

///|
test "macho encodes GOT relocations as extern symbol relocs" {
  let sec = new_section(".text")
  let reloc_sym = { id: 2 }
  sec.data.push((0x90000000 : UInt))
  sec.data.push((0xf9400000 : UInt))
  sec.relocs.push({
    offset: 0,
    kind: R_AARCH64_ADR_GOT_PAGE,
    sym: reloc_sym,
    addend: 0,
  })
  sec.relocs.push({
    offset: 4,
    kind: R_AARCH64_LD64_GOT_LO12_NC,
    sym: reloc_sym,
    addend: 0,
  })
  let symbols = [
    { id: 2, name: "_ext", section: None, value: 0, is_external: true },
  ]
  let bytes = encode_macho_object([sec], symbols)
  let section_base = 32 + 72
  let reloff = read_u32_le(bytes, section_base + 56).reinterpret_as_int()
  let nreloc = read_u32_le(bytes, section_base + 60).reinterpret_as_int()
  assert_eq(nreloc, 2)
  let addr0 = read_u32_le(bytes, reloff).reinterpret_as_int()
  let info0 = read_u32_le(bytes, reloff + 4)
  assert_eq(addr0, 0)
  let (symnum0, pcrel0, len0, ext0, rtype0) = decode_reloc_info(info0)
  assert_eq(symnum0, 0)
  assert_true(pcrel0)
  assert_eq(len0, 2)
  assert_true(ext0)
  assert_eq(rtype0, ARM64_RELOC_GOT_LOAD_PAGE21)
  let addr1 = read_u32_le(bytes, reloff + 8).reinterpret_as_int()
  let info1 = read_u32_le(bytes, reloff + 12)
  assert_eq(addr1, 4)
  let (symnum1, pcrel1, len1, ext1, rtype1) = decode_reloc_info(info1)
  assert_eq(symnum1, 0)
  assert_true(!pcrel1)
  assert_eq(len1, 2)
  assert_true(ext1)
  assert_eq(rtype1, ARM64_RELOC_GOT_LOAD_PAGEOFF12)
}
