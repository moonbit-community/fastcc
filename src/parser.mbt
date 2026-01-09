///|
struct Parser {
  tokens : Array[Token]
  mut index : Int
  diags : DiagBag
}

///|
fn collect_tokens(pp : Preprocessor) -> Array[Token] {
  let out : Array[Token] = []
  while true {
    let tok = next_pp_token(pp)
    out.push(tok)
    if tok.kind == Eof {
      break
    }
  }
  out
}

///|
fn new_parser(tokens : Array[Token], diags : DiagBag) -> Parser {
  { tokens, index: 0, diags }
}

///|
fn parse_translation_unit(pp : Preprocessor) -> TranslationUnit {
  let tokens = collect_tokens(pp)
  let parser = new_parser(tokens, pp.diags)
  parse_translation_unit_with(parser)
}

///|
fn parse_translation_unit_with(p : Parser) -> TranslationUnit {
  let decls : Array[Decl] = []
  while !is_at_end(p) {
    match parse_decl(p) {
      Some(decl) => decls.push(decl)
      None => synchronize(p)
    }
  }
  { decls, }
}

///|
fn parse_decl(p : Parser) -> Decl? {
  match parse_type_spec(p) {
    None => None
    Some((base_type, _loc)) =>
      match parse_declarator(p, base_type) {
        None => None
        Some((name, ty, loc)) =>
          if match_token(p, LParen) is Some(_) {
            let params = parse_param_list(p)
            if match_token(p, LBrace) is Some(lbrace) {
              let body = parse_compound_stmt(p, lbrace.loc)
              Some(Decl::FuncDef({ name, return_type: ty, params, body, loc }))
            } else {
              expect(p, Semicolon, "expected ';' after function declaration")
              |> ignore
              Some(Decl::FuncDecl({ name, return_type: ty, params, loc }))
            }
          } else {
            let init = if match_token(p, Assign) is Some(_) {
              Some(parse_expr(p))
            } else {
              None
            }
            expect(p, Semicolon, "expected ';' after declaration") |> ignore
            Some(Decl::Var({ name, ty, init, loc }))
          }
      }
  }
}

///|
fn parse_type_spec(p : Parser) -> (CType, SrcLoc)? {
  let tok = peek_token(p)
  match tok.kind {
    KwInt => {
      let consumed = advance_token(p)
      Some((CType::Int, consumed.loc))
    }
    KwVoid => {
      let consumed = advance_token(p)
      Some((CType::Void, consumed.loc))
    }
    _ => {
      add_parse_error(p, tok.loc, "expected type specifier")
      None
    }
  }
}

///|
fn parse_declarator(p : Parser, base : CType) -> (String, CType, SrcLoc)? {
  let mut ty = base
  while match_token(p, Star) is Some(_) {
    ty = CType::Pointer(ty)
  }
  let name_tok = expect_ident(p, "expected identifier")
  match name_tok {
    None => None
    Some(tok) => Some((tok.lexeme, ty, tok.loc))
  }
}

///|
fn parse_param_list(p : Parser) -> Array[Param] {
  let params : Array[Param] = []
  if match_token(p, RParen) is Some(_) {
    return params
  }
  if peek_token(p).kind == KwVoid {
    let void_tok = advance_token(p)
    if match_token(p, RParen) is Some(_) {
      return params
    }
    match parse_param_after_base(p, CType::Void, void_tok.loc) {
      Some(param) => params.push(param)
      None => ()
    }
  } else {
    match parse_type_spec(p) {
      Some((base, type_loc)) =>
        match parse_param_after_base(p, base, type_loc) {
          Some(param) => params.push(param)
          None => ()
        }
      None => ()
    }
  }
  while true {
    if match_token(p, Comma) is Some(_) {
      match parse_type_spec(p) {
        Some((base, type_loc)) =>
          match parse_param_after_base(p, base, type_loc) {
            Some(param) => params.push(param)
            None => ()
          }
        None => ()
      }
      continue
    }
    expect(p, RParen, "expected ')' after parameter list") |> ignore
    break
  }
  params
}

///|
fn parse_param_after_base(p : Parser, base : CType, loc : SrcLoc) -> Param? {
  let mut ty = base
  while match_token(p, Star) is Some(_) {
    ty = CType::Pointer(ty)
  }
  if peek_token(p).kind != Ident {
    add_parse_error(p, loc, "expected parameter name")
    return None
  }
  let name_tok = advance_token(p)
  Some({ name: name_tok.lexeme, ty, loc: name_tok.loc })
}

