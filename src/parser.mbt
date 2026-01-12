///|
struct Parser {
  tokens : Array[Token]
  mut index : Int
  diags : DiagBag
  type_scopes : Array[Map[String, CType]]
  mut anon_tag_id : Int
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
  { tokens, index: 0, diags, type_scopes: [{}], anon_tag_id: 0 }
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
      Some(items) =>
        for item in items {
          decls.push(item)
        }
      None => synchronize(p)
    }
  }
  { decls, }
}

///|
fn parse_decl(p : Parser) -> Array[Decl]? {
  if match_token(p, KwStaticAssert) is Some(assert_tok) {
    let static_assert = parse_static_assert(p, assert_tok.loc)
    expect(p, Semicolon, "expected ';' after _Static_assert") |> ignore
    return Some([Decl::StaticAssert(static_assert)])
  }
  if match_token(p, KwAsm) is Some(asm_tok) {
    let asm_stmt = parse_asm_stmt(p, asm_tok.loc)
    expect(p, Semicolon, "expected ';' after asm") |> ignore
    return Some([Decl::Asm(asm_stmt)])
  }
  let specs = match parse_decl_specs(p) {
    None =>
      if peek_token(p).kind == Ident && !has_typedef(p, peek_token(p).lexeme) {
        Some({
          ty: CType::Int(kind=CIntKind::Int, unsigned=false),
          loc: peek_token(p).loc,
          is_typedef: false,
          storage: StorageClass::Default,
          is_inline: false,
          attrs: empty_attrs(),
        })
      } else {
        None
      }
    Some(val) => Some(val)
  }
  match specs {
    None => None
    Some(specs) => {
      let base_type = specs.ty
      let is_typedef = specs.is_typedef
      let storage = specs.storage
      let is_inline = specs.is_inline
      let base_attrs = specs.attrs
      if match_token(p, Semicolon) is Some(semi) {
        if is_typedef {
          add_parse_error(p, semi.loc, "typedef requires a declarator")
          None
        } else {
          Some([Decl::TagDef(ty=base_type, loc=semi.loc)])
        }
      } else {
        let decls : Array[Decl] = []
        while true {
          match parse_init_declarator(p, base_type) {
            None => {
              synchronize(p)
              return None
            }
            Some((decl, init)) => {
              let combined_attrs = merge_attrs(base_attrs, decl.attrs)
              let adjusted_ty = apply_call_conv_to_type(
                decl.ty,
                normalize_call_conv(combined_attrs.call_conv),
              )
              if is_typedef {
                if init is Some(_) {
                  add_parse_error(
                    p,
                    decl.loc,
                    "typedef cannot have initializer",
                  )
                }
                let typedef_ty = apply_type_attrs(
                  adjusted_ty,
                  type_attrs_from(combined_attrs),
                )
                define_typedef(p, decl.name, typedef_ty)
                decls.push(
                  Decl::Typedef(
                    name=decl.name,
                    ty=typedef_ty,
                    attrs=combined_attrs,
                    loc=decl.loc,
                  ),
                )
              } else {
                match decl.params {
                  Some(params) =>
                    match adjusted_ty {
                      CType::Function(return_type~, ..) => {
                        let mut final_params = params
                        let mut lbrace = match_token(p, LBrace)
                        if lbrace is None &&
                          decl.is_old_style &&
                          is_type_start(p, peek_token(p)) {
                          final_params = parse_old_style_param_decls(
                            p, final_params,
                          )
                          lbrace = match_token(p, LBrace)
                          if lbrace is None {
                            add_parse_error(
                              p,
                              decl.loc,
                              "expected '{' after parameter declarations",
                            )
                          }
                        }
                        if lbrace is Some(lbrace_tok) {
                          if init is Some(_) {
                            add_parse_error(
                              p,
                              decl.loc,
                              "function cannot have initializer",
                            )
                          }
                          if decls.length() > 0 {
                            add_parse_error(
                              p,
                              decl.loc,
                              "function definition cannot be mixed with other declarators",
                            )
                          }
                          let body = parse_compound_stmt(p, lbrace_tok.loc)
                          decls.push(
                            Decl::FuncDef({
                              name: decl.name,
                              return_type,
                              params: final_params,
                              varargs: decl.varargs,
                              is_old_style: decl.is_old_style,
                              storage,
                              is_inline,
                              attrs: combined_attrs,
                              body,
                              loc: decl.loc,
                            }),
                          )
                          return Some(decls)
                        } else {
                          if init is Some(_) {
                            add_parse_error(
                              p,
                              decl.loc,
                              "function declaration cannot have initializer",
                            )
                          }
                          decls.push(
                            Decl::FuncDecl({
                              name: decl.name,
                              return_type,
                              params: final_params,
                              varargs: decl.varargs,
                              is_old_style: decl.is_old_style,
                              storage,
                              is_inline,
                              attrs: combined_attrs,
                              loc: decl.loc,
                            }),
                          )
                        }
                      }
                      _ => {
                        if is_inline {
                          add_parse_error(
                            p,
                            decl.loc,
                            "inline can only apply to functions",
                          )
                        }
                        decls.push(
                          Decl::Var({
                            name: decl.name,
                            ty: adjusted_ty,
                            init,
                            storage,
                            attrs: combined_attrs,
                            loc: decl.loc,
                          }),
                        )
                      }
                    }
                  _ => {
                    if is_inline {
                      add_parse_error(
                        p,
                        decl.loc,
                        "inline can only apply to functions",
                      )
                    }
                    decls.push(
                      Decl::Var({
                        name: decl.name,
                        ty: adjusted_ty,
                        init,
                        storage,
                        attrs: combined_attrs,
                        loc: decl.loc,
                      }),
                    )
                  }
                }
              }
            }
          }
          if match_token(p, Comma) is Some(_) {
            continue
          }
          break
        }
        expect(p, Semicolon, "expected ';' after declaration") |> ignore
        Some(decls)
      }
    }
  }
}

///|
fn parse_old_style_param_decls(
  p : Parser,
  params : Array[Param],
) -> Array[Param] {
  let updated = params
  let param_map : Map[String, Int] = {}
  for i = 0; i < params.length(); i = i + 1 {
    let name = params[i].name
    if name == "" {
      continue
    }
    if param_map.contains(name) {
      add_parse_error(p, params[i].loc, "duplicate parameter name")
    } else {
      param_map.set(name, i)
    }
  }
  let seen : Map[String, Bool] = {}
  while is_type_start(p, peek_token(p)) {
    match parse_decl_specs(p) {
      None => break
      Some(specs) => {
        let base = specs.ty
        if specs.is_typedef {
          add_parse_error(p, specs.loc, "typedef not allowed in parameter list")
        }
        if specs.is_inline {
          add_parse_error(p, specs.loc, "inline not allowed in parameter list")
        }
        if specs.storage != StorageClass::Default &&
          specs.storage != StorageClass::Register {
          add_parse_error(p, specs.loc, "invalid storage class for parameter")
        }
        let mut any_decl = false
        while true {
          match parse_declarator(p, base) {
            None => {
              add_parse_error(p, specs.loc, "expected parameter declarator")
              break
            }
            Some(decl) => {
              any_decl = true
              let combined_attrs = merge_attrs(specs.attrs, decl.attrs)
              let adjusted_ty = apply_call_conv_to_type(
                decl.ty,
                normalize_call_conv(combined_attrs.call_conv),
              )
              if decl.name == "" {
                add_parse_error(p, decl.loc, "parameter name missing")
              } else {
                match param_map.get(decl.name) {
                  None => add_parse_error(p, decl.loc, "unknown parameter name")
                  Some(idx) =>
                    if seen.contains(decl.name) {
                      add_parse_error(
                        p,
                        decl.loc,
                        "duplicate parameter declaration",
                      )
                    } else {
                      seen.set(decl.name, true)
                      updated[idx] = {
                        name: decl.name,
                        ty: adjusted_ty,
                        loc: decl.loc,
                      }
                    }
                }
              }
            }
          }
          if match_token(p, Comma) is Some(_) {
            continue
          }
          break
        }
        if !any_decl {
          add_parse_error(p, specs.loc, "expected parameter declarator")
        }
        ignore(expect(p, Semicolon, "expected ';' after parameter declaration"))
      }
    }
  }
  updated
}

///|
fn empty_qual() -> TypeQual {
  { is_const: false, is_volatile: false, is_restrict: false }
}

///|
fn merge_qual(a : TypeQual, b : TypeQual) -> TypeQual {
  {
    is_const: a.is_const || b.is_const,
    is_volatile: a.is_volatile || b.is_volatile,
    is_restrict: a.is_restrict || b.is_restrict,
  }
}

