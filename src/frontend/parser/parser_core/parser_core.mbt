///|
priv struct Parser {
  pp : @preproc.Preprocessor
  mut current : @tokens.Token
  mut lookahead : @tokens.Token
  buffer : Array[@tokens.Token]
  mut buffer_pos : Int
  diags : @diag.DiagBag
  typedef_counts : Array[Int]
  typedef_values : Array[@ast.CType?]
  typedef_scope_levels : Array[Int]
  typedef_scope_stack : Array[Int]
  mut next_typedef_scope_id : Int
  typedef_overrides : Array[Array[(Int, @ast.CType?, Int)]]
  pending_typedef_scopes : Array[Bool]
  mut anon_tag_id : Int
  mut next_expr_id : Int
  builtin_ids : BuiltinIds
}

///|
priv struct BuiltinIds {
  types_compatible_p : Int
  offsetof : Int
  va_arg : Int
}

///|
fn new_parser(pp : @preproc.Preprocessor) -> Parser {
  let text_len = pp.lexer.text_len
  let mut id_capacity = text_len / 64
  if id_capacity < 512 {
    id_capacity = 512
  } else if id_capacity > 65536 {
    id_capacity = 65536
  }
  let buffer_capacity = 64
  let scope_capacity = 128
  let override_capacity = 128
  let typedef_counts : Array[Int] = Array::new(capacity=id_capacity)
  let typedef_values : Array[@ast.CType?] = Array::new(capacity=id_capacity)
  let typedef_scope_levels : Array[Int] = Array::new(capacity=id_capacity)
  let typedef_scope_stack : Array[Int] = Array::new(capacity=scope_capacity)
  typedef_scope_stack.push(1)
  let typedef_overrides : Array[Array[(Int, @ast.CType?, Int)]] = Array::new(
    capacity=override_capacity,
  )
  typedef_overrides.push([])
  let pending_typedef_scopes : Array[Bool] = Array::new(capacity=scope_capacity)
  let buffer : Array[@tokens.Token] = Array::new(capacity=buffer_capacity)
  let next_typedef_scope_id = 2
  let builtin_defs = [
    ("__builtin_va_list", @ast.CType::Pointer(Void)),
    ("_Float16", Int(kind=Short, unsigned=true)),
  ]
  for def in builtin_defs {
    let (name, ty) = def
    let (_, id) = pp.interner.intern_view_with_id(name[:])
    ensure_typedef_capacity_with(
      typedef_counts, typedef_values, typedef_scope_levels, id,
    )
    typedef_counts[id - 1] = 1
    typedef_values[id - 1] = Some(ty)
    typedef_scope_levels[id - 1] = 1
  }
  let current = @preproc.next_pp_token(pp)
  let lookahead = @preproc.next_pp_token(pp)
  let (_, builtin_types_compatible_p) = pp.interner.intern_view_with_id(
    "__builtin_types_compatible_p"[:],
  )
  let (_, builtin_offsetof) = pp.interner.intern_view_with_id(
    "__builtin_offsetof"[:],
  )
  let (_, builtin_va_arg) = pp.interner.intern_view_with_id(
    "__builtin_va_arg"[:],
  )
  {
    pp,
    current,
    lookahead,
    buffer,
    buffer_pos: 0,
    diags: pp.diags,
    typedef_counts,
    typedef_values,
    typedef_scope_levels,
    typedef_scope_stack,
    next_typedef_scope_id,
    typedef_overrides,
    pending_typedef_scopes,
    anon_tag_id: 0,
    next_expr_id: 0,
    builtin_ids: {
      types_compatible_p: builtin_types_compatible_p,
      offsetof: builtin_offsetof,
      va_arg: builtin_va_arg,
    },
  }
}

///|
fn new_expr_id(p : Parser) -> Int {
  let id = p.next_expr_id + 1
  p.next_expr_id = id
  id
}

///|
fn special_ident_kind(
  tok : @tokens.Token,
  ids : @tokens.KeywordIds,
) -> @tokens.TokenKind? {
  match @tokens.keyword_kind_from_id(@tokens.token_id(tok), ids) {
    Some(kind) =>
      match kind {
        KwVoid
        | KwBool
        | KwChar
        | KwShort
        | KwInt
        | KwLong
        | KwFloat
        | KwDouble
        | KwSigned
        | KwUnsigned
        | KwConst
        | KwVolatile
        | KwRestrict
        | KwAtomic
        | KwInline
        | KwNoreturn => Some(kind)
        _ => None
      }
    None => None
  }
}

///|
pub fn parse_translation_unit(
  pp : @preproc.Preprocessor,
) -> @ast.TranslationUnit {
  let parser = new_parser(pp)
  parse_translation_unit_with(parser)
}

///|
fn parse_translation_unit_with(p : Parser) -> @ast.TranslationUnit {
  let mut decl_capacity = p.pp.lexer.text_len / 256
  if decl_capacity < 256 {
    decl_capacity = 256
  } else if decl_capacity > 16384 {
    decl_capacity = 16384
  }
  let decls : Array[@ast.Decl] = Array::new(capacity=decl_capacity)
  while !is_at_end(p) {
    match parse_decl(p) {
      Some(items) =>
        for item in items {
          decls.push(item)
        }
      None => synchronize(p)
    }
  }
  let expr_id_max = p.next_expr_id
  { decls, expr_id_max }
}

