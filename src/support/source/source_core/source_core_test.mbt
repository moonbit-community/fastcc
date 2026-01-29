///|
test "source core maps files" {
  let map = @source_core.new_source_map()
  let file = @source_core.add_file(map, "bar.c", "int x;")
  inspect(map.files.length(), content="1")
  inspect(file.id, content="0")
  let loc = @source_core.dummy_loc(file.id)
  inspect(loc.line, content="1")
}
