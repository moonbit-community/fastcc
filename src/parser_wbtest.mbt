///|
fn parse_text(text : String) -> (@ast.TranslationUnit, @diag.DiagBag) {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<test>", text)
  let pp = new_preprocessor(map, file, bag)
  let unit = parse_translation_unit(pp)
  (unit, bag)
}

///|
fn check_text(text : String) -> (@ast.TranslationUnit, @diag.DiagBag) {
  let (unit, bag) = parse_text(text)
  check_translation_unit(unit, bag) |> ignore
  (unit, bag)
}

///|
fn check_text_with_paths(
  text : String,
  paths : Array[String],
) -> (@ast.TranslationUnit, @diag.DiagBag) {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(map, "<test>", text)
  let pp = new_preprocessor(map, file, bag)
  for path in paths {
    add_include_path(pp, path)
  }
  let unit = parse_translation_unit(pp)
  check_translation_unit(unit, bag) |> ignore
  (unit, bag)
}

///|
fn struct_size_align_from_text(
  text : String,
  name : String,
) -> (Int, Int) raise {
  let (unit, bag) = parse_text(text)
  assert_true(!@diag.has_errors(bag))
  let sem_bag = @diag.new_diag_bag()
  let ctx = new_sem_context(sem_bag)
  for decl in unit.decls {
    check_decl(ctx, decl)
  }
  assert_true(!@diag.has_errors(sem_bag))
  let ty = @ast.CType::Struct(name~, id=0, fields=None, attrs=@ast.empty_attrs())
  match type_size_align(ctx, ty, @source.dummy_loc(0)) {
    Some((size, align)) => (size, align)
    None => fail("expected struct size")
  }
}

///|
fn collect_ident_ids_expr(
  expr : @ast.Expr,
  name : String,
  out : Array[Int],
) -> Unit {
  match expr {
    @ast.Expr::Ident(name=ident_name, id~, ..) =>
      if ident_name == name {
        out.push(id)
      }
    @ast.Expr::LabelAddr(..)
    | @ast.Expr::IntLit(..)
    | @ast.Expr::FloatLit(..)
    | @ast.Expr::CharLit(..)
    | @ast.Expr::StringLit(..)
    | @ast.Expr::BuiltinTypesCompatibleP(..)
    | @ast.Expr::BuiltinOffsetof(..)
    | @ast.Expr::SizeofType(..)
    | @ast.Expr::AlignofType(..) => ()
    @ast.Expr::BuiltinVaArg(list~, ..) =>
      collect_ident_ids_expr(list, name, out)
    @ast.Expr::Unary(expr=inner, ..)
    | @ast.Expr::Cast(expr=inner, ..)
    | @ast.Expr::SizeofExpr(expr=inner, ..)
    | @ast.Expr::AlignofExpr(expr=inner, ..) =>
      collect_ident_ids_expr(inner, name, out)
    @ast.Expr::CompoundLiteral(init~, ..) =>
      collect_ident_ids_init(init, name, out)
    @ast.Expr::StmtExpr(stmts~, ..) =>
      for stmt in stmts {
        match stmt {
          @ast.Stmt::ExprStmt(expr=inner, ..)
          | @ast.Stmt::Return(value=Some(inner), ..) =>
            collect_ident_ids_expr(inner, name, out)
          _ => ()
        }
      }
    @ast.Expr::Binary(left~, right~, ..) => {
      collect_ident_ids_expr(left, name, out)
      collect_ident_ids_expr(right, name, out)
    }
    @ast.Expr::Conditional(cond~, then_expr~, else_expr~, ..) => {
      collect_ident_ids_expr(cond, name, out)
      collect_ident_ids_expr(then_expr, name, out)
      collect_ident_ids_expr(else_expr, name, out)
    }
    @ast.Expr::Call(callee~, args~, ..) => {
      collect_ident_ids_expr(callee, name, out)
      for arg in args {
        collect_ident_ids_expr(arg, name, out)
      }
    }
    @ast.Expr::Index(base~, index~, ..) => {
      collect_ident_ids_expr(base, name, out)
      collect_ident_ids_expr(index, name, out)
    }
    @ast.Expr::Member(base~, ..) =>
      collect_ident_ids_expr(base, name, out)
  }
}

