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

///|
test "object section size overrides" {
  let sec = @object.Section::{
    name: ".data",
    data: [1, 2, 3, 4],
    relocs: [],
    align: 4,
    size_bytes: 20,
  }
  assert_eq(@object.section_size_bytes(sec), 20)
  assert_eq(@object.section_word_len(sec), 5)
}

///|
test "object section size derives from data" {
  let sec = @object.Section::{
    name: ".data",
    data: [1, 2, 3],
    relocs: [],
    align: 4,
    size_bytes: 0,
  }
  assert_eq(@object.section_size_bytes(sec), 12)
  assert_eq(@object.section_word_len(sec), 3)
}
