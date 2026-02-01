///|
fn read_u32_le_at(bytes : Bytes, offset : Int) -> UInt {
  let b0 = bytes[offset].to_uint()
  let b1 = bytes[offset + 1].to_uint() << 8
  let b2 = bytes[offset + 2].to_uint() << 16
  let b3 = bytes[offset + 3].to_uint() << 24
  b0 | b1 | b2 | b3
}

///|
fn read_padded_name(bytes : Bytes, offset : Int) -> String {
  let mut end = 0
  while end < 16 && bytes[offset + end] != 0 {
    end = end + 1
  }
  let buf = @buffer.new()
  let mut i = 0
  while i < end {
    buf.write_byte(bytes[offset + i])
    i = i + 1
  }
  try @encoding/utf8.decode(buf.to_bytes()) catch {
    _ => ""
  } noraise {
    s => s
  }
}

///|
fn parse_text(text : String) -> (@ast.TranslationUnit, @diag.DiagBag) {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<test>", text)
  let pp = @preproc.new_preprocessor(map, file, bag)
  let unit = @parser.parse_translation_unit(pp)
  (unit, bag)
}

///|
const LC_SEGMENT_64 : UInt = 0x19

///|
fn macho_section_file_offset(
  bytes : Bytes,
  seg : String,
  sect : String,
) -> Int? {
  let ncmds = read_u32_le_at(bytes, 16).reinterpret_as_int()
  let mut off = 32
  let mut i = 0
  while i < ncmds {
    let cmd = read_u32_le_at(bytes, off)
    let cmdsize = read_u32_le_at(bytes, off + 4).reinterpret_as_int()
    if cmd == LC_SEGMENT_64 {
      let nsects = read_u32_le_at(bytes, off + 64).reinterpret_as_int()
      let mut j = 0
      let mut sect_off = off + 72
      while j < nsects {
        let sectname = read_padded_name(bytes, sect_off)
        let segname = read_padded_name(bytes, sect_off + 16)
        if segname == seg && sectname == sect {
          return Some(read_u32_le_at(bytes, sect_off + 48).reinterpret_as_int())
        }
        sect_off = sect_off + 80
        j = j + 1
      }
    }
    off = off + cmdsize
    i = i + 1
  }
  None
}

///|
fn macho_text_section_offsets(bytes : Bytes) -> (Int, Int, Int) {
  let section_hdr = 32 + 72
  let text_off = read_u32_le_at(bytes, section_hdr + 48).reinterpret_as_int()
  let reloff = read_u32_le_at(bytes, section_hdr + 56).reinterpret_as_int()
  let nreloc = read_u32_le_at(bytes, section_hdr + 60).reinterpret_as_int()
  (text_off, reloff, nreloc)
}

///|
fn has_b_cond(bytes : Bytes, text_offset : Int, max_words : Int) -> Bool {
  let mut i = 0
  while i < max_words {
    let w = read_u32_le_at(bytes, text_offset + (i << 2))
    if (w & (0xff000010 : UInt)) == (0x54000000 : UInt) {
      return true
    }
    i = i + 1
  }
  false
}

///|
fn has_b_uncond(bytes : Bytes, text_offset : Int, max_words : Int) -> Bool {
  let mut i = 0
  while i < max_words {
    let w = read_u32_le_at(bytes, text_offset + (i << 2))
    if (w & (0x7c000000 : UInt)) == (0x14000000 : UInt) {
      return true
    }
    i = i + 1
  }
  false
}

///|
fn has_ldr_w(bytes : Bytes, text_offset : Int, max_words : Int) -> Bool {
  let mut i = 0
  while i < max_words {
    let w = read_u32_le_at(bytes, text_offset + (i << 2))
    let op = w & (0xffc00000 : UInt)
    if op == (0xb9400000 : UInt) || op == (0xb9800000 : UInt) {
      return true
    }
    i = i + 1
  }
  false
}

///|
fn find_word_offset(
  bytes : Bytes,
  text_offset : Int,
  max_words : Int,
  value : UInt,
) -> Int? {
  let mut i = 0
  while i < max_words {
    let off = text_offset + (i << 2)
    if read_u32_le_at(bytes, off) == value {
      return Some(off)
    }
    i = i + 1
  }
  None
}

