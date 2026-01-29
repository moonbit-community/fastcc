///|
test "lexeme pool intern" {
  let pool = new_lexeme_pool()
  let id = lexeme_pool_intern(pool, "foo")
  assert_true(id > 0)
  inspect(lexeme_pool_get(pool, id), content="foo")
}