///|
fn parse_compound_stmt(p : Parser, loc : SrcLoc) -> Stmt {
  let stmts : Array[Stmt] = []
  while !is_at_end(p) && peek_token(p).kind != RBrace {
    stmts.push(parse_stmt(p))
  }
  expect(p, RBrace, "expected '}'") |> ignore
  Stmt::Compound(stmts~, loc~)
}

///|
fn parse_stmt(p : Parser) -> Stmt {
  let tok = peek_token(p)
  if match_token(p, LBrace) is Some(lbrace) {
    return parse_compound_stmt(p, lbrace.loc)
  }
  if match_token(p, KwReturn) is Some(ret_tok) {
    if match_token(p, Semicolon) is Some(_) {
      return Stmt::Return(value=None, loc=ret_tok.loc)
    }
    let value = parse_expr(p)
    expect(p, Semicolon, "expected ';' after return") |> ignore
    return Stmt::Return(value=Some(value), loc=ret_tok.loc)
  }
  if is_type_start(tok.kind) {
    match parse_type_spec(p) {
      Some((base, _type_loc)) =>
        match parse_declarator(p, base) {
          Some((name, ty, decl_loc)) => {
            let init = if match_token(p, Assign) is Some(_) {
              Some(parse_expr(p))
            } else {
              None
            }
            expect(p, Semicolon, "expected ';' after declaration") |> ignore
            let decl = { name, ty, init, loc: decl_loc }
            return Stmt::DeclStmt(decl~, loc=decl_loc)
          }
          None => {
            synchronize(p)
            return Stmt::Empty(loc=tok.loc)
          }
        }
      None => {
        synchronize(p)
        return Stmt::Empty(loc=tok.loc)
      }
    }
  }
  if match_token(p, Semicolon) is Some(semi) {
    return Stmt::Empty(loc=semi.loc)
  }
  let expr = parse_expr(p)
  expect(p, Semicolon, "expected ';' after expression") |> ignore
  Stmt::ExprStmt(expr~, loc=expr_loc(expr))
}

///|
fn parse_expr(p : Parser) -> Expr {
  parse_expr_assign(p)
}

///|
fn parse_expr_assign(p : Parser) -> Expr {
  let left = parse_expr_eq(p)
  match match_token(p, Assign) {
    None => left
    Some(tok) => {
      let right = parse_expr_assign(p)
      Expr::Binary(op=BinaryOp::Assign, left~, right~, loc=tok.loc)
    }
  }
}

