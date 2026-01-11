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
}

///|
fn new_section(name : String) -> Section {
  { name, data: [], relocs: [] }
}

///|
fn section_size_bytes(sec : Section) -> Int {
  sec.data.length() << 2
}

///|
fn section_from_emitter(name : String, emitter : Arm64Emitter) -> Section {
  { name, data: emitter.code.copy(), relocs: emitter.relocs.copy() }
}
