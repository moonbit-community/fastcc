///|
const MH_MAGIC_64 : UInt = 0xfeedfacf

///|
const MH_OBJECT : UInt = 0x1

///|
const CPU_ARCH_ABI64 : Int = 0x01000000

///|
const CPU_TYPE_ARM : Int = 12

///|
const CPU_TYPE_ARM64 : Int = CPU_TYPE_ARM | CPU_ARCH_ABI64

///|
const CPU_SUBTYPE_ARM64_ALL : Int = 0

///|
const LC_SEGMENT_64 : UInt = 0x19

///|
const LC_SYMTAB : UInt = 0x2

///|
const LC_SOURCE_VERSION : UInt = 0x2a

///|
const LC_BUILD_VERSION : UInt = 0x32

///|
const PLATFORM_MACOS : UInt = 1

///|
const VM_PROT_READ : Int = 1

///|
const VM_PROT_WRITE : Int = 2

///|
const VM_PROT_EXECUTE : Int = 4

///|
const S_REGULAR : UInt = 0x0

///|
const S_ZEROFILL : UInt = 0x1

///|
const S_CSTRING_LITERALS : UInt = 0x2

///|
const S_ATTR_PURE_INSTRUCTIONS : UInt = 0x80000000

///|
const S_ATTR_SOME_INSTRUCTIONS : UInt = 0x00000400

///|
const N_EXT : Int = 0x01

///|
const N_SECT : Int = 0x0e

///|
const N_UNDF : Int = 0x0

///|
const ARM64_RELOC_UNSIGNED : Int = 0

///|
const ARM64_RELOC_BRANCH26 : Int = 2

///|
const ARM64_RELOC_PAGE21 : Int = 3

///|
const ARM64_RELOC_PAGEOFF12 : Int = 4

///|
const ARM64_RELOC_GOT_LOAD_PAGE21 : Int = 5

///|
const ARM64_RELOC_GOT_LOAD_PAGEOFF12 : Int = 6

///|
struct ObjSymbol {
  id : Int
  name : String
  section : String?
  value : Int
  is_external : Bool
}

///|
struct MachoSectionInfo {
  sectname : String
  segname : String
  flags : UInt
  align : Int
  is_zerofill : Bool
}

///|
struct MachoSectionLayout {
  section : Section
  info : MachoSectionInfo
  align_log2 : Int
  offset : Int
  size : Int
  reloff : Int
  nreloc : Int
  index : Int
}

///|
struct MachoSegmentLayout {
  name : String
  section_indices : Array[Int]
  fileoff : Int
  filesize : Int
  maxprot : Int
  initprot : Int
}

///|
fn align_up(value : Int, align : Int) -> Int {
  if align <= 0 {
    value
  } else {
    let mask = align - 1
    (value + mask) & mask.lnot()
  }
}

///|
fn align_log2(value : Int) -> Int {
  let mut v = if value <= 0 { 1 } else { value }
  let mut log = 0
  while v > 1 {
    v = v >> 1
    log = log + 1
  }
  log
}

///|
fn write_padded_name(buf : @buffer.Buffer, name : String, len : Int) -> Unit {
  let name_len = name.length()
  let mut ascii = name_len <= len
  if ascii {
    let mut i = 0
    while i < name_len && ascii {
      if name[i] > 0x7f {
        ascii = false
      }
      i = i + 1
    }
  }
  if ascii {
    let start = buf.length()
    buf.write_string_utf8(name[:])
    let written = buf.length() - start
    let mut i = written
    while i < len {
      buf.write_byte(0)
      i = i + 1
    }
  } else {
    let bytes = @encoding/utf8.encode(name)
    let mut i = 0
    while i < len {
      if i < bytes.length() {
        buf.write_byte(bytes[i])
      } else {
        buf.write_byte(0)
      }
      i = i + 1
    }
  }
}

///|
fn macho_section_info(name : String) -> MachoSectionInfo {
  match name {
    ".text" =>
      {
        sectname: "__text",
        segname: "__TEXT",
        flags: S_REGULAR | S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS,
        align: 4,
        is_zerofill: false,
      }
    ".rodata" =>
      {
        sectname: "__const",
        segname: "__TEXT",
        flags: S_REGULAR,
        align: 4,
        is_zerofill: false,
      }
    ".cstring" =>
      {
        sectname: "__cstring",
        segname: "__TEXT",
        flags: S_CSTRING_LITERALS,
        align: 1,
        is_zerofill: false,
      }
    ".data" =>
      {
        sectname: "__data",
        segname: "__DATA",
        flags: S_REGULAR,
        align: 4,
        is_zerofill: false,
      }
    ".bss" =>
      {
        sectname: "__bss",
        segname: "__DATA",
        flags: S_ZEROFILL,
        align: 4,
        is_zerofill: true,
      }
    _ =>
      {
        sectname: "__data",
        segname: "__DATA",
        flags: S_REGULAR,
        align: 4,
        is_zerofill: false,
      }
  }
}

