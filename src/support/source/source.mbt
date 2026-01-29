///|
pub(all) struct SrcLoc {
  file_id : Int
  line : Int
  col : Int
  offset : Int
} derive(Show, Eq, ToJson)

///|
pub(all) struct SourceFile {
  id : Int
  path : String
  text : String
}

///|
pub(all) struct SourceMap {
  files : Array[SourceFile]
}

///|
pub fn new_source_map() -> SourceMap {
  { files: [] }
}

///|
pub fn add_file(map : SourceMap, path : String, text : String) -> SourceFile {
  let id = map.files.length()
  let file = { id, path, text }
  map.files.push(file)
  file
}

///|
pub fn dummy_loc(file_id : Int) -> SrcLoc {
  { file_id, line: 1, col: 1, offset: 0 }
}
