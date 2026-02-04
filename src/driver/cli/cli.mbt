// Copyright (C) 2026 International Digital Economy Academy
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License as published by the Free Software Foundation; version 2.1
// of the License.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public
// License along with this library.  If not, see <https://www.gnu.org/licenses/>.

///|
pub struct CliConfig {
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
pub(all) enum CliMacroAction {
  Define(name~ : String, value~ : String?)
  Undef(name~ : String)
} derive(Show, Eq, ToJson)

///|
pub(all) enum CliParse {
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
      let name = @util.slice_string(spec, 0, i)
      let value = @util.slice_string(spec, i + 1, len)
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
    args.push(@util.slice_string(contents, start, i))
  }
  args
}

///|
fn expand_cli_args(host : &@host.Host, args : Array[String]) -> Array[String]? {
  let expanded : Array[String] = []
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg.has_prefix("@") && arg.length() > 1 {
      let path = @util.slice_string(arg, 1, arg.length())
      let contents = host.read_file_to_string(path) catch {
        err => {
          println(
            "error: failed to read argument file '\{path}': \{err.to_string()}",
          )
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
pub fn parse_cli_args(host~ : &@host.Host, args : Array[String]) -> CliParse {
  let expanded = match expand_cli_args(host, args) {
    None => return Error
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
        return Error
      }
      inputs.push(arg)
      run_input = true
      i = i + 1
      continue
    }
    if arg == "-h" || arg == "--help" {
      print_usage()
      return Help
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
        return Error
      }
      output = Some(expanded[i + 1])
      i = i + 2
      continue
    }
    if arg.has_prefix("-o") && arg.length() > 2 {
      output = Some(@util.slice_string(arg, 2, arg.length()))
      i = i + 1
      continue
    }
    if arg == "-I" {
      if i + 1 >= expanded.length() {
        println("error: missing argument for -I")
        print_usage()
        return Error
      }
      include_paths.push(expanded[i + 1])
      i = i + 2
      continue
    }
    if arg.has_prefix("-I") && arg.length() > 2 {
      include_paths.push(@util.slice_string(arg, 2, arg.length()))
      i = i + 1
      continue
    }
    if arg == "-D" {
      if i + 1 >= expanded.length() {
        println("error: missing argument for -D")
        print_usage()
        return Error
      }
      match split_define_spec(expanded[i + 1]) {
        None => {
          println("error: empty macro name in -D")
          print_usage()
          return Error
        }
        Some((name, value)) =>
          if name == "" {
            println("error: empty macro name in -D")
            print_usage()
            return Error
          } else {
            macro_actions.push(Define(name~, value~))
          }
      }
      i = i + 2
      continue
    }
    if arg.has_prefix("-D") && arg.length() > 2 {
      match split_define_spec(@util.slice_string(arg, 2, arg.length())) {
        None => {
          println("error: empty macro name in -D")
          print_usage()
          return Error
        }
        Some((name, value)) =>
          if name == "" {
            println("error: empty macro name in -D")
            print_usage()
            return Error
          } else {
            macro_actions.push(Define(name~, value~))
          }
      }
      i = i + 1
      continue
    }
    if arg == "-U" {
      if i + 1 >= expanded.length() {
        println("error: missing argument for -U")
        print_usage()
        return Error
      }
      let name = expanded[i + 1]
      if name == "" {
        println("error: empty macro name in -U")
        print_usage()
        return Error
      }
      macro_actions.push(Undef(name~))
      i = i + 2
      continue
    }
    if arg.has_prefix("-U") && arg.length() > 2 {
      let name = @util.slice_string(arg, 2, arg.length())
      if name == "" {
        println("error: empty macro name in -U")
        print_usage()
        return Error
      }
      macro_actions.push(Undef(name~))
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
        return Error
      }
      include_paths.push(expanded[i + 1])
      i = i + 2
      continue
    }
    if arg.has_prefix("-isystem") && arg.length() > 8 {
      include_paths.push(@util.slice_string(arg, 8, arg.length()))
      i = i + 1
      continue
    }
    if arg == "-L" {
      if i + 1 >= expanded.length() {
        println("error: missing argument for -L")
        print_usage()
        return Error
      }
      link_paths.push(expanded[i + 1])
      i = i + 2
      continue
    }
    if arg.has_prefix("-L") && arg.length() > 2 {
      link_paths.push(@util.slice_string(arg, 2, arg.length()))
      i = i + 1
      continue
    }
    if arg == "-l" {
      if i + 1 >= expanded.length() {
        println("error: missing argument for -l")
        print_usage()
        return Error
      }
      link_libs.push(expanded[i + 1])
      i = i + 2
      continue
    }
    if arg.has_prefix("-l") && arg.length() > 2 {
      link_libs.push(@util.slice_string(arg, 2, arg.length()))
      i = i + 1
      continue
    }
    if arg.has_prefix("-") {
      println("error: unsupported option '\{arg}'")
      print_usage()
      return Error
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
    return Error
  }
  if run && !run_input {
    println("error: -run requires an input file")
    return Error
  }
  if inputs.length() == 0 {
    println("error: no input files")
    print_usage()
    return Error
  }
  if output is Some(_) && inputs.length() != 1 {
    println("error: -o requires exactly one input file")
    return Error
  }
  Run({
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
