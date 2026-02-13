///|
/// Represents a file in the directory tree

///|
/// Recursively collects all text files from a directory
async fn collect_files_recursive(
  root_dir~ : @path.Path,
  curr_dir : @path.Path,
  files : Map[String, String],
) -> Unit {
  let entries = @fs.readdir(curr_dir.to_string())
  for entry in entries {
    if entry == "." || entry == ".." {
      continue
    }
    let path = curr_dir.join(entry)
    let kind = @fs.kind(path.to_string(), follow_symlink=true)
    match kind {
      Directory => collect_files_recursive(root_dir~, path, files)
      _ => {
        let bytes = @fs.read_file(path.to_string()).text()
        let rel_path = path.relative(base=root_dir)
        files[rel_path.to_string()] = bytes
      }
    }
  }
}

///|
struct CliOptions {
  mut dir_path : String
  mut output_file : String
}

///|
async fn main {
  let args = @env.args()

  let cli_options = CliOptions::{ dir_path: "", output_file: "" }
  loop args[:] {
    ["-o", output_file, ..] => cli_options.output_file = output_file
    [dir, .. args] => {
      cli_options.dir_path = dir
      continue args
    }
    [] => panic()
  }

  if cli_options.dir_path == "" || cli_options.output_file == "" {
    println("Usage: embed_headers <directory> -o <output_file>")
    return
  }

  let dir_path = @path.Path(cli_options.dir_path).resolve()
  let output_path = @path.Path(cli_options.output_file).resolve()
  let files = {}
  collect_files_recursive(root_dir=dir_path, dir_path, files)
  let buffer = StringBuilder::new()
  buffer.write_string("{\n")
  for path, content in files {
    buffer.write_string("  ")
    buffer.write_string(path.escape())
    buffer.write_string(": ")
    buffer.write_string(content.escape())
    buffer.write_string(",\n")
  }
  buffer.write_string("}")
  @fs.write_file(output_path.to_string(), "pub let headers : Map[String, String] = \{buffer.to_string()}\n", create=0o644)
}
