///|
fn parse_text(text : String) -> (TranslationUnit, DiagBag) {
  let bag = new_diag_bag()
  let map = new_source_map()
  let file = add_file(map, "<test>", text)
  let pp = new_preprocessor(file, bag)
  let unit = parse_translation_unit(pp)
  (unit, bag)
}

///|
fn check_text(text : String) -> (TranslationUnit, DiagBag) {
  let (unit, bag) = parse_text(text)
  check_translation_unit(unit, bag)
  (unit, bag)
}

///|
fn struct_size_align_from_text(
  text : String,
  name : String,
) -> (Int, Int) raise {
  let (unit, bag) = parse_text(text)
  assert_true(!has_errors(bag))
  let sem_bag = new_diag_bag()
  let ctx = new_sem_context(sem_bag)
  for decl in unit.decls {
    check_decl(ctx, decl)
  }
  assert_true(!has_errors(sem_bag))
  let ty = CType::Struct(name~, fields=None, attrs=empty_attrs())
  match type_size_align(ctx, ty, dummy_loc(0)) {
    Some((size, align)) => (size, align)
    None => fail("expected struct size")
  }
}

///|
test "parse function with return" {
  let (unit, bag) = parse_text("int main(){return 1;}")
  assert_true(!has_errors(bag))
  guard unit.decls.length() == 1 else { fail("expected single declaration") }
  match unit.decls[0] {
    Decl::FuncDef(func) => assert_eq(func.name, "main")
    _ => fail("expected function definition")
  }
}

///|
test "sem accepts local declarations" {
  let (_, bag) = check_text("int main(){int x = 1; return x;}")
  assert_true(!has_errors(bag))
}

///|
test "sem rejects missing return value" {
  let (_, bag) = check_text("int main(){return;}")
  assert_true(has_errors(bag))
}

///|
test "sem rejects undeclared identifier" {
  let (_, bag) = check_text("int main(){return x;}")
  assert_true(has_errors(bag))
}

///|
test "sem accepts implicit function call" {
  let (_, bag) = check_text("int main(){return foo(1);}")
  assert_true(!has_errors(bag))
}

///|
test "parse control flow and logical ops" {
  let (_, bag) = check_text(
    "int main(){int x=0;if(1){x=1;}else{x=2;}while(1){break;}do{x=x+1;}while(x<1);for(int i=0;i<3;i=i+1){continue;}switch(x){case 1 ... 3: x=2; break; default: x=3;}label: goto label;return (1?2:3,4);}",
  )
  assert_true(!has_errors(bag))
}

