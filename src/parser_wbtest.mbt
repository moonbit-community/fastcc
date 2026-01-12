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
