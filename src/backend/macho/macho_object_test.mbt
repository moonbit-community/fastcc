///|
test "macho encode and write" {
  let sec_text : @object.Section = {
    name: ".text",
    data: [0x1234],
    relocs: [
      { offset: 0, kind: @arm64.R_AARCH64_POINTER, sym: { id: 1 }, addend: 0 },
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
    {
      id: 1,
      name: "sym_text",
      section: Some(".text"),
      value: 0,
      is_external: false,
    },
    {
      id: 2,
      name: "sym_missing",
      section: Some(".missing"),
      value: 0,
      is_external: false,
    },
  ]
  let bytes = @macho.encode_macho_object([sec_text, sec_custom], symbols)
  assert_true(bytes.length() > 0)
  let case_dir = @testutil.make_case_dir("macho")
  let path = @testutil.join_path(case_dir, "tinycc.o")
  @macho.write_macho_object(
    host=@default_host.new(),
    path,
    [sec_text, sec_custom],
    symbols,
  )
  assert_true(@fs.path_exists(path))
}

///|
test "macho symtab missing section" {
  let symbols : Array[@macho.ObjSymbol] = [
    {
      id: 10,
      name: "sym_missing",
      section: Some(".nowhere"),
      value: 0,
      is_external: true,
    },
  ]
  let bytes = @macho.encode_macho_object([], symbols)
  assert_true(bytes.length() > 0)
}

///|
test "macho bss section encode and write" {
  let sec_bss : @object.Section = {
    name: ".bss",
    data: [],
    relocs: [],
    align: 0,
    size_bytes: 16,
  }
  let bytes = @macho.encode_macho_object([sec_bss], [])
  assert_true(bytes.length() > 0)
  let case_dir = @testutil.make_case_dir("macho-bss")
  let path = @testutil.join_path(case_dir, "bss.o")
  @macho.write_macho_object(host=@default_host.new(), path, [sec_bss], [])
  assert_true(@fs.path_exists(path))
}

///|
test "macho encode empty object" {
  let bytes = @macho.encode_macho_object([], [])
  assert_true(bytes.length() > 0)
}

///|
test "macho reloc variants" {
  let sec_text : @object.Section = {
    name: ".text",
    data: [0x90],
    relocs: [
      { offset: 0, kind: @arm64.R_AARCH64_POINTER, sym: { id: 1 }, addend: 0 },
      { offset: 0, kind: @arm64.R_AARCH64_CALL26, sym: { id: 2 }, addend: 0 },
      { offset: 0, kind: 999, sym: { id: 99 }, addend: 0 },
    ],
    align: 4,
    size_bytes: 0,
  }
  let sec_data : @object.Section = {
    name: ".data",
    data: [0x01, 0x02],
    relocs: [],
    align: 4,
    size_bytes: 0,
  }
  let symbols : Array[@macho.ObjSymbol] = [
    {
      id: 1,
      name: "sym_text",
      section: Some(".text"),
      value: 0,
      is_external: false,
    },
    { id: 2, name: "sym_undef", section: None, value: 0, is_external: true },
    {
      id: 3,
      name: "sym_data",
      section: Some(".data"),
      value: 4,
      is_external: false,
    },
  ]
  let bytes = @macho.encode_macho_object([sec_text, sec_data], symbols)
  assert_true(bytes.length() > 0)
  let case_dir = @testutil.make_case_dir("macho-reloc")
  let path = @testutil.join_path(case_dir, "reloc.o")
  @macho.write_macho_object(
    host=@default_host.new(),
    path,
    [sec_text, sec_data],
    symbols,
  )
  assert_true(@fs.path_exists(path))
}