///|
test "codegen emits arm64 main return 0 object" {
  let (unit, bag) = parse_text("int main(){return 0;}")
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!@diag.has_errors(bag))
  let (text_offset, _, _) = macho_text_section_offsets(bytes)
  assert_eq(read_u32_le_at(bytes, text_offset), (0xa9bf7bfd : UInt))
  assert_eq(read_u32_le_at(bytes, text_offset + 4), (0x910003fd : UInt))
  assert_true(
    find_word_offset(bytes, text_offset, 64, (0x52800000 : UInt)) is Some(_),
  )
  assert_true(
    find_word_offset(bytes, text_offset, 64, (0xa8c17bfd : UInt)) is Some(_),
  )
  assert_true(
    find_word_offset(bytes, text_offset, 64, (0xd65f03c0 : UInt)) is Some(_),
  )
}

///|
test "codegen handles __builtin_alloca" {
  let (unit, bag) = parse_text(
    "int f(int n){ void *p = __builtin_alloca(n); return p != 0; }",
  )
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(_bytes) => ()
  }
}

///|
test "codegen handles compound literal designators in function" {
  let (unit, bag) = parse_text(
    "typedef union U { int int32; void *ptr; } U;\n" +
    "typedef struct S { U u; long tag; } S;\n" +
    "#define MK(tag, val) (S){ (U){ .int32 = val }, tag }\n" +
    "S f(int x){ return MK(1, x); }",
  )
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!@diag.has_errors(bag))
  assert_true(bytes.length() > 0)
}

///|
test "codegen accepts enum range designator in array init" {
  let (unit, bag) = parse_text(
    "enum { OP_COUNT = 2 }; void f(){ int t[4] = { [OP_COUNT ... 3] = 1 }; }",
  )
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!@diag.has_errors(bag))
  assert_true(bytes.length() > 0)
}

///|
test "codegen emits call relocation for return f()" {
  let (unit, bag) = parse_text("int f(){return 0;} int main(){return f();}")
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!@diag.has_errors(bag))
  let (text_offset, reloff, nreloc) = macho_text_section_offsets(bytes)
  assert_eq(nreloc, 1)
  let call_off = match
    find_word_offset(bytes, text_offset, 64, (0x94000000 : UInt)) {
    None => fail("expected BL instruction")
    Some(v) => v
  }
  assert_eq(
    read_u32_le_at(bytes, reloff),
    (call_off - text_offset).reinterpret_as_uint(),
  )
  assert_eq(read_u32_le_at(bytes, reloff + 4), (0x2d000001 : UInt))
}

///|
test "codegen handles __builtin_frame_address and __builtin_return_address" {
  let (unit, bag) = parse_text(
    "int f(){ return __builtin_frame_address(0) != 0 && __builtin_return_address(0) != 0; }",
  )
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!@diag.has_errors(bag))
  assert_true(bytes.length() > 0)
}

///|
test "codegen handles __atomic_exchange builtin helper" {
  let (unit, bag) = parse_text(
    "int x; int out; void f(){ int v = 1; __atomic_exchange(&x, &v, &out, 0); }",
  )
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!@diag.has_errors(bag))
  assert_true(bytes.length() > 0)
}

///|
test "codegen accepts float constant initializers" {
  let (unit, bag) = parse_text(
    "double a = 0.0/0.0; double b = 1.0/0.0; float c = 0.0f/0.0f;",
  )
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!@diag.has_errors(bag))
  assert_true(bytes.length() > 0)
}

///|
test "codegen handles aggregate temp in switch default" {
  let (unit, bag) = parse_text(
    "struct S { int x; }; int f(int v){ switch(v){ default: return (struct S){1}.x; } }",
  )
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!@diag.has_errors(bag))
  assert_true(bytes.length() > 0)
}

///|
test "codegen emits conditional branch for if/else" {
  let (unit, bag) = parse_text(
    "int main(){int a=1; if(a) return 3; else return 4;}",
  )
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!@diag.has_errors(bag))
  let (text_offset, _, _) = macho_text_section_offsets(bytes)
  assert_true(has_b_cond(bytes, text_offset, 64))
}

///|
test "codegen emits branches for while + break/continue" {
  let (unit, bag) = parse_text(
    "int main(){int i=0; while(i<3){i=i+1; if(i==2) continue; if(i==3) break;} return i;}",
  )
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!@diag.has_errors(bag))
  let (text_offset, _, _) = macho_text_section_offsets(bytes)
  assert_true(has_b_cond(bytes, text_offset, 128))
  assert_true(has_b_uncond(bytes, text_offset, 128))
}

