///|
fn read_u32_le_at(bytes : Bytes, offset : Int) -> UInt {
  let b0 = bytes[offset].to_uint()
  let b1 = bytes[offset + 1].to_uint() << 8
  let b2 = bytes[offset + 2].to_uint() << 16
  let b3 = bytes[offset + 3].to_uint() << 24
  b0 | b1 | b2 | b3
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
  let text_offset = 208
  assert_eq(read_u32_le_at(bytes, text_offset), (0xa9bf7bfd : UInt))
  assert_eq(read_u32_le_at(bytes, text_offset + 4), (0x910003fd : UInt))
  assert_eq(read_u32_le_at(bytes, text_offset + 8), (0x52800000 : UInt))
  assert_eq(read_u32_le_at(bytes, text_offset + 12), (0xa8c17bfd : UInt))
  assert_eq(read_u32_le_at(bytes, text_offset + 16), (0xd65f03c0 : UInt))
}
