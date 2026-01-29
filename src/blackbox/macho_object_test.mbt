///|
fn macho_ensure_dir(path : String) -> Unit raise {
  if @fs.path_exists(path) {
    return
  }
  @fs.create_dir(path)
}

///|
fn macho_join_path(dir : String, name : String) -> String {
  if dir == "" {
    name
  } else if dir.has_suffix("/") {
    dir + name
  } else {
    dir + "/" + name
  }
}

///|
fn macho_make_case_dir(prefix : String) -> String raise {
  let root = match @env.current_dir() {
    Some(path) => path
    None => "."
  }
  let base = macho_join_path(root, "target/blackbox")
  macho_ensure_dir(base)
  let stamp = @ffi.bench_now_ns()
  let case_dir = macho_join_path(base, prefix + "-" + stamp.to_string())
  macho_ensure_dir(case_dir)
  case_dir
}

///|
test "object section helpers" {
  let sec = @object.new_section(".text")
  assert_eq(@object.section_word_len(sec), 0)
  assert_eq(@object.section_size_bytes(sec), 0)
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

  let rel : @object.Reloc = {
    offset: 4,
    kind: 1,
    sym: { id: 7 },
    addend: 9,
  }
  assert_eq(@object.reloc_addend(rel), 9)
}

///|
test "macho encode and write" {
  let sec_text : @object.Section = {
    name: ".text",
    data: [0x1234],
    relocs: [
      {
        offset: 0,
        kind: @arm64.R_AARCH64_POINTER,
        sym: { id: 1 },
        addend: 0,
      },
      {
        offset: 0,
        kind: @arm64.R_AARCH64_ADR_PREL_PG_HI21_NC,
        sym: { id: 2 },
        addend: 4,
      },
    ],
    align: 4,
    size_bytes: 0,
  }
  let sec_custom : @object.Section = {
    name: ".custom",
    data: [0x5678],
    relocs: [],
    align: 0,
    size_bytes: 0,
  }
  let symbols : Array[@macho.ObjSymbol] = [
    { id: 1, name: "sym_text", section: Some(".text"), value: 0, is_external: false },
    { id: 2, name: "sym_missing", section: Some(".missing"), value: 0, is_external: false },
  ]
  let bytes = @macho.encode_macho_object([sec_text, sec_custom], symbols)
  assert_true(bytes.length() > 0)

  let case_dir = macho_make_case_dir("macho")
  let path = macho_join_path(case_dir, "tinycc.o")
  @macho.write_macho_object(path, [sec_text, sec_custom], symbols)
  assert_true(@fs.path_exists(path))
}

///|
test "macho symtab missing section" {
  let symbols : Array[@macho.ObjSymbol] = [
    { id: 10, name: "sym_missing", section: Some(".nowhere"), value: 0, is_external: true },
  ]
  let bytes = @macho.encode_macho_object([], symbols)
  assert_true(bytes.length() > 0)
}
