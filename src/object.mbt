///|
struct Reloc {
  offset : Int
  kind : Int
  sym : Sym
  addend : Int64
}

///|
struct Section {
  name : String
  data : Array[UInt]
  relocs : Array[Reloc]
  align : Int
  size_bytes : Int
}

///|
fn new_section(name : String) -> Section {
  { name, data: [], relocs: [], align: 4, size_bytes: 0 }
}

///|
fn reloc_addend(rel : Reloc) -> Int64 {
  rel.addend
}

///|
fn section_size_bytes(sec : Section) -> Int {
  if sec.size_bytes > 0 {
    sec.size_bytes
  } else {
    sec.data.length() << 2
  }
}

///|
fn section_from_emitter(name : String, emitter : Arm64Emitter) -> Section {
  {
    name,
    data: emitter.code.copy(),
    relocs: emitter.relocs.copy(),
    align: 4,
    size_bytes: emitter.code.length() << 2,
  }
}
