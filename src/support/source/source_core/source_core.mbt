// Copyright (C) 2026 International Digital Economy Academy
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License as published by the Free Software Foundation; version 2.1
// of the License.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public
// License along with this library.  If not, see <https://www.gnu.org/licenses/>.

///|
pub(all) struct SrcLoc {
  file_id : Int32
  line : Int32
  col : Int32
  offset : Int32
} derive(Show, Eq, ToJson, Debug)

///|
pub(all) struct SourceFile {
  id : Int32
  path : String
  text : String
}

///|
pub(all) struct SourceMap {
  files : Array[SourceFile]
}

///|
pub fn new_source_map() -> SourceMap {
  { files: [], }
}

///|
pub fn add_file(map : SourceMap, path : String, text : String) -> SourceFile {
  let id = map.files.length()
  let file = { id, path, text, }
  map.files.push(file)
  file
}

///|
pub fn dummy_loc(file_id : Int32) -> SrcLoc {
  { file_id, line: 1, col: 1, offset: 0, }
}