///|
fn build_strtab(symbols : Array[ObjSymbol]) -> (Bytes, Array[Int]) {
  let buf = @buffer.new(size_hint=8 + symbols.length() * 8)
  buf.write_string_utf8(" "[:])
  buf.write_byte(0)
  let offsets : Array[Int] = Array::new(capacity=symbols.length())
  for sym in symbols {
    let off = buf.length()
    offsets.push(off)
    buf.write_string_utf8(sym.name[:])
    buf.write_byte(0)
  }
  let pad = -buf.length() & 7
  let mut i = 0
  while i < pad {
    buf.write_byte(0)
    i = i + 1
  }
  (buf.to_bytes(), offsets)
}

///|
fn build_symtab(
  symbols : Array[ObjSymbol],
  offsets : Array[Int],
  section_index : FastMap[String, Int],
) -> Bytes {
  let buf = @buffer.new(size_hint=symbols.length() * 16)
  let mut idx = 0
  while idx < symbols.length() {
    let sym = symbols[idx]
    let strx = offsets[idx]
    let _sym_id = sym.id
    let mut n_type = if sym.is_external { N_EXT } else { 0 }
    let (n_sect, n_value) = match sym.section {
      None => (0, 0)
      Some(sec_name) =>
        match section_index.get(sec_name) {
          None => (0, 0)
          Some(sec_idx) => {
            n_type = n_type | N_SECT
            (sec_idx, sym.value)
          }
        }
    }
    if n_sect == 0 {
      n_type = n_type | N_UNDF
    }
    buf.write_uint_le(strx.reinterpret_as_uint())
    buf.write_byte(n_type.to_byte())
    buf.write_byte(n_sect.to_byte())
    buf.write_uint16_le((0 : Int).to_uint16())
    buf.write_uint64_le(n_value.to_uint64())
    idx = idx + 1
  }
  buf.to_bytes()
}

///|
fn macho_reloc_type(kind : Int) -> (Int, Bool) {
  match kind {
    R_AARCH64_ADR_GOT_PAGE => (ARM64_RELOC_GOT_LOAD_PAGE21, true)
    R_AARCH64_LD64_GOT_LO12_NC => (ARM64_RELOC_GOT_LOAD_PAGEOFF12, false)
    R_AARCH64_CALL26 => (ARM64_RELOC_BRANCH26, true)
    R_AARCH64_JUMP26 => (ARM64_RELOC_BRANCH26, true)
    R_AARCH64_ADR_PREL_PG_HI21 => (ARM64_RELOC_PAGE21, true)
    R_AARCH64_ADR_PREL_PG_HI21_NC => (ARM64_RELOC_PAGE21, true)
    R_AARCH64_ADD_ABS_LO12_NC => (ARM64_RELOC_PAGEOFF12, false)
    R_AARCH64_LDST8_ABS_LO12_NC => (ARM64_RELOC_PAGEOFF12, false)
    R_AARCH64_POINTER => (ARM64_RELOC_UNSIGNED, false)
    _ => (ARM64_RELOC_UNSIGNED, false)
  }
}

///|
fn reloc_length(kind : Int) -> Int {
  match kind {
    R_AARCH64_POINTER => 3
    _ => 2
  }
}

///|
fn pack_reloc_info(
  symbolnum : Int,
  pcrel : Bool,
  length : Int,
  is_extern : Bool,
  r_type : Int,
) -> UInt {
  let mut info = symbolnum & 0x00ffffff
  if pcrel {
    info = info | (1 << 24)
  }
  info = info | ((length & 0x3) << 25)
  if is_extern {
    info = info | (1 << 27)
  }
  info = info | ((r_type & 0xf) << 28)
  info.reinterpret_as_uint()
}

