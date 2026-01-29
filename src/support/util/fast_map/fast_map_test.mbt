///|
test "fast_map_new supports set/get" {
  let map : @fast_map.FastMap[String, Int] = @fast_map.fast_map_new()
  map["key"] = 42
  assert_eq(map["key"], 42)
}
