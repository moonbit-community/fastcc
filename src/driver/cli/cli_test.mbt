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
test "cli parses -c" {
  let cfg = match
    @cli.parse_cli_args(host=@default_host.new(), ["prog", "-c", "main.c"]) {
    Run(v) => v
    _ => fail("expected run")
  }
  assert_true(cfg.compile_only)
  assert_eq(cfg.inputs, ["main.c"])
}
