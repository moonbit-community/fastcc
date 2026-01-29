///|
pub(all) struct StringInterner {
  buckets : Array[Int]
  next_by_id : Array[Int]
  strings : Array[String]
  views : Array[StringView]
  hashes : Array[UInt]
}

///|
let tok_hash_size : Int = 65536

///|
let tok_hash_mask : UInt = 65535

///|
pub let tok_hash_init : UInt = 1

///|
pub fn tok_hash_step(h : UInt, code : UInt16) -> UInt {
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

pub fn new_string_interner_with_capacity(capacity? : Int) -> StringInterner {
  match capacity {
    None => {
      buckets: Array::make(tok_hash_size, 0),
      next_by_id: [],
      strings: [],
      views: [],
      hashes: [],
    }
    Some(value) => {
      let cap = if value > 0 { value } else { 0 }
      {
        buckets: Array::make(tok_hash_size, 0),
        next_by_id: Array::new(capacity=cap),
        strings: Array::new(capacity=cap),
        views: Array::new(capacity=cap),
        hashes: Array::new(capacity=cap),
      }
    }
  }
}

///|
pub fn StringInterner::intern_view_with_id(
  self : StringInterner,
  view : StringView,
) -> (String, Int) {
  let hash = tok_hash_view(view)
  self.intern_view_with_id_hash(view, hash)
}

///|
pub fn StringInterner::intern_view_with_id_hash(
  self : StringInterner,
  view : StringView,
  hash : UInt,
) -> (String, Int) {
  let bucket = (hash & tok_hash_mask).reinterpret_as_int()
  let len = view.length()
  let mut id = self.buckets[bucket]
  while id != 0 {
    let idx = id - 1
    if self.hashes[idx] == hash {
      let stored = self.strings[idx]
      if stored.length() == len && view == self.views[idx] {
        return (stored, id)
      }
    }
    id = self.next_by_id[idx]
  }
  let owned = view.to_string()
  let idx = self.strings.length()
  self.strings.push(owned)
  self.views.push(self.strings[idx].view())
  self.hashes.push(hash)
  self.next_by_id.push(self.buckets[bucket])
  let id = idx + 1
  self.buckets[bucket] = id
  let stored = self.strings[idx]
  (stored, id)
}

///|
pub fn StringInterner::intern_view(self : StringInterner, view : StringView) -> String {
  let (value, _) = self.intern_view_with_id(view)
  value
}

///|
pub fn StringInterner::get(self : StringInterner, id : Int) -> String {
  let len = self.strings.length()
  if id <= 0 || id > len {
    return ""
  }
  self.strings[id - 1]
}

///|
