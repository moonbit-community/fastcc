///|
pub(all) struct Sym {
  id : Int
}

///|
pub(all) struct Reloc {
  offset : Int
  kind : Int
  sym : Sym
  addend : Int64
}

///|
pub(all) struct Section {
  name : String
  data : Array[UInt]
  relocs : Array[Reloc]
  align : Int
  size_bytes : Int
}

///|
pub fn new_section(name : String) -> Section {
  { name, data: [], relocs: [], align: 4, size_bytes: 0 }
}

///|
pub fn reloc_addend(rel : Reloc) -> Int64 {
  rel.addend
}

///|
pub fn section_size_bytes(sec : Section) -> Int {
  if sec.size_bytes > 0 {
    sec.size_bytes
  } else {
    sec.data.length() << 2
  }
}

///|
pub fn section_word_len(sec : Section) -> Int {
  if sec.size_bytes > 0 {
    sec.size_bytes >> 2
  } else {
    sec.data.length()
  }
}
