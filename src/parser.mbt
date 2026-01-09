///|
struct Parser {
  tokens : Array[Token]
  mut index : Int
  diags : DiagBag
  type_aliases : Map[String, CType]
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
  { tokens, index: 0, diags, type_aliases: {} }
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
  match parse_decl_specs(p) {
    None => None
    Some((base_type, _loc, is_typedef)) =>
      match parse_declarator(p, base_type) {
        None => None
        Some(decl) =>
          if is_typedef {
            expect(p, Semicolon, "expected ';' after typedef") |> ignore
            p.type_aliases.set(decl.name, decl.ty)
            Some(Decl::Typedef(name=decl.name, ty=decl.ty, loc=decl.loc))
          } else {
            match decl.params {
              Some(params) if decl.ty is CType::Function(return_type~, ..) =>
                if match_token(p, LBrace) is Some(lbrace) {
                  let body = parse_compound_stmt(p, lbrace.loc)
                  Some(
                    Decl::FuncDef({
                      name: decl.name,
                      return_type,
                      params,
                      body,
                      loc: decl.loc,
                    }),
                  )
                } else {
                  expect(
                    p,
                    Semicolon,
                    "expected ';' after function declaration",
                  )
                  |> ignore
                  Some(
                    Decl::FuncDecl({
                      name: decl.name,
                      return_type,
                      params,
                      loc: decl.loc,
                    }),
                  )
                }
              _ => {
                let init = if match_token(p, Assign) is Some(_) {
                  Some(parse_expr(p))
                } else {
                  None
                }
                expect(p, Semicolon, "expected ';' after declaration") |> ignore
                Some(
                  Decl::Var({
                    name: decl.name,
                    ty: decl.ty,
                    init,
                    loc: decl.loc,
                  }),
                )
              }
            }
          }
      }
  }
}

///|
fn parse_decl_specs(p : Parser) -> (CType, SrcLoc, Bool)? {
  let mut is_typedef = false
  if match_token(p, KwTypedef) is Some(_) {
    is_typedef = true
  }
  match parse_type_spec(p) {
    None => None
    Some((ty, loc)) => Some((ty, loc, is_typedef))
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
    KwStruct => parse_tagged_type(p, name => CType::Struct(name~))
    KwUnion => parse_tagged_type(p, name => CType::Union(name~))
    KwEnum => parse_tagged_type(p, name => CType::Enum(name~))
    Ident =>
      match p.type_aliases.get(tok.lexeme) {
        Some(aliased) => {
          let consumed = advance_token(p)
          Some((aliased, consumed.loc))
        }
        None => {
          add_parse_error(p, tok.loc, "expected type specifier")
          None
        }
      }
    _ => {
      add_parse_error(p, tok.loc, "expected type specifier")
      None
    }
  }
}

///|
struct Declarator {
  name : String
  ty : CType
  params : Array[Param]?
  loc : SrcLoc
}

///|
fn parse_declarator(p : Parser, base : CType) -> Declarator? {
  if is_paren_pointer_declarator(p) {
    return parse_paren_pointer_declarator(p, base)
  }
  let mut ty = base
  while match_token(p, Star) is Some(_) {
    ty = CType::Pointer(ty)
  }
  let name_tok = expect_ident(p, "expected identifier")
  match name_tok {
    None => None
    Some(tok) => {
      let (ty, params) = parse_declarator_suffix(p, ty)
      Some({ name: tok.lexeme, ty, params, loc: tok.loc })
    }
  }
}

///|
fn is_paren_pointer_declarator(p : Parser) -> Bool {
  peek_kind(p, 0) == LParen && peek_kind(p, 1) == Star
}

///|
fn parse_paren_pointer_declarator(p : Parser, base : CType) -> Declarator? {
  expect(p, LParen, "expected '(' in declarator") |> ignore
  let mut stars = 0
  while match_token(p, Star) is Some(_) {
    stars = stars + 1
  }
  let name_tok = expect_ident(p, "expected identifier")
  expect(p, RParen, "expected ')' in declarator") |> ignore
  match name_tok {
    None => None
    Some(tok) => {
      let (ty, params) = parse_declarator_suffix(p, base)
      let mut wrapped = ty
      let mut i = 0
      while i < stars {
        wrapped = CType::Pointer(wrapped)
        i = i + 1
      }
      Some({ name: tok.lexeme, ty: wrapped, params, loc: tok.loc })
    }
  }
}

