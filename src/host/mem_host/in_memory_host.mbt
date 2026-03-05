///|
struct InMemoryHost {
  files : Map[String, Bytes]
}

///|
pub impl @host.Host for InMemoryHost with path_exists(self, path) {
  self.files.contains(path)
}

///|
pub impl @host.Host for InMemoryHost with read_file_to_bytes(self, path) {
  match self.files.get(path) {
    None => fail("File not found in InMemoryHost: " + path)
    Some(bytes) => bytes
  }
}

///|
pub impl @host.Host for InMemoryHost with read_file_to_string(self, path) {
  match self.files.get(path) {
    None => fail("File not found in InMemoryHost: " + path)
    Some(bytes) => @encoding/utf8.decode(bytes, ignore_bom=true)
  }
}

///|
pub impl @host.Host for InMemoryHost with write_bytes_to_file(self, path, bytes) {
  self.files[path] = bytes
}

///|
pub impl @host.Host for InMemoryHost with remove_file(self, path) raise {
  if !self.files.contains(path) {
    fail("File not found in InMemoryHost: " + path)
  }
  self.files.remove(path)
}

///|
pub fn new() -> InMemoryHost {
  InMemoryHost::{ files: {} }
}
