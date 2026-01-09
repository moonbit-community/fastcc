///|
fn main {
  let bag = new_diag_bag()
  let map = new_source_map()
  let file = add_file(map, "<stdin>", "int x = 1; return x;")
  let pp = new_preprocessor(file, bag)
  let toks = dump_tokens(pp, 32)
  if has_errors(bag) {
    let d = bag.diags[0]
    println(format_diag(d))
  } else {
    for t in toks {
      println(t.lexeme)
    }
  }
}
