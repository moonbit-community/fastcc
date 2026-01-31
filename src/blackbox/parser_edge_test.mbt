///|
test "parser static assert with message" {
  let (unit, bag) = parse_unit("_Static_assert(1, \"ok\");\n")
  assert_true(!@diag.has_errors(bag))
  let mut found = false
  for decl in unit.decls {
    match decl {
      @ast.Decl::StaticAssert(sa) => {
        found = true
        assert_true(sa.message is Some(_))
      }
      _ => ()
    }
  }
  assert_true(found)
}

///|
test "parser control flow constructs" {
  let source = (
    #|int f(int x) {
    #|  int sum = 0;
    #|  int i;
    #|  for (i = 0; i < 3; i = i + 1) {
    #|    if (i == 1) continue;
    #|    sum += i;
    #|  }
    #|  switch (x) {
    #|    case 1: sum += 10; break;
    #|    default: sum += 20;
    #|  }
    #|  goto done;
    #|done:
    #|  return sum;
    #|}
  )
  let (_unit, bag) = parse_unit(source)
  assert_true(!@diag.has_errors(bag))
}

///|
test "parser inline function pointer error" {
  let source = "inline int (*fp)(int);\n"
  let (_unit, bag) = parse_unit(source)
  assert_true(@diag.has_errors(bag))
}

///|
test "parser old-style missing param name" {
  let source = "int f(a)\nint *;\n{ return 0; }\n"
  let (_unit, bag) = parse_unit(source)
  assert_true(@diag.has_errors(bag))
}
