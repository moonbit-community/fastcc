///|
pub fn slice_string(text : String, start : Int, end : Int) -> String {
  text.view(start_offset=start, end_offset=end).to_string()
}

///|
pub fn hex_digit_value(code : UInt16) -> Int? {
  let value = code.to_int()
  if value >= 48 && value <= 57 {
    return Some(value - 48)
  }
  if value >= 65 && value <= 70 {
    return Some(value - 55)
  }
  if value >= 97 && value <= 102 {
    return Some(value - 87)
  }
  None
}
