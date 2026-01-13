///|
fn parse_cli_args(
  args : Array[String],
) -> (Array[String], String?, String?, Bool) {
  let include_paths : Array[String] = []
  let mut input : String? = None
  let mut output : String? = None
  let mut compile_only = false
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if arg == "-I" {
      if i + 1 < args.length() {
        include_paths.push(args[i + 1])
        i = i + 2
        continue
      }
      i = i + 1
      continue
    }
    if arg.has_prefix("-I") && arg.length() > 2 {
      include_paths.push(slice_string(arg, 2, arg.length()))
      i = i + 1
      continue
    }
    if arg == "-c" {
      compile_only = true
      i = i + 1
      continue
    }
    if arg == "-o" {
      if i + 1 < args.length() {
        output = Some(args[i + 1])
        i = i + 2
        continue
      }
      i = i + 1
      continue
    }
    if !arg.has_prefix("-") && input is None {
      input = Some(arg)
      i = i + 1
      continue
    }
    i = i + 1
  }
  (include_paths, input, output, compile_only)
}

///|
fn load_input(path : String?) -> (String, String)? {
  match path {
    None => Some(("<stdin>", "int main(){return 0;}"))
    Some(p) =>
      try @fs.read_file_to_string(p) catch {
        err => {
          println("failed to read input: \{err.to_string()}")
          None
        }
      } noraise {
        text => Some((p, text))
      }
  }
}

///|
fn main {
  let (include_paths, input, output, compile_only) = parse_cli_args(@env.args())
  match load_input(input) {
    None => ()
    Some((path, text)) => {
      let bag = new_diag_bag()
      let map = new_source_map()
      let file = add_file(map, path, text)
      let pp = new_preprocessor(file, bag)
      for p in include_paths {
        add_include_path(pp, p)
      }
      if !compile_only {
        let toks = dump_tokens(pp, 32)
        for t in toks {
          println(t.lexeme)
        }
      } else {
        let unit = parse_translation_unit(pp)
        if !has_errors(bag) {
          check_translation_unit(unit, bag)
        }
        if !has_errors(bag) {
          match codegen_arm64_object_bytes(unit, bag) {
            None => ()
            Some(bytes) => {
              let out_path = match output {
                None => "a.o"
                Some(v) => v
              }
              @fs.write_bytes_to_file(out_path, bytes) catch {
                err => add_error(bag, dummy_loc(0), err.to_string())
              }
            }
          }
        }
      }
      if has_errors(bag) {
        let d = bag.diags[0]
        println(format_diag(d))
      }
    }
  }
}
