///|
test "object section defaults" {
  let sec = @object.new_section(".text")
  assert_eq(sec.name, ".text")
  assert_eq(@object.section_size_bytes(sec), 0)
  assert_eq(@object.section_word_len(sec), 0)
  let sym = @object.Sym::{ id: 7 }
  let rel = @object.Reloc::{ offset: 4, kind: 1, sym, addend: 0 }
  assert_eq(@object.reloc_addend(rel), 0)
}
