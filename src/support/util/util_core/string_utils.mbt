///|
pub fn slice_string(text : String, start : Int, end : Int) -> String {
  text.view(start_offset=start, end_offset=end).to_string()
}

///|
pub fn hex_digit_value(code : UInt16) -> Int? {
  if code >= 48 && code <= 57 {
    return Some(code.to_int() - 48)
  }
  if code >= 65 && code <= 70 {
    return Some(code.to_int() - 65 + 10)
  }
  if code >= 97 && code <= 102 {
    return Some(code.to_int() - 97 + 10)
  }
  None
}
