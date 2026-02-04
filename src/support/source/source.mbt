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
