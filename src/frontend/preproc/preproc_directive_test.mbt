///|
fn run_pp_collect(
  source : String,
  include_dirs : Array[String],
) -> (@diag.DiagBag, Array[@tokens.TokenKind]) raise {
  let case_dir = @testutil.make_case_dir("pp-directive")
  let path = @testutil.join_path(case_dir, "input.c")
  @testutil.write_string(path, source)
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, path, source)
  let pp = @preproc.new_preprocessor(map, file, bag)
  for dir in include_dirs {
    @preproc.add_include_path(pp, dir)
  }
  let kinds : Array[@tokens.TokenKind] = []
  while true {
    let tok = @preproc.next_pp_token(pp)
    if tok.kind == @tokens.TokenKind::Eof {
      break
    }
    kinds.push(tok.kind)
  }
  @preproc.finalize_preprocessor(pp)
  (bag, kinds)
}

///|
test "preproc directive hash eof" {
  let (bag, _kinds) = run_pp_collect("#", [])
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc directive hash newline" {
  let (bag, kinds) = run_pp_collect("#\nint x;", [])
  assert_true(!@diag.has_errors(bag))
  assert_true(kinds.length() > 0)
  assert_eq(kinds[0], @tokens.TokenKind::KwInt)
}

///|
test "preproc directive missing names" {
  let source = (
    #|#define
    #|#define 1
    #|#undef
    #|#undef 1
  )
  let (bag, _kinds) = run_pp_collect(source, [])
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc directive stray else/elif/endif" {
  let source = (
    #|#elif 1
    #|#else
    #|#endif
  )
  let (bag, _kinds) = run_pp_collect(source, [])
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc directive error warning active" {
  let source = (
    #|#error fail
    #|#warning warn
  )
  let (bag, _kinds) = run_pp_collect(source, [])
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc directive error warning inactive" {
  let source = (
    #|#if 0
    #|#error fail
    #|#warning warn
    #|#endif
    #|int x;
  )
  let (bag, _kinds) = run_pp_collect(source, [])
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc directive inactive ifdef ifndef" {
  let source = (
    #|#if 0
    #|#ifdef FOO
    #|int a;
    #|#endif
    #|#ifndef BAR
    #|int b;
    #|#endif
    #|#endif
  )
  let (bag, _kinds) = run_pp_collect(source, [])
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc directive elif branches" {
  let source_taken = (
    #|#if 1
    #|#elif 1
    #|#endif
  )
  let (bag_taken, _kinds) = run_pp_collect(source_taken, [])
  assert_true(!@diag.has_errors(bag_taken))

  let source_eval = (
    #|#if 0
    #|#elif 1
    #|#endif
  )
  let (bag_eval, _kinds) = run_pp_collect(source_eval, [])
  assert_true(!@diag.has_errors(bag_eval))
}

///|
test "preproc directive line inactive" {
  let source = (
    #|#if 0
    #|#line 99 "ignored.c"
    #|#endif
    #|int x;
  )
  let (bag, _kinds) = run_pp_collect(source, [])
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc directive pragma" {
  let source = (
    #|#pragma once
    #|int x;
  )
  let (bag, _kinds) = run_pp_collect(source, [])
  assert_true(!@diag.has_errors(bag))
}

///|
test "preproc directive unknown" {
  let source = (
    #|#unknown abc
    #|int x;
  )
  let (bag, _kinds) = run_pp_collect(source, [])
  assert_true(@diag.has_errors(bag))
}

///|
test "preproc directive include_next" {
  let case_dir = @testutil.make_case_dir("pp-include-next")
  let inc1 = @testutil.join_path(case_dir, "inc1")
  let inc2 = @testutil.join_path(case_dir, "inc2")
  @testutil.ensure_dir(inc1)
  @testutil.ensure_dir(inc2)
  @testutil.write_string(@testutil.join_path(inc1, "inc.h"), "#define INC_VAL 1\n")
  @testutil.write_string(@testutil.join_path(inc2, "inc.h"), "#define INC_VAL 2\n")
  let source = (
    #|#include_next <inc.h>
    #|#if INC_VAL == 2
    #|int ok;
    #|#else
    #|#error wrong_include
    #|#endif
  )
  let (bag, _kinds) = run_pp_collect(source, [inc1, inc2])
  assert_true(!@diag.has_errors(bag))
}
