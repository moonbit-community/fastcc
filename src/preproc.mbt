///|
struct Preprocessor {
  lexer : Lexer
}

///|
fn new_preprocessor(file : SourceFile, diags : DiagBag) -> Preprocessor {
  { lexer: new_lexer(file, diags) }
}

///|
fn next_pp_token(pp : Preprocessor) -> Token {
  next_token(pp.lexer)
}

///|
fn dump_tokens(pp : Preprocessor, max_count : Int) -> Array[Token] {
  let out : Array[Token] = []
  while out.length() < max_count {
    let tok = next_pp_token(pp)
    out.push(tok)
    match tok.kind {
      Eof => break
      _ => ()
    }
  }
  out
}
