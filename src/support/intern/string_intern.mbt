///|
pub type StringInterner = @intern_core.StringInterner

///|
pub let tok_hash_init : UInt = @intern_core.tok_hash_init

///|
pub fn tok_hash_step(h : UInt, code : UInt16) -> UInt {
  @intern_core.tok_hash_step(h, code)
}

///|
pub fn new_string_interner_with_capacity(capacity? : Int) -> StringInterner {
  match capacity {
    None => @intern_core.new_string_interner_with_capacity()
    Some(value) =>
      @intern_core.new_string_interner_with_capacity(capacity=value)
  }
}
