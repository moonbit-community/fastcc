///|
fn parse_text(text : String) -> (TranslationUnit, DiagBag) {
  let bag = new_diag_bag()
  let map = new_source_map()
  let file = add_file(map, "<test>", text)
  let pp = new_preprocessor(file, bag)
  let unit = parse_translation_unit(pp)
  (unit, bag)
}

///|
fn check_text(text : String) -> (TranslationUnit, DiagBag) {
  let (unit, bag) = parse_text(text)
  check_translation_unit(unit, bag)
  (unit, bag)
}

///|
test "parse function with return" {
  let (unit, bag) = parse_text("int main(){return 1;}")
  assert_true(!has_errors(bag))
  guard unit.decls.length() == 1 else { fail("expected single declaration") }
  match unit.decls[0] {
    Decl::FuncDef(func) => assert_eq(func.name, "main")
    _ => fail("expected function definition")
  }
}

///|
test "sem accepts local declarations" {
  let (_, bag) = check_text("int main(){int x = 1; return x;}")
  assert_true(!has_errors(bag))
}

///|
test "sem rejects missing return value" {
  let (_, bag) = check_text("int main(){return;}")
  assert_true(has_errors(bag))
}

///|
test "sem rejects undeclared identifier" {
  let (_, bag) = check_text("int main(){return x;}")
  assert_true(has_errors(bag))
}