///|
fn encode_macho_object(
  sections : Array[Section],
  symbols : Array[ObjSymbol],
) -> Bytes {
  let (strtab, str_offsets) = build_strtab(symbols)
  let header_size = 32
  let segment_order : Array[String] = []
  let segment_sections : FastMap[String, Array[Int]] = fast_map_new()
  let layouts : Array[MachoSectionLayout] = []
  for sec in sections {
    let info = macho_section_info(sec.name)
    if !segment_sections.contains(info.segname) {
      segment_sections.set(info.segname, [])
      segment_order.push(info.segname)
    }
    let align = if sec.align > 0 { sec.align } else { info.align }
    let layout = {
      section: sec,
      info,
      align_log2: align_log2(align),
      offset: 0,
      size: section_size_bytes(sec),
      reloff: 0,
      nreloc: 0,
      index: 0,
    }
    layouts.push(layout)
    let idx = layouts.length() - 1
    match segment_sections.get(info.segname) {
      None => ()
      Some(list) => {
        list.push(idx)
        segment_sections.set(info.segname, list)
      }
    }
  }
  let mut sizeofcmds = 24
  for seg in segment_order {
    let count = match segment_sections.get(seg) {
      None => 0
      Some(list) => list.length()
    }
    sizeofcmds = sizeofcmds + 72 + count * 80
  }
  sizeofcmds = sizeofcmds + 24 + 16
  let mut offset = header_size + sizeofcmds
  let mut section_index = 1
  for seg in segment_order {
    match segment_sections.get(seg) {
      None => ()
      Some(list) =>
        for idx in list {
          let layout = layouts[idx]
          let align = if layout.section.align > 0 {
            layout.section.align
          } else {
            layout.info.align
          }
          let aligned = if layout.info.is_zerofill {
            offset
          } else {
            align_up(offset, align)
          }
          let data_off = if layout.info.is_zerofill { 0 } else { aligned }
          let size = layout.size
          if !layout.info.is_zerofill {
            offset = aligned + size
          }
          layouts[idx] = {
            section: layout.section,
            info: layout.info,
            align_log2: align_log2(align),
            offset: data_off,
            size,
            reloff: 0,
            nreloc: 0,
            index: section_index,
          }
          section_index = section_index + 1
        }
    }
  }
  let mut reloc_offset = align_up(offset, 4)
  for seg in segment_order {
    match segment_sections.get(seg) {
      None => ()
      Some(list) =>
        for idx in list {
          let layout = layouts[idx]
          let rel_count = layout.section.relocs.length()
          let reloff = if rel_count > 0 { reloc_offset } else { 0 }
          if rel_count > 0 {
            reloc_offset = reloc_offset + rel_count * 8
          }
          layouts[idx] = {
            section: layout.section,
            info: layout.info,
            align_log2: layout.align_log2,
            offset: layout.offset,
            size: layout.size,
            reloff,
            nreloc: rel_count,
            index: layout.index,
          }
        }
    }
  }
  let symoff = align_up(reloc_offset, 4)
  let section_index_map = collect_section_indices(layouts)
  let symtab = build_symtab(symbols, str_offsets, section_index_map)
  let id_to_index : FastMap[Int, Int] = fast_map_new()
  let mut i = 0
  while i < symbols.length() {
    id_to_index.set(symbols[i].id, i)
    i = i + 1
  }
  let stroff = symoff + symtab.length()
  let ncmds = segment_order.length() + 3
  let out = @buffer.new(size_hint=stroff + strtab.length())
  out.write_uint_le(MH_MAGIC_64)
  out.write_int_le(CPU_TYPE_ARM64)
  out.write_int_le(CPU_SUBTYPE_ARM64_ALL)
  out.write_uint_le(MH_OBJECT)
  out.write_uint_le(ncmds.reinterpret_as_uint())
  out.write_uint_le(sizeofcmds.reinterpret_as_uint())
  out.write_uint_le(0)
  out.write_uint_le(0)
  for seg in segment_order {
    let indices = match segment_sections.get(seg) {
      None => []
      Some(list) => list
    }
    let cmdsize = 72 + indices.length() * 80
    let (fileoff, filesize) = segment_file_range(indices, layouts)
    let (maxprot, initprot) = segment_prot(seg)
    out.write_uint_le(LC_SEGMENT_64)
    out.write_uint_le(cmdsize.reinterpret_as_uint())
    write_padded_name(out, seg, 16)
    out.write_uint64_le(0)
    out.write_uint64_le(0)
    out.write_uint64_le(fileoff.to_uint64())
    out.write_uint64_le(filesize.to_uint64())
    out.write_int_le(maxprot)
    out.write_int_le(initprot)
    out.write_uint_le(indices.length().reinterpret_as_uint())
    out.write_uint_le(0)
    for idx in indices {
      let layout = layouts[idx]
      write_padded_name(out, layout.info.sectname, 16)
      write_padded_name(out, layout.info.segname, 16)
      out.write_uint64_le(0)
      out.write_uint64_le(layout.size.to_uint64())
      out.write_uint_le(layout.offset.reinterpret_as_uint())
      out.write_uint_le(layout.align_log2.reinterpret_as_uint())
      out.write_uint_le(layout.reloff.reinterpret_as_uint())
      out.write_uint_le(layout.nreloc.reinterpret_as_uint())
      out.write_uint_le(layout.info.flags)
      out.write_uint_le(0)
      out.write_uint_le(0)
      out.write_uint_le(0)
    }
  }
  out.write_uint_le(LC_SYMTAB)
  out.write_uint_le(24)
  out.write_uint_le(symoff.reinterpret_as_uint())
  out.write_uint_le(symbols.length().reinterpret_as_uint())
  out.write_uint_le(stroff.reinterpret_as_uint())
  out.write_uint_le(strtab.length().reinterpret_as_uint())
  out.write_uint_le(LC_BUILD_VERSION)
  out.write_uint_le(24)
  out.write_uint_le(PLATFORM_MACOS)
  out.write_uint_le(0x000a0600)
  out.write_uint_le(0x000a0600)
  out.write_uint_le(0)
  out.write_uint_le(LC_SOURCE_VERSION)
  out.write_uint_le(16)
  out.write_uint64_le(0)
  let mut fileoff = out.length()
  for seg in segment_order {
    match segment_sections.get(seg) {
      None => ()
      Some(list) =>
        for idx in list {
          let layout = layouts[idx]
          if layout.info.is_zerofill {
            continue
          }
          let align = 1 << layout.align_log2
          let aligned = align_up(fileoff, align)
          while fileoff < aligned {
            out.write_byte(0)
            fileoff = fileoff + 1
          }
          let word_len = section_word_len(layout.section)
          let mut i = 0
          while i < word_len {
            out.write_uint_le(layout.section.data[i])
            fileoff = fileoff + 4
            i = i + 1
          }
        }
    }
  }
  let reloc_aligned = align_up(fileoff, 4)
  while fileoff < reloc_aligned {
    out.write_byte(0)
    fileoff = fileoff + 1
  }
  for seg in segment_order {
    match segment_sections.get(seg) {
      None => ()
      Some(list) =>
        for idx in list {
          let layout = layouts[idx]
          for rel in layout.section.relocs {
            let (rtype, pcrel) = macho_reloc_type(rel.kind)
            let symbolnum = match id_to_index.get(rel.sym.id) {
              None => 0
              Some(idx) => idx
            }
            let len = reloc_length(rel.kind)
            let info = pack_reloc_info(symbolnum, pcrel, len, true, rtype)
            out.write_uint_le(rel.offset.reinterpret_as_uint())
            out.write_uint_le(info)
            fileoff = fileoff + 8
          }
        }
    }
  }
  let sym_aligned = align_up(fileoff, 4)
  while fileoff < sym_aligned {
    out.write_byte(0)
    fileoff = fileoff + 1
  }
  out.write_bytes(symtab)
  fileoff = fileoff + symtab.length()
  out.write_bytes(strtab)
  out.to_bytes()
}