///|
test "parse typedef and function pointer" {
  let (_, bag) = check_text(
    "typedef int myint; myint a[3]; int *fp(int); int (*pf)(int); int main(){return 0;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "parse multiple declarators" {
  let (_, bag) = check_text(
    "int a, *b; int f(int), g(int); int main(){int x=1, y=2; return x + y;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "parse casts and sizeof" {
  let (_, bag) = check_text(
    "int main(){int x=0; x++; ++x; return sizeof x + sizeof(int) + (int)x;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts pointer ops" {
  let (_, bag) = check_text("int x; int *p; int main(){p = &x; return *p;}")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts function pointer call" {
  let (_, bag) = check_text(
    "int f(int a){return a;} int (*pf)(int) = f; int main(){return pf(1);}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts prototype call with multiple args" {
  let (_, bag) = check_text(
    "int f(int a, int b){return a+b;} int main(){return f(1,2);}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts old-style function declaration" {
  let (_, bag) = check_text("int f(); int f(int); int main(){return f(1);}")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts old-style call with extra args" {
  let (_, bag) = check_text("int f(); int main(){return f(1,2,3);}")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts K&R function definition" {
  let (_, bag) = check_text(
    "int f(a,b) int a; char b; { return a + b; } int main(){return f(1,2);}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts K&R default int parameters" {
  let (_, bag) = check_text(
    "int f(a,b){return a + b;} int main(){return f(1,2);}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts builtin choose_expr without typechecking dead branch" {
  let (_, bag) = check_text(
    "int main(){return __builtin_choose_expr(1, 2, undeclared);}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts builtin types_compatible_p in _Static_assert" {
  let (_, bag) = check_text(
    "_Static_assert(__builtin_types_compatible_p(int, int) == 1, \"ok\"); _Static_assert(__builtin_types_compatible_p(int, char) == 0, \"ok\"); int main(){return 0;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts builtin va_arg with type argument" {
  let (_, bag) = check_text("int *p; int main(){return __builtin_va_arg(p, int);}")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts implicit int function definition" {
  let (_, bag) = check_text("f(){return 0;} int main(){return f();}")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts implicit int global variable" {
  let (_, bag) = check_text("x; int main(){return x;}")
  assert_true(!has_errors(bag))
}

///|
test "sem rejects void parameter" {
  let (_, bag) = check_text("int f(void x);")
  assert_true(has_errors(bag))
}

///|
test "sem rejects void parameter in list" {
  let (_, bag) = check_text("int f(void, int);")
  assert_true(has_errors(bag))
}

///|
test "sem rejects static function at block scope" {
  let (_, bag) = check_text("int main(){ static int f(); return 0; }")
  assert_true(has_errors(bag))
}

///|
test "sem rejects non-constant case label" {
  let (_, bag) = check_text("int main(){int x=1; switch(x){case x: return 0;}}")
  assert_true(has_errors(bag))
}

///|
test "sem rejects non-integer switch condition" {
  let (_, bag) = check_text("int main(){switch(1.0){case 1: return 0;}}")
  assert_true(has_errors(bag))
}

///|
test "sem rejects duplicate case values" {
  let (_, bag) = check_text(
    "int main(){switch(1){case 1: return 0; case 1: return 1;}}",
  )
  assert_true(has_errors(bag))
}

///|
test "sem rejects overlapping case ranges" {
  let (_, bag) = check_text(
    "int main(){switch(1){case 1 ... 3: return 0; case 2: return 1;}}",
  )
  assert_true(has_errors(bag))
}

///|
test "sem rejects duplicate default" {
  let (_, bag) = check_text(
    "int main(){switch(1){default: return 0; default: return 1;}}",
  )
  assert_true(has_errors(bag))
}

///|
test "sem rejects assignment to const" {
  let (_, bag) = check_text("const int x = 1; int main(){x = 2;}")
  assert_true(has_errors(bag))
}

///|
test "sem rejects increment of const" {
  let (_, bag) = check_text("int main(){const int x = 1; x++;}")
  assert_true(has_errors(bag))
}

///|
test "sem rejects assignment through const pointer" {
  let (_, bag) = check_text("int main(){const int *p; *p = 1;}")
  assert_true(has_errors(bag))
}

///|
test "sem rejects assignment to const pointer" {
  let (_, bag) = check_text("int main(){int *const p = 0; p = 0;}")
  assert_true(has_errors(bag))
}

///|
test "sem rejects assignment to const struct field" {
  let (_, bag) = check_text(
    "struct S { int x; }; int main(){const struct S s = {0}; s.x = 1;}",
  )
  assert_true(has_errors(bag))
}

///|
test "sem rejects assignment through const struct pointer" {
  let (_, bag) = check_text(
    "struct S { int x; }; int main(){const struct S s = {0}; const struct S *p = &s; p->x = 1;}",
  )
  assert_true(has_errors(bag))
}

///|
test "sem rejects incomplete struct object" {
  let (_, bag) = check_text("struct S; struct S s;")
  assert_true(has_errors(bag))
}

///|
test "sem accepts extern incomplete struct" {
  let (_, bag) = check_text("struct S; extern struct S s;")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts extern incomplete array" {
  let (_, bag) = check_text("extern int a[];")
  assert_true(!has_errors(bag))
}

///|
test "sem rejects array of incomplete element" {
  let (_, bag) = check_text("struct S; struct S a[1];")
  assert_true(has_errors(bag))
}

///|
test "sem rejects local incomplete array" {
  let (_, bag) = check_text("int main(){int a[];}")
  assert_true(has_errors(bag))
}

///|
test "sem accepts flexible array member last" {
  let (_, bag) = check_text("struct S { int n; int a[]; };")
  assert_true(!has_errors(bag))
}

///|
test "sem rejects flexible array member not last" {
  let (_, bag) = check_text("struct S { int a[]; int n; };")
  assert_true(has_errors(bag))
}

///|
test "sem rejects flexible array member in union" {
  let (_, bag) = check_text("union U { int a[]; };")
  assert_true(has_errors(bag))
}

///|
test "sem rejects struct/union tag conflict" {
  let (_, bag) = check_text(
    "struct S { int a; }; union S { int b; }; int main(){return 0;}",
  )
  assert_true(has_errors(bag))
}

///|
test "sem accepts struct access" {
  let (_, bag) = check_text(
    "struct S { int x; int y; }; int main(){struct S s; s.x = 1; return s.y;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts arrow access" {
  let (_, bag) = check_text(
    "struct S { int x; }; int main(){struct S s; struct S *p = &s; p->x = 1; return p->x;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts enum constants" {
  let (_, bag) = check_text("enum E { A = 1, B }; int main(){return A + B;}")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts enum constant expressions" {
  let (_, bag) = check_text(
    "enum { A = 1, B, C = A + 3, D }; int main(){return A + B + C + D;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts sizeof in enum constant" {
  let (_, bag) = check_text("enum { A = sizeof(int) }; int main(){return A;}")
  assert_true(!has_errors(bag))
}

///|
test "sem rejects sizeof incomplete enum" {
  let (_, bag) = check_text("enum E; int main(){return sizeof(enum E);}")
  assert_true(has_errors(bag))
}

///|
test "sem accepts array indexing" {
  let (_, bag) = check_text("int a[3]; int main(){return a[1];}")
  assert_true(!has_errors(bag))
}

///|
test "sem rejects enum assignment" {
  let (_, bag) = check_text("enum { A = 1 }; int main(){A = 2;}")
  assert_true(has_errors(bag))
}

///|
test "sem rejects non-constant enum value" {
  let (_, bag) = check_text("int x; enum E { A = x }; int main(){return 0;}")
  assert_true(has_errors(bag))
}

///|
test "parse aggregate initializers" {
  let (_, bag) = check_text(
    "int a[2][2] = {{1,2},{3,4}}; struct S { int x; int y; }; struct S s = { .y = 2, .x = 1 }; int main(){return a[0][1] + s.x + s.y;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem infers array size from initializer" {
  let (_, bag) = check_text("int a[] = {1,2}; int main(){return sizeof(a);}")
  assert_true(!has_errors(bag))
}

///|
test "sem infers array size with designator" {
  let (_, bag) = check_text(
    "int a[] = { [2] = 1 }; int main(){return sizeof(a);}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts sizeof in designator index" {
  let (_, bag) = check_text(
    "int a[] = { [sizeof(int)] = 1 }; int main(){return sizeof(a);}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts enum bitfield width" {
  let (_, bag) = check_text(
    "enum { W = 3 }; struct S { int a: W; }; int main(){return 0;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts sizeof in bitfield width" {
  let (_, bag) = check_text(
    "struct S { int a: sizeof(int); }; int main(){return 0;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem rejects non-const designator index" {
  let (_, bag) = check_text(
    "int x; int a[2] = { [x] = 1 }; int main(){return 0;}",
  )
  assert_true(has_errors(bag))
}

///|
test "sem rejects multiple union designators" {
  let (_, bag) = check_text(
    "union U { int a; int b; }; union U u = { .a = 1, .b = 2 };",
  )
  assert_true(has_errors(bag))
}

///|
test "parse bitfields and qualifiers" {
  let (_, bag) = check_text(
    "struct S { unsigned int a:3; int : 2; const int b; }; int main(){struct S s = { .b = 1 }; return 0;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem rejects non-integer bitfield" {
  let (_, bag) = check_text("struct S { float f:3; }; int main(){return 0;}")
  assert_true(has_errors(bag))
}

///|
test "sem rejects oversized bitfield" {
  let (_, bag) = check_text("struct S { int a: 33; }; int main(){return 0;}")
  assert_true(has_errors(bag))
}

///|
test "sem accepts typeof expression" {
  let (_, bag) = check_text("int x; typeof(x) y; int main(){y = 1; return y;}")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts typeof type" {
  let (_, bag) = check_text("typedef int T; typeof(T) y; int main(){return y;}")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts alignof in _Static_assert" {
  let (_, bag) = check_text(
    "_Static_assert(__alignof__(int) == 4, \"ok\"); _Static_assert(_Alignof(int) == 4, \"ok\"); int main(){return 0;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem applies aligned attribute to typedef and var" {
  let (_, bag) = check_text(
    "typedef int T __attribute__((aligned(8))); int x __attribute__((aligned(8))); _Static_assert(__alignof__(T) == 8, \"ok\"); _Static_assert(__alignof__(x) == 8, \"ok\"); int main(){return 0;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts _Static_assert" {
  let (_, bag) = check_text("_Static_assert(1, \"ok\"); int main(){return 0;}")
  assert_true(!has_errors(bag))
}

///|
test "sem rejects _Static_assert" {
  let (_, bag) = check_text("_Static_assert(0, \"no\"); int main(){return 0;}")
  assert_true(has_errors(bag))
}

///|
test "sem accepts _Static_assert without message" {
  let (_, bag) = check_text("_Static_assert(1); int main(){return 0;}")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts _Static_assert in struct" {
  let (_, bag) = check_text(
    "struct S { _Static_assert(1, \"ok\"); int x; }; int main(){return 0;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "parse asm label on declaration" {
  let (unit, bag) = parse_text("int f() __asm__(\"foo\");")
  assert_true(!has_errors(bag))
  guard unit.decls.length() == 1 else { fail("expected single declaration") }
  match unit.decls[0] {
    Decl::FuncDecl(func) => assert_eq(func.attrs.asm_label, Some("foo"))
    _ => fail("expected function declaration")
  }
}

///|
test "parse global asm block" {
  let (unit, bag) = parse_text("asm(\"nop\"); int main(){return 0;}")
  assert_true(!has_errors(bag))
  guard unit.decls.length() == 2 else { fail("expected two declarations") }
  match unit.decls[0] {
    Decl::Asm(_) => ()
    _ => fail("expected asm declaration")
  }
}

///|
test "sem accepts asm statement" {
  let (_, bag) = check_text("int main(){asm(\"nop\"); return 0;}")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts asm operands" {
  let (_, bag) = check_text(
    "int main(){int x=0; int y=1; asm(\"\" : \"=r\"(x) : \"r\"(y) : \"cc\"); return x;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts __attribute__ on declarations" {
  let (_, bag) = check_text(
    "int * __attribute__((unused)) p; struct __attribute__((packed)) S { char c; int x; }; int main(){return 0;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "attribute after label is accepted" {
  let (_, bag) = check_text(
    "int main(){label: __attribute__((unused)); return 0;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "attribute in pointer declarator sets call conv" {
  let (unit, bag) = parse_text(
    "typedef int (* __attribute__((stdcall)) Fn)(void);",
  )
  assert_true(!has_errors(bag))
  guard unit.decls.length() == 1 else { fail("expected single declaration") }
  match unit.decls[0] {
    Decl::Typedef(name="Fn", ty~, ..) =>
      match ty {
        CType::Pointer(inner) =>
          match inner {
            CType::Function(call_conv=CallConv::Stdcall, ..) => ()
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
  assert_true(has_errors(bag))
}

///|
test "sem accepts cdecl as default" {
  let (_, bag) = check_text("int __attribute__((cdecl)) f(); int f();")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts regparm zero as default" {
  let (_, bag) = check_text("int __attribute__((regparm(0))) f(); int f();")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts storage classes" {
  let (_, bag) = check_text(
    "static int x; extern int y; int main(){register int r=1; return r + x;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem rejects invalid global storage" {
  let (_, bag) = check_text("auto int x; int main(){return 0;}")
  assert_true(has_errors(bag))
  let (_, bag2) = check_text("register int y; int main(){return 0;}")
  assert_true(has_errors(bag2))
}

///|
test "sem rejects control flow outside context" {
  let (_, bag) = check_text("int main(){case 1: return 0;}")
  assert_true(has_errors(bag))
  let (_, bag2) = check_text("int main(){break;}")
  assert_true(has_errors(bag2))
  let (_, bag3) = check_text("int main(){continue;}")
  assert_true(has_errors(bag3))
  let (_, bag4) = check_text("int main(){goto missing;}")
  assert_true(has_errors(bag4))
}

///|
test "sem accepts string and char literals" {
  let (_, bag) = check_text(
    "enum { A = 'a' }; int main(){char *p = \"hi\"; char s[] = \"hi\"; return s[0] + A;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem rejects long string initializer" {
  let (_, bag) = check_text("int main(){char s[2] = \"hi\"; return 0;}")
  assert_true(has_errors(bag))
}

///|
test "sem accepts compound assignments and floats" {
  let (_, bag) = check_text(
    "int main(){int x=0; x+=1; x<<=2; double f=1.0; f/=2.0; return x;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts integer suffixes" {
  let (_, bag) = check_text(
    "enum { A = sizeof(1L), B = sizeof(1LL), C = sizeof(1u) }; int main(){unsigned long x = 1UL; return A + B + C + x;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "parse abstract declarators in sizeof" {
  let (_, bag) = check_text(
    "int f(int); int main(){return sizeof(int (*)(int)) + sizeof(int[3]);}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts varargs call" {
  let (_, bag) = check_text("int f(int, ...); int main(){return f(1, 2, 3);}")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts void pointer compatibility" {
  let (_, bag) = check_text(
    "int x; void *p; int *q; int main(){q = &x; p = q; q = p; return p == q;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "typedef scope does not leak" {
  let (_, bag) = check_text(
    "struct S { int x; }; int main(){typedef struct S T; { typedef int T; } T y; return y.x;}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts null pointer constants" {
  let (_, bag) = check_text("int *p; int main(){p = 0; return p == 0;}")
  assert_true(!has_errors(bag))
}

///|
test "sem accepts pointer conditional with null" {
  let (_, bag) = check_text("int *p; int main(){return (1 ? p : 0) == p;}")
  assert_true(!has_errors(bag))
}

///|
test "sem adjusts array parameters to pointers" {
  let (_, bag) = check_text(
    "int f(int a[]); int main(){int b[2]; return f(b);}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem adjusts function parameters to pointers" {
  let (_, bag) = check_text(
    "int cb(int); int f(int g(int)); int main(){return f(cb);}",
  )
  assert_true(!has_errors(bag))
}

///|
test "sem accepts reversed array indexing" {
  let (_, bag) = check_text("int a[2]; int main(){return 1[a];}")
  assert_true(!has_errors(bag))
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
  assert_true(!has_errors(bag))
}

///|
test "sem rejects incompatible global redeclarations" {
  let (_, bag) = check_text("int a[2]; int a[3];")
  assert_true(has_errors(bag))
}
