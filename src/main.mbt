///|
struct CliConfig {
  include_paths : Array[String]
  inputs : Array[String]
  output : String?
  compile_only : Bool
  bench : Bool
}

///|
enum CliParse {
  Run(CliConfig)
  Help
  Error
}

///|
fn print_usage() -> Unit {
  println("usage: tinycc.mbt [-c] [-bench] [-o OUT] [-I PATH]... [-isystem PATH]... FILE...")
}

///|
fn parse_cli_args(
  args : Array[String],
) -> CliParse {
  let include_paths : Array[String] = []
  include_paths.push("compat/include")
  let inputs : Array[String] = []
  let mut output : String? = None
  let mut compile_only = false
  let mut bench = false

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
    if arg == "-bench" {
      bench = true
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
    if arg.has_prefix("-W") || arg.has_prefix("-w") {
      i = i + 1
      continue
    }
    if arg.has_prefix("-O") || arg.has_prefix("-g") {
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
  CliParse::Run({ include_paths, inputs, output, compile_only, bench })
}

///|
struct BenchStats {
  mut parse_ns : UInt64
  mut sem_ns : UInt64
  mut codegen_ns : UInt64
  mut total_ns : UInt64
  mut files : Int
}

///|
fn bench_stats_new() -> BenchStats {
  {
    parse_ns: 0UL,
    sem_ns: 0UL,
    codegen_ns: 0UL,
    total_ns: 0UL,
    files: 0,
  }
}

///|
fn bench_delta_ns(start_ns : UInt64, end_ns : UInt64) -> UInt64 {
  end_ns - start_ns
}

///|
fn bench_ms(delta_ns : UInt64) -> Int {
  (delta_ns / 1_000_000UL).to_int()
}

///|
fn bench_us(delta_ns : UInt64) -> Int {
  ((delta_ns + 999UL) / 1_000UL).to_int()
}

///|
fn bench_stats_add(
  stats : BenchStats,
  parse_ns : UInt64,
  sem_ns : UInt64,
  codegen_ns : UInt64,
  total_ns : UInt64,
) -> Unit {
  stats.parse_ns = stats.parse_ns + parse_ns
  stats.sem_ns = stats.sem_ns + sem_ns
  stats.codegen_ns = stats.codegen_ns + codegen_ns
  stats.total_ns = stats.total_ns + total_ns
  stats.files = stats.files + 1
}

///|
fn bench_file_line(
  path : String,
  parse_ns : UInt64,
  sem_ns : UInt64,
  codegen_ns : UInt64,
  total_ns : UInt64,
) -> String {
  let parse_ms = bench_ms(parse_ns)
  let sem_ms = bench_ms(sem_ns)
  let codegen_ms = bench_ms(codegen_ns)
  let total_ms = bench_ms(total_ns)
  let parse_us = bench_us(parse_ns)
  let sem_us = bench_us(sem_ns)
  let codegen_us = bench_us(codegen_ns)
  let total_us = bench_us(total_ns)
  "bench: file=\{path} parse_ms=\{parse_ms} sem_ms=\{sem_ms} codegen_ms=\{codegen_ms} total_ms=\{total_ms} parse_us=\{parse_us} sem_us=\{sem_us} codegen_us=\{codegen_us} total_us=\{total_us}"
}

///|
fn bench_summary_line(stats : BenchStats) -> String {
  let parse_ms = bench_ms(stats.parse_ns)
  let sem_ms = bench_ms(stats.sem_ns)
  let codegen_ms = bench_ms(stats.codegen_ns)
  let total_ms = bench_ms(stats.total_ns)
  let parse_us = bench_us(stats.parse_ns)
  let sem_us = bench_us(stats.sem_ns)
  let codegen_us = bench_us(stats.codegen_ns)
  let total_us = bench_us(stats.total_ns)
  "bench: files=\{stats.files} parse_ms=\{parse_ms} sem_ms=\{sem_ms} codegen_ms=\{codegen_ms} total_ms=\{total_ms} parse_us=\{parse_us} sem_us=\{sem_us} codegen_us=\{codegen_us} total_us=\{total_us}"
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
      let bench_enabled = cfg.bench
      let bench_stats = bench_stats_new()
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
              let mut parse_ns = 0UL
              let mut sem_ns = 0UL
              let mut codegen_ns = 0UL
              let mut total_ns = 0UL
              let mut sem_ctx : SemContext? = None
              let total_start = if bench_enabled { bench_now_ns() } else { 0UL }
              let parse_start = total_start
              let unit = parse_translation_unit(pp)
              if bench_enabled {
                let parse_end = bench_now_ns()
                parse_ns = bench_delta_ns(parse_start, parse_end)
              }
              if !has_errors(bag) {
                if bench_enabled {
                  let sem_start = bench_now_ns()
                  sem_ctx = Some(check_translation_unit(unit, bag))
                  let sem_end = bench_now_ns()
                  sem_ns = bench_delta_ns(sem_start, sem_end)
                } else {
                  sem_ctx = Some(check_translation_unit(unit, bag))
                }
              }
              if !has_errors(bag) {
                let codegen_start = if bench_enabled { bench_now_ns() } else { 0UL }
                match sem_ctx {
                  None => ()
                  Some(ctx) =>
                    match codegen_arm64_object_bytes_with_sem(unit, ctx, bag) {
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
                if bench_enabled {
                  let codegen_end = bench_now_ns()
                  codegen_ns = bench_delta_ns(codegen_start, codegen_end)
                }
              }
              if bench_enabled {
                let total_end = bench_now_ns()
                total_ns = bench_delta_ns(total_start, total_end)
                bench_stats_add(bench_stats, parse_ns, sem_ns, codegen_ns, total_ns)
                println(bench_file_line(path, parse_ns, sem_ns, codegen_ns, total_ns))
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
      if bench_enabled && cfg.compile_only {
        println(bench_summary_line(bench_stats))
      }
      if any_errors {
        @sys.exit(1)
      }
    }
  }
}
