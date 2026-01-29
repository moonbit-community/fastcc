///|
pub type CliConfig = @cli.CliConfig

///|
pub type CliMacroAction = @cli.CliMacroAction

///|
pub type CliParse = @cli.CliParse

///|
pub fn parse_cli_args(args : Array[String]) -> CliParse {
  @cli.parse_cli_args(args)
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
pub fn bench_now_ns() -> UInt64 {
  @ffi.bench_now_ns()
}

///|
pub fn run_args(args : Array[String]) -> Int {
  run_with_args(args)
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
        @util.slice_string(input_path, 0, dot) + ".o"
      } else {
        input_path + ".o"
      }
  }
}

///|
fn format_diag_for_cli(map : @source.SourceMap, d : @diag.Diag) -> String {
  let loc = d.loc
  match map.files.get(loc.file_id) {
    None => d.message
    Some(file) => "\{file.path}:\{loc.line}:\{loc.col}: \{d.message}"
  }
}

///|
fn lex_cli_macro_tokens(pp : @preproc.Preprocessor, value : String) -> Array[@tokens.Token] {
  if value == "" {
    return []
  }
  let file = @source.add_file(pp.map, "<cmdline>", value)
  let lex = @lexer.new_lexer(
    file,
    pp.diags,
    pp.interner,
    pp.keyword_ids,
    pp.lexeme_pool,
  )
  let tokens : Array[@tokens.Token] = []
  while true {
    let tok = @lexer.next_token(lex)
    if tok.kind == Eof {
      break
    }
    tokens.push(tok)
  }
  @preproc.normalize_macro_tokens(tokens)
}

///|
fn apply_cli_macros(pp : @preproc.Preprocessor, actions : Array[CliMacroAction]) -> Unit {
  for action in actions {
    match action {
      CliMacroAction::Define(name~, value~) =>
        match value {
          None => @preproc.define_int_macro(pp, name, 1)
          Some(v) => @preproc.define_macro(pp, name, lex_cli_macro_tokens(pp, v))
        }
      CliMacroAction::Undef(name~) =>
        @preproc.remove_macro(pp, @preproc.macro_id_from_name(pp, name))
    }
  }
}

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
  let len = args.length()
  let buf = @buffer.new(size_hint=len * 16)
  let mut i = 0
  while i < len {
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
  @ffi.run_command(build_shell_command_bytes(args))
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
  let stamp = @ffi.bench_now_ns()
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
      let bag = @diag.new_diag_bag()
      let map = @source.new_source_map()
      let file = @source.add_file(map, path, text)
      let pp = @preproc.new_preprocessor(map, file, bag)
      @preproc.add_include_path(pp, "compat/include")
      for p in cfg.include_paths {
        @preproc.add_include_path(pp, p)
      }
      apply_cli_macros(pp, cfg.macro_actions)
      let mut parse_ns = 0UL
      let mut sem_ns = 0UL
      let mut codegen_ns = 0UL
      let mut total_ns = 0UL
      let mut sem_ctx : @sem.SemContext? = None
      let bench_enabled = cfg.bench
      let total_start = if bench_enabled { @ffi.bench_now_ns() } else { 0UL }
      let parse_start = total_start
      let unit = @parser.parse_translation_unit(pp)
      @preproc.finalize_preprocessor(pp)
      if bench_enabled {
        let parse_end = @ffi.bench_now_ns()
        parse_ns = bench_delta_ns(parse_start, parse_end)
      }
      if !@diag.has_errors(bag) {
        if bench_enabled {
          let sem_start = @ffi.bench_now_ns()
          sem_ctx = Some(@sem.check_translation_unit(unit, bag))
          let sem_end = @ffi.bench_now_ns()
          sem_ns = bench_delta_ns(sem_start, sem_end)
        } else {
          sem_ctx = Some(@sem.check_translation_unit(unit, bag))
        }
      }
      if !@diag.has_errors(bag) {
        let codegen_start = if bench_enabled { @ffi.bench_now_ns() } else { 0UL }
        if sem_ctx is Some(ctx) {
          if @codegen.codegen_arm64_object_bytes_with_sem(unit, ctx, bag) is Some(bytes) {
            @fs.write_bytes_to_file(output_path, bytes) catch {
              err => @diag.add_error(bag, @source.dummy_loc(0), err.to_string())
            }
          }
        }
        if bench_enabled {
          let codegen_end = @ffi.bench_now_ns()
          codegen_ns = bench_delta_ns(codegen_start, codegen_end)
        }
      }
      if bench_enabled {
        let total_end = @ffi.bench_now_ns()
        total_ns = bench_delta_ns(total_start, total_end)
        if bench_stats is Some(stats) {
          bench_stats_add(stats, parse_ns, sem_ns, codegen_ns, total_ns)
        }
        println(bench_file_line(path, parse_ns, sem_ns, codegen_ns, total_ns))
      }
      if @diag.has_errors(bag) {
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
pub fn run_main() -> Unit {
  @sys.exit(run_with_args(@env.args()))
}

///|
fn run_with_args(args : Array[String]) -> Int {
  @codegen.touch_unused_symbols()
  match parse_cli_args(args) {
    CliParse::Help => 0
    CliParse::Error => 1
    CliParse::Run(cfg) => {
      if cfg.run {
        if cfg.output is Some(_) {
          println("error: -o is not supported with -run")
          return 1
        }
        if cfg.inputs.length() != 1 {
          println("error: -run requires exactly one input file")
          return 1
        }
        let base = run_temp_base()
        let obj_path = base + ".o"
        let exe_path = base + ".out"
        if !compile_to_object_path(cfg, cfg.inputs[0], obj_path, None) {
          return 1
        }
        let link_status = run_shell_command(build_clang_link_args(obj_path, exe_path, cfg))
        if link_status != 0 {
          println("error: clang link failed")
          return 1
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
          return run_status
        }
        0
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
                let bag = @diag.new_diag_bag()
                let map = @source.new_source_map()
                let file = @source.add_file(map, path, text)
                let pp = @preproc.new_preprocessor(map, file, bag)
                @preproc.add_include_path(pp, "compat/include")
                for p in cfg.include_paths {
                  @preproc.add_include_path(pp, p)
                }
                apply_cli_macros(pp, cfg.macro_actions)
                let toks = @preproc.dump_tokens(pp, 32)
                for t in toks {
                  println(@tokens.token_text_with(pp.interner, pp.lexeme_pool, t))
                }
                if @diag.has_errors(bag) {
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
          return 1
        }
        0
      }
    }
  }
}
