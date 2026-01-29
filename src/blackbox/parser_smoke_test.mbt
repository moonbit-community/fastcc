///|
fn parse_unit(source : String) -> (@ast.TranslationUnit, @diag.DiagBag) {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<parser-test>", source)
  let pp = @preproc.new_preprocessor(map, file, bag)
  let unit = @parser.parse_translation_unit(pp)
  (unit, bag)
}

///|
fn find_var_decl(unit : @ast.TranslationUnit, name : String) -> @ast.VarDecl? {
  for decl in unit.decls {
    match decl {
      @ast.Decl::Var(v) => if v.name == name { return Some(v) }
      _ => ()
    }
  }
  None
}

///|
fn collect_asm_decls(unit : @ast.TranslationUnit) -> Array[@ast.AsmStmt] {
  let out : Array[@ast.AsmStmt] = []
  for decl in unit.decls {
    match decl {
      @ast.Decl::Asm(asm_stmt) => out.push(asm_stmt)
      _ => ()
    }
  }
  out
}

///|
test "parser handles static assert and asm decls" {
  let source =
    "_Static_assert(1);\nasm volatile(\"a\" \"b\");\nasm goto(\"jmp %l0\" : : : : target);\nasm(\"add\" : [out] \"=r\"(x) : \"r\"(y) : \"memory\");\n"
  let (unit, bag) = parse_unit(source)
  assert_true(!@diag.has_errors(bag))

  let mut static_asserts = 0
  for decl in unit.decls {
    match decl {
      @ast.Decl::StaticAssert(sa) => {
        static_asserts = static_asserts + 1
        assert_true(sa.message is None)
      }
      _ => ()
    }
  }
  assert_eq(static_asserts, 1)

  let asm_decls = collect_asm_decls(unit)
  assert_eq(asm_decls.length(), 3)

  let mut saw_concat = false
  let mut saw_goto = false
  let mut saw_operands = false
  for asm_stmt in asm_decls {
    if asm_stmt.template == "ab" {
      saw_concat = true
      assert_true(asm_stmt.is_volatile)
      assert_true(!asm_stmt.is_goto)
    }
    if asm_stmt.template == "jmp %l0" {
      saw_goto = true
      assert_true(asm_stmt.is_goto)
      assert_eq(asm_stmt.labels, ["target"])
    }
    if asm_stmt.template == "add" {
      saw_operands = true
      assert_eq(asm_stmt.outputs.length(), 1)
      assert_eq(asm_stmt.inputs.length(), 1)
      assert_eq(asm_stmt.clobbers, ["memory"])
    }
  }
  assert_true(saw_concat)
  assert_true(saw_goto)
  assert_true(saw_operands)
}

///|
test "parser typedef errors recover" {
  let source = "typedef int;\ntypedef int T = 1;\nint ok;\n"
  let (unit, bag) = parse_unit(source)
  assert_true(@diag.has_errors(bag))

  match find_var_decl(unit, "ok") {
    Some(_) => ()
    None => fail("expected ok declaration")
  }
}

///|
test "parser typeof and default int" {
  let source = "typeof(1) y;\nfoo;\n"
  let (unit, bag) = parse_unit(source)
  assert_true(!@diag.has_errors(bag))

  let y_decl = match find_var_decl(unit, "y") {
    Some(v) => v
    None => fail("expected y declaration")
  }
  match y_decl.ty {
    @ast.CType::TypeofExpr(_) => ()
    _ => fail("expected typeof expr type")
  }

  let foo_decl = match find_var_decl(unit, "foo") {
    Some(v) => v
    None => fail("expected foo declaration")
  }
  match foo_decl.ty {
    @ast.CType::Int(kind=@ast.CIntKind::Int, unsigned=false) => ()
    _ => fail("expected default int type")
  }
}

///|
test "parser attributes and qualifiers" {
  let source =
    "__attribute__((aligned(16), packed, weak, noreturn, constructor, destructor, always_inline, section(\"sec\" \"2\"), alias(\"ali\"), visibility(\"hidden\"), cleanup(cleanup_fn), cdecl, stdcall, fastcall, thiscall, regparm(2), dllimport, dllexport, nodecorate, nodebug)) int * volatile restrict p;\n_Atomic int q;\n"
  let (unit, bag) = parse_unit(source)
  assert_true(!@diag.has_errors(bag))

  match find_var_decl(unit, "p") {
    Some(_) => ()
    None => fail("expected p declaration")
  }
  match find_var_decl(unit, "q") {
    Some(_) => ()
    None => fail("expected q declaration")
  }
}

///|
test "parser attribute and typeof errors" {
  let source =
    "__attribute__ int a;\n__attribute__((123)) int b;\n__attribute__((section(1))) int c;\ntypeof int d;\ntypeof(struct) e;\nsigned unsigned int bad;\nint ok;\n"
  let (unit, bag) = parse_unit(source)
  assert_true(@diag.has_errors(bag))

  match find_var_decl(unit, "ok") {
    Some(_) => ()
    None => fail("expected ok declaration")
  }
}

///|
test "parser old-style parameter diagnostics" {
  let source =
    "int f(a, a, b)\nint a;\nint a;\nint ;\nstatic int b;\ninline int a;\ntypedef int t;\nint c;\n{ return 0; }\n"
  let (_unit, bag) = parse_unit(source)
  assert_true(@diag.has_errors(bag))
}

///|
test "parser arrays and varargs" {
  let source = "int arr[3];\nint arr_empty[1] = {};\nint (*fp)[2];\nint v(...);\n"
  let (unit, bag) = parse_unit(source)
  assert_true(!@diag.has_errors(bag))

  match find_var_decl(unit, "arr") {
    Some(_) => ()
    None => fail("expected arr declaration")
  }
  match find_var_decl(unit, "arr_empty") {
    Some(_) => ()
    None => fail("expected arr_empty declaration")
  }
  match find_var_decl(unit, "fp") {
    Some(_) => ()
    None => fail("expected fp declaration")
  }
}

///|
test "parser syncs after stray tokens" {
  let source = ";\nint ok;\n"
  let (unit, bag) = parse_unit(source)
  assert_true(!@diag.has_errors(bag))
  match find_var_decl(unit, "ok") {
    Some(_) => ()
    None => fail("expected ok declaration")
  }
}

///|
test "parser enum and struct errors" {
  let source = "enum Empty {};\nstruct ;\nint ok;\n"
  let (unit, bag) = parse_unit(source)
  assert_true(@diag.has_errors(bag))
  match find_var_decl(unit, "ok") {
    Some(_) => ()
    None => fail("expected ok declaration")
  }
}
