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
test "source map tracks files" {
  let map = @source.new_source_map()
  let file = @source.add_file(map, "foo.c", "int main(){}")
  inspect(map.files.length(), content="1")
  inspect(file.id, content="0")
  inspect(file.path, content="foo.c")
  let loc = @source.dummy_loc(file.id)
  inspect(loc.file_id, content="0")
  inspect(loc.line, content="1")
}