///|
fn collect_section_indices(
  layouts : Array[MachoSectionLayout],
) -> FastMap[String, Int] {
  let map : FastMap[String, Int] = fast_map_new()
  for layout in layouts {
    map.set(layout.section.name, layout.index)
  }
  map
}

///|
fn segment_file_range(
  indices : Array[Int],
  layouts : Array[MachoSectionLayout],
) -> (Int, Int) {
  let mut start = -1
  let mut end = 0
  for idx in indices {
    let layout = layouts[idx]
    if layout.info.is_zerofill {
      continue
    }
    if start < 0 || layout.offset < start {
      start = layout.offset
    }
    let end_here = layout.offset + layout.size
    if end_here > end {
      end = end_here
    }
  }
  if start < 0 {
    (0, 0)
  } else {
    (start, end - start)
  }
}

///|
fn segment_prot(name : String) -> (Int, Int) {
  if name == "__TEXT" {
    let prot = VM_PROT_READ | VM_PROT_EXECUTE
    (prot, prot)
  } else {
    let prot = VM_PROT_READ | VM_PROT_WRITE
    (prot, prot)
  }
}

///|
fn write_macho_object(
  path : String,
  sections : Array[Section],
  symbols : Array[ObjSymbol],
) -> Unit raise @fs.IOError {
  let bytes = encode_macho_object(sections, symbols)
  @fs.write_bytes_to_file(path, bytes)
}

///| keep unused definitions referenced to silence warnings
let _macho_layout_sentinel : MachoSegmentLayout? = None
