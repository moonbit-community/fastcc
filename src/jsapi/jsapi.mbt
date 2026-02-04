///|
pub fn run_args(host~ : &@host.Host, args : Array[String]) -> Int {
  @driver.run_args(host~, args)
}

///|
pub fn new_in_memory_host() -> &@host.Host {
  @mem_host.new() as &@host.Host
}

///|
pub fn host_write_string_to_file(
  host : &@host.Host,
  path : String,
  content : String,
) -> Unit {
  try! host.write_bytes_to_file(path, @encoding/utf8.encode(content))
}

///|
pub fn host_read_file(host : &@host.Host, path : String) -> Bytes {
  try! host.read_file_to_bytes(path)
}
