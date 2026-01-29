///|
fn parse_text(text : String) -> (@ast.TranslationUnit, @diag.DiagBag) {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<test>", text)
  let pp = @preproc.new_preprocessor(map, file, bag)
  let unit = @parser.parse_translation_unit(pp)
  (unit, bag)
}

///|
test "codegen emits object bytes" {
  let (unit, bag) = parse_text("int main(){return 0;}")
  assert_true(!@diag.has_errors(bag))
  @sem.check_translation_unit(unit, bag) |> ignore
  assert_true(!@diag.has_errors(bag))
  match @codegen.codegen_arm64_object_bytes(unit, bag) {
    None => fail("expected object bytes")
    Some(_bytes) => ()
  }
}
