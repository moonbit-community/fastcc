///|
struct StringInterner {
  map : Map[String, Int]
  strings : Array[String]
}

///|
fn new_string_interner() -> StringInterner {
  { map: Map::new(), strings: [] }
}

///|
fn StringInterner::intern_view_with_id(
  self : StringInterner,
  view : StringView,
) -> (String, Int) {
  match self.map.get_from_string(view) {
    Some(id) => (self.strings[id - 1], id)
    None => {
      let owned = view.to_string()
      let id = self.strings.length() + 1
      self.strings.push(owned)
      let stored = self.strings[id - 1]
      self.map.set(stored, id)
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
