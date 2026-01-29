///|
pub fn int_literal_end(text : String) -> Int {
  let len = text.length()
  if len == 0 {
    return 0
  }
  let first = text[0]
  if first == 48 {
    if len >= 2 {
      let next = text[1]
      if next == 120 || next == 88 {
        return scan_digits(text, 2, is_hex_digit_code)
      }
      if next == 98 || next == 66 {
        return scan_digits(text, 2, is_bin_digit_code)
      }
      return scan_digits(text, 1, is_oct_digit_code)
    }
    return 1
  }
  scan_digits(text, 0, is_dec_digit_code)
}

///|
pub fn int_literal_base(text : String) -> Int {
  let trimmed = @string_utils.slice_string(text, 0, int_literal_end(text))
  if trimmed.length() >= 2 && trimmed[0] == 48 {
    let next = trimmed[1]
    if next == 120 || next == 88 {
      return 16
    }
    if next == 98 || next == 66 {
      return 2
    }
    return 8
  }
  10
}

///|
pub fn int_literal_base_from(text : String, end : Int) -> Int {
  if end >= 2 && text[0] == 48 {
    let next = text[1]
    if next == 120 || next == 88 {
      return 16
    }
    if next == 98 || next == 66 {
      return 2
    }
    return 8
  }
  10
}

///|
pub fn parse_uint64_literal(text : String, base : Int) -> UInt64 {
  let mut value : UInt64 = 0
  let mut i = 0
  if base == 16 &&
    text.length() >= 2 &&
    text[0] == 48 &&
    (text[1] == 120 || text[1] == 88) {
    i = 2
  } else if base == 2 &&
    text.length() >= 2 &&
    text[0] == 48 &&
    (text[1] == 98 || text[1] == 66) {
    i = 2
  } else if base == 8 && text.length() > 1 && text[0] == 48 {
    i = 1
  }
  while i < text.length() {
    let code = text[i]
    let digit = match digit_value(code) {
      None => break
      Some(v) => v
    }
    if digit >= base {
      break
    }
    value = value * base.to_uint64() + digit.to_uint64()
    i = i + 1
  }
  value
}

///|
pub fn parse_uint64_literal_prefix(text : String, base : Int, end : Int) -> UInt64 {
  let mut value : UInt64 = 0
  let mut i = 0
  if base == 16 && end >= 2 && text[0] == 48 &&
    (text[1] == 120 || text[1] == 88) {
    i = 2
  } else if base == 2 && end >= 2 && text[0] == 48 &&
    (text[1] == 98 || text[1] == 66) {
    i = 2
  } else if base == 8 && end > 1 && text[0] == 48 {
    i = 1
  }
  while i < end {
    let code = text[i]
    let digit = match digit_value(code) {
      None => break
      Some(v) => v
    }
    if digit >= base {
      break
    }
    value = value * base.to_uint64() + digit.to_uint64()
    i = i + 1
  }
  value
}

///|
pub fn parse_int_suffix(suffix : String) -> (Int, Bool) {
  let mut long_count = 0
  let mut unsigned = false
  for code in suffix.to_lower() {
    if code == 'l' {
      long_count = long_count + 1
    } else if code == 'u' {
      unsigned = true
    }
  }
  if long_count > 2 {
    long_count = 2
  }
  (long_count, unsigned)
}

///|
pub fn parse_int_suffix_range(text : String, start : Int) -> (Int, Bool) {
  let mut long_count = 0
  let mut unsigned = false
  let len = text.length()
  let mut i = start
  while i < len {
    let code = text[i]
    if code == 108 || code == 76 {
      long_count = long_count + 1
    } else if code == 117 || code == 85 {
      unsigned = true
    }
    i = i + 1
  }
  if long_count > 2 {
    long_count = 2
  }
  (long_count, unsigned)
}

///|
fn scan_digits(text : String, start : Int, accept : (UInt16) -> Bool) -> Int {
  let mut i = start
  while i < text.length() {
    if !accept(text[i]) {
      break
    }
    i = i + 1
  }
  i
}

///|
fn is_dec_digit_code(code : UInt16) -> Bool {
  code >= 48 && code <= 57
}

///|
fn is_oct_digit_code(code : UInt16) -> Bool {
  code >= 48 && code <= 55
}

///|
fn is_bin_digit_code(code : UInt16) -> Bool {
  code == 48 || code == 49
}

///|
fn is_hex_digit_code(code : UInt16) -> Bool {
  is_dec_digit_code(code) ||
  (code >= 65 && code <= 70) ||
  (code >= 97 && code <= 102)
}

///|
fn digit_value(code : UInt16) -> Int? {
  if is_dec_digit_code(code) {
    Some(code.to_int() - 48)
  } else if code >= 65 && code <= 70 {
    Some(code.to_int() - 65 + 10)
  } else if code >= 97 && code <= 102 {
    Some(code.to_int() - 97 + 10)
  } else {
    None
  }
}
