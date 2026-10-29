///|
pub(open) trait Host {
  fn include_dir(Self) -> String
  fn path_exists(Self, path : String) -> Bool
  fn read_file_to_string(Self, path : String) -> String raise
  fn write_bytes_to_file(Self, path : String, bytes : Bytes) -> Unit raise
  fn remove_file(Self, path : String) -> Unit raise
}
