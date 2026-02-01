///|
test "fast_map_new supports set/get" {
  let map : @fast_map.FastMap[String, Int] = @fast_map.fast_map_new()
  assert_true(map.is_empty())
  map["key"] = 42
  assert_eq(map.length(), 1)
  assert_eq(map["key"], 42)
  let map2 : @fast_map.FastMap[String, Int] = @fast_map.fast_map_new(capacity=4)
  map2["b"] = 2
  assert_true(map2.contains("b"))
  assert_eq(map2["b"], 2)
}