///|
fn parse_declarator_suffix(p : Parser, ty_in : CType) -> (CType, Array[Param]?) {
  let mut ty = ty_in
  while match_token(p, LBracket) is Some(_) {
    let size = parse_array_size(p)
    expect(p, RBracket, "expected ']' after array size") |> ignore
    ty = CType::Array(elem=ty, size~)
  }
  let params = if match_token(p, LParen) is Some(_) {
    let params = parse_param_list(p)
    let param_types = params.map(param => param.ty)
    ty = CType::Function(return_type=ty, params=param_types)
    Some(params)
  } else {
    None
  }
  (ty, params)
}

///|
fn parse_array_size(p : Parser) -> Int? {
  if peek_token(p).kind == RBracket {
    return None
  }
  let tok = peek_token(p)
  if tok.kind == IntLit {
    ignore(advance_token(p))
    let value = try @strconv.parse_int(tok.lexeme, base=0) catch {
      _ => 0
    } noraise {
      v => v
    }
    return Some(value)
  }
  add_parse_error(p, tok.loc, "expected array size")
  None
}

///|
fn parse_tagged_type(p : Parser, ctor : (String) -> CType) -> (CType, SrcLoc)? {
  let kw = advance_token(p)
  let name = if peek_token(p).kind == Ident {
    advance_token(p).lexeme
  } else {
    ""
  }
  if match_token(p, LBrace) is Some(_) {
    skip_brace_block(p)
  }
  Some((ctor(name), kw.loc))
}

