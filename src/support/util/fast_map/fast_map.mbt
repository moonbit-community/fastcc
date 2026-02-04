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
pub type FastMap[K, V] = @hashmap.HashMap[K, V]

///|
pub fn[K, V] fast_map_new(capacity? : Int) -> FastMap[K, V] {
  match capacity {
    None => @hashmap.new()
    Some(value) => @hashmap.new(capacity=value)
  }
}