///|
fn collect_ident_ids_init(
  init : @ast.Initializer,
  name : String,
  out : Array[Int],
) -> Unit {
  match init {
    @ast.Initializer::Expr(expr=inner, ..) =>
      collect_ident_ids_expr(inner, name, out)
    @ast.Initializer::List(items~, ..) =>
      for item in items {
        collect_ident_ids_init(item.value, name, out)
      }
  }
}

///|
test "parse function with return" {
  let (unit, bag) = parse_text("int main(){return 1;}")
  assert_true(!@diag.has_errors(bag))
  guard unit.decls.length() == 1 else { fail("expected single declaration") }
  match unit.decls[0] {
    @ast.Decl::FuncDef(func) => assert_eq(func.name, "main")
    _ => fail("expected function definition")
  }
}

///|
test "sem accepts local declarations" {
  let (_, bag) = check_text("int main(){int x = 1; return x;}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts static local arrays used in sizeof macro" {
  let text =
    "#define ArraySize(x) (sizeof(x)/sizeof((x)[0]))\n" +
    "typedef struct { int x; } Foo;\n" +
    "int f(void){\n" +
    "  static Foo aTable[] = { {1}, {2} };\n" +
    "  return ArraySize(aTable) + aTable[0].x;\n" +
    "}\n"
  let (unit, bag) = parse_text(text)
  assert_true(!@diag.has_errors(bag))
  guard unit.decls.length() == 2 else { fail("expected two declarations") }
  match unit.decls[1] {
    @ast.Decl::FuncDef(func) =>
      match func.body {
        @ast.Stmt::Compound(stmts~, ..) => {
          guard stmts.length() >= 2 else { fail("expected decl and return") }
          let decl = match stmts[0] {
            @ast.Stmt::DeclStmt(decls~, ..) => {
              guard decls.length() > 0 else { fail("expected static decl") }
              decls[0]
            }
            _ => fail("expected decl statement")
          }
          assert_eq(decl.name, "aTable")
          assert_eq(decl.storage, @ast.StorageClass::Static)
          assert_true(decl.id > 0)
          let ret_expr = match stmts[1] {
            @ast.Stmt::Return(value=Some(expr), ..) => expr
            _ => fail("expected return statement")
          }
          let ids : Array[Int] = []
          collect_ident_ids_expr(ret_expr, "aTable", ids)
          assert_true(ids.length() > 0)
          for id in ids {
            assert_eq(id, decl.id)
          }
        }
        _ => fail("expected compound body")
      }
    _ => fail("expected function definition")
  }
  let (_, sem_bag) = check_text(text)
  assert_true(!@diag.has_errors(sem_bag))
}

///|
test "sem accepts compat header macros and declarations" {
  let text =
    "#include <stdint.h>\n" +
    "#include <math.h>\n" +
    "#include <string.h>\n" +
    "#include <stdlib.h>\n" +
    "#include <errno.h>\n" +
    "int f(const char *s, size_t n){\n" +
    "  int x = INT32_MIN;\n" +
    "  double y = INFINITY;\n" +
    "  void *p = memchr(s, 'a', n);\n" +
    "  void *q = alloca(16);\n" +
    "  return x < 0 && y > 0 && (p == 0 || p != 0) && q != 0 && ETIMEDOUT > 0;\n" +
    "}\n"
  let (_, bag) = check_text_with_paths(text, ["compat/include"])
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts pthread compat declarations" {
  let text =
    "#include <pthread.h>\n" +
    "void f(void){\n" +
    "  volatile pthread_t owner = 0;\n" +
    "  pthread_mutex_t *m = 0;\n" +
    "  owner = pthread_self();\n" +
    "  if (pthread_equal(owner, pthread_self())) { owner = 0; }\n" +
    "  pthread_mutex_trylock(m);\n" +
    "}\n"
  let (_, bag) = check_text_with_paths(text, ["compat/include"])
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts typeof in statement expression" {
  let (_, bag) = check_text(
    "int f(int *ptr){ __typeof__(ptr) x = ({ __typeof__(ptr) p = ptr; p; }); return x == ptr; }",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "parse typedef struct local decl" {
  let (unit, bag) = parse_text(
    "typedef struct { int x; } T; int main(){ T r; r.x = 1; return r.x; }",
  )
  assert_true(!@diag.has_errors(bag))
  assert_eq(unit.decls.length(), 2)
  guard unit.decls.length() >= 2 else { fail("expected two declarations") }
  match unit.decls[1] {
    @ast.Decl::FuncDef(func) =>
      match func.body {
        @ast.Stmt::Compound(stmts~, ..) => {
          let mut found = false
          for stmt in stmts {
            if stmt is @ast.Stmt::DeclStmt(..) {
              found = true
            }
          }
          assert_true(found)
          assert_eq(stmts.length(), 3)
        }
        _ => fail("expected compound body")
      }
    _ => fail("expected function definition")
  }
}

///|
test "parse __builtin_expect call" {
  let (unit, bag) = parse_text("int main(){return __builtin_expect(1, 0);}")
  assert_true(!@diag.has_errors(bag))
  match unit.decls[0] {
    @ast.Decl::FuncDef(func) =>
      match func.body {
        @ast.Stmt::Compound(stmts~, ..) =>
          match stmts[0] {
            @ast.Stmt::Return(value=Some(expr), ..) =>
              match expr {
                @ast.Expr::Call(callee=@ast.Expr::Ident(name~, ..), args~, ..) => {
                  assert_eq(name, "__builtin_expect")
                  assert_eq(args.length(), 2)
                }
                _ => fail("expected call expression")
              }
            _ => fail("expected return statement")
          }
        _ => fail("expected compound body")
      }
    _ => fail("expected function definition")
  }
}

///|
test "parse nested function pointer declarator" {
  let text =
    "void (*(*x)(void*, const char*))(void);\n" +
    "void *dlsym();\n" +
    "void (*(*y)(void*, const char*))(void) = (void(*(*)(void*, const char*))(void))dlsym;"
  let (_, bag) = parse_text(text)
  assert_true(!@diag.has_errors(bag))
}

///|
test "parse nested function pointer in struct field" {
  let text =
    "struct S {\n" +
    "  void (*(*x)(void*, const char*))(void);\n" +
    "};"
  let (_, bag) = parse_text(text)
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts nested function pointer field call" {
  let text =
    "struct S { void (*(*x)(int))(void); };\n" +
    "void g(struct S* s){ void (*fp)(void) = s->x(1); fp(); }\n"
  let (_, bag) = check_text(text)
  assert_true(!@diag.has_errors(bag))
}

///|
test "parser tracks typedef struct name" {
  let bag = @diag.new_diag_bag()
  let map = @source.new_source_map()
  let file = @source.add_file(
    map,
    "<test>",
    "typedef struct { int x; } T; int main(){ T r; return r.x; }",
  )
  let pp = new_preprocessor(map, file, bag)
  let parser = new_parser(pp)
  ignore(parse_translation_unit_with(parser))
  let (_, type_id) = parser.pp.interner.intern_view_with_id("T"[:])
  assert_true(get_typedef_count(parser, type_id) > 0)
}

///|
test "sem accepts typedef struct local decl" {
  let (_, bag) = check_text(
    "typedef struct { int x; } T; int main(){ T r; r.x = 1; return r.x; }",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts typedef struct local decl imaxdiv_t" {
  let (_, bag) = check_text(
    "typedef struct { int x; } imaxdiv_t; int main(){ imaxdiv_t r; r.x = 1; return r.x; }",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts __builtin_expect call" {
  let (_, bag) = check_text("int main(){return __builtin_expect(1, 0);}")
  assert_true(!@diag.has_errors(bag))
}


///|
test "sem rejects missing return value" {
  let (_, bag) = check_text("int main(){return;}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects undeclared identifier" {
  let (_, bag) = check_text("int main(){return x;}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem accepts implicit function call" {
  let (_, bag) = check_text("int main(){return foo(1);}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "parse control flow and logical ops" {
  let (_, bag) = check_text(
    "int main(){int x=0;if(1){x=1;}else{x=2;}while(1){break;}do{x=x+1;}while(x<1);for(int i=0;i<3;i=i+1){continue;}switch(x){case 1 ... 3: x=2; break; default: x=3;}label: goto label;return (1?2:3,4);}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "parse typedef and function pointer" {
  let (_, bag) = check_text(
    "typedef int myint; myint a[3]; int *fp(int); int (*pf)(int); int main(){return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "parse multiple declarators" {
  let (_, bag) = check_text(
    "int a, *b; int f(int), g(int); int main(){int x=1, y=2; return x + y;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "parse casts and sizeof" {
  let (_, bag) = check_text(
    "int main(){int x=0; x++; ++x; return sizeof x + sizeof(int) + (int)x;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts pointer ops" {
  let (_, bag) = check_text("int x; int *p; int main(){p = &x; return *p;}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts function pointer call" {
  let (_, bag) = check_text(
    "int f(int a){return a;} int (*pf)(int) = f; int main(){return pf(1);}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts prototype call with multiple args" {
  let (_, bag) = check_text(
    "int f(int a, int b){return a+b;} int main(){return f(1,2);}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts old-style function declaration" {
  let (_, bag) = check_text("int f(); int f(int); int main(){return f(1);}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts old-style call with extra args" {
  let (_, bag) = check_text("int f(); int main(){return f(1,2,3);}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts K&R function definition" {
  let (_, bag) = check_text(
    "int f(a,b) int a; char b; { return a + b; } int main(){return f(1,2);}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts K&R default int parameters" {
  let (_, bag) = check_text(
    "int f(a,b){return a + b;} int main(){return f(1,2);}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts builtin choose_expr without typechecking dead branch" {
  let (_, bag) = check_text(
    "int main(){return __builtin_choose_expr(1, 2, undeclared);}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "parse paren pointer declarator with attribute" {
  let (unit, bag) = parse_text(
    "int (__attribute__((unused)) *fp)(void);",
  )
  assert_true(!@diag.has_errors(bag))
  guard unit.decls.length() == 1 else { fail("expected one declaration") }
  match unit.decls[0] {
    @ast.Decl::Var(decl) => assert_eq(decl.name, "fp")
    _ => fail("expected variable declaration")
  }
}

///|
test "parse paren declarator without inner pointer" {
  let (unit, bag) = parse_text(
    "typedef int *(Func)(int);",
  )
  assert_true(!@diag.has_errors(bag))
  guard unit.decls.length() == 1 else { fail("expected one declaration") }
  match unit.decls[0] {
    @ast.Decl::Typedef(name="Func", ..) => ()
    _ => fail("expected typedef declaration")
  }
}

///|
test "sem accepts builtin types_compatible_p in _Static_assert" {
  let (_, bag) = check_text(
    "_Static_assert(__builtin_types_compatible_p(int, int) == 1, \"ok\"); _Static_assert(__builtin_types_compatible_p(int, char) == 0, \"ok\"); int main(){return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem treats plain char as unsigned" {
  let (_, bag) = check_text(
    "_Static_assert((char)-1 > 0, \"ok\"); int main(){return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts builtin va_arg with type argument" {
  let (_, bag) = check_text("int *p; int main(){return __builtin_va_arg(p, int);}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts builtin libc function signatures" {
  let (_, bag) = check_text(
    "char buf[8]; const char *s = \"abc\"; int main(){ char *p = __builtin_strcpy(buf, s); unsigned long n = __builtin_strlen(s); return __builtin_memcmp(p, s, n + 1); }",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem evaluates __builtin_offsetof for struct fields" {
  let (_, bag) = check_text(
    "struct S { char c; int x; }; _Static_assert(__builtin_offsetof(struct S, x) == 4, \"ok\"); int main(){return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem evaluates __builtin_offsetof for nested fields" {
  let (_, bag) = check_text(
    "struct A { int x; }; struct B { struct A a; int y; }; _Static_assert(__builtin_offsetof(struct B, a.x) == 0, \"ok\"); _Static_assert(__builtin_offsetof(struct B, y) == 4, \"ok\"); int main(){return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem evaluates __builtin_offsetof for union fields" {
  let (_, bag) = check_text(
    "union U { int x; char c; }; _Static_assert(__builtin_offsetof(union U, c) == 0, \"ok\"); int main(){return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects __builtin_offsetof on bitfields" {
  let (_, bag) = check_text(
    "struct S { int x:1; }; _Static_assert(__builtin_offsetof(struct S, x) == 0, \"ok\"); int main(){return 0;}",
  )
  assert_true(@diag.has_errors(bag))
}

///|
test "sem accepts __builtin_frame_address and __builtin_return_address" {
  let (_, bag) = check_text(
    "int main(){ return __builtin_frame_address(0) != 0 && __builtin_return_address(0) != 0; }",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects negative frame address level" {
  let (_, bag) = check_text("int main(){ return __builtin_frame_address(-1) != 0; }")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem accepts __atomic builtins" {
  let (_, bag) = check_text(
    "int x; int main(){ int v=1; int out=0; int expected=0; int desired=2; __atomic_store(&x, &v, 0); int r = __atomic_load(&x, &out, 0); int old = __atomic_exchange(&x, &desired, &out, 0); _Bool ok = __atomic_compare_exchange(&x, &expected, &desired, 0, 0, 0); int f = __atomic_fetch_add(&x, 1, 0); int g = __atomic_add_fetch(&x, 1, 0); return r + old + f + g + ok; }",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts _Atomic type qualifiers" {
  let (_, bag) = check_text(
    "typedef _Atomic(int) atomic_int; _Atomic int a; int _Atomic b; _Atomic(int *) p; int * _Atomic q; int main(){ return a + b + (p != 0) + (q != 0); }",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects __atomic_fetch_add on pointer target" {
  let (_, bag) = check_text("int *p; int main(){ return __atomic_fetch_add(&p, p, 0); }")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem accepts implicit int function definition" {
  let (_, bag) = check_text("f(){return 0;} int main(){return f();}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts implicit int global variable" {
  let (_, bag) = check_text("x; int main(){return x;}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects void parameter" {
  let (_, bag) = check_text("int f(void x);")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects void parameter in list" {
  let (_, bag) = check_text("int f(void, int);")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects static function at block scope" {
  let (_, bag) = check_text("int main(){ static int f(); return 0; }")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects non-constant case label" {
  let (_, bag) = check_text("int main(){int x=1; switch(x){case x: return 0;}}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects non-integer switch condition" {
  let (_, bag) = check_text("int main(){switch(1.0){case 1: return 0;}}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects duplicate case values" {
  let (_, bag) = check_text(
    "int main(){switch(1){case 1: return 0; case 1: return 1;}}",
  )
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects overlapping case ranges" {
  let (_, bag) = check_text(
    "int main(){switch(1){case 1 ... 3: return 0; case 2: return 1;}}",
  )
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects duplicate default" {
  let (_, bag) = check_text(
    "int main(){switch(1){default: return 0; default: return 1;}}",
  )
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects assignment to const" {
  let (_, bag) = check_text("const int x = 1; int main(){x = 2;}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects increment of const" {
  let (_, bag) = check_text("int main(){const int x = 1; x++;}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects assignment through const pointer" {
  let (_, bag) = check_text("int main(){const int *p; *p = 1;}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects assignment to const pointer" {
  let (_, bag) = check_text("int main(){int *const p = 0; p = 0;}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects assignment to const struct field" {
  let (_, bag) = check_text(
    "struct S { int x; }; int main(){const struct S s = {0}; s.x = 1;}",
  )
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects assignment through const struct pointer" {
  let (_, bag) = check_text(
    "struct S { int x; }; int main(){const struct S s = {0}; const struct S *p = &s; p->x = 1;}",
  )
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects incomplete struct object" {
  let (_, bag) = check_text("struct S; struct S s;")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem accepts extern incomplete struct" {
  let (_, bag) = check_text("struct S; extern struct S s;")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts extern incomplete array" {
  let (_, bag) = check_text("extern int a[];")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects array of incomplete element" {
  let (_, bag) = check_text("struct S; struct S a[1];")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects local incomplete array" {
  let (_, bag) = check_text("int main(){int a[];}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem accepts flexible array member last" {
  let (_, bag) = check_text("struct S { int n; int a[]; };")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects flexible array member not last" {
  let (_, bag) = check_text("struct S { int a[]; int n; };")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects flexible array member in union" {
  let (_, bag) = check_text("union U { int a[]; };")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects struct/union tag conflict" {
  let (_, bag) = check_text(
    "struct S { int a; }; union S { int b; }; int main(){return 0;}",
  )
  assert_true(@diag.has_errors(bag))
}

///|
test "sem accepts struct access" {
  let (_, bag) = check_text(
    "struct S { int x; int y; }; int main(){struct S s; s.x = 1; return s.y;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts arrow access" {
  let (_, bag) = check_text(
    "struct S { int x; }; int main(){struct S s; struct S *p = &s; p->x = 1; return p->x;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts enum constants" {
  let (_, bag) = check_text("enum E { A = 1, B }; int main(){return A + B;}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts enum constant expressions" {
  let (_, bag) = check_text(
    "enum { A = 1, B, C = A + 3, D }; int main(){return A + B + C + D;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts sizeof in enum constant" {
  let (_, bag) = check_text("enum { A = sizeof(int) }; int main(){return A;}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects sizeof incomplete enum" {
  let (_, bag) = check_text("enum E; int main(){return sizeof(enum E);}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem accepts array indexing" {
  let (_, bag) = check_text("int a[3]; int main(){return a[1];}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects enum assignment" {
  let (_, bag) = check_text("enum { A = 1 }; int main(){A = 2;}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects non-constant enum value" {
  let (_, bag) = check_text("int x; enum E { A = x }; int main(){return 0;}")
  assert_true(@diag.has_errors(bag))
}

///|
test "parse aggregate initializers" {
  let (_, bag) = check_text(
    "int a[2][2] = {{1,2},{3,4}}; struct S { int x; int y; }; struct S s = { .y = 2, .x = 1 }; int main(){return a[0][1] + s.x + s.y;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem infers array size from initializer" {
  let (_, bag) = check_text("int a[] = {1,2}; int main(){return sizeof(a);}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem infers array size with designator" {
  let (_, bag) = check_text(
    "int a[] = { [2] = 1 }; int main(){return sizeof(a);}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts sizeof in designator index" {
  let (_, bag) = check_text(
    "int a[] = { [sizeof(int)] = 1 }; int main(){return sizeof(a);}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts enum bitfield width" {
  let (_, bag) = check_text(
    "enum { W = 3 }; struct S { int a: W; }; int main(){return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts sizeof in bitfield width" {
  let (_, bag) = check_text(
    "struct S { int a: sizeof(int); }; int main(){return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects non-const designator index" {
  let (_, bag) = check_text(
    "int x; int a[2] = { [x] = 1 }; int main(){return 0;}",
  )
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects multiple union designators" {
  let (_, bag) = check_text(
    "union U { int a; int b; }; union U u = { .a = 1, .b = 2 };",
  )
  assert_true(@diag.has_errors(bag))
}

///|
test "parse bitfields and qualifiers" {
  let (_, bag) = check_text(
    "struct S { unsigned int a:3; int : 2; const int b; }; int main(){struct S s = { .b = 1 }; return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects non-integer bitfield" {
  let (_, bag) = check_text("struct S { float f:3; }; int main(){return 0;}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem rejects oversized bitfield" {
  let (_, bag) = check_text("struct S { int a: 33; }; int main(){return 0;}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem accepts typeof expression" {
  let (_, bag) = check_text("int x; typeof(x) y; int main(){y = 1; return y;}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts typeof type" {
  let (_, bag) = check_text("typedef int T; typeof(T) y; int main(){return y;}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts alignof in _Static_assert" {
  let (_, bag) = check_text(
    "_Static_assert(__alignof__(int) == 4, \"ok\"); _Static_assert(_Alignof(int) == 4, \"ok\"); int main(){return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem applies aligned attribute to typedef and var" {
  let (_, bag) = check_text(
    "typedef int T __attribute__((aligned(8))); int x __attribute__((aligned(8))); _Static_assert(__alignof__(T) == 8, \"ok\"); _Static_assert(__alignof__(x) == 8, \"ok\"); int main(){return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts _Static_assert" {
  let (_, bag) = check_text("_Static_assert(1, \"ok\"); int main(){return 0;}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects _Static_assert" {
  let (_, bag) = check_text("_Static_assert(0, \"no\"); int main(){return 0;}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem accepts _Static_assert without message" {
  let (_, bag) = check_text("_Static_assert(1); int main(){return 0;}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts _Static_assert in struct" {
  let (_, bag) = check_text(
    "struct S { _Static_assert(1, \"ok\"); int x; }; int main(){return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "parse asm label on declaration" {
  let (unit, bag) = parse_text("int f() __asm__(\"foo\");")
  assert_true(!@diag.has_errors(bag))
  guard unit.decls.length() == 1 else { fail("expected single declaration") }
  match unit.decls[0] {
    @ast.Decl::FuncDecl(func) => assert_eq(func.attrs.asm_label, Some("foo"))
    _ => fail("expected function declaration")
  }
}

///|
test "parse global asm block" {
  let (unit, bag) = parse_text("asm(\"nop\"); int main(){return 0;}")
  assert_true(!@diag.has_errors(bag))
  guard unit.decls.length() == 2 else { fail("expected two declarations") }
  match unit.decls[0] {
    @ast.Decl::Asm(_) => ()
    _ => fail("expected asm declaration")
  }
}

///|
test "sem accepts asm statement" {
  let (_, bag) = check_text("int main(){asm(\"nop\"); return 0;}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts asm operands" {
  let (_, bag) = check_text(
    "int main(){int x=0; int y=1; asm(\"\" : \"=r\"(x) : \"r\"(y) : \"cc\"); return x;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts __attribute__ on declarations" {
  let (_, bag) = check_text(
    "int * __attribute__((unused)) p; struct __attribute__((packed)) S { char c; int x; }; int main(){return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "attribute after label is accepted" {
  let (_, bag) = check_text(
    "int main(){label: __attribute__((unused)); return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "attribute in pointer declarator sets call conv" {
  let (unit, bag) = parse_text(
    "typedef int (* __attribute__((stdcall)) Fn)(void);",
  )
  assert_true(!@diag.has_errors(bag))
  guard unit.decls.length() == 1 else { fail("expected single declaration") }
  match unit.decls[0] {
    @ast.Decl::Typedef(name="Fn", ty~, ..) =>
      match ty {
        @ast.CType::Pointer(inner) =>
          match inner {
            @ast.CType::Function(call_conv=@ast.CallConv::Stdcall, ..) => ()
            _ => fail("expected function type")
          }
        _ => fail("expected pointer type")
      }
    _ => fail("expected typedef declaration")
  }
}

///|
test "attribute packed affects struct size" {
  let (size, align) = struct_size_align_from_text(
    "struct __attribute__((packed)) S { char c; int x; };", "S",
  )
  assert_eq(size, 5)
  assert_eq(align, 1)
}

///|
test "attribute aligned affects struct size" {
  let (size, align) = struct_size_align_from_text(
    "struct __attribute__((aligned(8))) S { char c; };", "S",
  )
  assert_eq(size, 8)
  assert_eq(align, 8)
}

///|
test "typedef aligned affects field size" {
  let (size, align) = struct_size_align_from_text(
    "typedef int __attribute__((aligned(8))) T; struct S { T x; };", "S",
  )
  assert_eq(size, 8)
  assert_eq(align, 8)
}

///|
test "field aligned affects struct size" {
  let (size, align) = struct_size_align_from_text(
    "struct S { char c; int x __attribute__((aligned(8))); };", "S",
  )
  assert_eq(size, 16)
  assert_eq(align, 8)
}

///|
test "field packed affects struct size" {
  let (size, align) = struct_size_align_from_text(
    "struct S { char c; int x __attribute__((packed)); };", "S",
  )
  assert_eq(size, 5)
  assert_eq(align, 1)
}

///|
test "attribute packed after struct affects size" {
  let (size, align) = struct_size_align_from_text(
    "struct S { char c; int x; } __attribute__((packed));", "S",
  )
  assert_eq(size, 5)
  assert_eq(align, 1)
}

///|
test "sem rejects call conv mismatch" {
  let (_, bag) = check_text("int __attribute__((stdcall)) f(); int f();")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem accepts cdecl as default" {
  let (_, bag) = check_text("int __attribute__((cdecl)) f(); int f();")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts regparm zero as default" {
  let (_, bag) = check_text("int __attribute__((regparm(0))) f(); int f();")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts storage classes" {
  let (_, bag) = check_text(
    "static int x; extern int y; int main(){register int r=1; return r + x;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects invalid global storage" {
  let (_, bag) = check_text("auto int x; int main(){return 0;}")
  assert_true(@diag.has_errors(bag))
  let (_, bag2) = check_text("register int y; int main(){return 0;}")
  assert_true(@diag.has_errors(bag2))
}

///|
test "sem rejects control flow outside context" {
  let (_, bag) = check_text("int main(){case 1: return 0;}")
  assert_true(@diag.has_errors(bag))
  let (_, bag2) = check_text("int main(){break;}")
  assert_true(@diag.has_errors(bag2))
  let (_, bag3) = check_text("int main(){continue;}")
  assert_true(@diag.has_errors(bag3))
  let (_, bag4) = check_text("int main(){goto missing;}")
  assert_true(@diag.has_errors(bag4))
}

///|
test "sem accepts computed goto" {
  let (_, bag) = check_text(
    "int main(){void *p = &&label; goto *p; label: return 0;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects computed goto non-pointer" {
  let (_, bag) = check_text("int main(){int x=0; goto *x;}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem accepts range designator initializer" {
  let (_, bag) = check_text("int a[4] = { [1 ... 2] = 7 };")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects empty range designator" {
  let (_, bag) = check_text("int a[4] = { [2 ... 1] = 7 };")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem accepts string and char literals" {
  let (_, bag) = check_text(
    "enum { A = 'a' }; int main(){char *p = \"hi\"; char s[] = \"hi\"; return s[0] + A;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts string initializer without terminator" {
  let (_, bag) = check_text("int main(){char s[2] = \"hi\"; return 0;}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects string initializer too long" {
  let (_, bag) = check_text("int main(){char s[1] = \"hi\"; return 0;}")
  assert_true(@diag.has_errors(bag))
}

///|
test "sem accepts sizeof on inferred array size" {
  let (_, bag) = check_text(
    "int f(){static const char *const debug[] = {\"a\", \"b\"}; return sizeof(debug)/sizeof(debug[0]);}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts compound assignments and floats" {
  let (_, bag) = check_text(
    "int main(){int x=0; x+=1; x<<=2; double f=1.0; f/=2.0; return x;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts integer suffixes" {
  let (_, bag) = check_text(
    "enum { A = sizeof(1L), B = sizeof(1LL), C = sizeof(1u) }; int main(){unsigned long x = 1UL; return A + B + C + x;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "parse abstract declarators in sizeof" {
  let (_, bag) = check_text(
    "int f(int); int main(){return sizeof(int (*)(int)) + sizeof(int[3]);}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts varargs call" {
  let (_, bag) = check_text("int f(int, ...); int main(){return f(1, 2, 3);}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts void pointer compatibility" {
  let (_, bag) = check_text(
    "int x; void *p; int *q; int main(){q = &x; p = q; q = p; return p == q;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "typedef scope does not leak" {
  let (_, bag) = check_text(
    "struct S { int x; }; int main(){typedef struct S T; { typedef int T; } T y; return y.x;}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts null pointer constants" {
  let (_, bag) = check_text("int *p; int main(){p = 0; return p == 0;}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts pointer conditional with null" {
  let (_, bag) = check_text("int *p; int main(){return (1 ? p : 0) == p;}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem adjusts array parameters to pointers" {
  let (_, bag) = check_text(
    "int f(int a[]); int main(){int b[2]; return f(b);}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem adjusts function parameters to pointers" {
  let (_, bag) = check_text(
    "int cb(int); int f(int g(int)); int main(){return f(cb);}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem accepts reversed array indexing" {
  let (_, bag) = check_text("int a[2]; int main(){return 1[a];}")
  assert_true(!@diag.has_errors(bag))
}

///|
test "parse _Float16 prototype" {
  let (_, bag) = check_text("extern _Float16 foo(_Float16);")
  if @diag.has_errors(bag) {
    for d in bag.diags {
      println("\{d.loc.line}:\{d.loc.col}: \{d.message}")
    }
  }
  assert_true(!@diag.has_errors(bag))
}

///|
test "int literal type selection by base" {
  let ty_decimal = int_literal_type("2147483648")
  assert_true(type_to_string(ty_decimal) == "long")
  let ty_hex = int_literal_type("0x80000000")
  assert_true(type_to_string(ty_hex) == "unsigned int")
  let ty_hex_big = int_literal_type("0x100000000")
  assert_true(type_to_string(ty_hex_big) == "long")
}

///|
test "sem allows compatible global redeclarations" {
  let (_, bag) = check_text(
    "extern int x; int x; int a[]; int a[3]; int main(){return x + a[0];}",
  )
  assert_true(!@diag.has_errors(bag))
}

///|
test "sem rejects incompatible global redeclarations" {
  let (_, bag) = check_text("int a[2]; int a[3];")
  assert_true(@diag.has_errors(bag))
}
