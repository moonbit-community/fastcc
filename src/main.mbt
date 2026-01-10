///|
fn parse_cli_args(args : Array[String]) -> (Array[String], String?) {
  let include_paths : Array[String] = []
  let mut input : String? = None
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
    if !arg.has_prefix("-") && input is None {
      input = Some(arg)
      i = i + 1
      continue
    }
    i = i + 1
  }
  (include_paths, input)
}

///|
fn load_input(path : String?) -> (String, String)? {
  match path {
    None => Some(("<stdin>", "int x = 1; return x;"))
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
  let (include_paths, input) = parse_cli_args(@env.args())
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
      let toks = dump_tokens(pp, 32)
      if has_errors(bag) {
        let d = bag.diags[0]
        println(format_diag(d))
      } else {
        for t in toks {
          println(t.lexeme)
        }
      }
    }
  }
}
