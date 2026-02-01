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
  let base_struct : @ast.CType = @ast.CType::Struct(
    name="S",
    id=1,
    fields=None,
    attrs=@ast.empty_attrs(),
  )
  let merged_struct = @ast.apply_type_attrs(base_struct, attrs)
  match merged_struct {
    @ast.CType::Struct(attrs=merged, ..) => assert_true(merged.packed)
    _ => fail("expected struct attrs")
  }
  let base_union : @ast.CType = @ast.CType::Union(
    name="U",
    id=2,
    fields=None,
    attrs=@ast.empty_attrs(),
  )
  let merged_union = @ast.apply_type_attrs(base_union, attrs)
  match merged_union {
    @ast.CType::Union(attrs=merged, ..) => assert_true(merged.packed)
    _ => fail("expected union attrs")
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
    @ast.normalize_call_conv(Some(@ast.CallConv::Default)),
    @ast.CallConv::Default,
  )
  assert_eq(
    @ast.normalize_call_conv(Some(@ast.CallConv::Regparm(count=2))),
    @ast.CallConv::Regparm(count=2),
  )
  assert_eq(
    @ast.normalize_call_conv(Some(@ast.CallConv::Regparm(count=0))),
    @ast.CallConv::Default,
  )
  assert_eq(
    @ast.merge_call_conv(@ast.CallConv::Cdecl, @ast.CallConv::Stdcall),
    @ast.CallConv::Cdecl,
  )
  let base_attrs = @ast.attrs_with(
    visibility=Some(@ast.Visibility::Hidden),
    call_conv=Some(@ast.CallConv::Cdecl),
  )
  let incoming_attrs = @ast.attrs_with(
    aligned=Some(@ast.AlignSpec::Default),
    section=Some("sec"),
    alias_name=Some("alias"),
    asm_label=Some("asm"),
    cleanup=Some("cleanup"),
    call_conv=Some(@ast.CallConv::Stdcall),
  )
  let merged = @ast.merge_attrs(base_attrs, incoming_attrs)
  assert_eq(merged.visibility, base_attrs.visibility)
  assert_eq(merged.section, incoming_attrs.section)
  assert_eq(merged.alias_name, incoming_attrs.alias_name)
  assert_eq(merged.asm_label, incoming_attrs.asm_label)
  assert_eq(merged.cleanup, incoming_attrs.cleanup)
  assert_eq(merged.call_conv, base_attrs.call_conv)
  assert_eq(merged.aligned, incoming_attrs.aligned)
  let qual = @ast.with_const(@ast.empty_qual())
  let qualified_ty : @ast.CType = @ast.CType::Qualified(qual~, base=base_int)
  let updated_qual = @ast.apply_call_conv_to_type(
    qualified_ty,
    @ast.CallConv::Cdecl,
  )
  match updated_qual {
    @ast.CType::Qualified(..) => ()
    _ => fail("expected qualified call conv")
  }
  let attributed_ty : @ast.CType = @ast.CType::Attributed(
    attrs=@ast.empty_attrs(),
    base=base_int,
  )
  let updated_attr = @ast.apply_call_conv_to_type(
    attributed_ty,
    @ast.CallConv::Cdecl,
  )
  match updated_attr {
    @ast.CType::Attributed(..) => ()
    _ => fail("expected attributed call conv")
  }
  let array_ty : @ast.CType = @ast.CType::Array(
    elem=base_int,
    size=Some(2),
    size_expr=None,
  )
  let updated_array = @ast.apply_call_conv_to_type(
    array_ty,
    @ast.CallConv::Cdecl,
  )
  match updated_array {
    @ast.CType::Array(..) => ()
    _ => fail("expected array call conv")
  }
  assert_eq(
    @ast.apply_call_conv_to_type(base_int, @ast.CallConv::Default),
    base_int,
  )
}

