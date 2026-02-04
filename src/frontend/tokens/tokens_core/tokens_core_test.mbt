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
test "lexeme pool intern" {
  let pool = @tokens_core.new_lexeme_pool(capacity=4)
  let id = @tokens_core.lexeme_pool_intern(pool, "bar")
  assert_true(id > 0)
  inspect(@tokens_core.lexeme_pool_get(pool, id), content="bar")
}
