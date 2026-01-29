///|
pub type FastMap[K, V] = @hashmap.HashMap[K, V]

///|
pub fn[K, V] fast_map_new(capacity? : Int) -> FastMap[K, V] {
  match capacity {
    None => @hashmap.new()
    Some(value) => @hashmap.new(capacity=value)
  }
}
