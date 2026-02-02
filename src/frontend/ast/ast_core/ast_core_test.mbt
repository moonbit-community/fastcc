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
test "attributes helpers" {
  let base = @ast_core.empty_attrs()
  assert_true(@ast_core.attrs_is_empty(base))
  let incoming = @ast_core.attrs_with(packed=true, weak=true)
  let merged = @ast_core.merge_attrs(base, incoming)
  assert_true(merged.packed)
  assert_true(merged.weak)
}

///|
test "type qualifiers helpers" {
  let base = @ast_core.empty_qual()
  let const_qual = @ast_core.with_const(base)
  let combined = @ast_core.merge_qual(
    const_qual,
    @ast_core.with_volatile(@ast_core.empty_qual()),
  )
  let ty = @ast_core.apply_qualifiers(Int(kind=Int, unsigned=false), combined)
  match ty {
    Qualified(qual~, ..) => assert_true(qual.is_const && qual.is_volatile)
    _ => fail("expected qualified type")
  }
}

///|
test "expr helpers" {
  let loc = @source.dummy_loc(0)
  let expr = @ast_core.Expr::IntLit(value="1", node_id=42, loc~)
  assert_true(@ast_core.expr_loc(expr) == loc)
  assert_eq(@ast_core.expr_node_id(expr), 42)
  assert_true(@ast_core.parse_int64_literal("0x10") is Some(16))
}
