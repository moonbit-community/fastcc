///|
type FastMap[K, V] = @util.FastMap[K, V]

///|
fn[K, V] fast_map_new(capacity? : Int) -> FastMap[K, V] {
  @util.fast_map_new(capacity?)
}
