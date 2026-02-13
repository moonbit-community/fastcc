///|
struct DefaultHost {}

///|
pub impl @host.Host for DefaultHost with include_dir(_self) {
  "/__FASTCC__/include"
}

///|
pub impl @host.Host for DefaultHost with path_exists(_self, path) {
  if path.has_prefix("/__FASTCC__/include/") {
    let rel_path = try! path["/__FASTCC__/include/".length():].to_string()
    match @include.headers.get(rel_path) {
      None => false
      Some(_) => true
    }
  } else {
    @fs.path_exists(path)
  }
}

///|
pub impl @host.Host for DefaultHost with read_file_to_string(_self, path) {
  if path.has_prefix("/__FASTCC__/include/") {
    let rel_path = try! path["/__FASTCC__/include/".length():].to_string()
    match @include.headers.get(rel_path) {
      None => fail("not found")
      Some(content) => content
    }
  } else {
    @fs.read_file_to_string(path)
  }
}

///|
pub impl @host.Host for DefaultHost with write_bytes_to_file(_self, path, bytes) {
  @fs.write_bytes_to_file(path, bytes)
}

///|
pub impl @host.Host for DefaultHost with remove_file(_self, path) raise {
  @fs.remove_file(path)
}

///|
pub fn new() -> DefaultHost {
  DefaultHost::{  }
}
