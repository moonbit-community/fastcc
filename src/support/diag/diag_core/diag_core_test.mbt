///|
test "diag core collects errors" {
  let bag = @diag_core.new_diag_bag()
  assert_true(!@diag_core.has_errors(bag))
  @diag_core.add_error(bag, @source.dummy_loc(0), "err")
  assert_true(@diag_core.has_errors(bag))
  inspect(@diag_core.error_count(bag), content="1")
}