///|
fn parse_decl(p : Parser) -> Array[@ast.Decl]? {
  if match_token(p, KwStaticAssert) is Some(assert_tok) {
    let static_assert = parse_static_assert(p, assert_tok.loc)
    expect(p, Semicolon, "expected ';' after _Static_assert") |> ignore
    return Some([StaticAssert(static_assert)])
  }
  if match_token(p, KwAsm) is Some(asm_tok) {
    let asm_stmt = parse_asm_stmt(p, asm_tok.loc)
    expect(p, Semicolon, "expected ';' after asm") |> ignore
    return Some([Asm(asm_stmt)])
  }
  let specs = match parse_decl_specs(p) {
    None => {
      let head = peek_token(p)
      if head.kind is Ident && !has_typedef(p, head) {
        Some({
          ty: Int(kind=Int, unsigned=false),
          loc: head.loc,
          is_typedef: false,
          storage: Default,
          is_inline: false,
          attrs: @ast.empty_attrs(),
        })
      } else {
        None
      }
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
          Some([TagDef(ty=base_type, loc=semi.loc)])
        }
      } else {
        let decls : Array[@ast.Decl] = []
        while true {
          match parse_init_declarator(p, base_type) {
            None => {
              synchronize(p)
              return None
            }
            Some((decl, init)) => {
              let combined_attrs = @ast.merge_attrs(base_attrs, decl.attrs)
              let adjusted_ty = @ast.apply_call_conv_to_type(
                decl.ty,
                @ast.normalize_call_conv(combined_attrs.call_conv),
              )
              if is_typedef {
                if init is Some(_) {
                  add_parse_error(
                    p,
                    decl.loc,
                    "typedef cannot have initializer",
                  )
                }
                let typedef_ty = @ast.apply_type_attrs(
                  adjusted_ty,
                  @ast.type_attrs_from(combined_attrs),
                )
                define_typedef(p, decl.name, typedef_ty)
                decls.push(
                  Typedef(
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
                      Function(return_type~, ..) => {
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
                            FuncDef({
                              name: decl.name,
                              id: decl.id,
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
                            FuncDecl({
                              name: decl.name,
                              id: decl.id,
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
                          Var({
                            name: decl.name,
                            id: decl.id,
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
                      Var({
                        name: decl.name,
                        id: decl.id,
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
  params : Array[@ast.Param],
) -> Array[@ast.Param] {
  let updated = params
  let param_map : @util.FastMap[String, Int] = @util.fast_map_new()
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
  let seen : @util.FastMap[String, Bool] = @util.fast_map_new()
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
        if specs.storage != Default && specs.storage != Register {
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
              let combined_attrs = @ast.merge_attrs(specs.attrs, decl.attrs)
              let adjusted_ty = @ast.apply_call_conv_to_type(
                decl.ty,
                @ast.normalize_call_conv(combined_attrs.call_conv),
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
                        id: decl.id,
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
fn strip_type_qualifiers(ty : @ast.CType) -> @ast.CType {
  match ty {
    Qualified(base~, ..) => strip_type_qualifiers(base)
    Attributed(base~, ..) => strip_type_qualifiers(base)
    _ => ty
  }
}

///|
fn parse_type_qualifiers(p : Parser) -> @ast.TypeQual {
  let mut qual = @ast.empty_qual()
  while true {
    let tok = peek_token(p)
    let mut kind = tok.kind
    if kind is Ident {
      if special_ident_kind(tok, p.pp.keyword_ids) is Some(mapped) {
        kind = mapped
      }
    }
    match kind {
      KwConst => {
        qual = @ast.with_const(qual)
        ignore(advance_token(p))
        continue
      }
      KwVolatile => {
        qual = @ast.with_volatile(qual)
        ignore(advance_token(p))
        continue
      }
      KwRestrict => {
        qual = @ast.with_restrict(qual)
        ignore(advance_token(p))
        continue
      }
      KwAtomic => {
        qual = @ast.with_atomic(qual)
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
priv struct DeclSpecs {
  ty : @ast.CType
  loc : @source.SrcLoc
  is_typedef : Bool
  storage : @ast.StorageClass
  is_inline : Bool
  attrs : @ast.Attributes
}

///|
fn parse_type_specifiers(
  p : Parser,
  allow_storage~ : Bool,
  allow_typedef~ : Bool,
) -> DeclSpecs? {
  let mut is_typedef = false
  let mut storage = @ast.StorageClass::Default
  let mut is_inline = false
  let mut saw_any = false
  let mut start_loc = peek_token(p).loc
  let mut qual = @ast.empty_qual()
  let mut attrs = @ast.empty_attrs()
  let mut signedness = 0
  let mut short_seen = false
  let mut long_count = 0
  let mut saw_char = false
  let mut saw_int = false
  let mut saw_bool = false
  let mut saw_float = false
  let mut saw_double = false
  let mut saw_void = false
  let mut base : @ast.CType? = None
  while true {
    let tok = peek_token(p)
    let mut kind = tok.kind
    if kind is Ident {
      if special_ident_kind(tok, p.pp.keyword_ids) is Some(mapped) {
        kind = mapped
      }
    }
    match kind {
      KwTypedef => {
        if allow_typedef {
          if is_typedef || storage != Default {
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
          match kind {
            KwInline => is_inline = true
            KwExtern => {
              if storage != Default || is_typedef {
                add_parse_error(p, tok.loc, "multiple storage classes")
              }
              storage = Extern
            }
            KwStatic => {
              if storage != Default || is_typedef {
                add_parse_error(p, tok.loc, "multiple storage classes")
              }
              storage = Static
            }
            KwAuto => {
              if storage != Default || is_typedef {
                add_parse_error(p, tok.loc, "multiple storage classes")
              }
              storage = Auto
            }
            KwRegister => {
              if storage != Default || is_typedef {
                add_parse_error(p, tok.loc, "multiple storage classes")
              }
              storage = Register
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
      KwNoreturn => {
        attrs = @ast.merge_attrs(attrs, @ast.attrs_with(noreturn=true))
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwAtomic => {
        ignore(advance_token(p))
        saw_any = true
        if match_token(p, LParen) is Some(_) {
          match parse_type_name(p) {
            None => {
              add_parse_error(p, tok.loc, "expected type name in _Atomic")
              return None
            }
            Some(ty) => {
              expect(p, RParen, "expected ')' after _Atomic type") |> ignore
              if base is Some(_) {
                add_parse_error(p, tok.loc, "multiple type specifiers")
              } else {
                base = Some(ty)
                start_loc = tok.loc
              }
              qual = @ast.with_atomic(qual)
            }
          }
        } else {
          qual = @ast.with_atomic(qual)
        }
        continue
      }
      KwConst => {
        qual = @ast.with_const(qual)
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwVolatile => {
        qual = @ast.with_volatile(qual)
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwRestrict => {
        qual = @ast.with_restrict(qual)
        ignore(advance_token(p))
        saw_any = true
        continue
      }
      KwAttribute => {
        let clause = parse_attribute_clause(p, tok.loc)
        attrs = @ast.merge_attrs(attrs, clause)
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
        if lookup_typedef(p, tok) is Some(aliased) {
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
        Void
      } else if saw_bool {
        Bool
      } else if saw_float || saw_double {
        if long_count > 0 && saw_double {
          Float(kind=LongDouble)
        } else if saw_double {
          Float(kind=Double)
        } else if long_count > 0 {
          add_parse_error(p, start_loc, "invalid long float")
          Float(kind=Float)
        } else {
          Float(kind=Float)
        }
      } else {
        let kind = if saw_char {
          @ast.CIntKind::Char
        } else if short_seen {
          Short
        } else if long_count >= 2 {
          LongLong
        } else if long_count == 1 {
          Long
        } else {
          Int
        }
        let unsigned = if kind == Char && signedness == 0 {
          @util.char_is_unsigned
        } else {
          signedness == 2
        }
        Int(kind~, unsigned~)
      }
  }
  if ty is Void && (signedness != 0 || short_seen || long_count > 0) {
    add_parse_error(p, start_loc, "invalid modifiers for void")
  }
  if ty is Bool && signedness != 0 {
    add_parse_error(p, start_loc, "invalid modifiers for _Bool")
  }
  let qualified = @ast.apply_qualifiers(ty, qual)
  let final_ty = @ast.apply_type_attrs(qualified, @ast.type_attrs_from(attrs))
  Some({ ty: final_ty, loc: start_loc, is_typedef, storage, is_inline, attrs })
}

///|
fn parse_decl_specs(p : Parser, allow_storage? : Bool = true) -> DeclSpecs? {
  parse_type_specifiers(p, allow_storage~, allow_typedef=true)
}

///|

///|
fn is_type_spec_start(p : Parser) -> Bool {
  let tok = peek_token(p)
  let mut kind = tok.kind
  if kind is Ident {
    if special_ident_kind(tok, p.pp.keyword_ids) is Some(mapped) {
      kind = mapped
    }
  }
  match kind {
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
    | KwAtomic
    | KwSigned
    | KwUnsigned
    | KwAttribute
    | KwTypeof => true
    Ident => has_typedef(p, peek_token(p))
    _ => false
  }
}

///|
fn parse_typeof_spec(p : Parser, loc : @source.SrcLoc) -> @ast.CType? {
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
  Some(TypeofExpr(expr~))
}

///|
fn normalize_attr_name(name : String) -> String {
  name.trim(chars="_").to_string().to_lower()
}

///|
fn parse_attr_string(p : Parser, loc : @source.SrcLoc) -> String? {
  if peek_token(p).kind != StrLit {
    add_parse_error(p, loc, "expected string literal in attribute")
    return None
  }
  let tok = advance_token(p)
  let (part, _len) = decode_string_literal(p, token_lexeme(p, tok), tok.loc)
  if peek_token(p).kind != StrLit {
    return Some(part)
  }
  let sb = StringBuilder::new(size_hint=token_lexeme_len(p, tok))
  sb.write_string(part)
  while peek_token(p).kind is StrLit {
    let next_tok = advance_token(p)
    let (next_part, _next_len) = decode_string_literal(
      p,
      token_lexeme(p, next_tok),
      next_tok.loc,
    )
    sb.write_string(next_part)
  }
  Some(sb.to_string())
}

///|
fn parse_static_assert(p : Parser, loc : @source.SrcLoc) -> @ast.StaticAssert {
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
fn parse_asm_label(p : Parser, loc : @source.SrcLoc) -> String? {
  expect(p, LParen, "expected '(' after asm") |> ignore
  let label = parse_attr_string(p, loc)
  expect(p, RParen, "expected ')' after asm label") |> ignore
  label
}

///|
fn parse_asm_operands(p : Parser) -> Array[@ast.AsmOperand] {
  let operands : Array[@ast.AsmOperand] = []
  let kind = peek_token(p).kind
  if kind is Colon || kind is RParen {
    return operands
  }
  while true {
    let start_loc = peek_token(p).loc
    let name = if match_token(p, LBracket) is Some(_) {
      let id = match expect_ident(p, "expected asm operand name") {
        None => ""
        Some(tok) => token_lexeme(p, tok)
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
    let constraint = parse_attr_string(p, start_loc).unwrap_or("")
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
  let kind = peek_token(p).kind
  if kind is Colon || kind is RParen {
    return clobbers
  }
  while true {
    let loc = peek_token(p).loc
    if parse_attr_string(p, loc) is Some(value) {
      clobbers.push(value)
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
  let kind = peek_token(p).kind
  if kind is Colon || kind is RParen {
    return labels
  }
  while true {
    let name = match expect_ident(p, "expected label identifier") {
      None => ""
      Some(tok) => token_lexeme(p, tok)
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
fn parse_asm_stmt(p : Parser, loc : @source.SrcLoc) -> @ast.AsmStmt {
  let mut is_volatile = false
  let mut is_goto = false
  while true {
    if match_token(p, KwVolatile) is Some(_) {
      is_volatile = true
      continue
    }
    if peek_token(p).kind is Ident {
      let tok = peek_token(p)
      match special_ident_kind(tok, p.pp.keyword_ids) {
        Some(KwVolatile) => {
          ignore(advance_token(p))
          is_volatile = true
          continue
        }
        _ => ()
      }
    }
    if match_token(p, KwGoto) is Some(_) {
      is_goto = true
      continue
    }
    break
  }
  expect(p, LParen, "expected '(' after asm") |> ignore
  let template = parse_attr_string(p, loc).unwrap_or("")
  let mut outputs : Array[@ast.AsmOperand] = []
  let mut inputs : Array[@ast.AsmOperand] = []
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
fn is_attr_name_token(kind : @tokens.TokenKind) -> Bool {
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
fn parse_attribute_clause(p : Parser, loc : @source.SrcLoc) -> @ast.Attributes {
  let mut attrs = @ast.empty_attrs()
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
    let name = normalize_attr_name(token_lexeme(p, name_tok))
    let mut has_args = false
    if match_token(p, LParen) is Some(_) {
      has_args = true
    }
    match name {
      "aligned" => {
        let spec = if has_args {
          if peek_token(p).kind is RParen {
            @ast.AlignSpec::Default
          } else {
            let expr = parse_expr_cond(p)
            Expr(expr~)
          }
        } else {
          Default
        }
        attrs = @ast.merge_attrs(attrs, @ast.attrs_with(aligned=Some(spec)))
        if has_args {
          expect(p, RParen, "expected ')' after aligned attribute") |> ignore
        }
      }
      "packed" => {
        attrs = @ast.merge_attrs(attrs, @ast.attrs_with(packed=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "weak" => {
        attrs = @ast.merge_attrs(attrs, @ast.attrs_with(weak=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "noreturn" => {
        attrs = @ast.merge_attrs(attrs, @ast.attrs_with(noreturn=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "constructor" => {
        attrs = @ast.merge_attrs(attrs, @ast.attrs_with(constructor_attr=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "destructor" => {
        attrs = @ast.merge_attrs(attrs, @ast.attrs_with(destructor=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "always_inline" => {
        attrs = @ast.merge_attrs(attrs, @ast.attrs_with(always_inline=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "section" =>
        if !has_args {
          add_parse_error(p, name_tok.loc, "expected '(' after section")
        } else {
          let section = parse_attr_string(p, name_tok.loc)
          attrs = @ast.merge_attrs(attrs, @ast.attrs_with(section~))
          expect(p, RParen, "expected ')' after section") |> ignore
        }
      "alias" =>
        if !has_args {
          add_parse_error(p, name_tok.loc, "expected '(' after alias")
        } else {
          let alias_name = parse_attr_string(p, name_tok.loc)
          attrs = @ast.merge_attrs(attrs, @ast.attrs_with(alias_name~))
          expect(p, RParen, "expected ')' after alias") |> ignore
        }
      "visibility" =>
        if !has_args {
          add_parse_error(p, name_tok.loc, "expected '(' after visibility")
        } else {
          let vis = parse_attr_string(p, name_tok.loc)
          let value = match vis {
            Some("default") => Some(@ast.Visibility::Default)
            Some("hidden") => Some(Hidden)
            Some("internal") => Some(Internal)
            Some("protected") => Some(Protected)
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
          attrs = @ast.merge_attrs(attrs, @ast.attrs_with(visibility=value))
          expect(p, RParen, "expected ')' after visibility") |> ignore
        }
      "cleanup" =>
        if !has_args {
          add_parse_error(p, name_tok.loc, "expected '(' after cleanup")
        } else {
          if expect_ident(p, "expected cleanup function name") is Some(id) {
            attrs = @ast.merge_attrs(
              attrs,
              @ast.attrs_with(cleanup=Some(token_lexeme(p, id))),
            )
          }
          expect(p, RParen, "expected ')' after cleanup") |> ignore
        }
      "cdecl" => {
        attrs = @ast.merge_attrs(attrs, @ast.attrs_with(call_conv=Some(Cdecl)))
        if has_args {
          skip_paren_group(p)
        }
      }
      "stdcall" => {
        attrs = @ast.merge_attrs(
          attrs,
          @ast.attrs_with(call_conv=Some(Stdcall)),
        )
        if has_args {
          skip_paren_group(p)
        }
      }
      "fastcall" => {
        attrs = @ast.merge_attrs(
          attrs,
          @ast.attrs_with(call_conv=Some(Fastcall)),
        )
        if has_args {
          skip_paren_group(p)
        }
      }
      "thiscall" => {
        attrs = @ast.merge_attrs(
          attrs,
          @ast.attrs_with(call_conv=Some(Thiscall)),
        )
        if has_args {
          skip_paren_group(p)
        }
      }
      "regparm" =>
        if !has_args {
          add_parse_error(p, name_tok.loc, "expected '(' after regparm")
        } else {
          let raw = if peek_token(p).kind is IntLit {
            let tok = advance_token(p)
            let parsed = try
              @strconv.parse_int(token_lexeme(p, tok), base=0)
            catch {
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
            attrs = @ast.merge_attrs(
              attrs,
              @ast.attrs_with(call_conv=Some(Regparm(count~))),
            )
          }
        }
      "dllimport" => {
        attrs = @ast.merge_attrs(attrs, @ast.attrs_with(dll_import=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "dllexport" => {
        attrs = @ast.merge_attrs(attrs, @ast.attrs_with(dll_export=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "nodecorate" => {
        attrs = @ast.merge_attrs(attrs, @ast.attrs_with(nodecorate=true))
        if has_args {
          skip_paren_group(p)
        }
      }
      "nodebug" => {
        attrs = @ast.merge_attrs(attrs, @ast.attrs_with(nodebug=true))
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
fn parse_attributes(p : Parser) -> @ast.Attributes {
  let mut attrs = @ast.empty_attrs()
  while peek_token(p).kind is KwAttribute {
    let clause = parse_attribute_clause(p, peek_token(p).loc)
    attrs = @ast.merge_attrs(attrs, clause)
  }
  attrs
}

///|
fn parse_pointer_chain(
  p : Parser,
  ty_in : @ast.CType,
) -> (@ast.CType, @ast.Attributes) {
  let mut ty = ty_in
  let mut attrs = @ast.empty_attrs()
  while match_token(p, Star) is Some(_) {
    let qual = parse_type_qualifiers(p)
    let pointer_attrs = parse_attributes(p)
    attrs = @ast.merge_attrs(attrs, pointer_attrs)
    ty = Pointer(ty)
    ty = @ast.apply_qualifiers(ty, qual)
  }
  (ty, attrs)
}

///|
fn parse_type_name(p : Parser) -> @ast.CType? {
  match parse_type_specifiers(p, allow_storage=false, allow_typedef=false) {
    None => None
    Some(specs) => {
      let base = specs.ty
      let base_attrs = specs.attrs
      // Parse any leading pointer chain first so we can handle cases like:
      //   void *(*fp)(void)
      // where the return type itself is a pointer and the direct-declarator is
      // a parenthesized pointer declarator.
      let (ty0, pointer_attrs) = parse_pointer_chain(p, base)
      let mut attrs = @ast.merge_attrs(base_attrs, pointer_attrs)
      attrs = @ast.merge_attrs(attrs, parse_attributes(p))
      if is_paren_pointer_declarator(p) {
        let (ty, paren_attrs) = parse_paren_pointer_abstract(p, ty0)
        attrs = @ast.merge_attrs(attrs, paren_attrs)
        let call_conv = @ast.normalize_call_conv(attrs.call_conv)
        Some(@ast.apply_call_conv_to_type(ty, call_conv))
      } else {
        let (full, _params, _varargs, _old_style, suffix_attrs) = parse_declarator_suffix(
          p, ty0,
        )
        attrs = @ast.merge_attrs(attrs, suffix_attrs)
        let call_conv = @ast.normalize_call_conv(attrs.call_conv)
        Some(@ast.apply_call_conv_to_type(full, call_conv))
      }
    }
  }
}

///|
priv struct Declarator {
  name : String
  id : Int
  ty : @ast.CType
  params : Array[@ast.Param]?
  varargs : Bool
  is_old_style : Bool
  attrs : @ast.Attributes
  loc : @source.SrcLoc
}

///|
fn parse_declarator(p : Parser, base : @ast.CType) -> Declarator? {
  // Parse pointer chain first so we can handle return-type pointers on
  // function-pointer declarators like:
  //   void *(*fp)(void)
  let (ty0, pointer_attrs) = parse_pointer_chain(p, base)
  let mut attrs = @ast.merge_attrs(pointer_attrs, parse_attributes(p))
  if peek_kind(p, 0) is LParen {
    match parse_paren_pointer_declarator(p, ty0) {
      None => None
      Some(decl) =>
        Some({
          name: decl.name,
          id: decl.id,
          ty: decl.ty,
          params: decl.params,
          varargs: decl.varargs,
          is_old_style: decl.is_old_style,
          attrs: @ast.merge_attrs(attrs, decl.attrs),
          loc: decl.loc,
        })
    }
  } else {
    let name_tok = expect_ident(p, "expected identifier")
    match name_tok {
      None => None
      Some(tok) => {
        let (ty, params, varargs, is_old_style, suffix_attrs) = parse_declarator_suffix(
          p, ty0,
        )
        attrs = @ast.merge_attrs(attrs, suffix_attrs)
        if match_token(p, KwAsm) is Some(asm_tok) {
          if parse_asm_label(p, asm_tok.loc) is Some(label) {
            attrs = @ast.merge_attrs(
              attrs,
              @ast.attrs_with(asm_label=Some(label)),
            )
          }
          attrs = @ast.merge_attrs(attrs, parse_attributes(p))
        }
        Some({
          name: token_lexeme(p, tok),
          id: @tokens.token_id(tok),
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
}

///|
fn parse_init_declarator(
  p : Parser,
  base : @ast.CType,
) -> (Declarator, @ast.Initializer?)? {
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
  base : @ast.CType,
  fallback_loc : @source.SrcLoc,
) -> Declarator? {
  // Like parse_declarator, but the name may be omitted (anonymous fields).
  let (ty0, pointer_attrs) = parse_pointer_chain(p, base)
  let mut attrs = @ast.merge_attrs(pointer_attrs, parse_attributes(p))
  if peek_kind(p, 0) is LParen {
    match parse_paren_pointer_declarator(p, ty0) {
      None => None
      Some(decl) =>
        Some({
          name: decl.name,
          id: decl.id,
          ty: decl.ty,
          params: decl.params,
          varargs: decl.varargs,
          is_old_style: decl.is_old_style,
          attrs: @ast.merge_attrs(attrs, decl.attrs),
          loc: decl.loc,
        })
    }
  } else {
    let (name, id, loc) = if peek_token(p).kind is Ident {
      let name_tok = advance_token(p)
      (token_lexeme(p, name_tok), @tokens.token_id(name_tok), name_tok.loc)
    } else {
      ("", 0, fallback_loc)
    }
    let (ty, params, varargs, is_old_style, suffix_attrs) = parse_declarator_suffix(
      p, ty0,
    )
    attrs = @ast.merge_attrs(attrs, suffix_attrs)
    Some({ name, id, ty, params, varargs, is_old_style, attrs, loc })
  }
}

///|
fn parse_initializer(p : Parser) -> @ast.Initializer {
  if p.current.kind is LBrace {
    let lbrace = advance_token(p)
    let items : Array[@ast.InitItem] = Array::new(capacity=4)
    if p.current.kind is RBrace {
      advance_token(p) |> ignore
      return List(items~, loc=lbrace.loc)
    }
    while true {
      let (designators, item_loc) = parse_designator_list(p)
      let value = parse_initializer(p)
      items.push({ designators, value, loc: item_loc })
      if p.current.kind is Comma {
        advance_token(p) |> ignore
        if p.current.kind is RBrace {
          advance_token(p) |> ignore
          break
        }
        continue
      }
      expect(p, RBrace, "expected '}' after initializer list") |> ignore
      break
    }
    return List(items~, loc=lbrace.loc)
  }
  let expr = parse_expr_eq(p)
  Expr(expr~, loc=@ast.expr_loc(expr))
}

///|
fn parse_designator_list(
  p : Parser,
) -> (Array[@ast.InitDesignator], @source.SrcLoc) {
  let designators : Array[@ast.InitDesignator] = Array::new(capacity=2)
  let mut start_loc = peek_token(p).loc
  while true {
    if p.current.kind is Dot {
      let dot_tok = advance_token(p)
      start_loc = dot_tok.loc
      let (name, id) = match expect_ident(p, "expected field name") {
        None => ("", 0)
        Some(tok) => (token_lexeme(p, tok), @tokens.token_id(tok))
      }
      designators.push(Field(name~, id~, loc=dot_tok.loc))
      continue
    }
    if p.current.kind is LBracket {
      let lbrack = advance_token(p)
      start_loc = lbrack.loc
      let start = parse_expr_cond(p)
      let end_expr = if p.current.kind is Ellipsis {
        advance_token(p) |> ignore
        Some(parse_expr_cond(p))
      } else {
        None
      }
      expect(p, RBracket, "expected ']' after designator") |> ignore
      match end_expr {
        None => designators.push(Index(expr=start, loc=lbrack.loc))
        Some(end) => designators.push(IndexRange(start~, end~, loc=lbrack.loc))
      }
      continue
    }
    if peek_token(p).kind is Ident && peek_kind(p, 1) is Colon {
      let name_tok = advance_token(p)
      start_loc = name_tok.loc
      expect(p, Colon, "expected ':' after designator") |> ignore
      designators.push(
        Field(
          name=token_lexeme(p, name_tok),
          id=@tokens.token_id(name_tok),
          loc=name_tok.loc,
        ),
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
      RParen => {
        if depth == 0 {
          return false
        }
        depth = depth - 1
      }
      Star => if depth == 0 { return true }
      _ => ()
    }
    i = i + 1
  }
  false
}

///|
priv enum DeclWrapper {
  Pointer(@ast.TypeQual)
  Array(Int?, @ast.Expr?)
  Function(Array[@ast.Param], Bool, Bool)
}

///|
priv struct ParenDeclParts {
  name : String
  id : Int
  loc : @source.SrcLoc
  wrappers : Array[DeclWrapper]
  params : Array[@ast.Param]?
  varargs : Bool
  is_old_style : Bool
  attrs : @ast.Attributes
}

///|
fn apply_decl_wrappers(
  base : @ast.CType,
  wrappers : Array[DeclWrapper],
) -> @ast.CType {
  let mut ty = base
  let mut i = wrappers.length()
  while i > 0 {
    i = i - 1
    match wrappers[i] {
      Pointer(qual) => {
        ty = Pointer(ty)
        ty = @ast.apply_qualifiers(ty, qual)
      }
      Array(size, size_expr) => ty = Array(elem=ty, size~, size_expr~)
      Function(params, varargs, is_old_style) => {
        let param_types = params.map(param => param.ty)
        ty = Function(
          return_type=ty,
          params=param_types,
          varargs~,
          is_old_style~,
          call_conv=Default,
        )
      }
    }
  }
  ty
}

///|
fn parse_inner_suffix_wrappers(
  p : Parser,
) -> (Array[DeclWrapper], Array[@ast.Param]?, Bool, Bool) {
  let wrappers : Array[DeclWrapper] = []
  while match_token(p, LBracket) is Some(_) {
    let (size, size_expr) = parse_array_size(p)
    expect(p, RBracket, "expected ']' after array size") |> ignore
    wrappers.push(Array(size, size_expr))
  }
  let mut params : Array[@ast.Param]? = None
  let mut varargs = false
  let mut old_style = false
  if match_token(p, LParen) is Some(_) {
    let (list, has_varargs, is_old_style) = parse_param_list(p)
    params = Some(list)
    varargs = has_varargs
    old_style = is_old_style
    wrappers.push(Function(list, varargs, old_style))
  }
  (wrappers, params, varargs, old_style)
}

///|
fn parse_suffix_wrappers(
  p : Parser,
) -> (Array[DeclWrapper], Array[@ast.Param]?, Bool, Bool, @ast.Attributes) {
  let mut attrs = parse_attributes(p)
  let wrappers : Array[DeclWrapper] = []
  while match_token(p, LBracket) is Some(_) {
    let (size, size_expr) = parse_array_size(p)
    expect(p, RBracket, "expected ']' after array size") |> ignore
    wrappers.push(Array(size, size_expr))
  }
  let mut params : Array[@ast.Param]? = None
  let mut varargs = false
  let mut old_style = false
  if match_token(p, LParen) is Some(_) {
    let (list, has_varargs, is_old_style) = parse_param_list(p)
    params = Some(list)
    varargs = has_varargs
    old_style = is_old_style
    wrappers.push(Function(list, varargs, old_style))
  }
  attrs = @ast.merge_attrs(attrs, parse_attributes(p))
  (wrappers, params, varargs, old_style, attrs)
}

///|
fn parse_paren_pointer_parts(
  p : Parser,
  allow_missing_name : Bool,
  fallback_loc : @source.SrcLoc,
) -> ParenDeclParts? {
  expect(p, LParen, "expected '(' in declarator") |> ignore
  let quals : Array[@ast.TypeQual] = []
  let mut attrs = parse_attributes(p)
  while match_token(p, Star) is Some(_) {
    quals.push(parse_type_qualifiers(p))
    attrs = @ast.merge_attrs(attrs, parse_attributes(p))
  }
  attrs = @ast.merge_attrs(attrs, parse_attributes(p))
  let mut name = ""
  let mut id = 0
  let mut loc = fallback_loc
  let mut nested_wrappers : Array[DeclWrapper] = []
  let mut nested_attrs = @ast.empty_attrs()
  if peek_kind(p, 0) is LParen {
    match parse_paren_pointer_parts(p, allow_missing_name, fallback_loc) {
      None => return None
      Some(parts) => {
        name = parts.name
        id = parts.id
        loc = parts.loc
        nested_wrappers = parts.wrappers
        nested_attrs = parts.attrs
      }
    }
  } else if peek_token(p).kind is Ident {
    let tok = advance_token(p)
    name = token_lexeme(p, tok)
    id = @tokens.token_id(tok)
    loc = tok.loc
  } else if allow_missing_name {
    name = ""
    id = 0
    loc = fallback_loc
  } else {
    expect_ident(p, "expected identifier") |> ignore
    return None
  }
  attrs = @ast.merge_attrs(attrs, parse_attributes(p))
  let (inner_wrappers, params, varargs, is_old_style) = parse_inner_suffix_wrappers(
    p,
  )
  attrs = @ast.merge_attrs(attrs, parse_attributes(p))
  expect(p, RParen, "expected ')' in declarator") |> ignore
  let wrappers = nested_wrappers
  for wrap in inner_wrappers {
    wrappers.push(wrap)
  }
  let mut i = quals.length()
  while i > 0 {
    i = i - 1
    wrappers.push(Pointer(quals[i]))
  }
  let combined_attrs = @ast.merge_attrs(attrs, nested_attrs)
  Some({
    name,
    id,
    loc,
    wrappers,
    params,
    varargs,
    is_old_style,
    attrs: combined_attrs,
  })
}

///|
fn parse_paren_pointer_declarator(p : Parser, base : @ast.CType) -> Declarator? {
  let fallback_loc = peek_token(p).loc
  match parse_paren_pointer_parts(p, false, fallback_loc) {
    None => None
    Some(parts) => {
      let (
        outer_wrappers,
        _outer_params,
        _outer_varargs,
        _outer_old_style,
        suffix_attrs,
      ) = parse_suffix_wrappers(p)
      let wrappers = parts.wrappers
      for wrap in outer_wrappers {
        wrappers.push(wrap)
      }
      let mut attrs = @ast.merge_attrs(parts.attrs, suffix_attrs)
      if match_token(p, KwAsm) is Some(asm_tok) {
        if parse_asm_label(p, asm_tok.loc) is Some(label) {
          attrs = @ast.merge_attrs(
            attrs,
            @ast.attrs_with(asm_label=Some(label)),
          )
        }
        attrs = @ast.merge_attrs(attrs, parse_attributes(p))
      }
      let mut ty = apply_decl_wrappers(base, wrappers)
      let call_conv = @ast.normalize_call_conv(attrs.call_conv)
      ty = @ast.apply_call_conv_to_type(ty, call_conv)
      Some({
        name: parts.name,
        id: parts.id,
        ty,
        params: parts.params,
        varargs: parts.varargs,
        is_old_style: parts.is_old_style,
        attrs,
        loc: parts.loc,
      })
    }
  }
}

///|
fn parse_paren_pointer_abstract(
  p : Parser,
  base : @ast.CType,
) -> (@ast.CType, @ast.Attributes) {
  let fallback_loc = peek_token(p).loc
  let parts = parse_paren_pointer_parts(p, true, fallback_loc)
  let parts = match parts {
    None => return (base, @ast.empty_attrs())
    Some(parts) => parts
  }
  let (
    outer_wrappers,
    _outer_params,
    _outer_varargs,
    _outer_old_style,
    suffix_attrs,
  ) = parse_suffix_wrappers(p)
  let wrappers = parts.wrappers
  for wrap in outer_wrappers {
    wrappers.push(wrap)
  }
  let attrs = @ast.merge_attrs(parts.attrs, suffix_attrs)
  let mut ty = apply_decl_wrappers(base, wrappers)
  let call_conv = @ast.normalize_call_conv(attrs.call_conv)
  ty = @ast.apply_call_conv_to_type(ty, call_conv)
  (ty, attrs)
}

///|
fn parse_declarator_suffix(
  p : Parser,
  ty_in : @ast.CType,
) -> (@ast.CType, Array[@ast.Param]?, Bool, Bool, @ast.Attributes) {
  let mut ty = ty_in
  let mut varargs = false
  let mut old_style = false
  let mut attrs = parse_attributes(p)
  let array_sizes : Array[(Int?, @ast.Expr?)] = []
  while match_token(p, LBracket) is Some(_) {
    let size = parse_array_size(p)
    expect(p, RBracket, "expected ']' after array size") |> ignore
    array_sizes.push(size)
  }
  let mut i = array_sizes.length()
  while i > 0 {
    i = i - 1
    let (size, size_expr) = array_sizes[i]
    ty = Array(elem=ty, size~, size_expr~)
  }
  let params = if match_token(p, LParen) is Some(_) {
    let (params, has_varargs, is_old_style) = parse_param_list(p)
    varargs = has_varargs
    old_style = is_old_style
    let param_types = params.map(param => param.ty)
    ty = Function(
      return_type=ty,
      params=param_types,
      varargs~,
      is_old_style=old_style,
      call_conv=Default,
    )
    Some(params)
  } else {
    None
  }
  attrs = @ast.merge_attrs(attrs, parse_attributes(p))
  let call_conv = @ast.normalize_call_conv(attrs.call_conv)
  ty = @ast.apply_call_conv_to_type(ty, call_conv)
  (ty, params, varargs, old_style, attrs)
}

///|
fn parse_array_size(p : Parser) -> (Int?, @ast.Expr?) {
  if peek_token(p).kind is RBracket {
    return (None, None)
  }
  if peek_token(p).kind is KwStatic {
    ignore(advance_token(p))
  }
  let loc = peek_token(p).loc
  if peek_token(p).kind is IntLit && peek_kind(p, 1) is RBracket {
    let tok = advance_token(p)
    let text = token_lexeme(p, tok)
    match @ast.parse_int64_literal(text) {
      Some(v) =>
        if v < 0 {
          add_parse_error(p, loc, "invalid array size")
          let expr = @ast.Expr::IntLit(
            value=text,
            node_id=new_expr_id(p),
            loc=tok.loc,
          )
          return (None, Some(expr))
        } else {
          return (Some(v.to_int()), None)
        }
      None => {
        let expr = @ast.Expr::IntLit(
          value=text,
          node_id=new_expr_id(p),
          loc=tok.loc,
        )
        return (None, Some(expr))
      }
    }
  }
  let expr = parse_expr_cond(p)
  let size = match @ast.const_i64_from_expr(expr) {
    None => None
    Some(v) =>
      if v < 0 {
        add_parse_error(p, loc, "invalid array size")
        None
      } else {
        Some(v.to_int())
      }
  }
  (size, Some(expr))
}

///|
fn next_anon_tag(p : Parser) -> (String, Int) {
  p.anon_tag_id = p.anon_tag_id + 1
  let name = "__anon_tag_\{p.anon_tag_id}"
  let (_, id) = p.pp.interner.intern_view_with_id(name[:])
  (name, id)
}

///|
fn parse_struct_type(
  p : Parser,
  is_union~ : Bool,
) -> (@ast.CType, @source.SrcLoc)? {
  let kw = advance_token(p)
  let mut attrs = parse_attributes(p)
  let mut name = ""
  let mut id = 0
  if peek_token(p).kind is Ident {
    let tok = advance_token(p)
    name = token_lexeme(p, tok)
    id = @tokens.token_id(tok)
  } else {
    ()
  }
  attrs = @ast.merge_attrs(attrs, parse_attributes(p))
  if match_token(p, LBrace) is Some(_) {
    let fields = parse_struct_fields(p)
    expect(p, RBrace, "expected '}' after fields") |> ignore
    attrs = @ast.merge_attrs(attrs, parse_attributes(p))
    if name == "" {
      let (anon_name, anon_id) = next_anon_tag(p)
      name = anon_name
      id = anon_id
    }
    let ty = if is_union {
      @ast.CType::Union(name~, id~, fields=Some(fields), attrs~)
    } else {
      Struct(name~, id~, fields=Some(fields), attrs~)
    }
    return Some((ty, kw.loc))
  }
  if name == "" {
    add_parse_error(p, kw.loc, "expected tag name or '{'")
    return None
  }
  let ty = if is_union {
    @ast.CType::Union(name~, id~, fields=None, attrs~)
  } else {
    Struct(name~, id~, fields=None, attrs~)
  }
  Some((ty, kw.loc))
}

///|
fn parse_struct_fields(p : Parser) -> Array[@ast.RecordItem] {
  let items : Array[@ast.RecordItem] = []
  while !is_at_end(p) && peek_token(p).kind != RBrace {
    if match_token(p, KwStaticAssert) is Some(assert_tok) {
      let static_assert = parse_static_assert(p, assert_tok.loc)
      expect(p, Semicolon, "expected ';' after _Static_assert") |> ignore
      items.push(StaticAssert(static_assert))
      continue
    }
    match parse_decl_specs(p, allow_storage=false) {
      None => {
        synchronize(p)
        break
      }
      Some(specs) => {
        let base = @ast.apply_type_attrs(
          specs.ty,
          @ast.type_attrs_from(specs.attrs),
        )
        let loc = specs.loc
        let is_typedef = specs.is_typedef
        if is_typedef {
          add_parse_error(p, loc, "typedef not allowed in struct field")
        }
        let mut any_field = false
        while true {
          let decl = if peek_token(p).kind is Colon {
            Some({
              name: "",
              id: 0,
              ty: base,
              params: None,
              varargs: false,
              is_old_style: false,
              attrs: @ast.empty_attrs(),
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
          if decl is Some(field_decl) {
            let stripped = strip_type_qualifiers(field_decl.ty)
            let allow_anon = field_decl.name == "" &&
              bit_width is None &&
              (stripped is Struct(..) || stripped is Union(..))
            if field_decl.name != "" || bit_width is Some(_) || allow_anon {
              any_field = true
              let combined_attrs = @ast.merge_attrs(
                specs.attrs,
                field_decl.attrs,
              )
              let adjusted_ty = @ast.apply_call_conv_to_type(
                field_decl.ty,
                @ast.normalize_call_conv(combined_attrs.call_conv),
              )
              items.push(
                Field({
                  name: field_decl.name,
                  id: field_decl.id,
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
fn parse_enum_type(p : Parser) -> (@ast.CType, @source.SrcLoc)? {
  let kw = advance_token(p)
  let mut name = ""
  let mut id = 0
  if peek_token(p).kind is Ident {
    let tok = advance_token(p)
    name = token_lexeme(p, tok)
    id = @tokens.token_id(tok)
  } else {
    ()
  }
  if match_token(p, LBrace) is Some(_) {
    let items = parse_enum_items(p)
    expect(p, RBrace, "expected '}' after enum") |> ignore
    if name == "" {
      let (anon_name, anon_id) = next_anon_tag(p)
      name = anon_name
      id = anon_id
    }
    return Some((Enum(name~, id~, items=Some(items)), kw.loc))
  }
  if name == "" {
    add_parse_error(p, kw.loc, "expected enum name or '{'")
    return None
  }
  Some((Enum(name~, id~, items=None), kw.loc))
}

///|
fn parse_enum_items(p : Parser) -> Array[@ast.EnumItem] {
  let items : Array[@ast.EnumItem] = []
  if peek_token(p).kind is RBrace {
    return items
  }
  while true {
    let name_tok = expect_ident(p, "expected enumerator name")
    if name_tok is Some(tok) {
      let value = if match_token(p, Assign) is Some(_) {
        Some(parse_expr_cond(p))
      } else {
        None
      }
      items.push({
        name: token_lexeme(p, tok),
        id: @tokens.token_id(tok),
        value,
        loc: tok.loc,
      })
    }
    if match_token(p, Comma) is Some(_) {
      if peek_token(p).kind is RBrace {
        break
      }
      continue
    }
    break
  }
  items
}

///|
fn parse_param_list(p : Parser) -> (Array[@ast.Param], Bool, Bool) {
  let params : Array[@ast.Param] = []
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
  let first_mapped = if first.kind is Ident {
    special_ident_kind(first, p.pp.keyword_ids)
  } else {
    None
  }
  if first.kind is Ident && first_mapped is None && !has_typedef(p, first) {
    old_style = true
    while true {
      match expect_ident(p, "expected parameter name") {
        None => break
        Some(tok) =>
          params.push({
            name: token_lexeme(p, tok),
            id: @tokens.token_id(tok),
            ty: Int(kind=Int, unsigned=false),
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
  if peek_token(p).kind is KwVoid {
    let void_tok = advance_token(p)
    if match_token(p, RParen) is Some(_) {
      return (params, varargs, false)
    }
    if parse_param_after_base(p, Void, @ast.empty_attrs(), void_tok.loc)
      is Some(param) {
      params.push(param)
    }
  } else if parse_type_specifiers(p, allow_storage=false, allow_typedef=false)
    is Some(specs) {
    if parse_param_after_base(p, specs.ty, specs.attrs, specs.loc)
      is Some(param) {
      params.push(param)
    }
  }
  while true {
    if match_token(p, Comma) is Some(_) {
      if match_token(p, Ellipsis) is Some(_) {
        varargs = true
        expect(p, RParen, "expected ')' after '...'") |> ignore
        break
      }
      if parse_type_specifiers(p, allow_storage=false, allow_typedef=false)
        is Some(specs) {
        if parse_param_after_base(p, specs.ty, specs.attrs, specs.loc)
          is Some(param) {
          params.push(param)
        }
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
  base : @ast.CType,
  attrs : @ast.Attributes,
  loc : @source.SrcLoc,
) -> @ast.Param? {
  match parse_param_declarator(p, base, loc) {
    Some(param) => {
      let call_conv = @ast.normalize_call_conv(attrs.call_conv)
      let adjusted_ty = @ast.apply_call_conv_to_type(param.ty, call_conv)
      Some({ name: param.name, id: param.id, ty: adjusted_ty, loc: param.loc })
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
  base : @ast.CType,
  fallback_loc : @source.SrcLoc,
) -> @ast.Param? {
  // Parse pointer chain first so we can handle return-type pointers on
  // function-pointer parameter declarators like:
  //   void *(*transform)(void*)
  let (ty0, pointer_attrs) = parse_pointer_chain(p, base)
  let mut attrs = @ast.merge_attrs(pointer_attrs, parse_attributes(p))
  if is_paren_pointer_declarator(p) {
    let parts = parse_paren_pointer_parts(p, true, fallback_loc)
    let parts = match parts {
      None => return None
      Some(parts) => parts
    }
    let (
      outer_wrappers,
      _outer_params,
      _outer_varargs,
      _outer_old_style,
      suffix_attrs,
    ) = parse_suffix_wrappers(p)
    let wrappers = parts.wrappers
    for wrap in outer_wrappers {
      wrappers.push(wrap)
    }
    attrs = @ast.merge_attrs(attrs, parts.attrs)
    attrs = @ast.merge_attrs(attrs, suffix_attrs)
    let mut ty = apply_decl_wrappers(ty0, wrappers)
    let call_conv = @ast.normalize_call_conv(attrs.call_conv)
    ty = @ast.apply_call_conv_to_type(ty, call_conv)
    return Some({ name: parts.name, id: parts.id, ty, loc: parts.loc })
  }
  if peek_token(p).kind is Ident {
    let name_tok = advance_token(p)
    let (ty, _params, _varargs, _old_style, suffix_attrs) = parse_declarator_suffix(
      p, ty0,
    )
    attrs = @ast.merge_attrs(attrs, suffix_attrs)
    let call_conv = @ast.normalize_call_conv(attrs.call_conv)
    let adjusted_ty = @ast.apply_call_conv_to_type(ty, call_conv)
    return Some({
      name: token_lexeme(p, name_tok),
      id: @tokens.token_id(name_tok),
      ty: adjusted_ty,
      loc: name_tok.loc,
    })
  }

  // Unnamed parameter: still allow declarator suffixes like `int[10]`.
  let (ty, _params, _varargs, _old_style, suffix_attrs) = parse_declarator_suffix(
    p, ty0,
  )
  attrs = @ast.merge_attrs(attrs, suffix_attrs)
  let call_conv = @ast.normalize_call_conv(attrs.call_conv)
  let adjusted_ty = @ast.apply_call_conv_to_type(ty, call_conv)
  Some({ name: "", id: 0, ty: adjusted_ty, loc: fallback_loc })
}

///|
fn parse_compound_stmt(p : Parser, loc : @source.SrcLoc) -> @ast.Stmt {
  p.pending_typedef_scopes.push(false)
  let stmts : Array[@ast.Stmt] = Array::new(capacity=8)
  while true {
    match p.current.kind {
      Eof | RBrace => break
      _ => stmts.push(parse_stmt(p))
    }
  }
  expect(p, RBrace, "expected '}'") |> ignore
  let did_scope = p.pending_typedef_scopes.pop().unwrap_or(false)
  if did_scope {
    pop_typedef_scope(p)
  }
  Compound(stmts~, loc~)
}

///|
fn parse_stmt(p : Parser) -> @ast.Stmt {
  let tok = peek_token(p)
  match tok.kind {
    LBrace => {
      let lbrace = advance_token(p)
      return parse_compound_stmt(p, lbrace.loc)
    }
    KwStaticAssert => {
      let assert_tok = advance_token(p)
      let static_assert = parse_static_assert(p, assert_tok.loc)
      expect(p, Semicolon, "expected ';' after _Static_assert") |> ignore
      return StaticAssert(static_assert)
    }
    KwAsm => {
      let asm_tok = advance_token(p)
      let asm_stmt = parse_asm_stmt(p, asm_tok.loc)
      expect(p, Semicolon, "expected ';' after asm") |> ignore
      return Asm(asm_stmt)
    }
    KwCase => {
      let case_tok = advance_token(p)
      let expr = parse_expr(p)
      let end_expr = if match_token(p, Ellipsis) is Some(_) {
        Some(parse_expr(p))
      } else {
        None
      }
      expect(p, Colon, "expected ':' after case") |> ignore
      let body = parse_stmt(p)
      return Case(expr~, end_expr~, body~, loc=case_tok.loc)
    }
    KwDefault => {
      let def_tok = advance_token(p)
      expect(p, Colon, "expected ':' after default") |> ignore
      let body = parse_stmt(p)
      return Default(body~, loc=def_tok.loc)
    }
    KwIf => {
      let if_tok = advance_token(p)
      return parse_if_stmt(p, if_tok.loc)
    }
    KwWhile => {
      let while_tok = advance_token(p)
      return parse_while_stmt(p, while_tok.loc)
    }
    KwDo => {
      let do_tok = advance_token(p)
      return parse_do_while_stmt(p, do_tok.loc)
    }
    KwFor => {
      let for_tok = advance_token(p)
      return parse_for_stmt(p, for_tok.loc)
    }
    KwSwitch => {
      let sw_tok = advance_token(p)
      return parse_switch_stmt(p, sw_tok.loc)
    }
    KwBreak => {
      let break_tok = advance_token(p)
      expect(p, Semicolon, "expected ';' after break") |> ignore
      return Break(loc=break_tok.loc)
    }
    KwContinue => {
      let cont_tok = advance_token(p)
      expect(p, Semicolon, "expected ';' after continue") |> ignore
      return Continue(loc=cont_tok.loc)
    }
    KwGoto => {
      let goto_tok = advance_token(p)
      if p.current.kind is Star {
        ignore(advance_token(p))
        let expr = parse_expr(p)
        expect(p, Semicolon, "expected ';' after goto") |> ignore
        return GotoExpr(expr~, loc=goto_tok.loc)
      } else {
        let name = match expect_ident(p, "expected label after goto") {
          None => ""
          Some(tok) => token_lexeme(p, tok)
        }
        expect(p, Semicolon, "expected ';' after goto") |> ignore
        return Goto(name~, loc=goto_tok.loc)
      }
    }
    KwReturn => {
      let ret_tok = advance_token(p)
      if match_token(p, Semicolon) is Some(_) {
        return Return(value=None, loc=ret_tok.loc)
      }
      let value = parse_expr(p)
      expect(p, Semicolon, "expected ';' after return") |> ignore
      return Return(value=Some(value), loc=ret_tok.loc)
    }
    Semicolon => {
      let semi = advance_token(p)
      return Empty(loc=semi.loc)
    }
    _ => ()
  }
  if tok.kind is Ident && peek_kind(p, 1) is Colon {
    let label_tok = advance_token(p)
    expect(p, Colon, "expected ':' after label") |> ignore
    ignore(parse_attributes(p))
    let body = parse_stmt(p)
    return Label(name=token_lexeme(p, label_tok), body~, loc=label_tok.loc)
  }
  if is_type_start(p, tok) {
    ensure_typedef_scope(p)
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
            return Empty(loc=semi.loc)
          }
          return TagDef(ty=base, loc=semi.loc)
        } else {
          let decls : Array[@ast.VarDecl] = Array::new(capacity=4)
          let mut decl_loc = tok.loc
          let mut saw_decl = false
          while true {
            match parse_init_declarator(p, base) {
              None => {
                synchronize(p)
                return Empty(loc=tok.loc)
              }
              Some((decl, init)) => {
                if !saw_decl {
                  decl_loc = decl.loc
                  saw_decl = true
                }
                let combined_attrs = @ast.merge_attrs(base_attrs, decl.attrs)
                let adjusted_ty = @ast.apply_call_conv_to_type(
                  decl.ty,
                  @ast.normalize_call_conv(combined_attrs.call_conv),
                )
                if is_typedef {
                  if init is Some(_) {
                    add_parse_error(
                      p,
                      decl.loc,
                      "typedef cannot have initializer",
                    )
                  }
                  let typedef_ty = @ast.apply_type_attrs(
                    adjusted_ty,
                    @ast.type_attrs_from(combined_attrs),
                  )
                  define_typedef(p, decl.name, typedef_ty)
                } else {
                  let mut actual_init = init
                  if adjusted_ty is Function(..) && actual_init is Some(_) {
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
                    id: decl.id,
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
            return Empty(loc=decl_loc)
          }
          if saw_decl {
            return DeclStmt(decls~, loc=decl_loc)
          }
          return Empty(loc=tok.loc)
        }
      }
      None => {
        synchronize(p)
        return Empty(loc=tok.loc)
      }
    }
  }
  let expr = parse_expr(p)
  expect(p, Semicolon, "expected ';' after expression") |> ignore
  ExprStmt(expr~, loc=@ast.expr_loc(expr))
}

///|
fn parse_if_stmt(p : Parser, loc : @source.SrcLoc) -> @ast.Stmt {
  expect(p, LParen, "expected '(' after if") |> ignore
  let cond = parse_expr(p)
  expect(p, RParen, "expected ')' after if condition") |> ignore
  let then_branch = parse_stmt(p)
  let else_branch = match p.current.kind {
    KwElse => {
      advance_token(p) |> ignore
      Some(parse_stmt(p))
    }
    _ => None
  }
  If(cond~, then_branch~, else_branch~, loc~)
}

///|
fn parse_while_stmt(p : Parser, loc : @source.SrcLoc) -> @ast.Stmt {
  expect(p, LParen, "expected '(' after while") |> ignore
  let cond = parse_expr(p)
  expect(p, RParen, "expected ')' after while condition") |> ignore
  let body = parse_stmt(p)
  While(cond~, body~, loc~)
}

///|
fn parse_do_while_stmt(p : Parser, loc : @source.SrcLoc) -> @ast.Stmt {
  let body = parse_stmt(p)
  expect(p, KwWhile, "expected while after do") |> ignore
  expect(p, LParen, "expected '(' after while") |> ignore
  let cond = parse_expr(p)
  expect(p, RParen, "expected ')' after do-while condition") |> ignore
  expect(p, Semicolon, "expected ';' after do-while") |> ignore
  DoWhile(cond~, body~, loc~)
}

///|
fn parse_for_stmt(p : Parser, loc : @source.SrcLoc) -> @ast.Stmt {
  expect(p, LParen, "expected '(' after for") |> ignore
  p.pending_typedef_scopes.push(false)
  let init = parse_for_init(p)
  let mut did_scope = false
  let scope_idx = p.pending_typedef_scopes.length() - 1
  if p.pending_typedef_scopes[scope_idx] {
    did_scope = true
  } else {
    p.pending_typedef_scopes.pop() |> ignore
  }
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
  if did_scope {
    let opened = p.pending_typedef_scopes.pop().unwrap_or(false)
    if opened {
      pop_typedef_scope(p)
    }
  }
  For(init~, cond~, step~, body~, loc~)
}

///|
fn parse_switch_stmt(p : Parser, loc : @source.SrcLoc) -> @ast.Stmt {
  expect(p, LParen, "expected '(' after switch") |> ignore
  let cond = parse_expr(p)
  expect(p, RParen, "expected ')' after switch condition") |> ignore
  let body = parse_stmt(p)
  Switch(cond~, body~, loc~)
}

///|
fn parse_for_init(p : Parser) -> @ast.Stmt? {
  if match_token(p, Semicolon) is Some(_) {
    return None
  }
  if is_type_start(p, peek_token(p)) {
    ensure_typedef_scope(p)
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
          return Some(TagDef(ty=base, loc=semi.loc))
        } else {
          let decls : Array[@ast.VarDecl] = Array::new(capacity=4)
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
                let combined_attrs = @ast.merge_attrs(base_attrs, decl.attrs)
                let adjusted_ty = @ast.apply_call_conv_to_type(
                  decl.ty,
                  @ast.normalize_call_conv(combined_attrs.call_conv),
                )
                if is_typedef {
                  if init is Some(_) {
                    add_parse_error(
                      p,
                      decl.loc,
                      "typedef cannot have initializer",
                    )
                  }
                  let typedef_ty = @ast.apply_type_attrs(
                    adjusted_ty,
                    @ast.type_attrs_from(combined_attrs),
                  )
                  define_typedef(p, decl.name, typedef_ty)
                } else {
                  let mut actual_init = init
                  if adjusted_ty is Function(..) && actual_init is Some(_) {
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
                    id: decl.id,
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
          return Some(DeclStmt(decls~, loc=decl_loc))
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
  Some(ExprStmt(expr~, loc=@ast.expr_loc(expr)))
}

///|
fn parse_expr(p : Parser) -> @ast.Expr {
  parse_expr_comma(p)
}

///|
fn parse_expr_comma(p : Parser) -> @ast.Expr {
  let mut expr = parse_expr_eq(p)
  while true {
    match p.current.kind {
      Comma => {
        let tok = advance_token(p)
        let right = parse_expr_eq(p)
        expr = Binary(
          op=Comma,
          left=expr,
          right~,
          node_id=new_expr_id(p),
          loc=tok.loc,
        )
      }
      _ => break
    }
  }
  expr
}

///|
fn parse_expr_eq(p : Parser) -> @ast.Expr {
  let left = parse_expr_cond(p)
  let op = match p.current.kind {
    Assign => Some(@ast.BinaryOp::Assign)
    PlusAssign => Some(AddAssign)
    MinusAssign => Some(SubAssign)
    StarAssign => Some(MulAssign)
    SlashAssign => Some(DivAssign)
    PercentAssign => Some(ModAssign)
    ShiftLeftAssign => Some(ShlAssign)
    ShiftRightAssign => Some(ShrAssign)
    AmpAssign => Some(BitAndAssign)
    PipeAssign => Some(BitOrAssign)
    CaretAssign => Some(BitXorAssign)
    _ => None
  }
  match op {
    None => left
    Some(op) => {
      let tok = advance_token(p)
      let right = parse_expr_eq(p)
      Binary(op~, left~, right~, node_id=new_expr_id(p), loc=tok.loc)
    }
  }
}

///|
fn parse_expr_cond(p : Parser) -> @ast.Expr {
  let cond = parse_expr_binary(p, 1)
  match p.current.kind {
    Question => {
      let tok = advance_token(p)
      let then_expr = parse_expr(p)
      expect(p, Colon, "expected ':' in conditional expression") |> ignore
      let else_expr = parse_expr_cond(p)
      Conditional(
        cond~,
        then_expr~,
        else_expr~,
        node_id=new_expr_id(p),
        loc=tok.loc,
      )
    }
    _ => cond
  }
}

///|

///|
fn parse_expr_binary(p : Parser, min_prec : Int) -> @ast.Expr {
  let mut expr = parse_expr_unary(p)
  while true {
    let mut prec = 0
    let mut op = @ast.BinaryOp::Add
    match p.current.kind {
      PipePipe => {
        op = LogOr
        prec = 1
      }
      AmpAmp => {
        op = LogAnd
        prec = 2
      }
      Pipe => {
        op = BitOr
        prec = 3
      }
      Caret => {
        op = BitXor
        prec = 4
      }
      Amp => {
        op = BitAnd
        prec = 5
      }
      Eq => {
        op = Eq
        prec = 6
      }
      Ne => {
        op = Ne
        prec = 6
      }
      Lt => {
        op = Lt
        prec = 7
      }
      Le => {
        op = Le
        prec = 7
      }
      Gt => {
        op = Gt
        prec = 7
      }
      Ge => {
        op = Ge
        prec = 7
      }
      ShiftLeft => {
        op = Shl
        prec = 8
      }
      ShiftRight => {
        op = Shr
        prec = 8
      }
      Plus => {
        op = Add
        prec = 9
      }
      Minus => {
        op = Sub
        prec = 9
      }
      Star => {
        op = Mul
        prec = 10
      }
      Slash => {
        op = Div
        prec = 10
      }
      Percent => {
        op = Mod
        prec = 10
      }
      _ => ()
    }
    if prec == 0 || prec < min_prec {
      break
    }
    let tok = advance_token(p)
    let right = parse_expr_binary(p, prec + 1)
    expr = Binary(op~, left=expr, right~, node_id=new_expr_id(p), loc=tok.loc)
  }
  expr
}

///|
fn parse_expr_unary(p : Parser) -> @ast.Expr {
  match p.current.kind {
    KwSizeof => {
      let tok = advance_token(p)
      if peek_kind(p, 0) is LParen && is_type_start(p, peek_token_at(p, 1)) {
        expect(p, LParen, "expected '(' after sizeof") |> ignore
        match parse_type_name(p) {
          None => {
            add_parse_error(p, tok.loc, "expected type name after sizeof")
            return IntLit(value="0", node_id=new_expr_id(p), loc=tok.loc)
          }
          Some(ty) => {
            expect(p, RParen, "expected ')' after sizeof type") |> ignore
            return SizeofType(ty~, node_id=new_expr_id(p), loc=tok.loc)
          }
        }
      }
      let expr = parse_expr_unary(p)
      return SizeofExpr(expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    KwAlignof => {
      let tok = advance_token(p)
      if peek_kind(p, 0) is LParen && is_type_start(p, peek_token_at(p, 1)) {
        expect(p, LParen, "expected '(' after alignof") |> ignore
        match parse_type_name(p) {
          None => {
            add_parse_error(p, tok.loc, "expected type name after alignof")
            return IntLit(value="0", node_id=new_expr_id(p), loc=tok.loc)
          }
          Some(ty) => {
            expect(p, RParen, "expected ')' after alignof type") |> ignore
            return AlignofType(ty~, node_id=new_expr_id(p), loc=tok.loc)
          }
        }
      }
      let expr = parse_expr_unary(p)
      return AlignofExpr(expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    _ => ()
  }
  if peek_kind(p, 0) is LParen && is_type_start(p, peek_token_at(p, 1)) {
    let lparen = advance_token(p)
    match parse_type_name(p) {
      None => {
        add_parse_error(p, lparen.loc, "expected type name in cast")
        return IntLit(value="0", node_id=new_expr_id(p), loc=lparen.loc)
      }
      Some(ty) => {
        expect(p, RParen, "expected ')' after cast type") |> ignore
        if peek_kind(p, 0) is LBrace {
          let init = parse_initializer(p)
          let literal = @ast.Expr::CompoundLiteral(
            ty~,
            init~,
            node_id=new_expr_id(p),
            loc=lparen.loc,
          )
          return parse_postfix_tail(p, literal)
        }
        let expr = parse_expr_unary(p)
        return Cast(ty~, expr~, node_id=new_expr_id(p), loc=lparen.loc)
      }
    }
  }
  match p.current.kind {
    AmpAmp => {
      let tok = advance_token(p)
      let name_tok = expect_ident(p, "expected label identifier after &&")
      match name_tok {
        None => IntLit(value="0", node_id=new_expr_id(p), loc=tok.loc)
        Some(label_tok) =>
          LabelAddr(
            name=token_lexeme(p, label_tok),
            id=@tokens.token_id(label_tok),
            node_id=new_expr_id(p),
            loc=tok.loc,
          )
      }
    }
    PlusPlus => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Unary(op=PreInc, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    MinusMinus => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Unary(op=PreDec, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    Plus => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Unary(op=Plus, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    Minus => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Unary(op=Minus, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    Bang => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Unary(op=Not, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    Tilde => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Unary(op=BitNot, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    Amp => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Unary(op=Addr, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    Star => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Unary(op=Deref, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    _ => parse_expr_postfix(p)
  }
}

///|
fn parse_expr_postfix(p : Parser) -> @ast.Expr {
  let expr = parse_expr_primary(p)
  parse_postfix_tail(p, expr)
}

///|
fn parse_postfix_tail(p : Parser, base : @ast.Expr) -> @ast.Expr {
  let mut expr = base
  while true {
    match p.current.kind {
      LParen => {
        let tok = advance_token(p)
        let args = parse_call_args(p)
        expr = Call(callee=expr, args~, node_id=new_expr_id(p), loc=tok.loc)
        continue
      }
      LBracket => {
        let tok = advance_token(p)
        let index = parse_expr(p)
        expect(p, RBracket, "expected ']' after index") |> ignore
        expr = Index(base=expr, index~, node_id=new_expr_id(p), loc=tok.loc)
        continue
      }
      Dot => {
        let tok = advance_token(p)
        let (name, id) = match expect_ident(p, "expected field name") {
          None => ("", 0)
          Some(tok) => (token_lexeme(p, tok), @tokens.token_id(tok))
        }
        expr = Member(
          base=expr,
          name~,
          id~,
          is_arrow=false,
          node_id=new_expr_id(p),
          loc=tok.loc,
        )
        continue
      }
      Arrow => {
        let tok = advance_token(p)
        let (name, id) = match expect_ident(p, "expected field name") {
          None => ("", 0)
          Some(tok) => (token_lexeme(p, tok), @tokens.token_id(tok))
        }
        expr = Member(
          base=expr,
          name~,
          id~,
          is_arrow=true,
          node_id=new_expr_id(p),
          loc=tok.loc,
        )
        continue
      }
      PlusPlus => {
        let tok = advance_token(p)
        expr = Unary(op=PostInc, expr~, node_id=new_expr_id(p), loc=tok.loc)
        continue
      }
      MinusMinus => {
        let tok = advance_token(p)
        expr = Unary(op=PostDec, expr~, node_id=new_expr_id(p), loc=tok.loc)
        continue
      }
      _ => break
    }
  }
  expr
}

///|
fn parse_call_args(p : Parser) -> Array[@ast.Expr] {
  let args : Array[@ast.Expr] = Array::new(capacity=4)
  match p.current.kind {
    RParen => {
      advance_token(p) |> ignore
      return args
    }
    _ => ()
  }
  while true {
    args.push(parse_expr_eq(p))
    match p.current.kind {
      Comma => {
        advance_token(p) |> ignore
        continue
      }
      _ => ()
    }
    expect(p, RParen, "expected ')' after arguments") |> ignore
    break
  }
  args
}

///|
fn parse_expr_primary(p : Parser) -> @ast.Expr {
  let tok = advance_token(p)
  match tok.kind {
    IntLit =>
      IntLit(value=token_lexeme(p, tok), node_id=new_expr_id(p), loc=tok.loc)
    FloatLit =>
      FloatLit(value=token_lexeme(p, tok), node_id=new_expr_id(p), loc=tok.loc)
    CharLit =>
      CharLit(
        value=parse_char_literal_value(p, tok),
        node_id=new_expr_id(p),
        loc=tok.loc,
      )
    StrLit => parse_string_literal_expr(p, tok)
    Ident =>
      match p.current.kind {
        LParen => {
          let id = @tokens.token_id(tok)
          if id == p.builtin_ids.types_compatible_p {
            expect(p, LParen, "expected '(' after __builtin_types_compatible_p")
            |> ignore
            let a = match parse_type_name(p) {
              None => {
                add_parse_error(p, tok.loc, "expected type name in builtin")
                @ast.default_int_type()
              }
              Some(ty) => ty
            }
            expect(p, Comma, "expected ',' in __builtin_types_compatible_p")
            |> ignore
            let b = match parse_type_name(p) {
              None => {
                add_parse_error(p, tok.loc, "expected type name in builtin")
                @ast.default_int_type()
              }
              Some(ty) => ty
            }
            expect(p, RParen, "expected ')' after __builtin_types_compatible_p")
            |> ignore
            BuiltinTypesCompatibleP(a~, b~, node_id=new_expr_id(p), loc=tok.loc)
          } else if id == p.builtin_ids.offsetof {
            expect(p, LParen, "expected '(' after __builtin_offsetof") |> ignore
            let ty = match parse_type_name(p) {
              None => {
                add_parse_error(
                  p,
                  tok.loc,
                  "expected type name in __builtin_offsetof",
                )
                @ast.default_int_type()
              }
              Some(v) => v
            }
            expect(p, Comma, "expected ',' in __builtin_offsetof") |> ignore
            let path : Array[String] = []
            if expect_ident(p, "expected member name in __builtin_offsetof")
              is Some(id) {
              path.push(token_lexeme(p, id))
            }
            while true {
              match p.current.kind {
                Dot => {
                  advance_token(p) |> ignore
                  if expect_ident(
                      p, "expected member name in __builtin_offsetof",
                    )
                    is Some(id) {
                    path.push(token_lexeme(p, id))
                  } else {
                    break
                  }
                }
                _ => break
              }
            }
            expect(p, RParen, "expected ')' after __builtin_offsetof") |> ignore
            BuiltinOffsetof(ty~, path~, node_id=new_expr_id(p), loc=tok.loc)
          } else if id == p.builtin_ids.va_arg {
            expect(p, LParen, "expected '(' after __builtin_va_arg") |> ignore
            let list = parse_expr_eq(p)
            expect(p, Comma, "expected ',' in __builtin_va_arg") |> ignore
            let ty = match parse_type_name(p) {
              None => {
                add_parse_error(p, tok.loc, "expected type name in builtin")
                @ast.default_int_type()
              }
              Some(v) => v
            }
            expect(p, RParen, "expected ')' after __builtin_va_arg") |> ignore
            BuiltinVaArg(list~, ty~, node_id=new_expr_id(p), loc=tok.loc)
          } else {
            Ident(
              name=token_lexeme(p, tok),
              id=@tokens.token_id(tok),
              node_id=new_expr_id(p),
              loc=tok.loc,
            )
          }
        }
        _ =>
          Ident(
            name=token_lexeme(p, tok),
            id=@tokens.token_id(tok),
            node_id=new_expr_id(p),
            loc=tok.loc,
          )
      }
    LParen =>
      match p.current.kind {
        LBrace => {
          let lbrace = advance_token(p)
          let block = parse_compound_stmt(p, lbrace.loc)
          expect(p, RParen, "expected ')' after statement expression") |> ignore
          match block {
            Compound(stmts~, ..) =>
              StmtExpr(stmts~, node_id=new_expr_id(p), loc=tok.loc)
            _ => StmtExpr(stmts=[], node_id=new_expr_id(p), loc=tok.loc)
          }
        }
        _ => {
          let expr = parse_expr(p)
          expect(p, RParen, "expected ')'") |> ignore
          expr
        }
      }
    _ => {
      add_parse_error(p, tok.loc, "unexpected token in expression")
      IntLit(value="0", node_id=new_expr_id(p), loc=tok.loc)
    }
  }
}

///|

///|
fn parse_string_literal_expr(p : Parser, first : @tokens.Token) -> @ast.Expr {
  let (value, len) = decode_string_literal(p, token_lexeme(p, first), first.loc)
  if peek_token(p).kind != StrLit {
    return StringLit(
      value~,
      length=len + 1,
      node_id=new_expr_id(p),
      loc=first.loc,
    )
  }
  let sb = StringBuilder::new(size_hint=token_lexeme_len(p, first))
  let mut byte_len = len
  sb.write_string(value)
  while peek_token(p).kind is StrLit {
    let tok = advance_token(p)
    let (part, part_len) = decode_string_literal(
      p,
      token_lexeme(p, tok),
      tok.loc,
    )
    sb.write_string(part)
    byte_len = byte_len + part_len
  }
  StringLit(
    value=sb.to_string(),
    length=byte_len + 1,
    node_id=new_expr_id(p),
    loc=first.loc,
  )
}

///|
fn decode_string_literal(
  p : Parser,
  lexeme : String,
  loc : @source.SrcLoc,
) -> (String, Int) {
  let len = lexeme.length()
  let size_hint = if len > 2 { len - 2 } else { 0 }
  let sb = StringBuilder::new(size_hint~)
  let mut i = 1
  let mut count = 0
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
fn parse_char_literal_value(p : Parser, tok : @tokens.Token) -> Int {
  let lexeme = token_lexeme(p, tok)
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
  loc : @source.SrcLoc,
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
  loc : @source.SrcLoc,
) -> (Int, Int) {
  let mut i = start
  let mut value = 0
  let mut saw = false
  while i < text.length() {
    let code = text[i]
    let digit = @util.hex_digit_value(code)
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
fn is_type_start(p : Parser, tok : @tokens.Token) -> Bool {
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
    KwAtomic => true
    KwExtern => true
    KwStatic => true
    KwAuto => true
    KwRegister => true
    KwInline => true
    KwStruct => true
    KwUnion => true
    KwEnum => true
    KwTypeof => true
    KwTypedef => true
    Ident => has_typedef(p, tok)
    _ => false
  }
}

///|
fn ensure_typedef_capacity_with(
  counts : Array[Int],
  values : Array[@ast.CType?],
  scope_levels : Array[Int],
  id : Int,
) -> Unit {
  if id <= 0 {
    return
  }
  let mut idx = counts.length()
  while idx < id {
    counts.push(0)
    values.push(None)
    scope_levels.push(0)
    idx = idx + 1
  }
}

///|
fn ensure_typedef_capacity(p : Parser, id : Int) -> Unit {
  ensure_typedef_capacity_with(
    p.typedef_counts,
    p.typedef_values,
    p.typedef_scope_levels,
    id,
  )
}

///|
fn get_typedef_count(p : Parser, id : Int) -> Int {
  if id <= 0 || id > p.typedef_counts.length() {
    0
  } else {
    p.typedef_counts[id - 1]
  }
}

///|
fn set_typedef_count(p : Parser, id : Int, count : Int) -> Unit {
  if id <= 0 {
    return
  }
  ensure_typedef_capacity(p, id)
  p.typedef_counts[id - 1] = count
}

///|
fn get_typedef_value(p : Parser, id : Int) -> @ast.CType? {
  if id <= 0 || id > p.typedef_values.length() {
    None
  } else {
    p.typedef_values[id - 1]
  }
}

///|
fn set_typedef_value(p : Parser, id : Int, value : @ast.CType?) -> Unit {
  if id <= 0 {
    return
  }
  ensure_typedef_capacity(p, id)
  p.typedef_values[id - 1] = value
}

///|
fn get_typedef_scope_level(p : Parser, id : Int) -> Int {
  if id <= 0 || id > p.typedef_scope_levels.length() {
    0
  } else {
    p.typedef_scope_levels[id - 1]
  }
}

///|
fn set_typedef_scope_level(p : Parser, id : Int, level : Int) -> Unit {
  if id <= 0 {
    return
  }
  ensure_typedef_capacity(p, id)
  p.typedef_scope_levels[id - 1] = level
}

///|
fn current_typedef_scope_id(p : Parser) -> Int {
  let len = p.typedef_scope_stack.length()
  if len == 0 {
    0
  } else {
    p.typedef_scope_stack[len - 1]
  }
}

///|
fn push_typedef_scope(p : Parser) -> Unit {
  let scope_id = p.next_typedef_scope_id
  p.next_typedef_scope_id = scope_id + 1
  p.typedef_scope_stack.push(scope_id)
  p.typedef_overrides.push([])
}

///|
fn pop_typedef_scope(p : Parser) -> Unit {
  if p.typedef_overrides.pop() is Some(overrides) {
    let mut i = overrides.length()
    while i > 0 {
      i = i - 1
      let (id, prev, prev_scope) = overrides[i]
      set_typedef_value(p, id, prev)
      set_typedef_scope_level(p, id, prev_scope)
      dec_typedef_count(p, id)
    }
  }
  p.typedef_scope_stack.pop() |> ignore
}

///|
fn ensure_typedef_scope(p : Parser) -> Unit {
  let len = p.pending_typedef_scopes.length()
  if len == 0 {
    return
  }
  let idx = len - 1
  if !p.pending_typedef_scopes[idx] {
    push_typedef_scope(p)
    p.pending_typedef_scopes[idx] = true
  }
}

///|
fn typedef_id_from_name(p : Parser, name : String) -> Int {
  if name == "" {
    return 0
  }
  let (_, id) = p.pp.interner.intern_view_with_id(name[:])
  id
}

///|
fn typedef_id_from_token(_p : Parser, tok : @tokens.Token) -> Int {
  if tok.kind != Ident {
    return 0
  }
  @tokens.token_id(tok)
}

///|
fn inc_typedef_count(p : Parser, id : Int) -> Unit {
  if id == 0 {
    return
  }
  let count = get_typedef_count(p, id)
  set_typedef_count(p, id, count + 1)
}

///|
fn dec_typedef_count(p : Parser, id : Int) -> Unit {
  if id == 0 {
    return
  }
  let count = get_typedef_count(p, id)
  if count <= 1 {
    set_typedef_count(p, id, 0)
  } else {
    set_typedef_count(p, id, count - 1)
  }
}

///|
fn typedef_ref_type(ty : @ast.CType) -> @ast.CType {
  match ty {
    Qualified(qual~, base~) => Qualified(qual~, base=typedef_ref_type(base))
    Attributed(attrs~, base~) => Attributed(attrs~, base=typedef_ref_type(base))
    Pointer(inner) => Pointer(typedef_ref_type(inner))
    Array(elem~, size~, size_expr~) =>
      Array(elem=typedef_ref_type(elem), size~, size_expr~)
    Function(return_type~, params~, varargs~, is_old_style~, call_conv~) =>
      Function(
        return_type=typedef_ref_type(return_type),
        params=params.map(t => typedef_ref_type(t)),
        varargs~,
        is_old_style~,
        call_conv~,
      )
    Struct(name~, id~, fields=Some(_), attrs~) =>
      Struct(name~, id~, fields=None, attrs~)
    Union(name~, id~, fields=Some(_), attrs~) =>
      Union(name~, id~, fields=None, attrs~)
    Enum(name~, id~, items=Some(_)) => Enum(name~, id~, items=None)
    _ => ty
  }
}

///|
fn define_typedef(p : Parser, name : String, ty : @ast.CType) -> Unit {
  let id = typedef_id_from_name(p, name)
  if id == 0 {
    return
  }
  let scope_id = current_typedef_scope_id(p)
  let prev_scope = get_typedef_scope_level(p, id)
  let already = prev_scope == scope_id
  let resolved = typedef_ref_type(ty)
  let idx = p.typedef_overrides.length() - 1
  if !already {
    let overrides = p.typedef_overrides[idx]
    overrides.push((id, get_typedef_value(p, id), prev_scope))
    p.typedef_overrides[idx] = overrides
    set_typedef_value(p, id, Some(resolved))
    set_typedef_scope_level(p, id, scope_id)
    inc_typedef_count(p, id)
  } else {
    set_typedef_value(p, id, Some(resolved))
  }
}

///|
fn lookup_typedef(p : Parser, tok : @tokens.Token) -> @ast.CType? {
  let id = typedef_id_from_token(p, tok)
  if id == 0 {
    return None
  }
  get_typedef_value(p, id)
}

///|
fn has_typedef(p : Parser, tok : @tokens.Token) -> Bool {
  let id = typedef_id_from_token(p, tok)
  if id == 0 {
    return false
  }
  get_typedef_count(p, id) > 0
}

///|
fn add_parse_error(p : Parser, loc : @source.SrcLoc, message : String) -> Unit {
  @diag.add_error(p.diags, loc, message)
}

///|
fn token_lexeme(p : Parser, tok : @tokens.Token) -> String {
  @tokens.token_text_with(p.pp.interner, p.pp.lexeme_pool, tok)
}

///|
fn token_lexeme_len(p : Parser, tok : @tokens.Token) -> Int {
  @tokens.token_text_len_with(p.pp.interner, p.pp.lexeme_pool, tok)
}

///|
fn peek_token(p : Parser) -> @tokens.Token {
  p.current
}

///|
fn peek_token_at(p : Parser, offset : Int) -> @tokens.Token {
  if offset <= 0 {
    return p.current
  }
  if offset == 1 {
    return p.lookahead
  }
  let target = p.buffer_pos + (offset - 2)
  while p.buffer.length() <= target {
    p.buffer.push(@preproc.next_pp_token(p.pp))
  }
  p.buffer[target]
}

///|
fn peek_kind(p : Parser, offset : Int) -> @tokens.TokenKind {
  peek_token_at(p, offset).kind
}

///|
fn advance_token(p : Parser) -> @tokens.Token {
  let tok = p.current
  p.current = p.lookahead
  if p.buffer_pos < p.buffer.length() {
    p.lookahead = p.buffer[p.buffer_pos]
    p.buffer_pos = p.buffer_pos + 1
    if p.buffer_pos == p.buffer.length() {
      p.buffer.clear()
      p.buffer_pos = 0
    }
  } else {
    p.lookahead = @preproc.next_pp_token(p.pp)
  }
  tok
}

///|
fn match_token(p : Parser, kind : @tokens.TokenKind) -> @tokens.Token? {
  if p.current.kind == kind {
    Some(advance_token(p))
  } else {
    None
  }
}

///|
fn expect(
  p : Parser,
  kind : @tokens.TokenKind,
  message : String,
) -> @tokens.Token {
  let tok = p.current
  if tok.kind == kind {
    return advance_token(p)
  }
  add_parse_error(p, tok.loc, message)
  tok
}

///|
fn expect_ident(p : Parser, message : String) -> @tokens.Token? {
  let tok = p.current
  if tok.kind is Ident {
    return Some(advance_token(p))
  }
  add_parse_error(p, tok.loc, message)
  None
}

///|
fn is_at_end(p : Parser) -> Bool {
  match peek_token(p).kind {
    Eof => true
    _ => false
  }
}

///|
fn synchronize(p : Parser) -> Unit {
  while !is_at_end(p) {
    let tok = advance_token(p)
    match tok.kind {
      Semicolon | RBrace => return
      _ => ()
    }
  }
}
