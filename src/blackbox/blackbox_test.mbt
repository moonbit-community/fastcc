///|
struct CCase {
  name : String
  source : String
  headers : Array[(String, String)]
  defines : Array[(String, Int)]
}

///|
fn read_string(path : String) -> String raise {
  @fs.read_file_to_string(path)
}

///|
fn shell_quote(arg : String) -> String {
  let sb = StringBuilder::new()
  sb.write_char('\'')
  for c in arg {
    if c == '\'' {
      sb.write_string("'\\''")
    } else {
      sb.write_char(c)
    }
  }
  sb.write_char('\'')
  sb.to_string()
}

///|
fn join_shell_args(args : Array[String]) -> String {
  let sb = StringBuilder::new()
  let len = args.length()
  let mut i = 0
  while i < len {
    if i > 0 {
      sb.write_char(' ')
    }
    sb.write_string(shell_quote(args[i]))
    i = i + 1
  }
  sb.to_string()
}

///|
fn command_bytes(cmd : String) -> Bytes {
  let bytes = @encoding/utf8.encode(cmd)
  let buf = @buffer.new(size_hint=bytes.length() + 1)
  buf.write_bytes(bytes)
  buf.write_byte((0 : Byte))
  buf.to_bytes()
}

///|
fn run_command(args : Array[String]) -> Int {
  @ffi.run_command(command_bytes(join_shell_args(args)))
}

///|
fn run_command_capture(args : Array[String], out_path : String) -> Int {
  let cmd = join_shell_args(args) + " > " + shell_quote(out_path) + " 2>&1"
  @ffi.run_command(command_bytes(cmd))
}

///|
fn compile_tinycc(
  c_path : String,
  obj_path : String,
  include_dirs : Array[String],
  defines : Array[(String, Int)],
) -> Bool raise {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let text = read_string(c_path)
  let file = @source.add_file(map, c_path, text)
  let pp = @preproc.new_preprocessor(map, file, bag)
  let root = @testutil.project_root()
  @preproc.add_include_path(pp, @testutil.join_path(root, "compat/include"))
  for dir in include_dirs {
    @preproc.add_include_path(pp, dir)
  }
  for item in defines {
    let (name, value) = item
    @preproc.define_int_macro(pp, name, value)
  }
  let unit = @parser.parse_translation_unit(pp)
  @preproc.finalize_preprocessor(pp)
  if @diag.has_errors(bag) {
    return false
  }
  let sem_ctx = @sem.check_translation_unit(unit, bag)
  if @diag.has_errors(bag) {
    return false
  }
  match @codegen.codegen_arm64_object_bytes_with_sem(unit, sem_ctx, bag) {
    None => false
    Some(bytes) => {
      @fs.write_bytes_to_file(obj_path, bytes)
      !@diag.has_errors(bag)
    }
  }
}

///|
fn compile_system(
  c_path : String,
  exe_path : String,
  include_dirs : Array[String],
  defines : Array[(String, Int)],
  libs : Array[String],
) -> Int {
  let args : Array[String] = []
  args.push("clang")
  args.push("-w")
  args.push("-std=c11")
  for dir in include_dirs {
    args.push("-I" + dir)
  }
  for item in defines {
    let (name, value) = item
    args.push("-D" + name + "=" + value.to_string())
  }
  args.push(c_path)
  args.push("-o")
  args.push(exe_path)
  for lib in libs {
    args.push("-l" + lib)
  }
  run_command(args)
}

///|
fn link_exe(obj_path : String, exe_path : String, libs : Array[String]) -> Int {
  let args : Array[String] = []
  args.push("clang")
  args.push("-w")
  args.push(obj_path)
  args.push("-o")
  args.push(exe_path)
  for lib in libs {
    args.push("-l" + lib)
  }
  run_command(args)
}