///|
fn qual_is_empty(qual : TypeQual) -> Bool {
  !qual.is_const && !qual.is_volatile && !qual.is_restrict
}

///|
fn with_const(qual : TypeQual) -> TypeQual {
  {
    is_const: true,
    is_volatile: qual.is_volatile,
    is_restrict: qual.is_restrict,
  }
}

///|
fn with_volatile(qual : TypeQual) -> TypeQual {
  { is_const: qual.is_const, is_volatile: true, is_restrict: qual.is_restrict }
}

///|
fn with_restrict(qual : TypeQual) -> TypeQual {
  { is_const: qual.is_const, is_volatile: qual.is_volatile, is_restrict: true }
}

///|
fn apply_qualifiers(ty : CType, qual : TypeQual) -> CType {
  if qual_is_empty(qual) {
    return ty
  }
  match ty {
    CType::Qualified(qual=existing, base~) =>
      CType::Qualified(qual=merge_qual(existing, qual), base~)
    _ => CType::Qualified(qual~, base=ty)
  }
}

///|
fn strip_type_qualifiers(ty : CType) -> CType {
  match ty {
    CType::Qualified(base~, ..) => strip_type_qualifiers(base)
    CType::Attributed(base~, ..) => strip_type_qualifiers(base)
    _ => ty
  }
}

///|
fn parse_type_qualifiers(p : Parser) -> TypeQual {
  let mut qual = empty_qual()
  while true {
    match peek_token(p).kind {
      KwConst => {
        qual = with_const(qual)
        ignore(advance_token(p))
        continue
      }
      KwVolatile => {
        qual = with_volatile(qual)
        ignore(advance_token(p))
        continue
      }
      KwRestrict => {
        qual = with_restrict(qual)
        ignore(advance_token(p))
        continue
      }
      _ => ()
    }
    break
  }
  qual
}

///|
struct DeclSpecs {
  ty : CType
  loc : SrcLoc
  is_typedef : Bool
  storage : StorageClass
  is_inline : Bool
  attrs : Attributes
}