///|
test "codegen emits .cstring and relocs for extern call with string literal" {
  let (unit, bag) = parse_text(
    "int puts(const char*); int main(){return puts(\"hi\");}",
  )
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!@diag.has_errors(bag))
  let (_, _, nreloc) = macho_text_section_offsets(bytes)
  assert_eq(nreloc, 3)
  let cstring_off = match
    macho_section_file_offset(bytes, "__TEXT", "__cstring") {
    None => fail("expected __TEXT,__cstring section")
    Some(v) => v
  }
  assert_eq(read_u32_le_at(bytes, cstring_off), (0x00006968 : UInt))
}

///|
test "codegen stores embedded-nul strings in .rodata" {
  let (unit, bag) = parse_text(
    "int main(){const char *s=\"a\\0b\"; return s[0];}",
  )
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!@diag.has_errors(bag))
  let rodata_off = match macho_section_file_offset(bytes, "__TEXT", "__const") {
    None => fail("expected __TEXT,__const section")
    Some(v) => v
  }
  assert_eq(read_u32_le_at(bytes, rodata_off), (0x00620061 : UInt))
}

///|
test "codegen supports local pointers: addr, deref, compare" {
  let (unit, bag) = parse_text(
    "int main(){int x=1; int *p=&x; if(p!=0){*p=3;} return x;}",
  )
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!@diag.has_errors(bag))
  let (_, _, _) = macho_text_section_offsets(bytes)

}

///|
test "codegen emits global load relocs for return x" {
  let (unit, bag) = parse_text("int x; int main(){return x;}")
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  assert_true(!@diag.has_errors(bag))
  let (text_offset, reloff, nreloc) = macho_text_section_offsets(bytes)
  let bytes_len = bytes.length()
  let max_words = (bytes_len - text_offset) / 4
  let scan_words = if max_words < 64 { max_words } else { 64 }
  assert_eq(nreloc, 2)
  let adrp_off = match
    find_word_offset(bytes, text_offset, scan_words, (0x90000000 : UInt)) {
    None => fail("expected ADRP instruction")
    Some(v) => v
  }
  let add_off = match
    find_word_offset(bytes, text_offset, scan_words, (0x91000000 : UInt)) {
    None => fail("expected ADD instruction")
    Some(v) => v
  }
  assert_true(has_ldr_w(bytes, text_offset, scan_words))
  assert_eq(
    read_u32_le_at(bytes, reloff),
    (adrp_off - text_offset).reinterpret_as_uint(),
  )
  assert_eq(read_u32_le_at(bytes, reloff + 4), (0x3d000001 : UInt))
  assert_eq(
    read_u32_le_at(bytes, reloff + 8),
    (add_off - text_offset).reinterpret_as_uint(),
  )
  assert_eq(read_u32_le_at(bytes, reloff + 12), (0x4c000001 : UInt))
}

///|
test "codegen emits .data for initialized global int" {
  let (unit, bag) = parse_text("int x=3; int main(){return x;}")
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  let data_off = match macho_section_file_offset(bytes, "__DATA", "__data") {
    None => fail("expected __DATA,__data section")
    Some(v) => v
  }
  assert_eq(read_u32_le_at(bytes, data_off), (3 : UInt))
}

///|
test "codegen emits .data for extern initialized global int" {
  let (unit, bag) = parse_text("extern int x=3; int main(){return x;}")
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  let data_off = match macho_section_file_offset(bytes, "__DATA", "__data") {
    None => fail("expected __DATA,__data section")
    Some(v) => v
  }
  assert_eq(read_u32_le_at(bytes, data_off), (3 : UInt))
}

///|
test "codegen keeps definition after extern redeclare" {
  let (unit, bag) = parse_text(
    "extern int x; int x=3; extern int x; int main(){return x;}",
  )
  assert_true(!@diag.has_errors(bag))
  check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  let bytes = match codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(b) => b
  }
  let data_off = match macho_section_file_offset(bytes, "__DATA", "__data") {
    None => fail("expected __DATA,__data section")
    Some(v) => v
  }
  assert_eq(read_u32_le_at(bytes, data_off), (3 : UInt))
}
