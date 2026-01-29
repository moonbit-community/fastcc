///|
test "ast attrs and call conv helpers" {
  let empty = @ast.empty_attrs()
  assert_true(@ast.attrs_is_empty(empty))

  let attrs = @ast.attrs_with(
    aligned=Some(@ast.AlignSpec::Default),
    packed=true,
    visibility=Some(@ast.Visibility::Hidden),
    section=Some("sec"),
  )
  assert_true(!@ast.attrs_is_empty(attrs))
  assert_true(@ast.has_type_attrs(attrs))

  let base_int = @ast.default_int_type()
  let applied = @ast.apply_type_attrs(base_int, attrs)
  match applied {
    @ast.CType::Attributed(..) => ()
    _ => fail("expected attributed type")
  }

  let fn_ty : @ast.CType = @ast.CType::Function(
    return_type=base_int,
    params=[],
    varargs=false,
    is_old_style=false,
    call_conv=@ast.CallConv::Default,
  )
  let updated = @ast.apply_call_conv_to_type(fn_ty, @ast.CallConv::Cdecl)
  match updated {
    @ast.CType::Function(call_conv=@ast.CallConv::Cdecl, ..) => ()
    _ => fail("expected cdecl call conv")
  }

  assert_eq(@ast.normalize_call_conv(None), @ast.CallConv::Default)
  assert_eq(
    @ast.normalize_call_conv(Some(@ast.CallConv::Regparm(count=2))),
    @ast.CallConv::Regparm(count=2),
  )
}

///|
test "ast expr utils" {
  let loc = @source.dummy_loc(0)
  let id_expr = @ast.Expr::Ident(name="x", id=1, node_id=11, loc=loc)
  assert_true(@ast.expr_is_lvalue_simple(id_expr))

  let member_expr = @ast.Expr::Member(
    base=id_expr,
    name="f",
    id=2,
    is_arrow=true,
    node_id=12,
    loc=loc,
  )
  assert_true(@ast.expr_is_lvalue_simple(member_expr))

  let stmt_expr = @ast.Expr::StmtExpr(
    stmts=[@ast.Stmt::ExprStmt(expr=id_expr, loc=loc)],
    node_id=13,
    loc=loc,
  )
  assert_true(@ast.expr_is_lvalue_simple(stmt_expr))

  let call_expr = @ast.Expr::Call(callee=id_expr, args=[], node_id=14, loc=loc)
  assert_true(@ast.expr_may_call(call_expr))
  let sizeof_expr = @ast.Expr::SizeofExpr(expr=id_expr, node_id=15, loc=loc)
  assert_true(!@ast.expr_may_call(sizeof_expr))

  let binary_expr = @ast.Expr::Binary(
    op=@ast.BinaryOp::Add,
    left=call_expr,
    right=sizeof_expr,
    node_id=16,
    loc=loc,
  )
  assert_true(@ast.expr_may_call(binary_expr))

  assert_eq(@ast.expr_loc(call_expr), loc)
  assert_eq(@ast.expr_node_id(call_expr), 14)
}

///|
test "ast literal helpers and qualifiers" {
  assert_eq(@ast.parse_int64_literal(""), None)
  assert_eq(@ast.parse_int64_literal("0x10"), Some(16))
  assert_eq(@ast.parse_int64_literal("0b101"), Some(5))
  assert_eq(@ast.parse_int64_literal("077"), Some(63))
  assert_eq(@ast.parse_int64_literal("12_34"), Some(1234))

  let loc = @source.dummy_loc(1)
  let lit = @ast.Expr::IntLit(value="7", node_id=1, loc=loc)
  let neg = @ast.Expr::Unary(op=@ast.UnaryOp::Minus, expr=lit, node_id=2, loc=loc)
  assert_eq(@ast.const_i64_from_expr(lit), Some(7))
  assert_eq(@ast.const_i64_from_expr(neg), Some(-7))

  let empty_qual = @ast.empty_qual()
  let with_const = @ast.with_const(empty_qual)
  let with_vol = @ast.with_volatile(empty_qual)
  let merged = @ast.merge_qual(with_const, with_vol)
  assert_true(merged.is_const)
  assert_true(merged.is_volatile)

  let base_int = @ast.default_int_type()
  let qualified = @ast.apply_qualifiers(base_int, merged)
  match qualified {
    @ast.CType::Qualified(..) => ()
    _ => fail("expected qualified type")
  }
}
