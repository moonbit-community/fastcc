///|
struct StringInterner {
  buckets : Array[Int]
  next_by_id : Array[Int]
  strings : Array[String]
}

///|
let tok_hash_size : Int = 16384

///|
let tok_hash_mask : UInt = 16383

///|
let tok_hash_init : UInt = 1

///|
fn tok_hash_step(h : UInt, code : UInt16) -> UInt {
  h + (h << 5) + (h >> 27) + code.to_uint()
}

///|
fn tok_hash_view(view : StringView) -> UInt {
  let len = view.length()
  let mut h : UInt = tok_hash_init
  for i in 0..<len {
    let code = view.code_unit_at(i)
    h = tok_hash_step(h, code)
  }
  h
}

fn new_string_interner_with_capacity(capacity? : Int) -> StringInterner {
  match capacity {
    None => {
      buckets: Array::make(tok_hash_size, 0),
      next_by_id: [],
      strings: [],
    }
    Some(value) => {
      let cap = if value > 0 { value } else { 0 }
      {
        buckets: Array::make(tok_hash_size, 0),
        next_by_id: Array::new(capacity=cap),
        strings: Array::new(capacity=cap),
      }
    }
  }
}

///|
fn StringInterner::intern_view_with_id(
  self : StringInterner,
  view : StringView,
) -> (String, Int) {
  let hash = tok_hash_view(view)
  self.intern_view_with_id_hash(view, hash)
}

///|
fn StringInterner::intern_view_with_id_hash(
  self : StringInterner,
  view : StringView,
  hash : UInt,
) -> (String, Int) {
  let bucket = (hash & tok_hash_mask).reinterpret_as_int()
  let len = view.length()
  let mut id = self.buckets[bucket]
  while id != 0 {
    let stored = self.strings[id - 1]
    if stored.length() == len && view == stored[:] {
      return (stored, id)
    }
    id = self.next_by_id[id - 1]
  }
  let owned = view.to_string()
  let id = self.strings.length() + 1
  self.strings.push(owned)
  self.next_by_id.push(self.buckets[bucket])
  self.buckets[bucket] = id
  let stored = self.strings[id - 1]
  (stored, id)
}

///|
fn StringInterner::intern_view(self : StringInterner, view : StringView) -> String {
  let (value, _) = self.intern_view_with_id(view)
  value
}

///|
