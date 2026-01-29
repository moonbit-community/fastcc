///|
test "lexeme pool intern" {
  let pool = @tokens.new_lexeme_pool()
  let id = @tokens.lexeme_pool_intern(pool, "foo")
  assert_true(id > 0)
  inspect(@tokens.lexeme_pool_get(pool, id), content="foo")
}
