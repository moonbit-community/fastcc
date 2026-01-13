///|
fn read_u32_le_at(bytes : Bytes, offset : Int) -> UInt {
  let b0 = bytes[offset].to_uint()
  let b1 = bytes[offset + 1].to_uint() << 8
  let b2 = bytes[offset + 2].to_uint() << 16
  let b3 = bytes[offset + 3].to_uint() << 24
  b0 | b1 | b2 | b3
}

///|
fn macho_text_section_offsets(bytes : Bytes) -> (Int, Int, Int) {
  let section_hdr = 32 + 72
  let text_off = read_u32_le_at(bytes, section_hdr + 48).to_int()
  let reloff = read_u32_le_at(bytes, section_hdr + 56).to_int()
  let nreloc = read_u32_le_at(bytes, section_hdr + 60).to_int()
  (text_off, reloff, nreloc)
}

///|
test "codegen emits arm64 main return 0 object" {
  let (unit, bag) = parse_text("int main(){return 0;}")
  assert_true(!has_errors(bag))
  check_translation_unit(unit, bag)
  assert_true(!has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!has_errors(bag))
  let (text_offset, _, _) = macho_text_section_offsets(bytes)
  assert_eq(read_u32_le_at(bytes, text_offset), (0xa9bf7bfd : UInt))
  assert_eq(read_u32_le_at(bytes, text_offset + 4), (0x910003fd : UInt))
  assert_eq(read_u32_le_at(bytes, text_offset + 8), (0x52800000 : UInt))
  assert_eq(read_u32_le_at(bytes, text_offset + 12), (0xa8c17bfd : UInt))
  assert_eq(read_u32_le_at(bytes, text_offset + 16), (0xd65f03c0 : UInt))
}

///|
test "codegen emits call relocation for return f()" {
  let (unit, bag) = parse_text("int f(){return 0;} int main(){return f();}")
  assert_true(!has_errors(bag))
  check_translation_unit(unit, bag)
  assert_true(!has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!has_errors(bag))
  let (text_offset, reloff, nreloc) = macho_text_section_offsets(bytes)
  assert_eq(nreloc, 1)
  assert_eq(read_u32_le_at(bytes, text_offset + 8), (0x94000000 : UInt))
  assert_eq(read_u32_le_at(bytes, reloff), (8 : UInt))
  assert_eq(read_u32_le_at(bytes, reloff + 4), (0x2d000001 : UInt))
}

///|
test "codegen emits global load relocs for return x" {
  let (unit, bag) = parse_text("int x; int main(){return x;}")
  assert_true(!has_errors(bag))
  check_translation_unit(unit, bag)
  assert_true(!has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!has_errors(bag))
  let (text_offset, reloff, nreloc) = macho_text_section_offsets(bytes)
  assert_eq(nreloc, 2)
  assert_eq(read_u32_le_at(bytes, text_offset + 8), (0x90000000 : UInt))
  assert_eq(read_u32_le_at(bytes, text_offset + 12), (0x91000000 : UInt))
  assert_eq(read_u32_le_at(bytes, text_offset + 16), (0xb9400000 : UInt))
  assert_eq(read_u32_le_at(bytes, reloff), (8 : UInt))
  assert_eq(read_u32_le_at(bytes, reloff + 4), (0x3d000001 : UInt))
  assert_eq(read_u32_le_at(bytes, reloff + 8), (12 : UInt))
  assert_eq(read_u32_le_at(bytes, reloff + 12), (0x4c000001 : UInt))
}
