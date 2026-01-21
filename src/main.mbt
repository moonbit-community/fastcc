///|
struct CliConfig {
  include_paths : Array[String]
  link_paths : Array[String]
  link_libs : Array[String]
  link_inputs : Array[String]
  inputs : Array[String]
  output : String?
  compile_only : Bool
  run : Bool
  run_args : Array[String]
  bench : Bool
  macro_actions : Array[CliMacroAction]
}

///|
enum CliMacroAction {
  Define(name~ : String, value~ : String?)
  Undef(name~ : String)
} derive(Show, Eq, ToJson)

///|
enum CliParse {
  Run(CliConfig)
  Help
  Error
}

///|
fn print_usage() -> Unit {
  println(
    "usage: tinycc.mbt [-c] [-run] [-bench] [-o OUT] [-I PATH]... [-isystem PATH]... [-L PATH]... [-l LIB]... [-D NAME[=VALUE]]... [-U NAME]... FILE...",
  )
}

///|
fn split_define_spec(spec : String) -> (String, String?)? {
  if spec == "" {
    return None
  }
  let len = spec.length()
  let mut i = 0
  while i < len {
    if spec[i] == 61 {
      let name = slice_string(spec, 0, i)
      let value = slice_string(spec, i + 1, len)
      return Some((name, Some(value)))
    }
    i = i + 1
  }
  Some((spec, None))
}

///|
fn is_cli_whitespace(code : Int) -> Bool {
  code == 32 || code == 9 || code == 10 || code == 13
}

///|
fn split_listfile_args(contents : String) -> Array[String] {
  let args : Array[String] = []
  let len = contents.length()
  let mut i = 0
  while i < len {
    while i < len && is_cli_whitespace(contents.code_unit_at(i).to_int()) {
      i = i + 1
    }
    if i >= len {
      break
    }
    let start = i
    while i < len && !is_cli_whitespace(contents.code_unit_at(i).to_int()) {
      i = i + 1
    }
    args.push(slice_string(contents, start, i))
  }
  args
}

///|
fn expand_cli_args(args : Array[String]) -> Array[String]? {
  let expanded : Array[String] = []
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg.has_prefix("@") && arg.length() > 1 {
      let path = slice_string(arg, 1, arg.length())
      let contents = try @fs.read_file_to_string(path) catch {
        err => {
          println("error: failed to read argument file '\{path}': \{err.to_string()}")
          return None
        }
      }
      for item in split_listfile_args(contents) {
        expanded.push(item)
      }
    } else {
      expanded.push(arg)
    }
    i = i + 1
  }
  Some(expanded)
}

///|
fn is_c_source_path(path : String) -> Bool {
  path.has_suffix(".c") || path.has_suffix(".i")
}

