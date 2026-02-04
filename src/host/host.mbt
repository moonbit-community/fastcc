///|
pub(open) trait Host {
  path_exists(Self, path : String) -> Bool
  read_file_to_string(Self, path : String) -> String raise
  write_bytes_to_file(Self, path : String, bytes : Bytes) -> Unit raise
  remove_file(Self, path : String) -> Unit raise
}
