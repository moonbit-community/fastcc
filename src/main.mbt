///|
fn split_cli_args(args : Array[String]) -> (Array[String], Array[String]) {
  let include_paths : Array[String] = []
  let out : Array[String] = []
  let mut i = 1
  let mut saw_input = false
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
    if arg == "-o" {
      if i + 1 < args.length() {
        out.push("-o")
        out.push(args[i + 1])
        i = i + 2
        continue
      }
      i = i + 1
      continue
    }
    if arg.has_prefix("-o") && arg.length() > 2 {
      out.push("-o")
      out.push(slice_string(arg, 2, arg.length()))
      i = i + 1
      continue
    }
    if arg == "-c" {
      out.push("-c")
      i = i + 1
      continue
    }
    if arg == "-h" || arg == "--help" {
      out.push("--help")
      i = i + 1
      continue
    }
    if arg.has_prefix("-") {
      i = i + 1
      continue
    }
    if !saw_input {
      out.push(arg)
      saw_input = true
    }
    i = i + 1
  }
  (include_paths, out)
}

///|
fn parse_cli_args(
  args : Array[String],
) -> (Array[String], String?, String?, Bool)? {
  let (include_paths, cli_args) = split_cli_args(args)
  let parser = @clap.Parser::new(prog="tinycc.mbt", args={
    "compile_only": @clap.Arg::flag(short='c', help="Compile only (-c)"),
    "output": @clap.Arg::named(
      short='o',
      nargs=@clap.Nargs::AtMost(1),
      help="Output file (-o)",
    ),
    "input": @clap.Arg::positional(
      nargs=@clap.Nargs::AtMost(1),
      help="Input file",
    ),
  })
  let value = @clap.SimpleValue::new(parser.prog)
  let help_message = try parser.parse(value, cli_args) catch {
    err => {
      println(err.to_string())
      return None
    }
  } noraise {
    msg => msg
  }
  match help_message {
    Some(msg) => {
      println(msg)
      None
    }
    None => {
      let input : Array[String] = try
        @clap.SimpleValue::get_positional(value)
      catch {
        _ => []
      } noraise {
        v => v
      }
      let output : String? = try
        @clap.SimpleValue::get_option(value, "output")
      catch {
        _ => None
      } noraise {
        v => v
      }
      let compile_only = @clap.SimpleValue::get_flag(value, "compile_only").unwrap_or(
        false,
      )
      let input_path = match input.get(0) {
        None => None
        Some(v) => Some(v)
      }
      Some((include_paths, input_path, output, compile_only))
    }
  }
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
  match parse_cli_args(@env.args()) {
    None => ()
    Some((include_paths, input, output, compile_only)) =>
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
}
