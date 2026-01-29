///|
pub type FastMap[K, V] = @util_core.FastMap[K, V]

///|
pub let char_is_unsigned : Bool = @util_core.char_is_unsigned

///|
pub fn[K, V] fast_map_new(capacity? : Int) -> FastMap[K, V] {
  match capacity {
    None => @util_core.fast_map_new()
    Some(value) => @util_core.fast_map_new(capacity=value)
  }
}

///|
pub fn int_literal_end(text : String) -> Int {
  @util_core.int_literal_end(text)
}

///|
pub fn int_literal_base(text : String) -> Int {
  @util_core.int_literal_base(text)
}

///|
pub fn int_literal_base_from(text : String, end : Int) -> Int {
  @util_core.int_literal_base_from(text, end)
}

///|
pub fn parse_uint64_literal(text : String, base : Int) -> UInt64 {
  @util_core.parse_uint64_literal(text, base)
}

///|
pub fn parse_uint64_literal_prefix(text : String, base : Int, end : Int) -> UInt64 {
  @util_core.parse_uint64_literal_prefix(text, base, end)
}

///|
pub fn parse_int_suffix(suffix : String) -> (Int, Bool) {
  @util_core.parse_int_suffix(suffix)
}

///|
pub fn parse_int_suffix_range(text : String, start : Int) -> (Int, Bool) {
  @util_core.parse_int_suffix_range(text, start)
}

///|
pub fn slice_string(text : String, start : Int, end : Int) -> String {
  @util_core.slice_string(text, start, end)
}

///|
pub fn hex_digit_value(code : UInt16) -> Int? {
  @util_core.hex_digit_value(code)
}
