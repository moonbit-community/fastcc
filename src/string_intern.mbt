///|
struct StringInterner {
  map : FastMap[StringView, Int]
  strings : Array[String]
}

fn new_string_interner_with_capacity(capacity? : Int) -> StringInterner {
  match capacity {
    None => { map: fast_map_new(), strings: [] }
    Some(value) => {
      let cap = if value > 0 { value } else { 0 }
      { map: fast_map_new(capacity=cap), strings: Array::new(capacity=cap) }
    }
  }
}

///|
fn StringInterner::intern_view_with_id(
  self : StringInterner,
  view : StringView,
) -> (String, Int) {
  match self.map.get(view) {
    Some(id) => (self.strings[id - 1], id)
    None => {
      let owned = view.to_string()
      let id = self.strings.length() + 1
      self.strings.push(owned)
      let stored = self.strings[id - 1]
      self.map.set(stored[:], id)
      (stored, id)
    }
  }
}

///|
fn StringInterner::intern_view(self : StringInterner, view : StringView) -> String {
  let (value, _) = self.intern_view_with_id(view)
  value
}

///|