///|
fn parse_expr_eq(p : Parser) -> Expr {
  let mut expr = parse_expr_rel(p)
  while true {
    match match_token(p, Eq) {
      Some(tok) => {
        let right = parse_expr_rel(p)
        expr = Expr::Binary(op=BinaryOp::Eq, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, Ne) {
      Some(tok) => {
        let right = parse_expr_rel(p)
        expr = Expr::Binary(op=BinaryOp::Ne, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    break
  }
  expr
}

///|
fn parse_expr_rel(p : Parser) -> Expr {
  let mut expr = parse_expr_add(p)
  while true {
    match match_token(p, Lt) {
      Some(tok) => {
        let right = parse_expr_add(p)
        expr = Expr::Binary(op=BinaryOp::Lt, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, Le) {
      Some(tok) => {
        let right = parse_expr_add(p)
        expr = Expr::Binary(op=BinaryOp::Le, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, Gt) {
      Some(tok) => {
        let right = parse_expr_add(p)
        expr = Expr::Binary(op=BinaryOp::Gt, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, Ge) {
      Some(tok) => {
        let right = parse_expr_add(p)
        expr = Expr::Binary(op=BinaryOp::Ge, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    break
  }
  expr
}

///|
fn parse_expr_add(p : Parser) -> Expr {
  let mut expr = parse_expr_mul(p)
  while true {
    match match_token(p, Plus) {
      Some(tok) => {
        let right = parse_expr_mul(p)
        expr = Expr::Binary(op=BinaryOp::Add, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, Minus) {
      Some(tok) => {
        let right = parse_expr_mul(p)
        expr = Expr::Binary(op=BinaryOp::Sub, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    break
  }
  expr
}

///|
fn parse_expr_mul(p : Parser) -> Expr {
  let mut expr = parse_expr_unary(p)
  while true {
    match match_token(p, Star) {
      Some(tok) => {
        let right = parse_expr_unary(p)
        expr = Expr::Binary(op=BinaryOp::Mul, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, Slash) {
      Some(tok) => {
        let right = parse_expr_unary(p)
        expr = Expr::Binary(op=BinaryOp::Div, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, Percent) {
      Some(tok) => {
        let right = parse_expr_unary(p)
        expr = Expr::Binary(op=BinaryOp::Mod, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    break
  }
  expr
}

///|
fn parse_expr_unary(p : Parser) -> Expr {
  match match_token(p, Plus) {
    Some(tok) => {
      let expr = parse_expr_unary(p)
      return Expr::Unary(op=UnaryOp::Plus, expr~, loc=tok.loc)
    }
    None => ()
  }
  match match_token(p, Minus) {
    Some(tok) => {
      let expr = parse_expr_unary(p)
      return Expr::Unary(op=UnaryOp::Minus, expr~, loc=tok.loc)
    }
    None => ()
  }
  match match_token(p, Bang) {
    Some(tok) => {
      let expr = parse_expr_unary(p)
      return Expr::Unary(op=UnaryOp::Not, expr~, loc=tok.loc)
    }
    None => ()
  }
  match match_token(p, Tilde) {
    Some(tok) => {
      let expr = parse_expr_unary(p)
      return Expr::Unary(op=UnaryOp::BitNot, expr~, loc=tok.loc)
    }
    None => ()
  }
  parse_expr_postfix(p)
}

///|
fn parse_expr_postfix(p : Parser) -> Expr {
  let mut expr = parse_expr_primary(p)
  while true {
    match match_token(p, LParen) {
      None => break
      Some(tok) => {
        let args = parse_call_args(p)
        expr = Expr::Call(callee=expr, args~, loc=tok.loc)
      }
    }
  }
  expr
}

///|
fn parse_call_args(p : Parser) -> Array[Expr] {
  let args : Array[Expr] = []
  if match_token(p, RParen) is Some(_) {
    return args
  }
  while true {
    args.push(parse_expr(p))
    if match_token(p, Comma) is Some(_) {
      continue
    }
    expect(p, RParen, "expected ')' after arguments") |> ignore
    break
  }
  args
}

///|
fn parse_expr_primary(p : Parser) -> Expr {
  let tok = advance_token(p)
  match tok.kind {
    IntLit => Expr::IntLit(value=tok.lexeme, loc=tok.loc)
    Ident => Expr::Ident(name=tok.lexeme, loc=tok.loc)
    LParen => {
      let expr = parse_expr(p)
      expect(p, RParen, "expected ')'") |> ignore
      expr
    }
    _ => {
      add_parse_error(p, tok.loc, "unexpected token in expression")
      Expr::IntLit(value="0", loc=tok.loc)
    }
  }
}

///|
fn is_type_start(kind : TokenKind) -> Bool {
  kind == KwInt || kind == KwVoid
}

///|
fn expr_loc(expr : Expr) -> SrcLoc {
  match expr {
    Expr::IntLit(loc~, ..) => loc
    Expr::Ident(loc~, ..) => loc
    Expr::Unary(loc~, ..) => loc
    Expr::Binary(loc~, ..) => loc
    Expr::Call(loc~, ..) => loc
  }
}

///|
fn add_parse_error(p : Parser, loc : SrcLoc, message : String) -> Unit {
  add_error(p.diags, loc, message)
}

///|
fn peek_token(p : Parser) -> Token {
  if p.index < p.tokens.length() {
    return p.tokens[p.index]
  }
  p.tokens[p.tokens.length() - 1]
}

///|
fn advance_token(p : Parser) -> Token {
  let tok = peek_token(p)
  if p.index < p.tokens.length() {
    p.index = p.index + 1
  }
  tok
}

///|
fn match_token(p : Parser, kind : TokenKind) -> Token? {
  let tok = peek_token(p)
  if tok.kind == kind {
    p.index = p.index + 1
    return Some(tok)
  }
  None
}

///|
fn expect(p : Parser, kind : TokenKind, message : String) -> Token {
  let tok = peek_token(p)
  if tok.kind == kind {
    p.index = p.index + 1
    return tok
  }
  add_parse_error(p, tok.loc, message)
  tok
}

///|
fn expect_ident(p : Parser, message : String) -> Token? {
  let tok = peek_token(p)
  if tok.kind == Ident {
    p.index = p.index + 1
    return Some(tok)
  }
  add_parse_error(p, tok.loc, message)
  None
}

///|
fn is_at_end(p : Parser) -> Bool {
  peek_token(p).kind == Eof
}

///|
fn synchronize(p : Parser) -> Unit {
  while !is_at_end(p) {
    let tok = advance_token(p)
    if tok.kind == Semicolon || tok.kind == RBrace {
      return
    }
  }
}