///|
fn parse_type_specifiers(
  p : Parser,
  allow_storage~ : Bool,
  allow_typedef~ : Bool,
) -> DeclSpecs? {
  let mut is_typedef = false
  let mut storage = StorageClass::Default
  let mut is_inline = false
  let mut saw_any = false
  let mut start_loc = peek_token(p).loc
  let mut qual = empty_qual()
  let mut attrs = empty_attrs()
  let mut signedness = 0
  let mut short_seen = false
  let mut long_count = 0
  let mut saw_char = false
  let mut saw_int = false
  let mut saw_bool = false
  let mut saw_float = false
  let mut saw_double = false
  let mut saw_void = false
  let mut base : CType? = None
  while true {
    let tok = peek_token(p)
    match tok.kind {
      KwTypedef => {
        if allow_typedef {
          if is_typedef || storage != StorageClass::Default {
            add_parse_error(p, tok.loc, "multiple storage classes")
          }
          is_typedef = true
        } else {
          add_parse_error(p, tok.loc, "unexpected typedef")
        }
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwExtern | KwStatic | KwAuto | KwRegister | KwInline =>
        if allow_storage {
          match tok.kind {
            KwInline => is_inline = true
            KwExtern => {
              if storage != StorageClass::Default || is_typedef {
                add_parse_error(p, tok.loc, "multiple storage classes")
              }
              storage = StorageClass::Extern
            }
            KwStatic => {
              if storage != StorageClass::Default || is_typedef {
                add_parse_error(p, tok.loc, "multiple storage classes")
              }
              storage = StorageClass::Static
            }
            KwAuto => {
              if storage != StorageClass::Default || is_typedef {
                add_parse_error(p, tok.loc, "multiple storage classes")
              }
              storage = StorageClass::Auto
            }
            KwRegister => {
              if storage != StorageClass::Default || is_typedef {
                add_parse_error(p, tok.loc, "multiple storage classes")
              }
              storage = StorageClass::Register
            }
            _ => ()
          }
          ignore(advance_token(p))
          saw_any = true
          continue
        } else {
          add_parse_error(p, tok.loc, "storage class not allowed here")
          ignore(advance_token(p))
          saw_any = true
          continue
        }
      KwConst => {
        qual = with_const(qual)
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwVolatile => {
        qual = with_volatile(qual)
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwRestrict => {
        qual = with_restrict(qual)
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwAttribute => {
        let clause = parse_attribute_clause(p, tok.loc)
        attrs = merge_attrs(attrs, clause)
        continue
      }
      KwSigned => {
        if signedness == 2 {
          add_parse_error(p, tok.loc, "signed/unsigned conflict")
        } else {
          signedness = 1
        }
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwUnsigned => {
        if signedness == 1 {
          add_parse_error(p, tok.loc, "signed/unsigned conflict")
        } else {
          signedness = 2
        }
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwShort => {
        short_seen = true
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwLong => {
        long_count = long_count + 1
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwInt => {
        saw_int = true
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwChar => {
        saw_char = true
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwBool => {
        saw_bool = true
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwFloat => {
        saw_float = true
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwDouble => {
        saw_double = true
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwVoid => {
        saw_void = true
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwStruct =>
        match base {
          Some(_) => {
            add_parse_error(p, tok.loc, "multiple type specifiers")
            break
          }
          None =>
            match parse_struct_type(p, is_union=false) {
              Some((ty, loc)) => {
                base = Some(ty)
                start_loc = loc
                saw_any = true
                continue
              }
              None => return None
            }
        }
      KwUnion =>
        match base {
          Some(_) => {
            add_parse_error(p, tok.loc, "multiple type specifiers")
            break
          }
          None =>
            match parse_struct_type(p, is_union=true) {
              Some((ty, loc)) => {
                base = Some(ty)
                start_loc = loc
                saw_any = true
                continue
              }
              None => return None
            }
        }
      KwEnum =>
        match base {
          Some(_) => {
            add_parse_error(p, tok.loc, "multiple type specifiers")
            break
          }
          None =>
            match parse_enum_type(p) {
              Some((ty, loc)) => {
                base = Some(ty)
                start_loc = loc
                saw_any = true
                continue
              }
              None => return None
            }
        }
      KwTypeof =>
        match base {
          Some(_) => {
            add_parse_error(p, tok.loc, "multiple type specifiers")
            ignore(advance_token(p))
            continue
          }
          None =>
            match parse_typeof_spec(p, tok.loc) {
              Some(ty) => {
                base = Some(ty)
                start_loc = tok.loc
                saw_any = true
                continue
              }
              None => return None
            }
        }
      Ident =>
        match lookup_typedef(p, tok.lexeme) {
          Some(aliased) =>
            if base is Some(_) ||
              saw_void ||
              saw_bool ||
              saw_float ||
              saw_double ||
              saw_char ||
              saw_int ||
              short_seen ||
              long_count > 0 ||
              signedness != 0 {
              break
            } else {
              ignore(advance_token(p))
              base = Some(aliased)
              start_loc = tok.loc
              saw_any = true
              continue
            }
          None => ()
        }
      _ => ()
    }
    break
  }
  if !saw_any {
    return None
  }
  let invalid_combo = saw_void ||
    saw_bool ||
    saw_float ||
    saw_double ||
    saw_char ||
    saw_int ||
    short_seen ||
    long_count > 0 ||
    signedness != 0
  if base is Some(_) && invalid_combo {
    add_parse_error(p, start_loc, "invalid type specifier combination")
  }
  let ty = match base {
    Some(val) => val
    None =>
      if saw_void {
        CType::Void
      } else if saw_bool {
        CType::Bool
      } else if saw_float || saw_double {
        if long_count > 0 && saw_double {
          CType::Float(kind=CFloatKind::LongDouble)
        } else if saw_double {
          CType::Float(kind=CFloatKind::Double)
        } else if long_count > 0 {
          add_parse_error(p, start_loc, "invalid long float")
          CType::Float(kind=CFloatKind::Float)
        } else {
          CType::Float(kind=CFloatKind::Float)
        }
      } else {
        let kind = if saw_char {
          CIntKind::Char
        } else if short_seen {
          CIntKind::Short
        } else if long_count >= 2 {
          CIntKind::LongLong
        } else if long_count == 1 {
          CIntKind::Long
        } else {
          CIntKind::Int
        }
        let unsigned = signedness == 2
        CType::Int(kind~, unsigned~)
      }
  }
  if ty is CType::Void && (signedness != 0 || short_seen || long_count > 0) {
    add_parse_error(p, start_loc, "invalid modifiers for void")
  }
  if ty is CType::Bool && signedness != 0 {
    add_parse_error(p, start_loc, "invalid modifiers for _Bool")
  }
  let qualified = apply_qualifiers(ty, qual)
  let final_ty = apply_type_attrs(qualified, type_attrs_from(attrs))
  Some({ ty: final_ty, loc: start_loc, is_typedef, storage, is_inline, attrs })
}

///|
fn parse_decl_specs(p : Parser, allow_storage? : Bool = true) -> DeclSpecs? {
  parse_type_specifiers(p, allow_storage~, allow_typedef=true)
}

///|

///|
fn is_type_spec_start(p : Parser) -> Bool {
  match peek_token(p).kind {
    KwVoid
    | KwBool
    | KwChar
    | KwInt
    | KwFloat
    | KwDouble
    | KwShort
    | KwLong
    | KwStruct
    | KwUnion
    | KwEnum
    | KwConst
    | KwVolatile
    | KwRestrict
    | KwSigned
    | KwUnsigned
    | KwAttribute
    | KwTypeof => true
    Ident => has_typedef(p, peek_token(p).lexeme)
    _ => false
  }
}

///|
fn parse_typeof_spec(p : Parser, loc : SrcLoc) -> CType? {
  ignore(advance_token(p))
  if match_token(p, LParen) is None {
    add_parse_error(p, loc, "expected '(' after typeof")
    return None
  }
  if is_type_spec_start(p) {
    match parse_type_name(p) {
      None => {
        add_parse_error(p, loc, "expected type name in typeof")
        return None
      }
      Some(ty) => {
        expect(p, RParen, "expected ')' after typeof type") |> ignore
        return Some(ty)
      }
    }
  }
  let expr = parse_expr(p)
  expect(p, RParen, "expected ')' after typeof expression") |> ignore
  Some(CType::TypeofExpr(expr~))
}

///|
fn normalize_attr_name(name : String) -> String {
  name.trim(chars="_").to_string().to_lower()
}

///|
fn parse_attr_string(p : Parser, loc : SrcLoc) -> String? {
  if peek_token(p).kind != StrLit {
    add_parse_error(p, loc, "expected string literal in attribute")
    return None
  }
  let sb = StringBuilder::new()
  let tok = advance_token(p)
  let (part, _len) = decode_string_literal(p, tok.lexeme, tok.loc)
  sb.write_string(part)
  while peek_token(p).kind == StrLit {
    let next_tok = advance_token(p)
    let (next_part, _next_len) = decode_string_literal(
      p,
      next_tok.lexeme,
      next_tok.loc,
    )
    sb.write_string(next_part)
  }
  Some(sb.to_string())
}

///|
fn parse_static_assert(p : Parser, loc : SrcLoc) -> StaticAssert {
  expect(p, LParen, "expected '(' after _Static_assert") |> ignore
  let expr = parse_expr_cond(p)
  let mut message : String? = None
  if match_token(p, Comma) is Some(_) {
    message = parse_attr_string(p, loc)
  }
  expect(p, RParen, "expected ')' after _Static_assert") |> ignore
  { expr, message, loc }
}

///|
fn parse_asm_label(p : Parser, loc : SrcLoc) -> String? {
  expect(p, LParen, "expected '(' after asm") |> ignore
  let label = parse_attr_string(p, loc)
  expect(p, RParen, "expected ')' after asm label") |> ignore
  label
}

///|
fn parse_asm_operands(p : Parser) -> Array[AsmOperand] {
  let operands : Array[AsmOperand] = []
  if peek_token(p).kind == Colon || peek_token(p).kind == RParen {
    return operands
  }
  while true {
    let start_loc = peek_token(p).loc
    let name = if match_token(p, LBracket) is Some(_) {
      let id = match expect_ident(p, "expected asm operand name") {
        None => ""
        Some(tok) => tok.lexeme
      }
      expect(p, RBracket, "expected ']' after asm operand name") |> ignore
      if id == "" {
        None
      } else {
        Some(id)
      }
    } else {
      None
    }
    let constraint = match parse_attr_string(p, start_loc) {
      None => ""
      Some(value) => value
    }
    expect(p, LParen, "expected '(' after asm constraint") |> ignore
    let expr = parse_expr(p)
    expect(p, RParen, "expected ')' after asm operand") |> ignore
    operands.push({ name, constraint, expr, loc: start_loc })
    if match_token(p, Comma) is Some(_) {
      continue
    }
    break
  }
  operands
}

///|
fn parse_asm_clobbers(p : Parser) -> Array[String] {
  let clobbers : Array[String] = []
  if peek_token(p).kind == Colon || peek_token(p).kind == RParen {
    return clobbers
  }
  while true {
    let loc = peek_token(p).loc
    match parse_attr_string(p, loc) {
      None => ()
      Some(value) => clobbers.push(value)
    }
    if match_token(p, Comma) is Some(_) {
      continue
    }
    break
  }
  clobbers
}

///|
fn parse_asm_labels(p : Parser) -> Array[String] {
  let labels : Array[String] = []
  if peek_token(p).kind == Colon || peek_token(p).kind == RParen {
    return labels
  }
  while true {
    let name = match expect_ident(p, "expected label identifier") {
      None => ""
      Some(tok) => tok.lexeme
    }
    if name != "" {
      labels.push(name)
    }
    if match_token(p, Comma) is Some(_) {
      continue
    }
    break
  }
  labels
}

///|
fn parse_asm_stmt(p : Parser, loc : SrcLoc) -> AsmStmt {
  let mut is_volatile = false
  let mut is_goto = false
  while true {
    if match_token(p, KwVolatile) is Some(_) {
      is_volatile = true
      continue
    }
    if match_token(p, KwGoto) is Some(_) {
      is_goto = true
      continue
    }
    break
  }
  expect(p, LParen, "expected '(' after asm") |> ignore
  let template = match parse_attr_string(p, loc) {
    None => ""
    Some(value) => value
  }
  let mut outputs : Array[AsmOperand] = []
  let mut inputs : Array[AsmOperand] = []
  let mut clobbers : Array[String] = []
  let mut labels : Array[String] = []
  if match_token(p, Colon) is Some(_) {
    outputs = parse_asm_operands(p)
    if match_token(p, Colon) is Some(_) {
      inputs = parse_asm_operands(p)
      if match_token(p, Colon) is Some(_) {
        clobbers = parse_asm_clobbers(p)
        if match_token(p, Colon) is Some(_) {
          labels = parse_asm_labels(p)
        }
      }
    }
  }
  expect(p, RParen, "expected ')' after asm") |> ignore
  { template, outputs, inputs, clobbers, labels, is_volatile, is_goto, loc }
}

///|
fn is_attr_name_token(kind : TokenKind) -> Bool {
  match kind {
    Ident | KwConst | KwVolatile | KwRestrict | KwInline | KwSigned => true
    _ => false
  }
}

///|
fn skip_paren_group(p : Parser) -> Unit {
  let mut depth = 1
  while depth > 0 && !is_at_end(p) {
    let tok = advance_token(p)
    match tok.kind {
      LParen => depth = depth + 1
      RParen => depth = depth - 1
      _ => ()
    }
  }
}

///|
fn parse_attribute_clause(p : Parser, loc : SrcLoc) -> Attributes {
  let mut attrs = empty_attrs()
  ignore(advance_token(p))
  if match_token(p, LParen) is None {
    add_parse_error(p, loc, "expected '(' after attribute")
    return attrs
  }
  if match_token(p, LParen) is None {
    add_parse_error(p, loc, "expected '(' after attribute")
    return attrs
  }
  while !is_at_end(p) && peek_token(p).kind != RParen {
    let name_tok = peek_token(p)
    if !is_attr_name_token(name_tok.kind) {
      add_parse_error(p, name_tok.loc, "expected attribute name")
      break
    }
    ignore(advance_token(p))
    let name = normalize_attr_name(name_tok.lexeme)
    let mut has_args = false
    if match_token(p, LParen) is Some(_) {
      has_args = true
    }
    match name {
      "aligned" => {
        let spec = if has_args {
          if peek_token(p).kind == RParen {
            AlignSpec::Default
          } else {
            let expr = parse_expr_cond(p)
            AlignSpec::Expr(expr~)
          }
        } else {
          AlignSpec::Default
        }
        attrs = merge_attrs(attrs, attrs_with(aligned=Some(spec)))
        if has_args {
          expect(p, RParen, "expected ')' after aligned attribute") |> ignore
        }
      }
      "packed" => {
        attrs = merge_attrs(attrs, attrs_with(packed=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "weak" => {
        attrs = merge_attrs(attrs, attrs_with(weak=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "noreturn" => {
        attrs = merge_attrs(attrs, attrs_with(noreturn=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "constructor" => {
        attrs = merge_attrs(attrs, attrs_with(constructor=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "destructor" => {
        attrs = merge_attrs(attrs, attrs_with(destructor=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "always_inline" => {
        attrs = merge_attrs(attrs, attrs_with(always_inline=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "section" =>
        if !has_args {
          add_parse_error(p, name_tok.loc, "expected '(' after section")
        } else {
          let section = parse_attr_string(p, name_tok.loc)
          attrs = merge_attrs(attrs, attrs_with(section~))
          expect(p, RParen, "expected ')' after section") |> ignore
        }
      "alias" =>
        if !has_args {
          add_parse_error(p, name_tok.loc, "expected '(' after alias")
        } else {
          let alias = parse_attr_string(p, name_tok.loc)
          attrs = merge_attrs(attrs, attrs_with(alias~))
          expect(p, RParen, "expected ')' after alias") |> ignore
        }
      "visibility" =>
        if !has_args {
          add_parse_error(p, name_tok.loc, "expected '(' after visibility")
        } else {
          let vis = parse_attr_string(p, name_tok.loc)
          let value = match vis {
            Some("default") => Some(Visibility::Default)
            Some("hidden") => Some(Visibility::Hidden)
            Some("internal") => Some(Visibility::Internal)
            Some("protected") => Some(Visibility::Protected)
            Some(_) => {
              add_parse_error(
                p,
                name_tok.loc,
                "expected visibility(\"default|hidden|internal|protected\")",
              )
              None
            }
            None => None
          }
          attrs = merge_attrs(attrs, attrs_with(visibility=value))
          expect(p, RParen, "expected ')' after visibility") |> ignore
        }
      "cleanup" =>
        if !has_args {
          add_parse_error(p, name_tok.loc, "expected '(' after cleanup")
        } else {
          match expect_ident(p, "expected cleanup function name") {
            None => ()
            Some(id) =>
              attrs = merge_attrs(attrs, attrs_with(cleanup=Some(id.lexeme)))
          }
          expect(p, RParen, "expected ')' after cleanup") |> ignore
        }
      "cdecl" => {
        attrs = merge_attrs(attrs, attrs_with(call_conv=Some(CallConv::Cdecl)))
        if has_args {
          skip_paren_group(p)
        }
      }
      "stdcall" => {
        attrs = merge_attrs(
          attrs,
          attrs_with(call_conv=Some(CallConv::Stdcall)),
        )
        if has_args {
          skip_paren_group(p)
        }
      }
      "fastcall" => {
        attrs = merge_attrs(
          attrs,
          attrs_with(call_conv=Some(CallConv::Fastcall)),
        )
        if has_args {
          skip_paren_group(p)
        }
      }
      "thiscall" => {
        attrs = merge_attrs(
          attrs,
          attrs_with(call_conv=Some(CallConv::Thiscall)),
        )
        if has_args {
          skip_paren_group(p)
        }
      }
      "regparm" =>
        if !has_args {
          add_parse_error(p, name_tok.loc, "expected '(' after regparm")
        } else {
          let raw = if peek_token(p).kind == IntLit {
            let tok = advance_token(p)
            let parsed = try @strconv.parse_int(tok.lexeme, base=0) catch {
              _ => 0
            } noraise {
              v => v
            }
            expect(p, RParen, "expected ')' after regparm") |> ignore
            parsed
          } else {
            skip_paren_group(p)
            0
          }
          let mut count = raw
          if count < 0 {
            count = 0
          } else if count > 3 {
            count = 3
          }
          if count > 0 {
            attrs = merge_attrs(
              attrs,
              attrs_with(call_conv=Some(CallConv::Regparm(count~))),
            )
          }
        }
      "dllimport" => {
        attrs = merge_attrs(attrs, attrs_with(dll_import=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "dllexport" => {
        attrs = merge_attrs(attrs, attrs_with(dll_export=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "nodecorate" => {
        attrs = merge_attrs(attrs, attrs_with(nodecorate=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "nodebug" => {
        attrs = merge_attrs(attrs, attrs_with(nodebug=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      _ => if has_args { skip_paren_group(p) }
    }
    if match_token(p, Comma) is Some(_) {
      continue
    }
    break
  }
  expect(p, RParen, "expected ')' after attribute list") |> ignore
  expect(p, RParen, "expected ')' after attribute") |> ignore
  attrs
}

///|
fn parse_attributes(p : Parser) -> Attributes {
  let mut attrs = empty_attrs()
  while peek_token(p).kind == KwAttribute {
    let clause = parse_attribute_clause(p, peek_token(p).loc)
    attrs = merge_attrs(attrs, clause)
  }
  attrs
}

///|
fn parse_pointer_chain(p : Parser, ty_in : CType) -> (CType, Attributes) {
  let mut ty = ty_in
  let mut attrs = empty_attrs()
  while match_token(p, Star) is Some(_) {
    let qual = parse_type_qualifiers(p)
    let pointer_attrs = parse_attributes(p)
    attrs = merge_attrs(attrs, pointer_attrs)
    ty = CType::Pointer(ty)
    ty = apply_qualifiers(ty, qual)
  }
  (ty, attrs)
}

///|
fn parse_type_name(p : Parser) -> CType? {
  match parse_type_specifiers(p, allow_storage=false, allow_typedef=false) {
    None => None
    Some(specs) => {
      let base = specs.ty
      let base_attrs = specs.attrs
      if is_paren_pointer_declarator(p) {
        let (ty, pointer_attrs) = parse_paren_pointer_abstract(p, base)
        let combined_attrs = merge_attrs(base_attrs, pointer_attrs)
        let call_conv = normalize_call_conv(combined_attrs.call_conv)
        Some(apply_call_conv_to_type(ty, call_conv))
      } else {
        let (ty, pointer_attrs) = parse_pointer_chain(p, base)
        let (full, _params, _varargs, _old_style, suffix_attrs) = parse_declarator_suffix(
          p, ty,
        )
        let combined_attrs = merge_attrs(
          merge_attrs(base_attrs, pointer_attrs),
          suffix_attrs,
        )
        let call_conv = normalize_call_conv(combined_attrs.call_conv)
        Some(apply_call_conv_to_type(full, call_conv))
      }
    }
  }
}

///|
struct Declarator {
  name : String
  ty : CType
  params : Array[Param]?
  varargs : Bool
  is_old_style : Bool
  attrs : Attributes
  loc : SrcLoc
}

///|
fn parse_declarator(p : Parser, base : CType) -> Declarator? {
  if is_paren_pointer_declarator(p) {
    return parse_paren_pointer_declarator(p, base)
  }
  let (ty, pointer_attrs) = parse_pointer_chain(p, base)
  let mut attrs = merge_attrs(pointer_attrs, parse_attributes(p))
  let name_tok = expect_ident(p, "expected identifier")
  match name_tok {
    None => None
    Some(tok) => {
      let (ty, params, varargs, is_old_style, suffix_attrs) = parse_declarator_suffix(
        p, ty,
      )
      attrs = merge_attrs(attrs, suffix_attrs)
      if match_token(p, KwAsm) is Some(asm_tok) {
        match parse_asm_label(p, asm_tok.loc) {
          None => ()
          Some(label) =>
            attrs = merge_attrs(attrs, attrs_with(asm_label=Some(label)))
        }
        attrs = merge_attrs(attrs, parse_attributes(p))
      }
      Some({
        name: tok.lexeme,
        ty,
        params,
        varargs,
        is_old_style,
        attrs,
        loc: tok.loc,
      })
    }
  }
}

///|
fn parse_init_declarator(
  p : Parser,
  base : CType,
) -> (Declarator, Initializer?)? {
  match parse_declarator(p, base) {
    None => None
    Some(decl) => {
      let init = if match_token(p, Assign) is Some(_) {
        Some(parse_initializer(p))
      } else {
        None
      }
      Some((decl, init))
    }
  }
}

///|
fn parse_field_declarator(
  p : Parser,
  base : CType,
  fallback_loc : SrcLoc,
) -> Declarator? {
  if is_paren_pointer_declarator(p) {
    expect(p, LParen, "expected '(' in declarator") |> ignore
    let quals : Array[TypeQual] = []
    let mut attrs = parse_attributes(p)
    while match_token(p, Star) is Some(_) {
      quals.push(parse_type_qualifiers(p))
      attrs = merge_attrs(attrs, parse_attributes(p))
    }
    attrs = merge_attrs(attrs, parse_attributes(p))
    let name_tok = if peek_token(p).kind == Ident {
      Some(advance_token(p))
    } else {
      None
    }
    expect(p, RParen, "expected ')' in declarator") |> ignore
    let (ty, params, varargs, is_old_style, suffix_attrs) = parse_declarator_suffix(
      p, base,
    )
    attrs = merge_attrs(attrs, suffix_attrs)
    let mut wrapped = ty
    for qual in quals {
      wrapped = CType::Pointer(wrapped)
      wrapped = apply_qualifiers(wrapped, qual)
    }
    let (name, loc) = match name_tok {
      Some(tok) => (tok.lexeme, tok.loc)
      None => ("", fallback_loc)
    }
    return Some({ name, ty: wrapped, params, varargs, is_old_style, attrs, loc })
  }
  let (ty, pointer_attrs) = parse_pointer_chain(p, base)
  let mut attrs = merge_attrs(pointer_attrs, parse_attributes(p))
  let (name, loc) = if peek_token(p).kind == Ident {
    let name_tok = advance_token(p)
    (name_tok.lexeme, name_tok.loc)
  } else {
    ("", fallback_loc)
  }
  let (ty, params, varargs, is_old_style, suffix_attrs) = parse_declarator_suffix(
    p, ty,
  )
  attrs = merge_attrs(attrs, suffix_attrs)
  Some({ name, ty, params, varargs, is_old_style, attrs, loc })
}

///|
fn parse_initializer(p : Parser) -> Initializer {
  if match_token(p, LBrace) is Some(lbrace) {
    let items : Array[InitItem] = []
    if match_token(p, RBrace) is Some(_) {
      return Initializer::List(items~, loc=lbrace.loc)
    }
    while true {
      let (designators, item_loc) = parse_designator_list(p)
      let value = parse_initializer(p)
      items.push({ designators, value, loc: item_loc })
      if match_token(p, Comma) is Some(_) {
        if match_token(p, RBrace) is Some(_) {
          break
        }
        continue
      }
      expect(p, RBrace, "expected '}' after initializer list") |> ignore
      break
    }
    return Initializer::List(items~, loc=lbrace.loc)
  }
  let expr = parse_expr_eq(p)
  Initializer::Expr(expr~, loc=expr_loc(expr))
}

///|
fn parse_designator_list(p : Parser) -> (Array[InitDesignator], SrcLoc) {
  let designators : Array[InitDesignator] = []
  let mut start_loc = peek_token(p).loc
  while true {
    if match_token(p, Dot) is Some(dot_tok) {
      start_loc = dot_tok.loc
      let name = match expect_ident(p, "expected field name") {
        None => ""
        Some(id) => id.lexeme
      }
      designators.push(InitDesignator::Field(name~, loc=dot_tok.loc))
      continue
    }
    if match_token(p, LBracket) is Some(lbrack) {
      start_loc = lbrack.loc
      let index = parse_expr_cond(p)
      expect(p, RBracket, "expected ']' after designator") |> ignore
      designators.push(InitDesignator::Index(expr=index, loc=lbrack.loc))
      continue
    }
    if peek_token(p).kind == Ident && peek_kind(p, 1) == Colon {
      let name_tok = advance_token(p)
      start_loc = name_tok.loc
      expect(p, Colon, "expected ':' after designator") |> ignore
      designators.push(
        InitDesignator::Field(name=name_tok.lexeme, loc=name_tok.loc),
      )
      continue
    }
    break
  }
  if designators.length() > 0 {
    if match_token(p, Assign) is None {
      add_parse_error(p, peek_token(p).loc, "expected '=' after designator")
    }
  }
  (designators, start_loc)
}

///|
fn is_paren_pointer_declarator(p : Parser) -> Bool {
  if peek_kind(p, 0) != LParen {
    return false
  }
  let mut depth = 0
  let mut i = 1
  while true {
    match peek_kind(p, i) {
      Eof => return false
      LParen => depth = depth + 1
      RParen => if depth == 0 { return false } else { depth = depth - 1 }
      Star => if depth == 0 { return true }
      _ => ()
    }
    i = i + 1
  }
  false
}

///|
fn parse_paren_pointer_declarator(p : Parser, base : CType) -> Declarator? {
  expect(p, LParen, "expected '(' in declarator") |> ignore
  let quals : Array[TypeQual] = []
  let mut attrs = parse_attributes(p)
  while match_token(p, Star) is Some(_) {
    quals.push(parse_type_qualifiers(p))
    attrs = merge_attrs(attrs, parse_attributes(p))
  }
  attrs = merge_attrs(attrs, parse_attributes(p))
  let name_tok = expect_ident(p, "expected identifier")
  expect(p, RParen, "expected ')' in declarator") |> ignore
  match name_tok {
    None => None
    Some(tok) => {
      let (ty, params, varargs, is_old_style, suffix_attrs) = parse_declarator_suffix(
        p, base,
      )
      attrs = merge_attrs(attrs, suffix_attrs)
      if match_token(p, KwAsm) is Some(asm_tok) {
        match parse_asm_label(p, asm_tok.loc) {
          None => ()
          Some(label) =>
            attrs = merge_attrs(attrs, attrs_with(asm_label=Some(label)))
        }
        attrs = merge_attrs(attrs, parse_attributes(p))
      }
      let mut wrapped = ty
      for qual in quals {
        wrapped = CType::Pointer(wrapped)
        wrapped = apply_qualifiers(wrapped, qual)
      }
      Some({
        name: tok.lexeme,
        ty: wrapped,
        params,
        varargs,
        is_old_style,
        attrs,
        loc: tok.loc,
      })
    }
  }
}

///|
fn parse_paren_pointer_abstract(
  p : Parser,
  base : CType,
) -> (CType, Attributes) {
  expect(p, LParen, "expected '(' in declarator") |> ignore
  let quals : Array[TypeQual] = []
  let mut attrs = parse_attributes(p)
  while match_token(p, Star) is Some(_) {
    quals.push(parse_type_qualifiers(p))
    attrs = merge_attrs(attrs, parse_attributes(p))
  }
  attrs = merge_attrs(attrs, parse_attributes(p))
  expect(p, RParen, "expected ')' in declarator") |> ignore
  let (ty, _params, _varargs, _old_style, suffix_attrs) = parse_declarator_suffix(
    p, base,
  )
  attrs = merge_attrs(attrs, suffix_attrs)
  let mut wrapped = ty
  for qual in quals {
    wrapped = CType::Pointer(wrapped)
    wrapped = apply_qualifiers(wrapped, qual)
  }
  (wrapped, attrs)
}

///|
fn parse_declarator_suffix(
  p : Parser,
  ty_in : CType,
) -> (CType, Array[Param]?, Bool, Bool, Attributes) {
  let mut ty = ty_in
  let mut varargs = false
  let mut old_style = false
  let mut attrs = parse_attributes(p)
  while match_token(p, LBracket) is Some(_) {
    let size = parse_array_size(p)
    expect(p, RBracket, "expected ']' after array size") |> ignore
    ty = CType::Array(elem=ty, size~)
  }
  let params = if match_token(p, LParen) is Some(_) {
    let (params, has_varargs, is_old_style) = parse_param_list(p)
    varargs = has_varargs
    old_style = is_old_style
    let param_types = params.map(param => param.ty)
    ty = CType::Function(
      return_type=ty,
      params=param_types,
      varargs~,
      is_old_style=old_style,
      call_conv=CallConv::Default,
    )
    Some(params)
  } else {
    None
  }
  attrs = merge_attrs(attrs, parse_attributes(p))
  let call_conv = normalize_call_conv(attrs.call_conv)
  ty = apply_call_conv_to_type(ty, call_conv)
  (ty, params, varargs, old_style, attrs)
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
fn next_anon_tag(p : Parser) -> String {
  p.anon_tag_id = p.anon_tag_id + 1
  "__anon_tag_\{p.anon_tag_id}"
}

///|
fn parse_struct_type(p : Parser, is_union~ : Bool) -> (CType, SrcLoc)? {
  let kw = advance_token(p)
  let mut attrs = parse_attributes(p)
  let mut name = if peek_token(p).kind == Ident {
    advance_token(p).lexeme
  } else {
    ""
  }
  attrs = merge_attrs(attrs, parse_attributes(p))
  if match_token(p, LBrace) is Some(_) {
    let fields = parse_struct_fields(p)
    expect(p, RBrace, "expected '}' after fields") |> ignore
    attrs = merge_attrs(attrs, parse_attributes(p))
    if name == "" {
      name = next_anon_tag(p)
    }
    let ty = if is_union {
      CType::Union(name~, fields=Some(fields), attrs~)
    } else {
      CType::Struct(name~, fields=Some(fields), attrs~)
    }
    return Some((ty, kw.loc))
  }
  if name == "" {
    add_parse_error(p, kw.loc, "expected tag name or '{'")
    return None
  }
  let ty = if is_union {
    CType::Union(name~, fields=None, attrs~)
  } else {
    CType::Struct(name~, fields=None, attrs~)
  }
  Some((ty, kw.loc))
}

///|
fn parse_struct_fields(p : Parser) -> Array[RecordItem] {
  let items : Array[RecordItem] = []
  while !is_at_end(p) && peek_token(p).kind != RBrace {
    if match_token(p, KwStaticAssert) is Some(assert_tok) {
      let static_assert = parse_static_assert(p, assert_tok.loc)
      expect(p, Semicolon, "expected ';' after _Static_assert") |> ignore
      items.push(RecordItem::StaticAssert(static_assert))
      continue
    }
    match parse_decl_specs(p, allow_storage=false) {
      None => {
        synchronize(p)
        break
      }
      Some(specs) => {
        let base = apply_type_attrs(specs.ty, type_attrs_from(specs.attrs))
        let loc = specs.loc
        let is_typedef = specs.is_typedef
        if is_typedef {
          add_parse_error(p, loc, "typedef not allowed in struct field")
        }
        let mut any_field = false
        while true {
          let decl = if peek_token(p).kind == Colon {
            Some({
              name: "",
              ty: base,
              params: None,
              varargs: false,
              is_old_style: false,
              attrs: empty_attrs(),
              loc,
            })
          } else {
            parse_field_declarator(p, base, loc)
          }
          let bit_width = if match_token(p, Colon) is Some(_) {
            Some(parse_expr_cond(p))
          } else {
            None
          }
          match decl {
            None => ()
            Some(field_decl) => {
              let stripped = strip_type_qualifiers(field_decl.ty)
              let allow_anon = field_decl.name == "" &&
                bit_width is None &&
                (stripped is CType::Struct(..) || stripped is CType::Union(..))
              if field_decl.name != "" || bit_width is Some(_) || allow_anon {
                any_field = true
                let combined_attrs = merge_attrs(specs.attrs, field_decl.attrs)
                let adjusted_ty = apply_call_conv_to_type(
                  field_decl.ty,
                  normalize_call_conv(combined_attrs.call_conv),
                )
                items.push(
                  RecordItem::Field({
                    name: field_decl.name,
                    ty: adjusted_ty,
                    bit_width,
                    attrs: combined_attrs,
                    loc: field_decl.loc,
                  }),
                )
              } else {
                add_parse_error(p, loc, "expected field declarator")
              }
            }
          }
          if match_token(p, Comma) is Some(_) {
            continue
          }
          break
        }
        if !any_field {
          add_parse_error(p, loc, "expected field declarator")
        }
        expect(p, Semicolon, "expected ';' after struct field") |> ignore
      }
    }
  }
  items
}

///|
fn parse_enum_type(p : Parser) -> (CType, SrcLoc)? {
  let kw = advance_token(p)
  let mut name = if peek_token(p).kind == Ident {
    advance_token(p).lexeme
  } else {
    ""
  }
  if match_token(p, LBrace) is Some(_) {
    let items = parse_enum_items(p)
    expect(p, RBrace, "expected '}' after enum") |> ignore
    if name == "" {
      name = next_anon_tag(p)
    }
    return Some((CType::Enum(name~, items=Some(items)), kw.loc))
  }
  if name == "" {
    add_parse_error(p, kw.loc, "expected enum name or '{'")
    return None
  }
  Some((CType::Enum(name~, items=None), kw.loc))
}

///|
fn parse_enum_items(p : Parser) -> Array[EnumItem] {
  let items : Array[EnumItem] = []
  if peek_token(p).kind == RBrace {
    return items
  }
  while true {
    let name_tok = expect_ident(p, "expected enumerator name")
    match name_tok {
      None => ()
      Some(tok) => {
        let value = if match_token(p, Assign) is Some(_) {
          Some(parse_expr_cond(p))
        } else {
          None
        }
        items.push({ name: tok.lexeme, value, loc: tok.loc })
      }
    }
    if match_token(p, Comma) is Some(_) {
      if peek_token(p).kind == RBrace {
        break
      }
      continue
    }
    break
  }
  items
}

///|
fn parse_param_list(p : Parser) -> (Array[Param], Bool, Bool) {
  let params : Array[Param] = []
  let mut varargs = false
  let mut old_style = false
  if match_token(p, RParen) is Some(_) {
    old_style = true
    return (params, varargs, old_style)
  }
  if match_token(p, Ellipsis) is Some(_) {
    expect(p, RParen, "expected ')' after '...'") |> ignore
    return (params, true, false)
  }
  let first = peek_token(p)
  if first.kind == Ident && !has_typedef(p, first.lexeme) {
    old_style = true
    while true {
      match expect_ident(p, "expected parameter name") {
        None => break
        Some(tok) =>
          params.push({
            name: tok.lexeme,
            ty: CType::Int(kind=CIntKind::Int, unsigned=false),
            loc: tok.loc,
          })
      }
      if match_token(p, Comma) is Some(_) {
        continue
      }
      break
    }
    expect(p, RParen, "expected ')' after parameter list") |> ignore
    return (params, varargs, old_style)
  }
  if peek_token(p).kind == KwVoid {
    let void_tok = advance_token(p)
    if match_token(p, RParen) is Some(_) {
      return (params, varargs, false)
    }
    match parse_param_after_base(p, CType::Void, empty_attrs(), void_tok.loc) {
      Some(param) => params.push(param)
      None => ()
    }
  } else {
    match parse_type_specifiers(p, allow_storage=false, allow_typedef=false) {
      Some(specs) =>
        match parse_param_after_base(p, specs.ty, specs.attrs, specs.loc) {
          Some(param) => params.push(param)
          None => ()
        }
      None => ()
    }
  }
  while true {
    if match_token(p, Comma) is Some(_) {
      if match_token(p, Ellipsis) is Some(_) {
        varargs = true
        expect(p, RParen, "expected ')' after '...'") |> ignore
        break
      }
      match parse_type_specifiers(p, allow_storage=false, allow_typedef=false) {
        Some(specs) =>
          match parse_param_after_base(p, specs.ty, specs.attrs, specs.loc) {
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
  (params, varargs, old_style)
}

///|
fn parse_param_after_base(
  p : Parser,
  base : CType,
  attrs : Attributes,
  loc : SrcLoc,
) -> Param? {
  match parse_param_declarator(p, base, loc) {
    Some(param) => {
      let call_conv = normalize_call_conv(attrs.call_conv)
      let adjusted_ty = apply_call_conv_to_type(param.ty, call_conv)
      Some({ name: param.name, ty: adjusted_ty, loc: param.loc })
    }
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
    let quals : Array[TypeQual] = []
    let mut attrs = parse_attributes(p)
    while match_token(p, Star) is Some(_) {
      quals.push(parse_type_qualifiers(p))
      attrs = merge_attrs(attrs, parse_attributes(p))
    }
    attrs = merge_attrs(attrs, parse_attributes(p))
    let name_tok = if peek_token(p).kind == Ident {
      Some(advance_token(p))
    } else {
      None
    }
    expect(p, RParen, "expected ')' in declarator") |> ignore
    let (ty, _params, _varargs, _old_style, suffix_attrs) = parse_declarator_suffix(
      p, base,
    )
    attrs = merge_attrs(attrs, suffix_attrs)
    let mut wrapped = ty
    for qual in quals {
      wrapped = CType::Pointer(wrapped)
      wrapped = apply_qualifiers(wrapped, qual)
    }
    let call_conv = normalize_call_conv(attrs.call_conv)
    let adjusted_ty = apply_call_conv_to_type(wrapped, call_conv)
    let (name, loc) = match name_tok {
      Some(tok) => (tok.lexeme, tok.loc)
      None => ("", fallback_loc)
    }
    return Some({ name, ty: adjusted_ty, loc })
  }
  let (ty, pointer_attrs) = parse_pointer_chain(p, base)
  let mut attrs = merge_attrs(pointer_attrs, parse_attributes(p))
  if peek_token(p).kind == Ident {
    let name_tok = advance_token(p)
    let (ty, _params, _varargs, _old_style, suffix_attrs) = parse_declarator_suffix(
      p, ty,
    )
    attrs = merge_attrs(attrs, suffix_attrs)
    let call_conv = normalize_call_conv(attrs.call_conv)
    let adjusted_ty = apply_call_conv_to_type(ty, call_conv)
    return Some({ name: name_tok.lexeme, ty: adjusted_ty, loc: name_tok.loc })
  }
  let call_conv = normalize_call_conv(attrs.call_conv)
  let adjusted_ty = apply_call_conv_to_type(ty, call_conv)
  Some({ name: "", ty: adjusted_ty, loc: fallback_loc })
}

///|
fn parse_compound_stmt(p : Parser, loc : SrcLoc) -> Stmt {
  push_typedef_scope(p)
  let stmts : Array[Stmt] = []
  while !is_at_end(p) && peek_token(p).kind != RBrace {
    stmts.push(parse_stmt(p))
  }
  expect(p, RBrace, "expected '}'") |> ignore
  pop_typedef_scope(p)
  Stmt::Compound(stmts~, loc~)
}

///|
fn parse_stmt(p : Parser) -> Stmt {
  let tok = peek_token(p)
  if match_token(p, LBrace) is Some(lbrace) {
    return parse_compound_stmt(p, lbrace.loc)
  }
  if match_token(p, KwStaticAssert) is Some(assert_tok) {
    let static_assert = parse_static_assert(p, assert_tok.loc)
    expect(p, Semicolon, "expected ';' after _Static_assert") |> ignore
    return Stmt::StaticAssert(static_assert)
  }
  if match_token(p, KwAsm) is Some(asm_tok) {
    let asm_stmt = parse_asm_stmt(p, asm_tok.loc)
    expect(p, Semicolon, "expected ';' after asm") |> ignore
    return Stmt::Asm(asm_stmt)
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
    ignore(parse_attributes(p))
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
      Some(specs) => {
        let base = specs.ty
        let is_typedef = specs.is_typedef
        let storage = specs.storage
        let is_inline = specs.is_inline
        let base_attrs = specs.attrs
        if match_token(p, Semicolon) is Some(semi) {
          if is_typedef {
            add_parse_error(p, semi.loc, "typedef requires a declarator")
            return Stmt::Empty(loc=semi.loc)
          }
          return Stmt::TagDef(ty=base, loc=semi.loc)
        } else {
          let decls : Array[VarDecl] = []
          let mut decl_loc = tok.loc
          let mut saw_decl = false
          while true {
            match parse_init_declarator(p, base) {
              None => {
                synchronize(p)
                return Stmt::Empty(loc=tok.loc)
              }
              Some((decl, init)) => {
                if !saw_decl {
                  decl_loc = decl.loc
                  saw_decl = true
                }
                let combined_attrs = merge_attrs(base_attrs, decl.attrs)
                let adjusted_ty = apply_call_conv_to_type(
                  decl.ty,
                  normalize_call_conv(combined_attrs.call_conv),
                )
                if is_typedef {
                  if init is Some(_) {
                    add_parse_error(
                      p,
                      decl.loc,
                      "typedef cannot have initializer",
                    )
                  }
                  let typedef_ty = apply_type_attrs(
                    adjusted_ty,
                    type_attrs_from(combined_attrs),
                  )
                  define_typedef(p, decl.name, typedef_ty)
                } else {
                  let mut actual_init = init
                  if adjusted_ty is CType::Function(..) &&
                    actual_init is Some(_) {
                    add_parse_error(
                      p,
                      decl.loc,
                      "function declaration cannot have initializer",
                    )
                    actual_init = None
                  }
                  if is_inline {
                    add_parse_error(
                      p,
                      decl.loc,
                      "inline can only apply to functions",
                    )
                  }
                  decls.push({
                    name: decl.name,
                    ty: adjusted_ty,
                    init: actual_init,
                    storage,
                    attrs: combined_attrs,
                    loc: decl.loc,
                  })
                }
              }
            }
            if match_token(p, Comma) is Some(_) {
              continue
            }
            break
          }
          expect(p, Semicolon, "expected ';' after declaration") |> ignore
          if is_typedef {
            return Stmt::Empty(loc=decl_loc)
          }
          if saw_decl {
            return Stmt::DeclStmt(decls~, loc=decl_loc)
          }
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
  push_typedef_scope(p)
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
  pop_typedef_scope(p)
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
      Some(specs) => {
        let base = specs.ty
        let is_typedef = specs.is_typedef
        let storage = specs.storage
        let is_inline = specs.is_inline
        let base_attrs = specs.attrs
        if match_token(p, Semicolon) is Some(semi) {
          if is_typedef {
            add_parse_error(p, semi.loc, "typedef requires a declarator")
            return None
          }
          return Some(Stmt::TagDef(ty=base, loc=semi.loc))
        } else {
          let decls : Array[VarDecl] = []
          let mut decl_loc = peek_token(p).loc
          let mut saw_decl = false
          while true {
            match parse_init_declarator(p, base) {
              None => {
                synchronize(p)
                return None
              }
              Some((decl, init)) => {
                if !saw_decl {
                  decl_loc = decl.loc
                  saw_decl = true
                }
                let combined_attrs = merge_attrs(base_attrs, decl.attrs)
                let adjusted_ty = apply_call_conv_to_type(
                  decl.ty,
                  normalize_call_conv(combined_attrs.call_conv),
                )
                if is_typedef {
                  if init is Some(_) {
                    add_parse_error(
                      p,
                      decl.loc,
                      "typedef cannot have initializer",
                    )
                  }
                  let typedef_ty = apply_type_attrs(
                    adjusted_ty,
                    type_attrs_from(combined_attrs),
                  )
                  define_typedef(p, decl.name, typedef_ty)
                } else {
                  let mut actual_init = init
                  if adjusted_ty is CType::Function(..) &&
                    actual_init is Some(_) {
                    add_parse_error(
                      p,
                      decl.loc,
                      "function declaration cannot have initializer",
                    )
                    actual_init = None
                  }
                  if is_inline {
                    add_parse_error(
                      p,
                      decl.loc,
                      "inline can only apply to functions",
                    )
                  }
                  decls.push({
                    name: decl.name,
                    ty: adjusted_ty,
                    init: actual_init,
                    storage,
                    attrs: combined_attrs,
                    loc: decl.loc,
                  })
                }
              }
            }
            if match_token(p, Comma) is Some(_) {
              continue
            }
            break
          }
          expect(p, Semicolon, "expected ';' after for declaration") |> ignore
          if is_typedef || !saw_decl {
            return None
          }
          return Some(Stmt::DeclStmt(decls~, loc=decl_loc))
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
  match match_assign_op(p) {
    None => left
    Some((op, tok)) => {
      let right = parse_expr_eq(p)
      Expr::Binary(op~, left~, right~, loc=tok.loc)
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
  if match_token(p, KwSizeof) is Some(tok) {
    if peek_kind(p, 0) == LParen && is_type_start(p, peek_token_at(p, 1)) {
      expect(p, LParen, "expected '(' after sizeof") |> ignore
      match parse_type_name(p) {
        None => {
          add_parse_error(p, tok.loc, "expected type name after sizeof")
          return Expr::IntLit(value="0", loc=tok.loc)
        }
        Some(ty) => {
          expect(p, RParen, "expected ')' after sizeof type") |> ignore
          return Expr::SizeofType(ty~, loc=tok.loc)
        }
      }
    }
    let expr = parse_expr_unary(p)
    return Expr::SizeofExpr(expr~, loc=tok.loc)
  }
  if peek_kind(p, 0) == LParen && is_type_start(p, peek_token_at(p, 1)) {
    let lparen = advance_token(p)
    match parse_type_name(p) {
      None => {
        add_parse_error(p, lparen.loc, "expected type name in cast")
        return Expr::IntLit(value="0", loc=lparen.loc)
      }
      Some(ty) => {
        expect(p, RParen, "expected ')' after cast type") |> ignore
        let expr = parse_expr_unary(p)
        return Expr::Cast(ty~, expr~, loc=lparen.loc)
      }
    }
  }
  match match_token(p, PlusPlus) {
    Some(tok) => {
      let expr = parse_expr_unary(p)
      return Expr::Unary(op=UnaryOp::PreInc, expr~, loc=tok.loc)
    }
    None => ()
  }
  match match_token(p, MinusMinus) {
    Some(tok) => {
      let expr = parse_expr_unary(p)
      return Expr::Unary(op=UnaryOp::PreDec, expr~, loc=tok.loc)
    }
    None => ()
  }
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
      Some(tok) => {
        let args = parse_call_args(p)
        expr = Expr::Call(callee=expr, args~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, LBracket) {
      Some(tok) => {
        let index = parse_expr(p)
        expect(p, RBracket, "expected ']' after index") |> ignore
        expr = Expr::Index(base=expr, index~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, Dot) {
      Some(tok) => {
        let name = match expect_ident(p, "expected field name") {
          None => ""
          Some(id) => id.lexeme
        }
        expr = Expr::Member(base=expr, name~, is_arrow=false, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, Arrow) {
      Some(tok) => {
        let name = match expect_ident(p, "expected field name") {
          None => ""
          Some(id) => id.lexeme
        }
        expr = Expr::Member(base=expr, name~, is_arrow=true, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, PlusPlus) {
      Some(tok) => {
        expr = Expr::Unary(op=UnaryOp::PostInc, expr~, loc=tok.loc)
        continue
      }
      None => ()
    }
    match match_token(p, MinusMinus) {
      Some(tok) => {
        expr = Expr::Unary(op=UnaryOp::PostDec, expr~, loc=tok.loc)
        continue
      }
      None => ()
    }
    break
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
    FloatLit => Expr::FloatLit(value=tok.lexeme, loc=tok.loc)
    CharLit =>
      Expr::CharLit(value=parse_char_literal_value(p, tok), loc=tok.loc)
    StrLit => parse_string_literal_expr(p, tok)
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
fn match_assign_op(p : Parser) -> (BinaryOp, Token)? {
  let tok = peek_token(p)
  let op = match tok.kind {
    Assign => Some(BinaryOp::Assign)
    PlusAssign => Some(BinaryOp::AddAssign)
    MinusAssign => Some(BinaryOp::SubAssign)
    StarAssign => Some(BinaryOp::MulAssign)
    SlashAssign => Some(BinaryOp::DivAssign)
    PercentAssign => Some(BinaryOp::ModAssign)
    ShiftLeftAssign => Some(BinaryOp::ShlAssign)
    ShiftRightAssign => Some(BinaryOp::ShrAssign)
    AmpAssign => Some(BinaryOp::BitAndAssign)
    PipeAssign => Some(BinaryOp::BitOrAssign)
    CaretAssign => Some(BinaryOp::BitXorAssign)
    _ => None
  }
  match op {
    None => None
    Some(op_val) => {
      ignore(advance_token(p))
      Some((op_val, tok))
    }
  }
}

///|
fn parse_string_literal_expr(p : Parser, first : Token) -> Expr {
  let sb = StringBuilder::new()
  let mut byte_len = 0
  let (value, len) = decode_string_literal(p, first.lexeme, first.loc)
  sb.write_string(value)
  byte_len = byte_len + len
  while peek_token(p).kind == StrLit {
    let tok = advance_token(p)
    let (part, part_len) = decode_string_literal(p, tok.lexeme, tok.loc)
    sb.write_string(part)
    byte_len = byte_len + part_len
  }
  Expr::StringLit(value=sb.to_string(), length=byte_len + 1, loc=first.loc)
}

///|
fn decode_string_literal(
  p : Parser,
  lexeme : String,
  loc : SrcLoc,
) -> (String, Int) {
  let sb = StringBuilder::new()
  let mut i = 1
  let mut count = 0
  let len = lexeme.length()
  while i + 1 < len {
    let code = lexeme[i]
    if code == 92 {
      if i + 1 >= len {
        add_parse_error(p, loc, "unterminated escape sequence")
        break
      }
      let next = lexeme[i + 1]
      if next == 10 {
        i = i + 2
        continue
      }
      let (value, next_index) = decode_escape_value(p, lexeme, i + 1, loc)
      if value >= 0 {
        sb.write_char(value.to_uint16().unsafe_to_char())
        count = count + 1
      }
      i = next_index
      continue
    }
    sb.write_char(code.unsafe_to_char())
    count = count + 1
    i = i + 1
  }
  (sb.to_string(), count)
}

///|
fn parse_char_literal_value(p : Parser, tok : Token) -> Int {
  let lexeme = tok.lexeme
  if lexeme.length() < 3 {
    add_parse_error(p, tok.loc, "invalid character literal")
    return 0
  }
  let len = lexeme.length()
  let mut value = 0
  let mut i = 1
  if i + 1 >= len {
    add_parse_error(p, tok.loc, "invalid character literal")
    return 0
  }
  let code = lexeme[i]
  if code == 92 {
    let (esc, next_index) = decode_escape_value(p, lexeme, i + 1, tok.loc)
    value = esc
    i = next_index
  } else {
    value = code.to_int()
    i = i + 1
  }
  if i + 1 < len {
    add_parse_error(p, tok.loc, "multi-character literal")
  }
  value
}

///|
fn decode_escape_value(
  p : Parser,
  text : String,
  start : Int,
  loc : SrcLoc,
) -> (Int, Int) {
  if start >= text.length() {
    add_parse_error(p, loc, "unterminated escape sequence")
    return (0, start)
  }
  let code = text[start]
  match code {
    97 => (7, start + 1) // \a
    98 => (8, start + 1) // \b
    102 => (12, start + 1) // \f
    110 => (10, start + 1) // \n
    114 => (13, start + 1) // \r
    116 => (9, start + 1) // \t
    118 => (11, start + 1) // \v
    92 => (92, start + 1) // \\
    39 => (39, start + 1) // \'
    34 => (34, start + 1) // \"
    63 => (63, start + 1) // \?
    120 | 88 => parse_hex_escape(p, text, start + 1, loc) // \x
    _ =>
      if is_oct_digit(code) {
        parse_octal_escape(text, start)
      } else {
        (code.to_int(), start + 1)
      }
  }
}

///|
fn parse_hex_escape(
  p : Parser,
  text : String,
  start : Int,
  loc : SrcLoc,
) -> (Int, Int) {
  let mut i = start
  let mut value = 0
  let mut saw = false
  while i < text.length() {
    let code = text[i]
    let digit = hex_digit_value(code)
    match digit {
      None => break
      Some(v) => {
        value = value * 16 + v
        saw = true
        i = i + 1
      }
    }
  }
  if !saw {
    add_parse_error(p, loc, "invalid hex escape")
  }
  (value, i)
}

///|
fn parse_octal_escape(text : String, start : Int) -> (Int, Int) {
  let mut i = start
  let mut value = 0
  let mut count = 0
  while i < text.length() && count < 3 {
    let code = text[i]
    if !is_oct_digit(code) {
      break
    }
    value = value * 8 + (code.to_int() - 48)
    i = i + 1
    count = count + 1
  }
  (value, i)
}

///|
fn is_oct_digit(code : UInt16) -> Bool {
  code >= 48 && code <= 55
}

///|
fn hex_digit_value(code : UInt16) -> Int? {
  if code >= 48 && code <= 57 {
    return Some(code.to_int() - 48)
  }
  if code >= 65 && code <= 70 {
    return Some(code.to_int() - 65 + 10)
  }
  if code >= 97 && code <= 102 {
    return Some(code.to_int() - 97 + 10)
  }
  None
}

///|
fn is_type_start(p : Parser, tok : Token) -> Bool {
  match tok.kind {
    KwVoid => true
    KwBool => true
    KwChar => true
    KwShort => true
    KwInt => true
    KwLong => true
    KwFloat => true
    KwDouble => true
    KwSigned => true
    KwUnsigned => true
    KwConst => true
    KwVolatile => true
    KwRestrict => true
    KwExtern => true
    KwStatic => true
    KwAuto => true
    KwRegister => true
    KwInline => true
    KwStruct => true
    KwUnion => true
    KwEnum => true
    KwTypedef => true
    Ident => has_typedef(p, tok.lexeme)
    _ => false
  }
}

///|
fn expr_loc(expr : Expr) -> SrcLoc {
  match expr {
    Expr::IntLit(loc~, ..) => loc
    Expr::FloatLit(loc~, ..) => loc
    Expr::CharLit(loc~, ..) => loc
    Expr::StringLit(loc~, ..) => loc
    Expr::Ident(loc~, ..) => loc
    Expr::Unary(loc~, ..) => loc
    Expr::Cast(loc~, ..) => loc
    Expr::SizeofExpr(loc~, ..) => loc
    Expr::SizeofType(loc~, ..) => loc
    Expr::Binary(loc~, ..) => loc
    Expr::Conditional(loc~, ..) => loc
    Expr::Call(loc~, ..) => loc
    Expr::Index(loc~, ..) => loc
    Expr::Member(loc~, ..) => loc
  }
}

///|
fn push_typedef_scope(p : Parser) -> Unit {
  p.type_scopes.push({})
}

///|
fn pop_typedef_scope(p : Parser) -> Unit {
  ignore(p.type_scopes.pop())
}

///|
fn define_typedef(p : Parser, name : String, ty : CType) -> Unit {
  if p.type_scopes.length() == 0 {
    p.type_scopes.push({})
  }
  let idx = p.type_scopes.length() - 1
  let scope = p.type_scopes[idx]
  scope.set(name, ty)
  p.type_scopes[idx] = scope
}

///|
fn lookup_typedef(p : Parser, name : String) -> CType? {
  let mut i = p.type_scopes.length()
  while i > 0 {
    i = i - 1
    let scope = p.type_scopes[i]
    if scope.contains(name) {
      return scope.get(name)
    }
  }
  None
}

///|
fn has_typedef(p : Parser, name : String) -> Bool {
  lookup_typedef(p, name) is Some(_)
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
