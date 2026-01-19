///|
struct Parser {
  pp : Preprocessor
  mut current : Token
  mut lookahead : Token
  diags : DiagBag
  typedef_counts : Array[Int]
  typedef_values : Array[CType?]
  typedef_scope_levels : Array[Int]
  typedef_scope_stack : Array[Int]
  mut next_typedef_scope_id : Int
  typedef_overrides : Array[Array[(Int, CType?, Int)]]
  pending_typedef_scopes : Array[Bool]
  mut anon_tag_id : Int
  mut next_expr_id : Int
  builtin_ids : BuiltinIds
}

///|
struct BuiltinIds {
  types_compatible_p : Int
  offsetof : Int
  va_arg : Int
}

///|
fn new_parser(pp : Preprocessor) -> Parser {
  let typedef_counts : Array[Int] = []
  let typedef_values : Array[CType?] = []
  let typedef_scope_levels : Array[Int] = []
  let typedef_scope_stack : Array[Int] = [1]
  let next_typedef_scope_id = 2
  let builtin_defs = [
    ("__builtin_va_list", CType::Pointer(CType::Void)),
    ("_Float16", CType::Int(kind=CIntKind::Short, unsigned=true)),
  ]
  for def in builtin_defs {
    let (name, ty) = def
    let (_, id) = pp.interner.intern_view_with_id(name[:])
    ensure_typedef_capacity_with(
      typedef_counts,
      typedef_values,
      typedef_scope_levels,
      id,
    )
    typedef_counts[id - 1] = 1
    typedef_values[id - 1] = Some(ty)
    typedef_scope_levels[id - 1] = 1
  }
  let current = next_pp_token(pp)
  let lookahead = next_pp_token(pp)
  let (_, builtin_types_compatible_p) =
    pp.interner.intern_view_with_id("__builtin_types_compatible_p"[:])
  let (_, builtin_offsetof) =
    pp.interner.intern_view_with_id("__builtin_offsetof"[:])
  let (_, builtin_va_arg) = pp.interner.intern_view_with_id("__builtin_va_arg"[:])
  {
    pp,
    current,
    lookahead,
    diags: pp.diags,
    typedef_counts,
    typedef_values,
    typedef_scope_levels,
    typedef_scope_stack,
    next_typedef_scope_id,
    typedef_overrides: [[]],
    pending_typedef_scopes: [],
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
fn special_ident_kind(tok : Token, ids : KeywordIds) -> TokenKind? {
  match keyword_kind_from_id(tok.id, ids) {
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
        | KwInline
        | KwNoreturn => Some(kind)
        _ => None
      }
    None => None
  }
}

///|
fn parse_translation_unit(pp : Preprocessor) -> TranslationUnit {
  let parser = new_parser(pp)
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
  let expr_id_max = p.next_expr_id
  { decls, expr_id_max }
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
    None => {
      let head = peek_token(p)
      if head.kind == Ident && !has_typedef(p, head) {
        Some({
          ty: CType::Int(kind=CIntKind::Int, unsigned=false),
          loc: head.loc,
          is_typedef: false,
          storage: StorageClass::Default,
          is_inline: false,
          attrs: empty_attrs(),
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
                            Decl::FuncDecl({
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
                          Decl::Var({
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
                      Decl::Var({
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
  params : Array[Param],
) -> Array[Param] {
  let updated = params
  let param_map : FastMap[String, Int] = fast_map_new()
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
  let seen : FastMap[String, Bool] = fast_map_new()
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
    let tok = peek_token(p)
    let mut kind = tok.kind
    if kind == Ident {
      match special_ident_kind(tok, p.pp.keyword_ids) {
        Some(mapped) => kind = mapped
        None => ()
      }
    }
    match kind {
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
    let mut kind = tok.kind
    if kind == Ident {
      match special_ident_kind(tok, p.pp.keyword_ids) {
        Some(mapped) => kind = mapped
        None => ()
      }
    }
    match kind {
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
          match kind {
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
      KwNoreturn => {
        attrs = merge_attrs(attrs, attrs_with(noreturn=true))
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
        match lookup_typedef(p, tok) {
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
  let tok = peek_token(p)
  let mut kind = tok.kind
  if kind == Ident {
    match special_ident_kind(tok, p.pp.keyword_ids) {
      Some(mapped) => kind = mapped
      None => ()
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
    | KwSigned
    | KwUnsigned
    | KwAttribute
    | KwTypeof => true
    Ident => has_typedef(p, peek_token(p))
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
  let tok = advance_token(p)
  let (part, _len) = decode_string_literal(p, tok.lexeme, tok.loc)
  if peek_token(p).kind != StrLit {
    return Some(part)
  }
  let sb = StringBuilder::new(size_hint=tok.lexeme.length())
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
    if peek_token(p).kind == Ident {
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
        attrs = merge_attrs(attrs, attrs_with(constructor_attr=true))
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
          let alias_name = parse_attr_string(p, name_tok.loc)
          attrs = merge_attrs(attrs, attrs_with(alias_name~))
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
      // Parse any leading pointer chain first so we can handle cases like:
      //   void *(*fp)(void)
      // where the return type itself is a pointer and the direct-declarator is
      // a parenthesized pointer declarator.
      let (ty0, pointer_attrs) = parse_pointer_chain(p, base)
      let mut attrs = merge_attrs(base_attrs, pointer_attrs)
      attrs = merge_attrs(attrs, parse_attributes(p))
      if is_paren_pointer_declarator(p) {
        let (ty, paren_attrs) = parse_paren_pointer_abstract(p, ty0)
        attrs = merge_attrs(attrs, paren_attrs)
        let call_conv = normalize_call_conv(attrs.call_conv)
        Some(apply_call_conv_to_type(ty, call_conv))
      } else {
        let (full, _params, _varargs, _old_style, suffix_attrs) = parse_declarator_suffix(
          p, ty0,
        )
        attrs = merge_attrs(attrs, suffix_attrs)
        let call_conv = normalize_call_conv(attrs.call_conv)
        Some(apply_call_conv_to_type(full, call_conv))
      }
    }
  }
}

///|
struct Declarator {
  name : String
  id : Int
  ty : CType
  params : Array[Param]?
  varargs : Bool
  is_old_style : Bool
  attrs : Attributes
  loc : SrcLoc
}

///|
fn parse_declarator(p : Parser, base : CType) -> Declarator? {
  // Parse pointer chain first so we can handle return-type pointers on
  // function-pointer declarators like:
  //   void *(*fp)(void)
  let (ty0, pointer_attrs) = parse_pointer_chain(p, base)
  let mut attrs = merge_attrs(pointer_attrs, parse_attributes(p))
  if is_paren_pointer_declarator(p) {
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
          attrs: merge_attrs(attrs, decl.attrs),
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
          id: tok.id,
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
  // Like parse_declarator, but the name may be omitted (anonymous fields).
  let (ty0, pointer_attrs) = parse_pointer_chain(p, base)
  let mut attrs = merge_attrs(pointer_attrs, parse_attributes(p))
  if is_paren_pointer_declarator(p) {
    expect(p, LParen, "expected '(' in declarator") |> ignore
    let quals : Array[TypeQual] = []
    let mut inner_attrs = parse_attributes(p)
    while match_token(p, Star) is Some(_) {
      quals.push(parse_type_qualifiers(p))
      inner_attrs = merge_attrs(inner_attrs, parse_attributes(p))
    }
    inner_attrs = merge_attrs(inner_attrs, parse_attributes(p))
    let name_tok = if peek_token(p).kind == Ident {
      Some(advance_token(p))
    } else {
      None
    }
    let inner_array_sizes : Array[(Int?, Expr?)] = []
    while match_token(p, LBracket) is Some(_) {
      let size = parse_array_size(p)
      expect(p, RBracket, "expected ']' after array size") |> ignore
      inner_array_sizes.push(size)
    }
    expect(p, RParen, "expected ')' in declarator") |> ignore
    let (ty, params, varargs, is_old_style, suffix_attrs) = parse_declarator_suffix(
      p, ty0,
    )
    attrs = merge_attrs(merge_attrs(attrs, inner_attrs), suffix_attrs)
    let mut wrapped = ty
    for qual in quals {
      wrapped = CType::Pointer(wrapped)
      wrapped = apply_qualifiers(wrapped, qual)
    }
    let mut i = inner_array_sizes.length()
    while i > 0 {
      i = i - 1
      let (size, size_expr) = inner_array_sizes[i]
      wrapped = CType::Array(elem=wrapped, size~, size_expr~)
    }
    let (name, id, loc) = match name_tok {
      Some(tok) => (tok.lexeme, tok.id, tok.loc)
      None => ("", 0, fallback_loc)
    }
    Some({ name, id, ty: wrapped, params, varargs, is_old_style, attrs, loc })
  } else {
    let (name, id, loc) = if peek_token(p).kind == Ident {
      let name_tok = advance_token(p)
      (name_tok.lexeme, name_tok.id, name_tok.loc)
    } else {
      ("", 0, fallback_loc)
    }
    let (ty, params, varargs, is_old_style, suffix_attrs) = parse_declarator_suffix(
      p, ty0,
    )
    attrs = merge_attrs(attrs, suffix_attrs)
    Some({ name, id, ty, params, varargs, is_old_style, attrs, loc })
  }
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
      let (name, id) = match expect_ident(p, "expected field name") {
        None => ("", 0)
        Some(tok) => (tok.lexeme, tok.id)
      }
      designators.push(InitDesignator::Field(name~, id~, loc=dot_tok.loc))
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
        InitDesignator::Field(name=name_tok.lexeme, id=name_tok.id, loc=name_tok.loc),
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
  let inner_array_sizes : Array[(Int?, Expr?)] = []
  let mut inner_params : Array[Param]? = None
  let mut inner_varargs = false
  let mut inner_old_style = false
  attrs = merge_attrs(attrs, parse_attributes(p))
  while match_token(p, LBracket) is Some(_) {
    let size = parse_array_size(p)
    expect(p, RBracket, "expected ']' after array size") |> ignore
    inner_array_sizes.push(size)
  }
  if match_token(p, LParen) is Some(_) {
    let (params, has_varargs, is_old_style) = parse_param_list(p)
    inner_params = Some(params)
    inner_varargs = has_varargs
    inner_old_style = is_old_style
  }
  attrs = merge_attrs(attrs, parse_attributes(p))
  expect(p, RParen, "expected ')' in declarator") |> ignore
  match name_tok {
    None => None
    Some(tok) => {
      let (
        post_ty,
        _outer_params,
        _outer_varargs,
        _outer_old_style,
        suffix_attrs,
      ) = parse_declarator_suffix(p, base)
      attrs = merge_attrs(attrs, suffix_attrs)
      if match_token(p, KwAsm) is Some(asm_tok) {
        match parse_asm_label(p, asm_tok.loc) {
          None => ()
          Some(label) =>
            attrs = merge_attrs(attrs, attrs_with(asm_label=Some(label)))
        }
        attrs = merge_attrs(attrs, parse_attributes(p))
      }
      let mut wrapped = post_ty
      for qual in quals {
        wrapped = CType::Pointer(wrapped)
        wrapped = apply_qualifiers(wrapped, qual)
      }
      let mut i = inner_array_sizes.length()
      while i > 0 {
        i = i - 1
        let (size, size_expr) = inner_array_sizes[i]
        wrapped = CType::Array(elem=wrapped, size~, size_expr~)
      }
      if inner_params is Some(params) {
        let param_types = params.map(param => param.ty)
        wrapped = CType::Function(
          return_type=wrapped,
          params=param_types,
          varargs=inner_varargs,
          is_old_style=inner_old_style,
          call_conv=CallConv::Default,
        )
      }
      Some({
        name: tok.lexeme,
        id: tok.id,
        ty: wrapped,
        params: inner_params,
        varargs: inner_varargs,
        is_old_style: inner_old_style,
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
  let inner_array_sizes : Array[(Int?, Expr?)] = []
  while match_token(p, LBracket) is Some(_) {
    let size = parse_array_size(p)
    expect(p, RBracket, "expected ']' after array size") |> ignore
    inner_array_sizes.push(size)
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
  let mut i = inner_array_sizes.length()
  while i > 0 {
    i = i - 1
    let (size, size_expr) = inner_array_sizes[i]
    wrapped = CType::Array(elem=wrapped, size~, size_expr~)
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
  let array_sizes : Array[(Int?, Expr?)] = []
  while match_token(p, LBracket) is Some(_) {
    let size = parse_array_size(p)
    expect(p, RBracket, "expected ']' after array size") |> ignore
    array_sizes.push(size)
  }
  let mut i = array_sizes.length()
  while i > 0 {
    i = i - 1
    let (size, size_expr) = array_sizes[i]
    ty = CType::Array(elem=ty, size~, size_expr~)
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
fn parse_array_size(p : Parser) -> (Int?, Expr?) {
  if peek_token(p).kind == RBracket {
    return (None, None)
  }
  let loc = peek_token(p).loc
  let expr = parse_expr_cond(p)
  let size = match const_i64_from_expr(expr) {
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
fn parse_struct_type(p : Parser, is_union~ : Bool) -> (CType, SrcLoc)? {
  let kw = advance_token(p)
  let mut attrs = parse_attributes(p)
  let mut name = ""
  let mut id = 0
  if peek_token(p).kind == Ident {
    let tok = advance_token(p)
    name = tok.lexeme
    id = tok.id
  } else {
    ()
  }
  attrs = merge_attrs(attrs, parse_attributes(p))
  if match_token(p, LBrace) is Some(_) {
    let fields = parse_struct_fields(p)
    expect(p, RBrace, "expected '}' after fields") |> ignore
    attrs = merge_attrs(attrs, parse_attributes(p))
    if name == "" {
      let (anon_name, anon_id) = next_anon_tag(p)
      name = anon_name
      id = anon_id
    }
    let ty = if is_union {
      CType::Union(name~, id~, fields=Some(fields), attrs~)
    } else {
      CType::Struct(name~, id~, fields=Some(fields), attrs~)
    }
    return Some((ty, kw.loc))
  }
  if name == "" {
    add_parse_error(p, kw.loc, "expected tag name or '{'")
    return None
  }
  let ty = if is_union {
    CType::Union(name~, id~, fields=None, attrs~)
  } else {
    CType::Struct(name~, id~, fields=None, attrs~)
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
              id: 0,
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
  let mut name = ""
  let mut id = 0
  if peek_token(p).kind == Ident {
    let tok = advance_token(p)
    name = tok.lexeme
    id = tok.id
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
    return Some((CType::Enum(name~, id~, items=Some(items)), kw.loc))
  }
  if name == "" {
    add_parse_error(p, kw.loc, "expected enum name or '{'")
    return None
  }
  Some((CType::Enum(name~, id~, items=None), kw.loc))
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
        items.push({ name: tok.lexeme, id: tok.id, value, loc: tok.loc })
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
  let first_mapped = if first.kind == Ident {
    special_ident_kind(first, p.pp.keyword_ids)
  } else {
    None
  }
  if first.kind == Ident && first_mapped is None &&
    !has_typedef(p, first) {
    old_style = true
    while true {
      match expect_ident(p, "expected parameter name") {
        None => break
        Some(tok) =>
          params.push({
            name: tok.lexeme,
            id: tok.id,
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
      Some({
        name: param.name,
        id: param.id,
        ty: adjusted_ty,
        loc: param.loc,
      })
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
  // Parse pointer chain first so we can handle return-type pointers on
  // function-pointer parameter declarators like:
  //   void *(*transform)(void*)
  let (ty0, pointer_attrs) = parse_pointer_chain(p, base)
  let mut attrs = merge_attrs(pointer_attrs, parse_attributes(p))

  if is_paren_pointer_declarator(p) {
    expect(p, LParen, "expected '(' in declarator") |> ignore
    let quals : Array[TypeQual] = []
    let mut inner_attrs = parse_attributes(p)
    while match_token(p, Star) is Some(_) {
      quals.push(parse_type_qualifiers(p))
      inner_attrs = merge_attrs(inner_attrs, parse_attributes(p))
    }
    inner_attrs = merge_attrs(inner_attrs, parse_attributes(p))
    let name_tok = if peek_token(p).kind == Ident {
      Some(advance_token(p))
    } else {
      None
    }
    let inner_array_sizes : Array[(Int?, Expr?)] = []
    while match_token(p, LBracket) is Some(_) {
      let size = parse_array_size(p)
      expect(p, RBracket, "expected ']' after array size") |> ignore
      inner_array_sizes.push(size)
    }
    expect(p, RParen, "expected ')' in declarator") |> ignore
    let (ty, _params, _varargs, _old_style, suffix_attrs) = parse_declarator_suffix(
      p, ty0,
    )
    attrs = merge_attrs(merge_attrs(attrs, inner_attrs), suffix_attrs)
    let mut wrapped = ty
    for qual in quals {
      wrapped = CType::Pointer(wrapped)
      wrapped = apply_qualifiers(wrapped, qual)
    }
    let mut i = inner_array_sizes.length()
    while i > 0 {
      i = i - 1
      let (size, size_expr) = inner_array_sizes[i]
      wrapped = CType::Array(elem=wrapped, size~, size_expr~)
    }
    let call_conv = normalize_call_conv(attrs.call_conv)
    let adjusted_ty = apply_call_conv_to_type(wrapped, call_conv)
    let (name, id, loc) = match name_tok {
      Some(tok) => (tok.lexeme, tok.id, tok.loc)
      None => ("", 0, fallback_loc)
    }
    return Some({ name, id, ty: adjusted_ty, loc })
  }

  if peek_token(p).kind == Ident {
    let name_tok = advance_token(p)
    let (ty, _params, _varargs, _old_style, suffix_attrs) = parse_declarator_suffix(
      p, ty0,
    )
    attrs = merge_attrs(attrs, suffix_attrs)
    let call_conv = normalize_call_conv(attrs.call_conv)
    let adjusted_ty = apply_call_conv_to_type(ty, call_conv)
    return Some({
      name: name_tok.lexeme,
      id: name_tok.id,
      ty: adjusted_ty,
      loc: name_tok.loc,
    })
  }

  // Unnamed parameter: still allow declarator suffixes like `int[10]`.
  let (ty, _params, _varargs, _old_style, suffix_attrs) = parse_declarator_suffix(p, ty0)
  attrs = merge_attrs(attrs, suffix_attrs)
  let call_conv = normalize_call_conv(attrs.call_conv)
  let adjusted_ty = apply_call_conv_to_type(ty, call_conv)
  Some({ name: "", id: 0, ty: adjusted_ty, loc: fallback_loc })
}

///|
fn parse_compound_stmt(p : Parser, loc : SrcLoc) -> Stmt {
  p.pending_typedef_scopes.push(false)
  let stmts : Array[Stmt] = []
  while !is_at_end(p) && peek_token(p).kind != RBrace {
    stmts.push(parse_stmt(p))
  }
  expect(p, RBrace, "expected '}'") |> ignore
  let did_scope = p.pending_typedef_scopes.pop().unwrap_or(false)
  if did_scope { pop_typedef_scope(p) }
  Stmt::Compound(stmts~, loc~)
}

///|
fn parse_stmt(p : Parser) -> Stmt {
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
      return Stmt::StaticAssert(static_assert)
    }
    KwAsm => {
      let asm_tok = advance_token(p)
      let asm_stmt = parse_asm_stmt(p, asm_tok.loc)
      expect(p, Semicolon, "expected ';' after asm") |> ignore
      return Stmt::Asm(asm_stmt)
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
      return Stmt::Case(expr~, end_expr~, body~, loc=case_tok.loc)
    }
    KwDefault => {
      let def_tok = advance_token(p)
      expect(p, Colon, "expected ':' after default") |> ignore
      let body = parse_stmt(p)
      return Stmt::Default(body~, loc=def_tok.loc)
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
      return Stmt::Break(loc=break_tok.loc)
    }
    KwContinue => {
      let cont_tok = advance_token(p)
      expect(p, Semicolon, "expected ';' after continue") |> ignore
      return Stmt::Continue(loc=cont_tok.loc)
    }
    KwGoto => {
      let goto_tok = advance_token(p)
      let name = match expect_ident(p, "expected label after goto") {
        None => ""
        Some(tok) => tok.lexeme
      }
      expect(p, Semicolon, "expected ';' after goto") |> ignore
      return Stmt::Goto(name~, loc=goto_tok.loc)
    }
    KwReturn => {
      let ret_tok = advance_token(p)
      if match_token(p, Semicolon) is Some(_) {
        return Stmt::Return(value=None, loc=ret_tok.loc)
      }
      let value = parse_expr(p)
      expect(p, Semicolon, "expected ';' after return") |> ignore
      return Stmt::Return(value=Some(value), loc=ret_tok.loc)
    }
    Semicolon => {
      let semi = advance_token(p)
      return Stmt::Empty(loc=semi.loc)
    }
    _ => ()
  }
  if tok.kind == Ident && peek_kind(p, 1) == Colon {
    let label_tok = advance_token(p)
    expect(p, Colon, "expected ':' after label") |> ignore
    ignore(parse_attributes(p))
    let body = parse_stmt(p)
    return Stmt::Label(name=label_tok.lexeme, body~, loc=label_tok.loc)
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
  let else_branch = if p.current.kind == KwElse {
    advance_token(p) |> ignore
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
    if opened { pop_typedef_scope(p) }
  }
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
  while true {
    match p.current.kind {
      Comma => {
        let tok = advance_token(p)
        let right = parse_expr_eq(p)
        expr =
          Expr::Binary(
            op=BinaryOp::Comma,
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
fn parse_expr_eq(p : Parser) -> Expr {
  let left = parse_expr_cond(p)
  match p.current.kind {
    Assign => {
      let tok = advance_token(p)
      let right = parse_expr_eq(p)
      Expr::Binary(
        op=BinaryOp::Assign,
        left~,
        right~,
        node_id=new_expr_id(p),
        loc=tok.loc,
      )
    }
    PlusAssign => {
      let tok = advance_token(p)
      let right = parse_expr_eq(p)
      Expr::Binary(
        op=BinaryOp::AddAssign,
        left~,
        right~,
        node_id=new_expr_id(p),
        loc=tok.loc,
      )
    }
    MinusAssign => {
      let tok = advance_token(p)
      let right = parse_expr_eq(p)
      Expr::Binary(
        op=BinaryOp::SubAssign,
        left~,
        right~,
        node_id=new_expr_id(p),
        loc=tok.loc,
      )
    }
    StarAssign => {
      let tok = advance_token(p)
      let right = parse_expr_eq(p)
      Expr::Binary(
        op=BinaryOp::MulAssign,
        left~,
        right~,
        node_id=new_expr_id(p),
        loc=tok.loc,
      )
    }
    SlashAssign => {
      let tok = advance_token(p)
      let right = parse_expr_eq(p)
      Expr::Binary(
        op=BinaryOp::DivAssign,
        left~,
        right~,
        node_id=new_expr_id(p),
        loc=tok.loc,
      )
    }
    PercentAssign => {
      let tok = advance_token(p)
      let right = parse_expr_eq(p)
      Expr::Binary(
        op=BinaryOp::ModAssign,
        left~,
        right~,
        node_id=new_expr_id(p),
        loc=tok.loc,
      )
    }
    ShiftLeftAssign => {
      let tok = advance_token(p)
      let right = parse_expr_eq(p)
      Expr::Binary(
        op=BinaryOp::ShlAssign,
        left~,
        right~,
        node_id=new_expr_id(p),
        loc=tok.loc,
      )
    }
    ShiftRightAssign => {
      let tok = advance_token(p)
      let right = parse_expr_eq(p)
      Expr::Binary(
        op=BinaryOp::ShrAssign,
        left~,
        right~,
        node_id=new_expr_id(p),
        loc=tok.loc,
      )
    }
    AmpAssign => {
      let tok = advance_token(p)
      let right = parse_expr_eq(p)
      Expr::Binary(
        op=BinaryOp::BitAndAssign,
        left~,
        right~,
        node_id=new_expr_id(p),
        loc=tok.loc,
      )
    }
    PipeAssign => {
      let tok = advance_token(p)
      let right = parse_expr_eq(p)
      Expr::Binary(
        op=BinaryOp::BitOrAssign,
        left~,
        right~,
        node_id=new_expr_id(p),
        loc=tok.loc,
      )
    }
    CaretAssign => {
      let tok = advance_token(p)
      let right = parse_expr_eq(p)
      Expr::Binary(
        op=BinaryOp::BitXorAssign,
        left~,
        right~,
        node_id=new_expr_id(p),
        loc=tok.loc,
      )
    }
    _ => left
  }
}

///|
fn parse_expr_cond(p : Parser) -> Expr {
  let cond = parse_expr_binary(p, 1)
  match p.current.kind {
    Question => {
      let tok = advance_token(p)
      let then_expr = parse_expr(p)
      expect(p, Colon, "expected ':' in conditional expression") |> ignore
      let else_expr = parse_expr_cond(p)
      Expr::Conditional(
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
fn binary_op_info(kind : TokenKind) -> (BinaryOp, Int) {
  match kind {
    PipePipe => (BinaryOp::LogOr, 1)
    AmpAmp => (BinaryOp::LogAnd, 2)
    Pipe => (BinaryOp::BitOr, 3)
    Caret => (BinaryOp::BitXor, 4)
    Amp => (BinaryOp::BitAnd, 5)
    Eq => (BinaryOp::Eq, 6)
    Ne => (BinaryOp::Ne, 6)
    Lt => (BinaryOp::Lt, 7)
    Le => (BinaryOp::Le, 7)
    Gt => (BinaryOp::Gt, 7)
    Ge => (BinaryOp::Ge, 7)
    ShiftLeft => (BinaryOp::Shl, 8)
    ShiftRight => (BinaryOp::Shr, 8)
    Plus => (BinaryOp::Add, 9)
    Minus => (BinaryOp::Sub, 9)
    Star => (BinaryOp::Mul, 10)
    Slash => (BinaryOp::Div, 10)
    Percent => (BinaryOp::Mod, 10)
    _ => (BinaryOp::Add, 0)
  }
}

///|
fn parse_expr_binary(p : Parser, min_prec : Int) -> Expr {
  let mut expr = parse_expr_unary(p)
  while true {
    let (op, prec) = binary_op_info(p.current.kind)
    if prec == 0 || prec < min_prec {
      break
    }
    let tok = advance_token(p)
    let right = parse_expr_binary(p, prec + 1)
    expr = Expr::Binary(op~, left=expr, right~, node_id=new_expr_id(p), loc=tok.loc)
  }
  expr
}

///|
fn parse_expr_unary(p : Parser) -> Expr {
  match p.current.kind {
    KwSizeof => {
      let tok = advance_token(p)
      if peek_kind(p, 0) == LParen && is_type_start(p, peek_token_at(p, 1)) {
        expect(p, LParen, "expected '(' after sizeof") |> ignore
        match parse_type_name(p) {
          None => {
            add_parse_error(p, tok.loc, "expected type name after sizeof")
            return Expr::IntLit(value="0", node_id=new_expr_id(p), loc=tok.loc)
          }
          Some(ty) => {
            expect(p, RParen, "expected ')' after sizeof type") |> ignore
            return Expr::SizeofType(ty~, node_id=new_expr_id(p), loc=tok.loc)
          }
        }
      }
      let expr = parse_expr_unary(p)
      return Expr::SizeofExpr(expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    KwAlignof => {
      let tok = advance_token(p)
      if peek_kind(p, 0) == LParen && is_type_start(p, peek_token_at(p, 1)) {
        expect(p, LParen, "expected '(' after alignof") |> ignore
        match parse_type_name(p) {
          None => {
            add_parse_error(p, tok.loc, "expected type name after alignof")
            return Expr::IntLit(value="0", node_id=new_expr_id(p), loc=tok.loc)
          }
          Some(ty) => {
            expect(p, RParen, "expected ')' after alignof type") |> ignore
            return Expr::AlignofType(ty~, node_id=new_expr_id(p), loc=tok.loc)
          }
        }
      }
      let expr = parse_expr_unary(p)
      return Expr::AlignofExpr(expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    _ => ()
  }
  if peek_kind(p, 0) == LParen && is_type_start(p, peek_token_at(p, 1)) {
    let lparen = advance_token(p)
    match parse_type_name(p) {
      None => {
        add_parse_error(p, lparen.loc, "expected type name in cast")
        return Expr::IntLit(value="0", node_id=new_expr_id(p), loc=lparen.loc)
      }
      Some(ty) => {
        expect(p, RParen, "expected ')' after cast type") |> ignore
        if peek_kind(p, 0) == LBrace {
          let init = parse_initializer(p)
          let literal =
            Expr::CompoundLiteral(
              ty~,
              init~,
              node_id=new_expr_id(p),
              loc=lparen.loc,
            )
          return parse_postfix_tail(p, literal)
        }
        let expr = parse_expr_unary(p)
        return Expr::Cast(ty~, expr~, node_id=new_expr_id(p), loc=lparen.loc)
      }
    }
  }
  match p.current.kind {
    PlusPlus => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Expr::Unary(op=UnaryOp::PreInc, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    MinusMinus => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Expr::Unary(op=UnaryOp::PreDec, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    Plus => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Expr::Unary(op=UnaryOp::Plus, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    Minus => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Expr::Unary(op=UnaryOp::Minus, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    Bang => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Expr::Unary(op=UnaryOp::Not, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    Tilde => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Expr::Unary(op=UnaryOp::BitNot, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    Amp => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Expr::Unary(op=UnaryOp::Addr, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    Star => {
      let tok = advance_token(p)
      let expr = parse_expr_unary(p)
      Expr::Unary(op=UnaryOp::Deref, expr~, node_id=new_expr_id(p), loc=tok.loc)
    }
    _ => parse_expr_postfix(p)
  }
}

///|
fn parse_expr_postfix(p : Parser) -> Expr {
  let expr = parse_expr_primary(p)
  parse_postfix_tail(p, expr)
}

///|
fn parse_postfix_tail(p : Parser, base : Expr) -> Expr {
  let mut expr = base
  while true {
    match p.current.kind {
      LParen => {
        let tok = advance_token(p)
        let args = parse_call_args(p)
        expr =
          Expr::Call(callee=expr, args~, node_id=new_expr_id(p), loc=tok.loc)
        continue
      }
      LBracket => {
        let tok = advance_token(p)
        let index = parse_expr(p)
        expect(p, RBracket, "expected ']' after index") |> ignore
        expr =
          Expr::Index(base=expr, index~, node_id=new_expr_id(p), loc=tok.loc)
        continue
      }
      Dot => {
        let tok = advance_token(p)
        let (name, id) = match expect_ident(p, "expected field name") {
          None => ("", 0)
          Some(tok) => (tok.lexeme, tok.id)
        }
        expr =
          Expr::Member(
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
          Some(tok) => (tok.lexeme, tok.id)
        }
        expr =
          Expr::Member(
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
        expr =
          Expr::Unary(
            op=UnaryOp::PostInc,
            expr~,
            node_id=new_expr_id(p),
            loc=tok.loc,
          )
        continue
      }
      MinusMinus => {
        let tok = advance_token(p)
        expr =
          Expr::Unary(
            op=UnaryOp::PostDec,
            expr~,
            node_id=new_expr_id(p),
            loc=tok.loc,
          )
        continue
      }
      _ => break
    }
  }
  expr
}

///|
fn parse_call_args(p : Parser) -> Array[Expr] {
  let args : Array[Expr] = []
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
fn parse_expr_primary(p : Parser) -> Expr {
  let tok = advance_token(p)
  match tok.kind {
    IntLit =>
      Expr::IntLit(value=tok.lexeme, node_id=new_expr_id(p), loc=tok.loc)
    FloatLit =>
      Expr::FloatLit(value=tok.lexeme, node_id=new_expr_id(p), loc=tok.loc)
    CharLit =>
      Expr::CharLit(
        value=parse_char_literal_value(p, tok),
        node_id=new_expr_id(p),
        loc=tok.loc,
      )
    StrLit => parse_string_literal_expr(p, tok)
    Ident =>
      match p.current.kind {
        LParen => {
          let id = tok.id
          if id == p.builtin_ids.types_compatible_p {
            expect(
              p,
              LParen,
              "expected '(' after __builtin_types_compatible_p",
            ) |> ignore
            let a = match parse_type_name(p) {
              None => {
                add_parse_error(p, tok.loc, "expected type name in builtin")
                default_int_type()
              }
              Some(ty) => ty
            }
            expect(p, Comma, "expected ',' in __builtin_types_compatible_p")
            |> ignore
            let b = match parse_type_name(p) {
              None => {
                add_parse_error(p, tok.loc, "expected type name in builtin")
                default_int_type()
              }
              Some(ty) => ty
            }
            expect(
              p,
              RParen,
              "expected ')' after __builtin_types_compatible_p",
            ) |> ignore
            Expr::BuiltinTypesCompatibleP(
              a~,
              b~,
              node_id=new_expr_id(p),
              loc=tok.loc,
            )
          } else if id == p.builtin_ids.offsetof {
            expect(p, LParen, "expected '(' after __builtin_offsetof") |> ignore
            let ty = match parse_type_name(p) {
              None => {
                add_parse_error(p, tok.loc, "expected type name in __builtin_offsetof")
                default_int_type()
              }
              Some(v) => v
            }
            expect(p, Comma, "expected ',' in __builtin_offsetof") |> ignore
            let path : Array[String] = []
            match expect_ident(p, "expected member name in __builtin_offsetof") {
              None => ()
              Some(id) => path.push(id.lexeme)
            }
            while p.current.kind == Dot {
              advance_token(p) |> ignore
              match expect_ident(p, "expected member name in __builtin_offsetof") {
                None => break
                Some(id) => path.push(id.lexeme)
              }
            }
            expect(p, RParen, "expected ')' after __builtin_offsetof") |> ignore
            Expr::BuiltinOffsetof(
              ty~,
              path~,
              node_id=new_expr_id(p),
              loc=tok.loc,
            )
          } else if id == p.builtin_ids.va_arg {
            expect(p, LParen, "expected '(' after __builtin_va_arg") |> ignore
            let list = parse_expr_eq(p)
            expect(p, Comma, "expected ',' in __builtin_va_arg") |> ignore
            let ty = match parse_type_name(p) {
              None => {
                add_parse_error(p, tok.loc, "expected type name in builtin")
                default_int_type()
              }
              Some(v) => v
            }
            expect(p, RParen, "expected ')' after __builtin_va_arg") |> ignore
            Expr::BuiltinVaArg(list~, ty~, node_id=new_expr_id(p), loc=tok.loc)
          } else {
            Expr::Ident(
              name=tok.lexeme,
              id=tok.id,
              node_id=new_expr_id(p),
              loc=tok.loc,
            )
          }
        }
        _ =>
          Expr::Ident(
            name=tok.lexeme,
            id=tok.id,
            node_id=new_expr_id(p),
            loc=tok.loc,
          )
      }
    LParen =>
      if p.current.kind == LBrace {
        let lbrace = advance_token(p)
        let block = parse_compound_stmt(p, lbrace.loc)
        expect(p, RParen, "expected ')' after statement expression") |> ignore
        match block {
          Stmt::Compound(stmts~, ..) =>
            Expr::StmtExpr(stmts~, node_id=new_expr_id(p), loc=tok.loc)
          _ => Expr::StmtExpr(stmts=[], node_id=new_expr_id(p), loc=tok.loc)
        }
      } else {
        let expr = parse_expr(p)
        expect(p, RParen, "expected ')'") |> ignore
        expr
      }
    _ => {
      add_parse_error(p, tok.loc, "unexpected token in expression")
      Expr::IntLit(value="0", node_id=new_expr_id(p), loc=tok.loc)
    }
  }
}

///|
///|
fn parse_string_literal_expr(p : Parser, first : Token) -> Expr {
  let (value, len) = decode_string_literal(p, first.lexeme, first.loc)
  if peek_token(p).kind != StrLit {
    return Expr::StringLit(
      value=value,
      length=len + 1,
      node_id=new_expr_id(p),
      loc=first.loc,
    )
  }
  let sb = StringBuilder::new(size_hint=first.lexeme.length())
  let mut byte_len = len
  sb.write_string(value)
  while peek_token(p).kind == StrLit {
    let tok = advance_token(p)
    let (part, part_len) = decode_string_literal(p, tok.lexeme, tok.loc)
    sb.write_string(part)
    byte_len = byte_len + part_len
  }
  Expr::StringLit(
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
  loc : SrcLoc,
) -> (String, Int) {
  let len = lexeme.length()
  let size_hint = if len > 2 { len - 2 } else { 0 }
  let sb = StringBuilder::new(size_hint=size_hint)
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
    Ident => has_typedef(p, tok)
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
    Expr::BuiltinTypesCompatibleP(loc~, ..) => loc
    Expr::BuiltinOffsetof(loc~, ..) => loc
    Expr::BuiltinVaArg(loc~, ..) => loc
    Expr::Unary(loc~, ..) => loc
    Expr::Cast(loc~, ..) => loc
    Expr::CompoundLiteral(loc~, ..) => loc
    Expr::StmtExpr(loc~, ..) => loc
    Expr::SizeofExpr(loc~, ..) => loc
    Expr::SizeofType(loc~, ..) => loc
    Expr::AlignofExpr(loc~, ..) => loc
    Expr::AlignofType(loc~, ..) => loc
    Expr::Binary(loc~, ..) => loc
    Expr::Conditional(loc~, ..) => loc
    Expr::Call(loc~, ..) => loc
    Expr::Index(loc~, ..) => loc
    Expr::Member(loc~, ..) => loc
  }
}

///|
fn expr_node_id(expr : Expr) -> Int {
  match expr {
    Expr::IntLit(node_id~, ..) => node_id
    Expr::FloatLit(node_id~, ..) => node_id
    Expr::CharLit(node_id~, ..) => node_id
    Expr::StringLit(node_id~, ..) => node_id
    Expr::Ident(node_id~, ..) => node_id
    Expr::BuiltinTypesCompatibleP(node_id~, ..) => node_id
    Expr::BuiltinOffsetof(node_id~, ..) => node_id
    Expr::BuiltinVaArg(node_id~, ..) => node_id
    Expr::Unary(node_id~, ..) => node_id
    Expr::Cast(node_id~, ..) => node_id
    Expr::CompoundLiteral(node_id~, ..) => node_id
    Expr::StmtExpr(node_id~, ..) => node_id
    Expr::SizeofExpr(node_id~, ..) => node_id
    Expr::SizeofType(node_id~, ..) => node_id
    Expr::AlignofExpr(node_id~, ..) => node_id
    Expr::AlignofType(node_id~, ..) => node_id
    Expr::Binary(node_id~, ..) => node_id
    Expr::Conditional(node_id~, ..) => node_id
    Expr::Call(node_id~, ..) => node_id
    Expr::Index(node_id~, ..) => node_id
    Expr::Member(node_id~, ..) => node_id
  }
}

///|
fn ensure_typedef_capacity_with(
  counts : Array[Int],
  values : Array[CType?],
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
  if id <= 0 {
    return 0
  }
  if id <= p.typedef_counts.length() {
    p.typedef_counts[id - 1]
  } else {
    0
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
fn get_typedef_value(p : Parser, id : Int) -> CType? {
  if id <= 0 {
    return None
  }
  if id <= p.typedef_values.length() {
    p.typedef_values[id - 1]
  } else {
    None
  }
}

///|
fn set_typedef_value(p : Parser, id : Int, value : CType?) -> Unit {
  if id <= 0 {
    return
  }
  ensure_typedef_capacity(p, id)
  p.typedef_values[id - 1] = value
}

///|
fn get_typedef_scope_level(p : Parser, id : Int) -> Int {
  if id <= 0 {
    return 0
  }
  if id <= p.typedef_scope_levels.length() {
    p.typedef_scope_levels[id - 1]
  } else {
    0
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
  if len == 0 { 0 } else { p.typedef_scope_stack[len - 1] }
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
  match p.typedef_overrides.pop() {
    None => ()
    Some(overrides) => {
      let mut i = overrides.length()
      while i > 0 {
        i = i - 1
        let (id, prev, prev_scope) = overrides[i]
        set_typedef_value(p, id, prev)
        set_typedef_scope_level(p, id, prev_scope)
        dec_typedef_count(p, id)
      }
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
fn typedef_id_from_token(_p : Parser, tok : Token) -> Int {
  if tok.kind != Ident {
    return 0
  }
  if tok.id > 0 { tok.id } else { 0 }
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
fn typedef_ref_type(ty : CType) -> CType {
  match ty {
    CType::Qualified(qual~, base~) =>
      CType::Qualified(qual~, base=typedef_ref_type(base))
    CType::Attributed(attrs~, base~) =>
      CType::Attributed(attrs~, base=typedef_ref_type(base))
    CType::Pointer(inner) => CType::Pointer(typedef_ref_type(inner))
    CType::Array(elem~, size~, size_expr~) =>
      CType::Array(elem=typedef_ref_type(elem), size~, size_expr~)
    CType::Function(return_type~, params~, varargs~, is_old_style~, call_conv~) =>
      CType::Function(
        return_type=typedef_ref_type(return_type),
        params=params.map(t => typedef_ref_type(t)),
        varargs~,
        is_old_style~,
        call_conv~,
      )
    CType::Struct(name~, id~, fields=Some(_), attrs~) =>
      CType::Struct(name~, id~, fields=None, attrs~)
    CType::Union(name~, id~, fields=Some(_), attrs~) =>
      CType::Union(name~, id~, fields=None, attrs~)
    CType::Enum(name~, id~, items=Some(_)) => CType::Enum(name~, id~, items=None)
    _ => ty
  }
}

///|
fn define_typedef(p : Parser, name : String, ty : CType) -> Unit {
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
fn lookup_typedef(p : Parser, tok : Token) -> CType? {
  let id = typedef_id_from_token(p, tok)
  if id == 0 {
    return None
  }
  get_typedef_value(p, id)
}

///|
fn has_typedef(p : Parser, tok : Token) -> Bool {
  let id = typedef_id_from_token(p, tok)
  if id == 0 {
    return false
  }
  get_typedef_count(p, id) > 0
}

///|
fn add_parse_error(p : Parser, loc : SrcLoc, message : String) -> Unit {
  add_error(p.diags, loc, message)
}

///|
fn peek_token(p : Parser) -> Token {
  p.current
}

///|
fn peek_token_at(p : Parser, offset : Int) -> Token {
  if offset <= 0 { p.current } else { p.lookahead }
}

///|
fn peek_kind(p : Parser, offset : Int) -> TokenKind {
  peek_token_at(p, offset).kind
}

///|
fn advance_token(p : Parser) -> Token {
  let tok = p.current
  p.current = p.lookahead
  p.lookahead = next_pp_token(p.pp)
  tok
}

///|
fn match_token(p : Parser, kind : TokenKind) -> Token? {
  if p.current.kind == kind {
    Some(advance_token(p))
  } else {
    None
  }
}

///|
fn expect(p : Parser, kind : TokenKind, message : String) -> Token {
  let tok = p.current
  if tok.kind == kind {
    return advance_token(p)
  }
  add_parse_error(p, tok.loc, message)
  tok
}

///|
fn expect_ident(p : Parser, message : String) -> Token? {
  let tok = p.current
  if tok.kind == Ident {
    return Some(advance_token(p))
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
