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
fn section_word_len(sec : Section) -> Int {
  if sec.size_bytes > 0 {
    sec.size_bytes >> 2
  } else {
    sec.data.length()
  }
}

///|
fn section_from_emitter(name : String, emitter : Arm64Emitter) -> Section {
  let code_len = emitter.code_len
  let zero : UInt = 0
  let data : Array[UInt] = Array::make(code_len, zero)
  let mut i = 0
  while i < code_len {
    data[i] = emitter.code[i]
    i = i + 1
  }
  {
    name,
    data,
    relocs: emitter.relocs.copy(),
    align: 4,
    size_bytes: code_len << 2,
  }
}

///|
fn section_from_emitter_take(name : String, emitter : Arm64Emitter) -> Section {
  let code_len = emitter.code_len
  {
    name,
    data: emitter.code,
    relocs: emitter.relocs,
    align: 4,
    size_bytes: code_len << 2,
  }
}
