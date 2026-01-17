///|
struct StringInterner {
  map : Map[String, String]
}

///|
fn new_string_interner() -> StringInterner {
  { map: Map::new() }
}

///|
fn StringInterner::intern_view(self : StringInterner, view : StringView) -> String {
  match self.map.get_from_string(view) {
    Some(existing) => existing
    None => {
      let owned = view.to_string()
      self.map.set(owned, owned)
      owned
    }
  }
}

///|