///|
fn run_case(case : CCase) -> Unit raise {
  let root = @testutil.project_root()
  let base_dir = @testutil.join_path(root, "target/blackbox")
  @testutil.ensure_dir(base_dir)
  let stamp = @ffi.bench_now_ns()
  let case_dir = @testutil.join_path(base_dir, case.name + "-" + stamp.to_string())
  @testutil.ensure_dir(case_dir)

  let include_dirs : Array[String] = []
  if case.headers.length() > 0 {
    include_dirs.push(case_dir)
  }

  for item in case.headers {
    let (name, contents) = item
    @testutil.write_string(@testutil.join_path(case_dir, name), contents)
  }

  let c_path = @testutil.join_path(case_dir, case.name + ".c")
  @testutil.write_string(c_path, case.source)

  let tiny_obj = @testutil.join_path(case_dir, "tiny.o")
  let tiny_exe = @testutil.join_path(case_dir, "tiny.out")
  let sys_exe = @testutil.join_path(case_dir, "sys.out")
  let tiny_out = @testutil.join_path(case_dir, "tiny.txt")
  let sys_out = @testutil.join_path(case_dir, "sys.txt")

  assert_true(compile_tinycc(c_path, tiny_obj, include_dirs, case.defines))
  assert_eq(link_exe(tiny_obj, tiny_exe, []), 0)

  let tiny_status = run_command_capture([tiny_exe], tiny_out)
  let sys_build_status = compile_system(c_path, sys_exe, include_dirs, case.defines, [])
  assert_eq(sys_build_status, 0)
  let sys_status = run_command_capture([sys_exe], sys_out)

  assert_eq(tiny_status, sys_status)
  assert_eq(read_string(tiny_out), read_string(sys_out))
}

///|
fn compile_failure(source : String) -> Unit raise {
  let root = @testutil.project_root()
  let base_dir = @testutil.join_path(root, "target/blackbox")
  @testutil.ensure_dir(base_dir)
  let stamp = @ffi.bench_now_ns()
  let case_dir = @testutil.join_path(base_dir, "fail-" + stamp.to_string())
  @testutil.ensure_dir(case_dir)

  let c_path = @testutil.join_path(case_dir, "fail.c")
  @testutil.write_string(c_path, source)

  let obj_path = @testutil.join_path(case_dir, "fail.o")
  let sys_exe = @testutil.join_path(case_dir, "fail.out")

  assert_true(!compile_tinycc(c_path, obj_path, [], []))
  let sys_status = compile_system(c_path, sys_exe, [], [], [])
  assert_true(sys_status != 0)
}

