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

///|
/// Create a unique directory under `target/blackbox/` for tests that need to
/// write temporary files.
pub fn make_case_dir(prefix : String) -> String raise {
  let root = project_root()
  let base = join_path(root, "target/blackbox")
  ensure_dir(base)
  let stamp = @env.now().to_string()
  let mut attempt = 0
  while true {
    let suffix = if attempt == 0 { "" } else { "-" + attempt.to_string() }
    let dir = join_path(base, prefix + "-" + stamp + suffix)
    if !@fs.path_exists(dir) {
      @fs.create_dir(dir)
      return dir
    }
    attempt = attempt + 1
  }
  fail("unreachable")
}