///|
fn parse_cli_args(
  args : Array[String],
) -> CliParse {
  let expanded = match expand_cli_args(args) {
    None => return CliParse::Error
    Some(v) => v
  }
  let include_paths : Array[String] = []
  let link_paths : Array[String] = []
  let link_libs : Array[String] = []
  let link_inputs : Array[String] = []
  let inputs : Array[String] = []
  let run_args : Array[String] = []
  let macro_actions : Array[CliMacroAction] = []
  let mut output : String? = None
  let mut compile_only = false
  let mut run = false
  let mut bench = false

  let mut i = 1
  let mut run_input = false
  while i < expanded.length() {
    let arg = expanded[i]
    if run && run_input {
      run_args.push(arg)
      i = i + 1
      continue
    }
    if run && !run_input {
      if arg == "--" {
        i = i + 1
        while i < expanded.length() {
          run_args.push(expanded[i])
          i = i + 1
        }
        break
      }
      if arg.has_prefix("-") && arg != "-" {
        println("error: unsupported option after -run '\{arg}'")
        return CliParse::Error
      }
      inputs.push(arg)
      run_input = true
      i = i + 1
      continue
    }
    if arg == "-h" || arg == "--help" {
      print_usage()
      return CliParse::Help
    }
    if arg == "-c" {
      compile_only = true
      i = i + 1
      continue
    }
    if arg == "-run" {
      run = true
      i = i + 1
      continue
    }
    if arg == "-bench" {
      bench = true
      i = i + 1
      continue
    }
    if arg == "-o" {
      if i + 1 >= expanded.length() {
        println("error: missing argument for -o")
        print_usage()
        return CliParse::Error
      }
      output = Some(expanded[i + 1])
      i = i + 2
      continue
    }
    if arg.has_prefix("-o") && arg.length() > 2 {
      output = Some(slice_string(arg, 2, arg.length()))
      i = i + 1
      continue
    }
    if arg == "-I" {
      if i + 1 >= expanded.length() {
        println("error: missing argument for -I")
        print_usage()
        return CliParse::Error
      }
      include_paths.push(expanded[i + 1])
      i = i + 2
      continue
    }
    if arg.has_prefix("-I") && arg.length() > 2 {
      include_paths.push(slice_string(arg, 2, arg.length()))
      i = i + 1
      continue
    }
    if arg == "-D" {
      if i + 1 >= expanded.length() {
        println("error: missing argument for -D")
        print_usage()
        return CliParse::Error
      }
      match split_define_spec(expanded[i + 1]) {
        None => {
          println("error: empty macro name in -D")
          print_usage()
          return CliParse::Error
        }
        Some((name, value)) =>
          if name == "" {
            println("error: empty macro name in -D")
            print_usage()
            return CliParse::Error
          } else {
            macro_actions.push(CliMacroAction::Define(name~, value~))
          }
      }
      i = i + 2
      continue
    }
    if arg.has_prefix("-D") && arg.length() > 2 {
      match split_define_spec(slice_string(arg, 2, arg.length())) {
        None => {
          println("error: empty macro name in -D")
          print_usage()
          return CliParse::Error
        }
        Some((name, value)) =>
          if name == "" {
            println("error: empty macro name in -D")
            print_usage()
            return CliParse::Error
          } else {
            macro_actions.push(CliMacroAction::Define(name~, value~))
          }
      }
      i = i + 1
      continue
    }
    if arg == "-U" {
      if i + 1 >= expanded.length() {
        println("error: missing argument for -U")
        print_usage()
        return CliParse::Error
      }
      let name = expanded[i + 1]
      if name == "" {
        println("error: empty macro name in -U")
        print_usage()
        return CliParse::Error
      }
      macro_actions.push(CliMacroAction::Undef(name=name))
      i = i + 2
      continue
    }
    if arg.has_prefix("-U") && arg.length() > 2 {
      let name = slice_string(arg, 2, arg.length())
      if name == "" {
        println("error: empty macro name in -U")
        print_usage()
        return CliParse::Error
      }
      macro_actions.push(CliMacroAction::Undef(name~))
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
    if arg == "-fPIC" || arg == "-fpic" {
      i = i + 1
      continue
    }
    if arg.has_prefix("-Z") {
      i = i + 1
      continue
    }
    if arg.has_prefix("-Q") {
      i = i + 1
      continue
    }
    if arg == "-isystem" {
      if i + 1 >= expanded.length() {
        println("error: missing argument for -isystem")
        print_usage()
        return CliParse::Error
      }
      include_paths.push(expanded[i + 1])
      i = i + 2
      continue
    }
    if arg.has_prefix("-isystem") && arg.length() > 8 {
      include_paths.push(slice_string(arg, 8, arg.length()))
      i = i + 1
      continue
    }
    if arg == "-L" {
      if i + 1 >= expanded.length() {
        println("error: missing argument for -L")
        print_usage()
        return CliParse::Error
      }
      link_paths.push(expanded[i + 1])
      i = i + 2
      continue
    }
    if arg.has_prefix("-L") && arg.length() > 2 {
      link_paths.push(slice_string(arg, 2, arg.length()))
      i = i + 1
      continue
    }
    if arg == "-l" {
      if i + 1 >= expanded.length() {
        println("error: missing argument for -l")
        print_usage()
        return CliParse::Error
      }
      link_libs.push(expanded[i + 1])
      i = i + 2
      continue
    }
    if arg.has_prefix("-l") && arg.length() > 2 {
      link_libs.push(slice_string(arg, 2, arg.length()))
      i = i + 1
      continue
    }
    if arg.has_prefix("-") {
      println("error: unsupported option '\{arg}'")
      print_usage()
      return CliParse::Error
    }
    if is_c_source_path(arg) {
      inputs.push(arg)
    } else {
      link_inputs.push(arg)
    }
    i = i + 1
  }

  if run && compile_only {
    println("error: -run cannot be combined with -c")
    return CliParse::Error
  }
  if run && !run_input {
    println("error: -run requires an input file")
    return CliParse::Error
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
  CliParse::Run({
    include_paths,
    link_paths,
    link_libs,
    link_inputs,
    inputs,
    output,
    compile_only,
    run,
    run_args,
    bench,
    macro_actions,
  })
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
fn lex_cli_macro_tokens(pp : Preprocessor, value : String) -> Array[Token] {
  if value == "" {
    return []
  }
  let file = add_file(pp.map, "<cmdline>", value)
  let lex = new_lexer(file, pp.diags, pp.interner, pp.keyword_ids)
  let tokens : Array[Token] = []
  while true {
    let tok = next_token(lex)
    if tok.kind == Eof {
      break
    }
    tokens.push(tok)
  }
  normalize_macro_tokens(tokens)
}

///|
fn apply_cli_macros(pp : Preprocessor, actions : Array[CliMacroAction]) -> Unit {
  for action in actions {
    match action {
      CliMacroAction::Define(name~, value~) =>
        match value {
          None => define_int_macro(pp, name, 1)
          Some(v) => define_macro(pp, name, lex_cli_macro_tokens(pp, v))
        }
      CliMacroAction::Undef(name~) =>
        remove_macro(pp, macro_id_from_name(pp, name))
    }
  }
}

///|
#borrow(cmd)
extern "C" fn run_command(cmd : Bytes) -> Int = "tinyccmbt_run_command"

///|
fn write_shell_quoted_arg(buf : @buffer.Buffer, arg : String) -> Unit {
  buf.write_byte((39 : Byte))
  for b in @encoding/utf8.encode(arg) {
    if b == (39 : Byte) {
      buf.write_byte((39 : Byte))
      buf.write_byte((92 : Byte))
      buf.write_byte((39 : Byte))
      buf.write_byte((39 : Byte))
    } else {
      buf.write_byte(b)
    }
  }
  buf.write_byte((39 : Byte))
}

///|
fn build_shell_command_bytes(args : Array[String]) -> Bytes {
  let buf = @buffer.new(size_hint=args.length() * 16)
  let mut i = 0
  while i < args.length() {
    if i > 0 {
      buf.write_byte((32 : Byte))
    }
    write_shell_quoted_arg(buf, args[i])
    i = i + 1
  }
  buf.write_byte((0 : Byte))
  buf.to_bytes()
}

///|
fn run_shell_command(args : Array[String]) -> Int {
  run_command(build_shell_command_bytes(args))
}

///|
fn temp_dir() -> String {
  match @sys.get_env_var("TMPDIR") {
    Some(v) => v
    None => "/tmp"
  }
}

///|
fn join_temp_path(dir : String, name : String) -> String {
  if dir == "" {
    name
  } else if dir.has_suffix("/") {
    dir + name
  } else {
    dir + "/" + name
  }
}

///|
fn run_temp_base() -> String {
  let stamp = bench_now_ns()
  join_temp_path(temp_dir(), "tinycc.mbt.run.\{stamp}")
}

///|
fn compile_to_object_path(
  cfg : CliConfig,
  input_path : String,
  output_path : String,
  bench_stats : BenchStats?,
) -> Bool {
  match load_input(input_path) {
    None => false
    Some((path, text)) => {
      let bag = new_diag_bag()
      let map = new_source_map()
      let file = add_file(map, path, text)
      let pp = new_preprocessor(map, file, bag)
      add_include_path(pp, "compat/include")
      for p in cfg.include_paths {
        add_include_path(pp, p)
      }
      apply_cli_macros(pp, cfg.macro_actions)
      let mut parse_ns = 0UL
      let mut sem_ns = 0UL
      let mut codegen_ns = 0UL
      let mut total_ns = 0UL
      let mut sem_ctx : SemContext? = None
      let bench_enabled = cfg.bench
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
              Some(bytes) =>
                @fs.write_bytes_to_file(output_path, bytes) catch {
                  err => add_error(bag, dummy_loc(0), err.to_string())
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
        match bench_stats {
          None => ()
          Some(stats) => bench_stats_add(stats, parse_ns, sem_ns, codegen_ns, total_ns)
        }
        println(bench_file_line(path, parse_ns, sem_ns, codegen_ns, total_ns))
      }
      if has_errors(bag) {
        for d in bag.diags {
          println(format_diag_for_cli(pp.map, d))
        }
        false
      } else {
        true
      }
    }
  }
}

///|
fn build_clang_link_args(
  obj_path : String,
  exe_path : String,
  cfg : CliConfig,
) -> Array[String] {
  let args : Array[String] = []
  args.push("clang")
  args.push("-w")
  args.push(obj_path)
  args.push("-o")
  args.push(exe_path)
  for input in cfg.link_inputs {
    args.push(input)
  }
  for path in cfg.link_paths {
    args.push("-L" + path)
  }
  for lib in cfg.link_libs {
    args.push("-l" + lib)
  }
  args
}

///|
fn main {
  touch_unused_symbols()
  match parse_cli_args(@env.args()) {
    CliParse::Help => ()
    CliParse::Error => @sys.exit(1)
    CliParse::Run(cfg) => {
      if cfg.run {
        if cfg.output is Some(_) {
          println("error: -o is not supported with -run")
          @sys.exit(1)
        }
        if cfg.inputs.length() != 1 {
          println("error: -run requires exactly one input file")
          @sys.exit(1)
        }
        let base = run_temp_base()
        let obj_path = base + ".o"
        let exe_path = base + ".out"
        if !compile_to_object_path(cfg, cfg.inputs[0], obj_path, None) {
          @sys.exit(1)
        }
        let link_status = run_shell_command(build_clang_link_args(obj_path, exe_path, cfg))
        if link_status != 0 {
          println("error: clang link failed")
          @sys.exit(1)
        }
        let run_args : Array[String] = []
        run_args.push(exe_path)
        for arg in cfg.run_args {
          run_args.push(arg)
        }
        let run_status = run_shell_command(run_args)
        @fs.remove_file(obj_path) catch {
          _ => ()
        }
        @fs.remove_file(exe_path) catch {
          _ => ()
        }
        if run_status != 0 {
          @sys.exit(run_status)
        }
      } else {
        let mut any_errors = false
        let bench_enabled = cfg.bench
        let bench_stats = bench_stats_new()
        for input_path in cfg.inputs {
          if !cfg.compile_only {
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
                add_include_path(pp, "compat/include")
                for p in cfg.include_paths {
                  add_include_path(pp, p)
                }
                apply_cli_macros(pp, cfg.macro_actions)
                let toks = dump_tokens(pp, 32)
                for t in toks {
                  println(t.lexeme)
                }
                if has_errors(bag) {
                  any_errors = true
                  for d in bag.diags {
                    println(format_diag_for_cli(pp.map, d))
                  }
                }
              }
            }
          } else {
            let out_path = match cfg.output {
              None => default_output_path(input_path)
              Some(v) => v
            }
            if !compile_to_object_path(cfg, input_path, out_path, Some(bench_stats)) {
              any_errors = true
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
}