///|
test "blackbox compare outputs" {
  let cases : Array[CCase] = [
    {
      name: "arith_loop",
      source: (
        #|#include <stdio.h>
        #|int main() {
        #|  int sum = 0;
        #|  for (int i = 0; i < 6; i++) {
        #|    sum += i;
        #|  }
        #|  printf("sum=%d\n", sum);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "struct_union_bitfield",
      source: (
        #|#include <stdio.h>
        #|struct S { int a; unsigned b:4; unsigned c:4; };
        #|union U { int x; char bytes[4]; };
        #|int main() {
        #|  struct S s = { 7, 3, 12 };
        #|  union U u;
        #|  u.x = 0x41424344;
        #|  printf("%d %u %u %c\n", s.a, s.b, s.c, u.bytes[0]);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "enum_switch",
      source: (
        #|#include <stdio.h>
        #|enum E { A = 1, B = 3, C = 5 };
        #|int main() {
        #|  enum E e = B;
        #|  int v = 0;
        #|  switch (e) {
        #|    case A: v = 10; break;
        #|    case B: v = 20; break;
        #|    default: v = 30; break;
        #|  }
        #|  printf("v=%d\n", v);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "macros_paste_stringize",
      source: (
        #|#include <stdio.h>
        #|#define STR(x) #x
        #|#define CAT(a,b) a##b
        #|int main() {
        #|  int foobar = 11;
        #|  printf("%s %d\n", STR(hi), CAT(foo,bar));
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "macro_nested",
      source: (
        #|#include <stdio.h>
        #|#define WRAP(x) x
        #|struct P { int a; int b; };
        #|int main() {
        #|  struct P p = WRAP(((struct P){1, 2}));
        #|  int arr[3] = {4, 5, 6};
        #|  printf("%d %d\n", p.b, WRAP(arr[1]));
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "include_has_include",
      source: (
        #|#include <stdio.h>
        #|#if __has_include("bb_hdr.h")
        #|#include "bb_hdr.h"
        #|#else
        #|#define HDRVAL 0
        #|#endif
        #|int main() {
        #|  printf("hdr=%d\n", HDRVAL);
        #|  return 0;
        #|}
      ),
      headers: [
        ("bb_hdr.h", "#define HDRVAL 7\n"),
      ],
      defines: [],
    },
    {
      name: "compound_literal",
      source: (
        #|#include <stdio.h>
        #|struct P { int x; int y; };
        #|int main() {
        #|  struct P *p = (struct P[]){ {3, 4}, {5, 6} };
        #|  printf("%d %d\n", p[1].x, p[1].y);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "pointer_casts",
      source: (
        #|#include <stdio.h>
        #|int main() {
        #|  int x = 5;
        #|  int *p = &x;
        #|  int **pp = &p;
        #|  *p = 9;
        #|  printf("%d\n", **pp);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "float_ops",
      source: (
        #|#include <stdio.h>
        #|int main() {
        #|  float a = 1.25f;
        #|  double b = 2.5;
        #|  double c = a + b;
        #|  if (c > 3.0) c -= 0.5;
        #|  printf("%.2f\n", c);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "long_long_ops",
      source: (
        #|#include <stdio.h>
        #|int main() {
        #|  long long a = 1LL << 33;
        #|  unsigned long long b = (unsigned long long)a + 5ULL;
        #|  long long c = -9;
        #|  unsigned long long d = (unsigned long long)c;
        #|  printf("%lld %llu\n", a, b);
        #|  printf("%llu\n", d);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "unsigned_ops",
      source: (
        #|#include <stdio.h>
        #|int main() {
        #|  unsigned int u = 0xffffffffu;
        #|  unsigned int v = u >> 28;
        #|  unsigned int w = (u ^ 0x0f0f0f0fU) & 0x00ff00ffU;
        #|  printf("%u %u\n", v, w);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "compare_ops",
      source: (
        #|#include <stdio.h>
        #|int main() {
        #|  long long a = -9;
        #|  long long b = 12;
        #|  unsigned long long ua = 0xffffffffULL;
        #|  unsigned long long ub = ua + 2ULL;
        #|  double d1 = 1.5;
        #|  double d2 = 2.5;
        #|  float f1 = 3.0f;
        #|  float f2 = 2.0f;
        #|  int cmp1 = a < b;
        #|  int cmp2 = ua < ub;
        #|  int cmp3 = d1 < d2;
        #|  int cmp4 = f1 >= f2;
        #|  printf("%d %d %d %d\n", cmp1, cmp2, cmp3, cmp4);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "shift_immediates",
      source: (
        #|#include <stdio.h>
        #|int main() {
        #|  int x = 7;
        #|  int y = x << 0;
        #|  int z = x >> 0;
        #|  int a = x + 4095;
        #|  int b = x - 1;
        #|  int c = x ^ 0xffffffff;
        #|  printf("%d %d %d %d %d\n", y, z, a, b, c);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "builtin_file_line",
      source: (
        #|#include <stdio.h>
        #|int main() {
        #|  printf("%s:%d\n", __FILE__, __LINE__);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "predefined_macros",
      source: (
        #|#include <stdio.h>
        #|int main() {
        #|  printf("extra=%d\n", EXTRA);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [("EXTRA", 3)],
    },
    {
      name: "pp_if_literals",
      source: (
        #|#include <stdio.h>
        #|#if defined(EXTRA) && defined EXTRA && EXTRA == 3 && ('A' == 65) && ('\n' == 10) && ((1 << 3) == 8)
        #|int main() {
        #|  puts("pp");
        #|  return 0;
        #|}
        #|#else
        #|int main() {
        #|  puts("pp_bad");
        #|  return 1;
        #|}
        #|#endif
      ),
      headers: [],
      defines: [("EXTRA", 3)],
    },
    {
      name: "pp_if_ops",
      source: (
        #|#include <stdio.h>
        #|#define MACRO_INT 7
        #|#if defined(EXTRA) && defined EXTRA && EXTRA == 3 && MACRO_INT == 7 && \
        #|  ('A' == 65) && ('\t' == 9) && ('\101' == 65) && ('\x41' == 65) && \
        #|  (!0) && ((~0U & 3U) == 3U) && (+2 == 2) && (-1 < 0) && \
        #|  ((6 / 3) == 2) && ((7 % 3) == 1) && ((1 << 3) == 8) && ((8 >> 2) == 2) && \
        #|  ((3 < 4) && (4 <= 4) && (5 > 4) && (5 >= 5)) && \
        #|  ((3 == 3) && (3 != 4)) && ((1 & 3) == 1) && ((1 ^ 3) == 2) && ((1 | 2) == 3)
        #|int main() {
        #|  puts("pp_ops");
        #|  return 0;
        #|}
        #|#else
        #|int main() {
        #|  puts("pp_ops_bad");
        #|  return 1;
        #|}
        #|#endif
      ),
      headers: [],
      defines: [("EXTRA", 3)],
    },
    {
      name: "line_directive",
      source: (
        #|#include <stdio.h>
        #|#line 99 "virtual.c"
        #|int main() {
        #|  printf("%s:%d\n", __FILE__, __LINE__);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "static_local",
      source: (
        #|#include <stdio.h>
        #|int bump() {
        #|  static int x = 3;
        #|  return x++;
        #|}
        #|int main() {
        #|  printf("%d %d\n", bump(), bump());
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "redecl_qual_attr",
      source: (
        #|#include <stdio.h>
        #|const int g;
        #|const int g;
        #|__attribute__((aligned(16))) int h;
        #|__attribute__((aligned(16))) int h;
        #|int foo();
        #|int foo(int x);
        #|int foo(int x) { return x + 1; }
        #|int main() {
        #|  printf("%d\n", foo(1));
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "redecl_compat",
      source: (
        #|#include <stdio.h>
        #|int arr2[2];
        #|int arr2[2];
        #|int f(int);
        #|int f(int);
        #|int f(int x) { return x + arr2[0]; }
        #|int main() {
        #|  arr2[0] = 2;
        #|  printf("%d\n", f(3));
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "redecl_bool_float",
      source: (
        #|#include <stdio.h>
        #|extern _Bool b;
        #|_Bool b = 1;
        #|extern _Bool b;
        #|extern float f;
        #|float f = 1.5f;
        #|extern float f;
        #|extern double d;
        #|double d = 2.5;
        #|extern double d;
        #|int main() {
        #|  printf("%d %.1f %.1f\n", b ? 1 : 0, (double)f, d);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "tagdef_stmt",
      source: (
        #|#include <stdio.h>
        #|int main() {
        #|  struct Local;
        #|  struct Local { int x; };
        #|  struct Local v = { 7 };
        #|  printf("%d\n", v.x);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "typedefs_compat",
      source: (
        #|#include <stdio.h>
        #|typedef int T;
        #|typedef int T;
        #|int main() {
        #|  T x = 4;
        #|  printf("%d\n", x);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "array_and_func_compat",
      source: (
        #|#include <stdio.h>
        #|extern int arr4[2];
        #|int arr4[2] = {1, 2};
        #|extern int arr4[2];
        #|int foo_bar(int a, float b);
        #|int foo_bar(int a, float b) { return a + (int)b; }
        #|int main() {
        #|  printf("%d %d\n", arr4[1], foo_bar(3, 4.0f));
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "array_unsized_compat",
      source: (
        #|#include <stdio.h>
        #|extern int arr5[];
        #|int arr5[2] = {3, 4};
        #|extern int arr5[];
        #|int main() {
        #|  printf("%d\n", arr5[1]);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "designated_init",
      source: (
        #|#include <stdio.h>
        #|struct P { int x; int y; int z; };
        #|int main() {
        #|  struct P p = { .y = 4, .x = 1, .z = 2 };
        #|  printf("%d %d %d\n", p.x, p.y, p.z);
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
    {
      name: "varargs_sum",
      source: (
        #|#include <stdio.h>
        #|#include <stdarg.h>
        #|int sum(int n, ...) {
        #|  va_list ap;
        #|  va_start(ap, n);
        #|  int s = 0;
        #|  for (int i = 0; i < n; i++) {
        #|    s += va_arg(ap, int);
        #|  }
        #|  va_end(ap);
        #|  return s;
        #|}
        #|int main() {
        #|  printf("%d\n", sum(4, 1, 2, 3, 4));
        #|  return 0;
        #|}
      ),
      headers: [],
      defines: [],
    },
  ]

  for case in cases {
    run_case(case)
  }
}

///|
test "blackbox compile failures" {
  compile_failure((
    #|#include "missing_header.h"
    #|int main() { return 0; }
  ))
  compile_failure((
    #|#define F(x) x
    #|int main() { return F(1, 2); }
  ))
  compile_failure((
    #|#if
    #|int main() { return 0; }
    #|#endif
  ))
  compile_failure((
    #|#line
    #|int main() { return 0; }
  ))
  compile_failure((
    #|#if 123z
    #|int main() { return 0; }
    #|#endif
  ))
  compile_failure((
    #|#if 1/0
    #|int main() { return 0; }
    #|#endif
  ))
  compile_failure((
    #|#if 1%0
    #|int main() { return 0; }
    #|#endif
  ))
  compile_failure((
    #|#if '\x'
    #|int main() { return 0; }
    #|#endif
  ))
  compile_failure((
    #|#if defined()
    #|int main() { return 0; }
    #|#endif
  ))
  compile_failure((
    #|#if defined(FOO
    #|int main() { return 0; }
    #|#endif
  ))
  compile_failure((
    #|int main() {
    #|  default: return 0;
    #|}
  ))
  compile_failure((
    #|int main() {
    #|  case 1: return 0;
    #|}
  ))
  compile_failure((
    #|int main() {
    #|  int x = 3;
    #|  switch (x) {
    #|    case x: return 0;
    #|  }
    #|  return 1;
    #|}
  ))
  compile_failure((
    #|int main() {
    #|  switch (1) {
    #|    case 0: break;
    #|    case 0: break;
    #|  }
    #|  return 0;
    #|}
  ))
  compile_failure((
    #|int main() {
    #|  break;
    #|}
  ))
  compile_failure((
    #|int main() {
    #|  continue;
    #|}
  ))
  compile_failure((
    #|void f() {
    #|  return 1;
    #|}
    #|int main() {
    #|  f();
    #|  return 0;
    #|}
  ))
  compile_failure((
    #|int main() {
    #|  double x = 1.0;
    #|  switch (x) {
    #|    case 1: break;
    #|  }
    #|  return 0;
    #|}
  ))
  compile_failure((
    #|struct S { int a; };
    #|int main() {
    #|  struct S s = {1};
    #|  if (s) {
    #|    return 0;
    #|  }
    #|  return 1;
    #|}
  ))
  compile_failure((
    #|int main() {
    #|  goto L;
    #|  L: ;
    #|  L: ;
    #|  return 0;
    #|}
  ))
  compile_failure((
    #|int f(int);
    #|int f(double);
    #|int main() { return 0; }
  ))
  compile_failure((
    #|int g(int, ...);
    #|int g(int);
    #|int main() { return 0; }
  ))
  compile_failure((
    #|int arr[2];
    #|int arr[3];
    #|int main() { return 0; }
  ))
  compile_failure((
    #|int main() {
    #|  int x = 3;
    #|  switch (1) {
    #|    case 1 ... x: return 0;
    #|  }
    #|  return 1;
    #|}
  ))
  compile_failure((
    #|int main() {
    #|  switch (1) {
    #|    default: break;
    #|    default: break;
    #|  }
    #|  return 0;
    #|}
  ))
  compile_failure((
    #|int main() {
    #|  switch (1) {
    #|    case 5 ... 6: break;
    #|    case 1 ... 2: break;
    #|    case 1 ... 3: break;
    #|  }
    #|  return 0;
    #|}
  ))
  compile_failure((
    #|int main() {
    #|  goto *5;
    #|}
  ))
  compile_failure((
    #|int v;
    #|float v;
    #|int main() { return 0; }
  ))
  compile_failure((
    #|int arr4c[2];
    #|int arr4c[2];
    #|int arr4c[3];
    #|int main() { return 0; }
  ))
  compile_failure((
    #|int fn2(int a, int b);
    #|int fn2(int a);
    #|int main() { return 0; }
  ))
}

///|
test "driver run args" {
  let root = @testutil.project_root()
  let base_dir = @testutil.join_path(root, "target/blackbox")
  @testutil.ensure_dir(base_dir)
  let stamp = @ffi.bench_now_ns()
  let case_dir = @testutil.join_path(base_dir, "driver-" + stamp.to_string())
  @testutil.ensure_dir(case_dir)

  let run_path = @testutil.join_path(case_dir, "run.c")
  @testutil.write_string(run_path, "int main() { return 3; }\n")
  assert_eq(@driver.run_args(["tinycc", "-run", run_path]), 3)

  let obj_path = @testutil.join_path(case_dir, "run.o")
  let compile_status = @driver.run_args(["tinycc", "-c", run_path, "-o", obj_path])
  assert_eq(compile_status, 0)
  assert_true(try @fs.is_file(obj_path) catch { _ => false })
}