///|
test "ast expr utils" {
  let loc = @source.dummy_loc(0)
  let id_expr = @ast.Expr::Ident(name="x", id=1, node_id=11, loc~)
  assert_true(@ast.expr_is_lvalue_simple(id_expr))
  let base_int = @ast.default_int_type()
  let member_expr = @ast.Expr::Member(
    base=id_expr,
    name="f",
    id=2,
    is_arrow=true,
    node_id=12,
    loc~,
  )
  assert_true(@ast.expr_is_lvalue_simple(member_expr))
  let stmt_expr = @ast.Expr::StmtExpr(
    stmts=[@ast.Stmt::ExprStmt(expr=id_expr, loc~)],
    node_id=13,
    loc~,
  )
  assert_true(@ast.expr_is_lvalue_simple(stmt_expr))
  assert_true(@ast.expr_may_call(stmt_expr))
  let call_expr = @ast.Expr::Call(callee=id_expr, args=[], node_id=14, loc~)
  assert_true(@ast.expr_may_call(call_expr))
  let sizeof_expr = @ast.Expr::SizeofExpr(expr=id_expr, node_id=15, loc~)
  assert_true(!@ast.expr_may_call(sizeof_expr))
  let binary_expr = @ast.Expr::Binary(
    op=@ast.BinaryOp::Add,
    left=call_expr,
    right=sizeof_expr,
    node_id=16,
    loc~,
  )
  assert_true(@ast.expr_may_call(binary_expr))
  let cond_expr = @ast.Expr::Conditional(
    cond=id_expr,
    then_expr=call_expr,
    else_expr=sizeof_expr,
    node_id=17,
    loc~,
  )
  assert_true(@ast.expr_may_call(cond_expr))
  let index_expr = @ast.Expr::Index(
    base=call_expr,
    index=id_expr,
    node_id=18,
    loc~,
  )
  assert_true(@ast.expr_may_call(index_expr))
  let builtin_va = @ast.Expr::BuiltinVaArg(
    list=call_expr,
    ty=base_int,
    node_id=19,
    loc~,
  )
  assert_true(@ast.expr_may_call(builtin_va))
  let deref_expr = @ast.Expr::Unary(
    op=@ast.UnaryOp::Deref,
    expr=id_expr,
    node_id=20,
    loc~,
  )
  assert_true(@ast.expr_is_lvalue_simple(deref_expr))
  let empty_stmt_expr = @ast.Expr::StmtExpr(stmts=[], node_id=21, loc~)
  assert_true(!@ast.expr_is_lvalue_simple(empty_stmt_expr))
  let non_expr_stmt = @ast.Stmt::Break(loc~)
  let bad_stmt_expr = @ast.Expr::StmtExpr(
    stmts=[non_expr_stmt],
    node_id=22,
    loc~,
  )
  assert_true(!@ast.expr_is_lvalue_simple(bad_stmt_expr))
  let int_expr = @ast.Expr::IntLit(value="1", node_id=23, loc~)
  assert_true(!@ast.expr_is_lvalue_simple(int_expr))
  assert_eq(@ast.expr_loc(call_expr), loc)
  assert_eq(@ast.expr_node_id(call_expr), 14)
  let types_compat = @ast.Expr::BuiltinTypesCompatibleP(
    a=base_int,
    b=base_int,
    node_id=24,
    loc~,
  )
  assert_eq(@ast.expr_node_id(types_compat), 24)
  let offset_expr = @ast.Expr::BuiltinOffsetof(
    ty=base_int,
    path=[],
    node_id=25,
    loc~,
  )
  assert_eq(@ast.expr_node_id(offset_expr), 25)
  let align_expr = @ast.Expr::AlignofExpr(expr=id_expr, node_id=25, loc~)
  assert_eq(@ast.expr_node_id(align_expr), 25)
  let align_type = @ast.Expr::AlignofType(ty=base_int, node_id=26, loc~)
  assert_eq(@ast.expr_node_id(align_type), 26)
}

///|
test "ast literal helpers and qualifiers" {
  assert_eq(@ast.parse_int64_literal(""), None)
  assert_eq(@ast.parse_int64_literal("0x10"), Some(16))
  assert_eq(@ast.parse_int64_literal("0x1a"), Some(26))
  assert_eq(@ast.parse_int64_literal("0XAF"), Some(175))
  assert_eq(@ast.parse_int64_literal("0x"), Some(0))
  assert_eq(@ast.parse_int64_literal("0x1g"), Some(1))
  assert_eq(@ast.parse_int64_literal("0b101"), Some(5))
  assert_eq(@ast.parse_int64_literal("077"), Some(63))
  assert_eq(@ast.parse_int64_literal("12_34"), Some(1234))
  assert_eq(@ast.parse_int64_literal("09"), None)
  assert_eq(@ast.parse_int64_literal("0x__"), None)
  let loc = @source.dummy_loc(1)
  let lit = @ast.Expr::IntLit(value="7", node_id=1, loc~)
  let plus = @ast.Expr::Unary(op=@ast.UnaryOp::Plus, expr=lit, node_id=3, loc~)
  let neg = @ast.Expr::Unary(op=@ast.UnaryOp::Minus, expr=lit, node_id=2, loc~)
  assert_eq(@ast.const_i64_from_expr(lit), Some(7))
  assert_eq(@ast.const_i64_from_expr(plus), Some(7))
  assert_eq(@ast.const_i64_from_expr(neg), Some(-7))
  let neg_ident = @ast.Expr::Unary(
    op=@ast.UnaryOp::Minus,
    expr=@ast.Expr::Ident(name="y", id=2, node_id=4, loc~),
    node_id=5,
    loc~,
  )
  assert_eq(@ast.const_i64_from_expr(neg_ident), None)
  assert_eq(
    @ast.const_i64_from_expr(@ast.Expr::Ident(name="z", id=3, node_id=6, loc~)),
    None,
  )
  let empty_qual = @ast.empty_qual()
  let with_const = @ast.with_const(empty_qual)
  let with_vol = @ast.with_volatile(empty_qual)
  let with_res = @ast.with_restrict(empty_qual)
  let merged = @ast.merge_qual(with_const, with_vol)
  assert_true(merged.is_const)
  assert_true(merged.is_volatile)
  assert_true(with_res.is_restrict)
  let base_int = @ast.default_int_type()
  let qualified = @ast.apply_qualifiers(base_int, merged)
  match qualified {
    @ast.CType::Qualified(..) => ()
    _ => fail("expected qualified type")
  }
  let merged_again = @ast.apply_qualifiers(
    qualified,
    @ast.with_atomic(@ast.empty_qual()),
  )
  match merged_again {
    @ast.CType::Qualified(..) => ()
    _ => fail("expected merged qualified type")
  }
}
