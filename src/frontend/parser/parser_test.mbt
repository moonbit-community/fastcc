///|
test "parser parses translation unit" {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<test>", "int main(){return 0;}")
  let pp = @preproc.new_preprocessor(map, file, bag)
  let unit = @parser.parse_translation_unit(pp)
  assert_true(unit.decls.length() > 0)
  assert_true(!@diag.has_errors(bag))
}
