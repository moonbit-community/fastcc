///|
struct CliConfig {
  include_paths : Array[String]
  inputs : Array[String]
  output : String?
  compile_only : Bool
}

///|
enum CliParse {
  Run(CliConfig)
  Help
  Error
}

///|
fn print_usage() -> Unit {
  println("usage: tinycc.mbt [-c] [-o OUT] [-I PATH]... [-isystem PATH]... FILE...")
}

///|
fn parse_cli_args(
  args : Array[String],
) -> CliParse {
  let include_paths : Array[String] = []
  let inputs : Array[String] = []
  let mut output : String? = None
  let mut compile_only = false

  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if arg == "-h" || arg == "--help" {
      print_usage()
      return CliParse::Help
    }
    if arg == "-c" {
      compile_only = true
      i = i + 1
      continue
    }
    if arg == "-o" {
      if i + 1 >= args.length() {
        println("error: missing argument for -o")
        print_usage()
        return CliParse::Error
      }
      output = Some(args[i + 1])
      i = i + 2
      continue
    }
    if arg.has_prefix("-o") && arg.length() > 2 {
      output = Some(slice_string(arg, 2, arg.length()))
      i = i + 1
      continue
    }
    if arg == "-I" {
      if i + 1 >= args.length() {
        println("error: missing argument for -I")
        print_usage()
        return CliParse::Error
      }
      include_paths.push(args[i + 1])
      i = i + 2
      continue
    }
    if arg.has_prefix("-I") && arg.length() > 2 {
      include_paths.push(slice_string(arg, 2, arg.length()))
      i = i + 1
      continue
    }
    if arg == "-isystem" {
      if i + 1 >= args.length() {
        println("error: missing argument for -isystem")
        print_usage()
        return CliParse::Error
      }
      include_paths.push(args[i + 1])
      i = i + 2
      continue
    }
    if arg.has_prefix("-isystem") && arg.length() > 8 {
      include_paths.push(slice_string(arg, 8, arg.length()))
      i = i + 1
      continue
    }
    if arg.has_prefix("-") {
      println("error: unsupported option '\{arg}'")
      print_usage()
      return CliParse::Error
    }
    inputs.push(arg)
    i = i + 1
  }

  if inputs.length() == 0 {
    println("error: no input files")
    print_usage()
    return CliParse::Error
  }
  if output is Some(_) && inputs.length() != 1 {
    println("error: -o requires exactly one input file")
    return CliParse::Error
  }
  CliParse::Run({ include_paths, inputs, output, compile_only })
}

///|
fn load_input(path : String) -> (String, String)? {
  try @fs.read_file_to_string(path) catch {
    err => {
      println("failed to read input: \{err.to_string()}")
      None
    }
  } noraise {
    text => Some((path, text))
  }
}

///|
fn default_output_path(input_path : String) -> String {
  let slash = match input_path.rev_find("/") {
    None => -1
    Some(idx) => idx
  }
  match input_path.rev_find(".") {
    None => input_path + ".o"
    Some(dot) =>
      if dot > slash {
        slice_string(input_path, 0, dot) + ".o"
      } else {
        input_path + ".o"
      }
  }
}

///|
fn format_diag_for_cli(map : SourceMap, d : Diag) -> String {
  let loc = d.loc
  match map.files.get(loc.file_id) {
    None => d.message
    Some(file) => "\{file.path}:\{loc.line}:\{loc.col}: \{d.message}"
  }
}

///|
fn main {
  touch_unused_symbols()
  match parse_cli_args(@env.args()) {
    CliParse::Help => ()
    CliParse::Error => @sys.exit(1)
    CliParse::Run(cfg) => {
      let mut any_errors = false
      for input_path in cfg.inputs {
        match load_input(input_path) {
          None => {
            any_errors = true
            continue
          }
          Some((path, text)) => {
            let bag = new_diag_bag()
            let map = new_source_map()
            let file = add_file(map, path, text)
            let pp = new_preprocessor(map, file, bag)
            for p in cfg.include_paths {
              add_include_path(pp, p)
            }
            if !cfg.compile_only {
              let toks = dump_tokens(pp, 32)
              for t in toks {
                println(t.lexeme)
              }
            } else {
              let unit = parse_translation_unit(pp)
              if !has_errors(bag) {
                check_translation_unit(unit, bag) |> ignore
              }
              if !has_errors(bag) {
                match codegen_arm64_object_bytes(unit, bag) {
                  None => ()
                  Some(bytes) => {
                    let out_path = match cfg.output {
                      None => default_output_path(input_path)
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
              any_errors = true
              for d in bag.diags {
                println(format_diag_for_cli(pp.map, d))
              }
            }
          }
        }
      }
      if any_errors {
        @sys.exit(1)
      }
    }
  }
}
