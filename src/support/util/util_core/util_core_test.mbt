///|
test "util core helpers" {
  inspect(@util_core.slice_string("abcd", 1, 3), content="bc")
  assert_true(@util_core.int_literal_base("0x10") == 16)
}
