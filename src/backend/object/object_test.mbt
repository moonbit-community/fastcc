///|
test "object section defaults" {
  let sec = @object.new_section(".text")
  assert_eq(sec.name, ".text")
  assert_eq(@object.section_size_bytes(sec), 0)
  assert_eq(@object.section_word_len(sec), 0)
  sec.data.push(0x1234)
  assert_eq(@object.section_word_len(sec), 1)
  assert_eq(@object.section_size_bytes(sec), 4)

  let sec_fixed : @object.Section = {
    name: ".data",
    data: [],
    relocs: [],
    align: 4,
    size_bytes: 12,
  }
  assert_eq(@object.section_word_len(sec_fixed), 3)
  assert_eq(@object.section_size_bytes(sec_fixed), 12)

  let sym = @object.Sym::{ id: 7 }
  let rel = @object.Reloc::{ offset: 4, kind: 1, sym, addend: 9 }
  assert_eq(@object.reloc_addend(rel), 9)
}
