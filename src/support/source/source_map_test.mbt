///|
test "source map add file" {
  let map = @source.new_source_map()
  assert_eq(map.files.length(), 0)
  let file0 = @source.add_file(map, "<a>", "int a;")
  assert_eq(file0.id, 0)
  assert_eq(file0.path, "<a>")
  assert_eq(file0.text, "int a;")
  assert_eq(map.files.length(), 1)
  let file1 = @source.add_file(map, "<b>", "int b;")
  assert_eq(file1.id, 1)
  assert_eq(file1.path, "<b>")
  assert_eq(file1.text, "int b;")
  assert_eq(map.files.length(), 2)
  assert_eq(map.files[1].path, "<b>")
}

///|
test "source dummy loc" {
  let loc = @source.dummy_loc(7)
  assert_eq(loc.file_id, 7)
  assert_eq(loc.line, 1)
  assert_eq(loc.col, 1)
  assert_eq(loc.offset, 0)
}
