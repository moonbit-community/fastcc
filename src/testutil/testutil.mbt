///|
/// Small helpers for tests that need filesystem paths or temporary dirs.
/// Keep this tiny and dependency-light so it can be reused across packages.
///|
pub fn project_root() -> String {
  match @env.current_dir() {
    Some(path) => path
    None => "."
  }
}

///|
pub fn join_path(dir : String, name : String) -> String {
  if dir == "" {
    name
  } else if dir.has_suffix("/") {
    dir + name
  } else {
    dir + "/" + name
  }
}

///|
pub fn ensure_dir(path : String) -> Unit raise {
  if @fs.path_exists(path) {
    return
  }
  @fs.create_dir(path)
}

///|
pub fn write_string(path : String, contents : String) -> Unit raise {
  @fs.write_string_to_file(path, contents)
}

