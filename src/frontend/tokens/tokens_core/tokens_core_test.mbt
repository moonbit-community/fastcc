///|
test "lexeme pool intern" {
  let pool = @tokens_core.new_lexeme_pool(capacity=4)
  let id = @tokens_core.lexeme_pool_intern(pool, "bar")
  assert_true(id > 0)
  inspect(@tokens_core.lexeme_pool_get(pool, id), content="bar")
}
