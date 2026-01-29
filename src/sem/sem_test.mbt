///|
test "sem accepts empty translation unit" {
  let bag = @diag.new_diag_bag()
  let unit = @ast.TranslationUnit::{ decls: [], expr_id_max: 0 }
  let _ctx = check_translation_unit(unit, bag)
  assert_true(!@diag.has_errors(bag))
}
