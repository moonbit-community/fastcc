///|
pub type FastMap[K, V] = @hashmap.HashMap[K, V]

///|
pub fn[K, V] fast_map_new(capacity? : Int) -> FastMap[K, V] {
  match capacity {
    None => @hashmap.new()
    Some(value) => {
      let cap = if value > 0 { value } else { 0 }
      @hashmap.new(capacity=cap)
    }
  }
}
