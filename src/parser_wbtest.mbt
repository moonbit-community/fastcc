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
