///|
test "string utils helpers" {
  inspect(@string_utils.slice_string("abcd", 1, 3), content="bc")
  inspect(@string_utils.hex_digit_value('A'), content="Some(10)")
  inspect(@string_utils.hex_digit_value('f'), content="Some(15)")
}
