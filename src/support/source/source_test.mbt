///|
test "source map tracks files" {
  let map = new_source_map()
  let file = add_file(map, "foo.c", "int main(){}")
  inspect(map.files.length(), content="1")
  inspect(file.id, content="0")
  inspect(file.path, content="foo.c")
  let loc = dummy_loc(file.id)
  inspect(loc.file_id, content="0")
  inspect(loc.line, content="1")
}
