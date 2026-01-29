///|
test "parser tracks typedef struct name" {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(
    map,
    "<test>",
    "typedef struct { int x; } T; int main(){ T r; return r.x; }",
  )
  let pp = @preproc.new_preprocessor(map, file, bag)
  let parser = new_parser(pp)
  ignore(parse_translation_unit_with(parser))
  let (_, type_id) = parser.pp.interner.intern_view_with_id("T"[:])
  assert_true(get_typedef_count(parser, type_id) > 0)
}
