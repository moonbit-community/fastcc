///|
test "diag bag collects errors" {
  let bag = @diag.new_diag_bag()
  assert_true(!@diag.has_errors(bag))
  @diag.add_error(bag, @source.dummy_loc(0), "oops")
  assert_true(@diag.has_errors(bag))
  inspect(@diag.error_count(bag), content="1")
}

///|
test "diag formatting" {
  let diag : @diag.Diag = { loc: @source.dummy_loc(0), message: "msg" }
  inspect(@diag.format_diag(diag), content="msg")
}
