///|
test "diag bag and formatting" {
  let bag = @diag.new_diag_bag()
  assert_true(!@diag.has_errors(bag))
  assert_eq(@diag.error_count(bag), 0)
  let loc = @source.dummy_loc(3)
  @diag.add_error(bag, loc, "oops")
  assert_true(@diag.has_errors(bag))
  assert_eq(@diag.error_count(bag), 1)
  let diag0 = bag.diags[0]
  assert_eq(@diag.format_diag(diag0), "oops")
  assert_eq(diag0.loc, loc)
}
