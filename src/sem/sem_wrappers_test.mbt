///|
fn new_sem_ctx() -> (@sem.SemContext, @diag.DiagBag) {
  let bag = @diag.new_diag_bag()
  let unit : @ast.TranslationUnit = { decls: [], expr_id_max: 0 }
  let ctx = @sem.check_translation_unit(unit, bag)
  (ctx, bag)
}

///|
test "sem wrapper basics" {
  let loc = @source.dummy_loc(0)
  let (ctx_err, bag_err) = new_sem_ctx()
  @sem.add_sem_error(ctx_err, loc, "oops")
  assert_true(@diag.has_errors(bag_err))
  let base_int = @ast.CType::Int(kind=@ast.CIntKind::Int, unsigned=false)
  let array_ty = @ast.CType::Array(elem=base_int, size=None, size_expr=None)
  let sized = @sem.apply_inferred_array_size(array_ty, 4)
  match sized {
    @ast.CType::Array(size=Some(4), ..) => ()
    _ => fail("expected inferred array size")
  }
  assert_true(
    @sem.is_char_type(@ast.CType::Int(kind=@ast.CIntKind::Char, unsigned=false)),
  )
  assert_true(!@sem.is_char_type(base_int))
  let qual : @ast.TypeQual = {
    is_const: true,
    is_volatile: false,
    is_restrict: false,
    is_atomic: false,
  }
  let qualified = @ast.CType::Qualified(qual~, base=base_int)
  let stripped_qual = @sem.strip_qualifiers(qualified)
  assert_eq(stripped_qual, base_int)
  let attrs = @ast.empty_attrs()
  let attributed = @ast.CType::Attributed(attrs~, base=base_int)
  let stripped_attrs = @sem.strip_qual_attrs(attributed)
  assert_eq(stripped_attrs, base_int)
  let (ctx_const, bag_const) = new_sem_ctx()
  let lit = @ast.Expr::IntLit(value="7", node_id=1, loc~)
  assert_eq(@sem.try_eval_int_const(ctx_const, lit), Some(7))
  assert_true(!@diag.has_errors(bag_const))
  let (ctx_sizeof, bag_sizeof) = new_sem_ctx()
  let str_expr = @ast.Expr::StringLit(value="hi", length=2, node_id=2, loc~)
  let sizeof_ty = @sem.type_for_sizeof(ctx_sizeof, str_expr)
  match sizeof_ty {
    @ast.CType::Array(size=Some(2), ..) => ()
    _ => fail("expected sizeof string to yield array type")
  }
  assert_true(!@diag.has_errors(bag_sizeof))
  let vla_expr = @ast.Expr::IntLit(value="3", node_id=3, loc~)
  let vla_ty = @ast.CType::Array(
    elem=base_int,
    size=None,
    size_expr=Some(vla_expr),
  )
  assert_true(@sem.type_contains_vla(vla_ty))
  let (ctx_lvalue, bag_lvalue) = new_sem_ctx()
  let non_lvalue = @ast.Expr::IntLit(value="1", node_id=4, loc~)
  assert_true(@sem.type_of_lvalue(ctx_lvalue, non_lvalue) is None)
  assert_true(@diag.has_errors(bag_lvalue))
}
