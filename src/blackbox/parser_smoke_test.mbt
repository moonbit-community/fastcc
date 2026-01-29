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
