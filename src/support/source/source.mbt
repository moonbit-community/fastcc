///|
struct SrcLoc {
  file_id : Int
  line : Int
  col : Int
  offset : Int
} derive(Show, Eq, ToJson)

///|
struct SourceFile {
  id : Int
  path : String
  text : String
}

///|
struct SourceMap {
  files : Array[SourceFile]
}

///|
fn new_source_map() -> SourceMap {
  { files: [] }
}

///|
fn add_file(map : SourceMap, path : String, text : String) -> SourceFile {
  let id = map.files.length()
  let file = { id, path, text }
  map.files.push(file)
  file
}

///|
fn dummy_loc(file_id : Int) -> SrcLoc {
  { file_id, line: 1, col: 1, offset: 0 }
}
