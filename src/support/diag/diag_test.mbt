///|
test "diag bag collects errors" {
  let bag = new_diag_bag()
  assert_true(!has_errors(bag))
  add_error(bag, @source.dummy_loc(0), "oops")
  assert_true(has_errors(bag))
  inspect(bag.diags.length(), content="1")
}