///|
fn skip_brace_block(p : Parser) -> Unit {
  let mut depth = 1
  while depth > 0 && !is_at_end(p) {
    let tok = advance_token(p)
    if tok.kind == LBrace {
      depth = depth + 1
    } else if tok.kind == RBrace {
      depth = depth - 1
    }
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
  match parse_param_declarator(p, base, loc) {
    Some(param) => Some(param)
    None => {
      add_parse_error(p, loc, "expected parameter declarator")
      None
    }
  }
}

///|
fn parse_param_declarator(
  p : Parser,
  base : CType,
  fallback_loc : SrcLoc,
) -> Param? {
  if is_paren_pointer_declarator(p) {
    expect(p, LParen, "expected '(' in declarator") |> ignore
    let mut stars = 0
    while match_token(p, Star) is Some(_) {
      stars = stars + 1
    }
    let name_tok = if peek_token(p).kind == Ident {
      Some(advance_token(p))
    } else {
      None
    }
    expect(p, RParen, "expected ')' in declarator") |> ignore
    let (ty, _params) = parse_declarator_suffix(p, base)
    let mut wrapped = ty
    let mut i = 0
    while i < stars {
      wrapped = CType::Pointer(wrapped)
      i = i + 1
    }
    let (name, loc) = match name_tok {
      Some(tok) => (tok.lexeme, tok.loc)
      None => ("", fallback_loc)
    }
    return Some({ name, ty: wrapped, loc })
  }
  let mut ty = base
  while match_token(p, Star) is Some(_) {
    ty = CType::Pointer(ty)
  }
  if peek_token(p).kind == Ident {
    let name_tok = advance_token(p)
    let (ty, _params) = parse_declarator_suffix(p, ty)
    return Some({ name: name_tok.lexeme, ty, loc: name_tok.loc })
  }
  Some({ name: "", ty, loc: fallback_loc })
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
  if match_token(p, KwCase) is Some(case_tok) {
    let expr = parse_expr(p)
    let end_expr = if match_token(p, Ellipsis) is Some(_) {
      Some(parse_expr(p))
    } else {
      None
    }
    expect(p, Colon, "expected ':' after case") |> ignore
    let body = parse_stmt(p)
    return Stmt::Case(expr~, end_expr~, body~, loc=case_tok.loc)
  }
  if match_token(p, KwDefault) is Some(def_tok) {
    expect(p, Colon, "expected ':' after default") |> ignore
    let body = parse_stmt(p)
    return Stmt::Default(body~, loc=def_tok.loc)
  }
  if match_token(p, KwIf) is Some(if_tok) {
    return parse_if_stmt(p, if_tok.loc)
  }
  if match_token(p, KwWhile) is Some(while_tok) {
    return parse_while_stmt(p, while_tok.loc)
  }
  if match_token(p, KwDo) is Some(do_tok) {
    return parse_do_while_stmt(p, do_tok.loc)
  }
  if match_token(p, KwFor) is Some(for_tok) {
    return parse_for_stmt(p, for_tok.loc)
  }
  if match_token(p, KwSwitch) is Some(sw_tok) {
    return parse_switch_stmt(p, sw_tok.loc)
  }
  if match_token(p, KwBreak) is Some(break_tok) {
    expect(p, Semicolon, "expected ';' after break") |> ignore
    return Stmt::Break(loc=break_tok.loc)
  }
  if match_token(p, KwContinue) is Some(cont_tok) {
    expect(p, Semicolon, "expected ';' after continue") |> ignore
    return Stmt::Continue(loc=cont_tok.loc)
  }
  if match_token(p, KwGoto) is Some(goto_tok) {
    let name = match expect_ident(p, "expected label after goto") {
      None => ""
      Some(tok) => tok.lexeme
    }
    expect(p, Semicolon, "expected ';' after goto") |> ignore
    return Stmt::Goto(name~, loc=goto_tok.loc)
  }
  if tok.kind == Ident && peek_kind(p, 1) == Colon {
    let label_tok = advance_token(p)
    expect(p, Colon, "expected ':' after label") |> ignore
    let body = parse_stmt(p)
    return Stmt::Label(name=label_tok.lexeme, body~, loc=label_tok.loc)
  }
  if match_token(p, KwReturn) is Some(ret_tok) {
    if match_token(p, Semicolon) is Some(_) {
      return Stmt::Return(value=None, loc=ret_tok.loc)
    }
    let value = parse_expr(p)
    expect(p, Semicolon, "expected ';' after return") |> ignore
    return Stmt::Return(value=Some(value), loc=ret_tok.loc)
  }
  if is_type_start(p, tok) {
    match parse_decl_specs(p) {
      Some((base, _type_loc, is_typedef)) =>
        match parse_declarator(p, base) {
          Some(decl) => {
            if is_typedef {
              expect(p, Semicolon, "expected ';' after typedef") |> ignore
              p.type_aliases.set(decl.name, decl.ty)
              return Stmt::Empty(loc=decl.loc)
            }
            let init = if match_token(p, Assign) is Some(_) {
              Some(parse_expr(p))
            } else {
              None
            }
            expect(p, Semicolon, "expected ';' after declaration") |> ignore
            let decl_stmt = {
              name: decl.name,
              ty: decl.ty,
              init,
              loc: decl.loc,
            }
            return Stmt::DeclStmt(decl=decl_stmt, loc=decl.loc)
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
fn parse_if_stmt(p : Parser, loc : SrcLoc) -> Stmt {
  expect(p, LParen, "expected '(' after if") |> ignore
  let cond = parse_expr(p)
  expect(p, RParen, "expected ')' after if condition") |> ignore
  let then_branch = parse_stmt(p)
  let else_branch = if match_token(p, KwElse) is Some(_) {
    Some(parse_stmt(p))
  } else {
    None
  }
  Stmt::If(cond~, then_branch~, else_branch~, loc~)
}

///|
fn parse_while_stmt(p : Parser, loc : SrcLoc) -> Stmt {
  expect(p, LParen, "expected '(' after while") |> ignore
  let cond = parse_expr(p)
  expect(p, RParen, "expected ')' after while condition") |> ignore
  let body = parse_stmt(p)
  Stmt::While(cond~, body~, loc~)
}

///|
fn parse_do_while_stmt(p : Parser, loc : SrcLoc) -> Stmt {
  let body = parse_stmt(p)
  expect(p, KwWhile, "expected while after do") |> ignore
  expect(p, LParen, "expected '(' after while") |> ignore
  let cond = parse_expr(p)
  expect(p, RParen, "expected ')' after do-while condition") |> ignore
  expect(p, Semicolon, "expected ';' after do-while") |> ignore
  Stmt::DoWhile(cond~, body~, loc~)
}

///|
fn parse_for_stmt(p : Parser, loc : SrcLoc) -> Stmt {
  expect(p, LParen, "expected '(' after for") |> ignore
  let init = parse_for_init(p)
  let cond = if match_token(p, Semicolon) is Some(_) {
    None
  } else {
    let cond_expr = parse_expr(p)
    expect(p, Semicolon, "expected ';' after for condition") |> ignore
    Some(cond_expr)
  }
  let step = if match_token(p, RParen) is Some(_) {
    None
  } else {
    let step_expr = parse_expr(p)
    expect(p, RParen, "expected ')' after for step") |> ignore
    Some(step_expr)
  }
  let body = parse_stmt(p)
  Stmt::For(init~, cond~, step~, body~, loc~)
}

///|
fn parse_switch_stmt(p : Parser, loc : SrcLoc) -> Stmt {
  expect(p, LParen, "expected '(' after switch") |> ignore
  let cond = parse_expr(p)
  expect(p, RParen, "expected ')' after switch condition") |> ignore
  let body = parse_stmt(p)
  Stmt::Switch(cond~, body~, loc~)
}

///|
fn parse_for_init(p : Parser) -> Stmt? {
  if match_token(p, Semicolon) is Some(_) {
    return None
  }
  if is_type_start(p, peek_token(p)) {
    match parse_decl_specs(p) {
      Some((base, _type_loc, is_typedef)) =>
        match parse_declarator(p, base) {
          Some(decl) => {
            if is_typedef {
              expect(p, Semicolon, "expected ';' after typedef") |> ignore
              p.type_aliases.set(decl.name, decl.ty)
              return None
            }
            let init = if match_token(p, Assign) is Some(_) {
              Some(parse_expr(p))
            } else {
              None
            }
            expect(p, Semicolon, "expected ';' after for declaration") |> ignore
            let decl_stmt = {
              name: decl.name,
              ty: decl.ty,
              init,
              loc: decl.loc,
            }
            return Some(Stmt::DeclStmt(decl=decl_stmt, loc=decl.loc))
          }
          None => {
            synchronize(p)
            return None
          }
        }
      None => {
        synchronize(p)
        return None
      }
    }
  }
  let expr = parse_expr(p)
  expect(p, Semicolon, "expected ';' after for init") |> ignore
  Some(Stmt::ExprStmt(expr~, loc=expr_loc(expr)))
}

///|
fn parse_expr(p : Parser) -> Expr {
  parse_expr_comma(p)
}

///|
fn parse_expr_comma(p : Parser) -> Expr {
  let mut expr = parse_expr_eq(p)
  while match_token(p, Comma) is Some(tok) {
    let right = parse_expr_eq(p)
    expr = Expr::Binary(op=BinaryOp::Comma, left=expr, right~, loc=tok.loc)
  }
  expr
}

///|
fn parse_expr_eq(p : Parser) -> Expr {
  let left = parse_expr_cond(p)
  match match_token(p, Assign) {
    None => left
    Some(tok) => {
      let right = parse_expr_eq(p)
      Expr::Binary(op=BinaryOp::Assign, left~, right~, loc=tok.loc)
    }
  }
}

///|
fn parse_expr_cond(p : Parser) -> Expr {
  let cond = parse_expr_lor(p)
  match match_token(p, Question) {
    None => cond
    Some(tok) => {
      let then_expr = parse_expr(p)
      expect(p, Colon, "expected ':' in conditional expression") |> ignore
      let else_expr = parse_expr_cond(p)
      Expr::Conditional(cond~, then_expr~, else_expr~, loc=tok.loc)
    }
  }
}

///|
fn parse_expr_lor(p : Parser) -> Expr {
  let mut expr = parse_expr_land(p)
  while match_token(p, PipePipe) is Some(tok) {
    let right = parse_expr_land(p)
    expr = Expr::Binary(op=BinaryOp::LogOr, left=expr, right~, loc=tok.loc)
  }
  expr
}

///|
fn parse_expr_land(p : Parser) -> Expr {
  let mut expr = parse_expr_or(p)
  while match_token(p, AmpAmp) is Some(tok) {
    let right = parse_expr_or(p)
    expr = Expr::Binary(op=BinaryOp::LogAnd, left=expr, right~, loc=tok.loc)
  }
  expr
}

///|
fn parse_expr_or(p : Parser) -> Expr {
  let mut expr = parse_expr_xor(p)
  while match_token(p, Pipe) is Some(tok) {
    let right = parse_expr_xor(p)
    expr = Expr::Binary(op=BinaryOp::BitOr, left=expr, right~, loc=tok.loc)
  }
  expr
}

///|
fn parse_expr_xor(p : Parser) -> Expr {
  let mut expr = parse_expr_and(p)
  while match_token(p, Caret) is Some(tok) {
    let right = parse_expr_and(p)
    expr = Expr::Binary(op=BinaryOp::BitXor, left=expr, right~, loc=tok.loc)
  }
  expr
}

///|
fn parse_expr_and(p : Parser) -> Expr {
  let mut expr = parse_expr_cmpeq(p)
  while match_token(p, Amp) is Some(tok) {
    let right = parse_expr_cmpeq(p)
    expr = Expr::Binary(op=BinaryOp::BitAnd, left=expr, right~, loc=tok.loc)
  }
  expr
}

///|
fn parse_expr_cmpeq(p : Parser) -> Expr {
  let mut expr = parse_expr_cmp(p)
  while true {
    match match_token(p, Eq) {
      Some(tok) => {
        let right = parse_expr_cmp(p)
        expr = Expr::Binary(op=BinaryOp::Eq, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, Ne) {
      Some(tok) => {
        let right = parse_expr_cmp(p)
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
fn parse_expr_cmp(p : Parser) -> Expr {
  let mut expr = parse_expr_shift(p)
  while true {
    match match_token(p, Lt) {
      Some(tok) => {
        let right = parse_expr_shift(p)
        expr = Expr::Binary(op=BinaryOp::Lt, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, Le) {
      Some(tok) => {
        let right = parse_expr_shift(p)
        expr = Expr::Binary(op=BinaryOp::Le, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, Gt) {
      Some(tok) => {
        let right = parse_expr_shift(p)
        expr = Expr::Binary(op=BinaryOp::Gt, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, Ge) {
      Some(tok) => {
        let right = parse_expr_shift(p)
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
fn parse_expr_shift(p : Parser) -> Expr {
  let mut expr = parse_expr_sum(p)
  while true {
    match match_token(p, ShiftLeft) {
      Some(tok) => {
        let right = parse_expr_sum(p)
        expr = Expr::Binary(op=BinaryOp::Shl, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, ShiftRight) {
      Some(tok) => {
        let right = parse_expr_sum(p)
        expr = Expr::Binary(op=BinaryOp::Shr, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    break
  }
  expr
}

///|
fn parse_expr_sum(p : Parser) -> Expr {
  let mut expr = parse_expr_prod(p)
  while true {
    match match_token(p, Plus) {
      Some(tok) => {
        let right = parse_expr_prod(p)
        expr = Expr::Binary(op=BinaryOp::Add, left=expr, right~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, Minus) {
      Some(tok) => {
        let right = parse_expr_prod(p)
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
fn parse_expr_prod(p : Parser) -> Expr {
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
  match match_token(p, Amp) {
    Some(tok) => {
      let expr = parse_expr_unary(p)
      return Expr::Unary(op=UnaryOp::Addr, expr~, loc=tok.loc)
    }
    None => ()
  }
  match match_token(p, Star) {
    Some(tok) => {
      let expr = parse_expr_unary(p)
      return Expr::Unary(op=UnaryOp::Deref, expr~, loc=tok.loc)
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
fn is_type_start(p : Parser, tok : Token) -> Bool {
  match tok.kind {
    KwInt => true
    KwVoid => true
    KwStruct => true
    KwUnion => true
    KwEnum => true
    KwTypedef => true
    Ident => p.type_aliases.contains(tok.lexeme)
    _ => false
  }
}

///|
fn expr_loc(expr : Expr) -> SrcLoc {
  match expr {
    Expr::IntLit(loc~, ..) => loc
    Expr::Ident(loc~, ..) => loc
    Expr::Unary(loc~, ..) => loc
    Expr::Binary(loc~, ..) => loc
    Expr::Conditional(loc~, ..) => loc
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
fn peek_token_at(p : Parser, offset : Int) -> Token {
  let idx = p.index + offset
  if idx >= 0 && idx < p.tokens.length() {
    return p.tokens[idx]
  }
  p.tokens[p.tokens.length() - 1]
}

///|
fn peek_kind(p : Parser, offset : Int) -> TokenKind {
  peek_token_at(p, offset).kind
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
