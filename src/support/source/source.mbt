///|
pub type SrcLoc = @source_core.SrcLoc

///|
pub type SourceFile = @source_core.SourceFile

///|
pub type SourceMap = @source_core.SourceMap

///|
pub fn new_source_map() -> SourceMap {
  @source_core.new_source_map()
}

///|
pub fn add_file(map : SourceMap, path : String, text : String) -> SourceFile {
  @source_core.add_file(map, path, text)
}

///|
pub fn dummy_loc(file_id : Int) -> SrcLoc {
  @source_core.dummy_loc(file_id)
}
