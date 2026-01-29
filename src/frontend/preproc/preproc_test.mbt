///|
test "preprocessor token dump" {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<test>", "int x;")
  let pp = new_preprocessor(map, file, bag)
  let toks = dump_tokens(pp, 8)
  assert_true(toks.length() > 0)
  assert_true(!@diag.has_errors(bag))
}
