///|
struct DefaultHost {}

///|
pub impl @host.Host for DefaultHost with path_exists(_self, path) {
  @fs.path_exists(path)
}

///|
pub impl @host.Host for DefaultHost with read_file_to_string(_self, path) {
  @fs.read_file_to_string(path)
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
