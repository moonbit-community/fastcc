///|
test "string utils helpers" {
  assert_eq(@string_utils.slice_string("abc", 0, 3), "abc")
  assert_eq(@string_utils.slice_string("abc", 1, 2), "b")
  inspect(@string_utils.slice_string("abcd", 1, 3), content="bc")
  assert_eq(@string_utils.hex_digit_value('5'), Some(5))
  inspect(@string_utils.hex_digit_value('A'), content="Some(10)")
  inspect(@string_utils.hex_digit_value('f'), content="Some(15)")
  assert_eq(@string_utils.hex_digit_value('g'), None)
}
