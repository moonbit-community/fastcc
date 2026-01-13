///|
struct RegPool {
  free : Array[Int]
}

///|
fn new_reg_pool() -> RegPool {
  { free: [9, 10, 11, 12, 13, 14, 15] }
}

///|
fn take_reg(pool : RegPool) -> Int raise {
  match pool.free.pop() {
    None => fail("codegen: out of temporary registers")
    Some(r) => r
  }
}

///|
fn give_reg(pool : RegPool, r : Int) -> Unit {
  pool.free.push(r)
}

///|
struct LocalSlot {
  offset : Int
  ty : CType
}

///|
struct LocalAlloc {
  sem : SemContext
  mut used_bytes : Int
  scopes : Array[Map[String, LocalSlot]]
}

///|
fn new_local_alloc(sem : SemContext) -> LocalAlloc {
  { sem, used_bytes: 0, scopes: [] }
}

///|
fn cg_push_scope(alloc : LocalAlloc) -> Unit {
  alloc.scopes.push({})
  push_scope(alloc.sem)
}

///|
fn cg_pop_scope(alloc : LocalAlloc) -> Unit {
  alloc.scopes.pop() |> ignore
  pop_scope(alloc.sem)
}

///|
fn lookup_local(alloc : LocalAlloc, name : String) -> LocalSlot? {
  let mut i = alloc.scopes.length()
  while i > 0 {
    i = i - 1
    let scope = alloc.scopes[i]
    if scope.contains(name) {
      return scope.get(name)
    }
  }
  None
}

///|
fn type_size_align_or_error(
  sem : SemContext,
  ty : CType,
  loc : SrcLoc,
) -> (Int, Int)? {
  match type_size_align(sem, ty, loc) {
    None => None
    Some((size, align)) => Some((size, align))
  }
}

///|
fn arm64_sz_from_size(size : Int) -> Int? {
  match size {
    1 => Some(0)
    2 => Some(1)
    4 => Some(2)
    8 => Some(3)
    _ => None
  }
}

///|
fn alloc_local(
  alloc : LocalAlloc,
  name : String,
  ty : CType,
  loc : SrcLoc,
) -> LocalSlot? {
  let (size, align) = match type_size_align_or_error(alloc.sem, ty, loc) {
    None => return None
    Some(v) => v
  }
  let aligned = align_up(alloc.used_bytes, align)
  alloc.used_bytes = aligned + size
  let offset = -(aligned + size)
  let slot = { offset, ty }
  let idx = alloc.scopes.length() - 1
  alloc.scopes[idx].set(name, slot)
  let sem_idx = alloc.sem.locals.length() - 1
  alloc.sem.locals[sem_idx].set(name, ty)
  Some(slot)
}

///|
fn layout_stmt(alloc : LocalAlloc, stmt : Stmt) -> Unit {
  match stmt {
    Stmt::Compound(stmts~, ..) => {
      cg_push_scope(alloc)
      for s in stmts {
        layout_stmt(alloc, s)
      }
      cg_pop_scope(alloc)
    }
    Stmt::DeclStmt(decls~, ..) => {
      for d in decls {
        alloc_local(alloc, d.name, d.ty, d.loc) |> ignore
        match d.init {
          None => ()
          Some(init) => layout_initializer(alloc, init)
        }
      }
    }
    Stmt::If(cond~, then_branch~, else_branch~, ..) => {
      layout_expr(alloc, cond)
      layout_stmt(alloc, then_branch)
      match else_branch {
        None => ()
        Some(s) => layout_stmt(alloc, s)
      }
    }
    Stmt::While(cond~, body~, ..) => {
      layout_expr(alloc, cond)
      layout_stmt(alloc, body)
    }
    Stmt::DoWhile(cond~, body~, ..) => {
      layout_stmt(alloc, body)
      layout_expr(alloc, cond)
    }
    Stmt::For(init~, cond~, step~, body~, ..) => {
      cg_push_scope(alloc)
      match init {
        None => ()
        Some(s) => layout_stmt(alloc, s)
      }
      match cond {
        None => ()
        Some(e) => layout_expr(alloc, e)
      }
      match step {
        None => ()
        Some(e) => layout_expr(alloc, e)
      }
      layout_stmt(alloc, body)
      cg_pop_scope(alloc)
    }
    Stmt::Switch(cond~, body~, ..) => {
      layout_expr(alloc, cond)
      layout_stmt(alloc, body)
    }
    Stmt::Case(expr~, end_expr~, body~, ..) => {
      layout_expr(alloc, expr)
      match end_expr {
        None => ()
        Some(e) => layout_expr(alloc, e)
      }
      layout_stmt(alloc, body)
    }
    Stmt::Default(body~, ..) => layout_stmt(alloc, body)
    Stmt::Label(body=body, ..) => layout_stmt(alloc, body)
    Stmt::Return(value~, ..) =>
      match value {
        None => ()
        Some(e) => layout_expr(alloc, e)
      }
    Stmt::ExprStmt(expr~, ..) => layout_expr(alloc, expr)
    Stmt::Asm(_) |
    Stmt::Goto(name=_, loc=_) |
    Stmt::Break(_) |
    Stmt::Continue(_) |
    Stmt::TagDef(ty=_, loc=_) |
    Stmt::StaticAssert(_) |
    Stmt::Empty(_) => ()
  }
}

///|
fn layout_initializer(alloc : LocalAlloc, init : Initializer) -> Unit {
  match init {
    Initializer::Expr(expr~, ..) => layout_expr(alloc, expr)
    Initializer::List(items~, ..) =>
      for item in items {
        layout_initializer(alloc, item.value)
      }
  }
}

///|
fn layout_expr(alloc : LocalAlloc, expr : Expr) -> Unit {
  match expr {
    Expr::Unary(expr=inner, ..) => layout_expr(alloc, inner)
    Expr::Cast(expr=inner, ..) => layout_expr(alloc, inner)
    Expr::SizeofExpr(expr=inner, ..) => layout_expr(alloc, inner)
    Expr::AlignofExpr(expr=inner, ..) => layout_expr(alloc, inner)
    Expr::Binary(left~, right~, ..) => {
      layout_expr(alloc, left)
      layout_expr(alloc, right)
    }
    Expr::Conditional(cond~, then_expr~, else_expr~, ..) => {
      layout_expr(alloc, cond)
      layout_expr(alloc, then_expr)
      layout_expr(alloc, else_expr)
    }
    Expr::Call(callee~, args~, ..) => {
      layout_expr(alloc, callee)
      for a in args {
        layout_expr(alloc, a)
      }
    }
    Expr::Index(base~, index~, ..) => {
      layout_expr(alloc, base)
      layout_expr(alloc, index)
    }
    Expr::Member(base~, ..) => layout_expr(alloc, base)
    Expr::BuiltinVaArg(list~, ..) => layout_expr(alloc, list)
    _ => ()
  }
}

///|
fn emit_mov(emitter : Arm64Emitter, is64 : Bool, dst : Int, src : Int) -> Unit {
  let base : Int = if is64 { 0xaa0003e0 } else { 0x2a0003e0 }
  emit32(emitter, base.lor(dst).lor(src << 16).reinterpret_as_uint())
}

///|
fn emit_cmp(emitter : Arm64Emitter, is64 : Bool, a : Int, b : Int) -> Unit {
  let base : Int = if is64 { 0xeb00001f } else { 0x6b00001f }
  emit32(emitter, base.lor(a << 5).lor(b << 16).reinterpret_as_uint())
}

///|
fn emit_sxtw(emitter : Arm64Emitter, dst : Int, src : Int) -> Unit {
  emit32(
    emitter,
    (0x93407c00 : Int).lor(dst).lor(src << 5).reinterpret_as_uint(),
  )
}

///|
const ARM64_COND_EQ : Int = 0

///|
const ARM64_COND_NE : Int = 1

///|
fn emit_b_cond_placeholder(emitter : Arm64Emitter, cond : Int) -> Int {
  let at = emitter_pc(emitter)
  emit32(
    emitter,
    (0x54000000 : Int).lor(cond & 0xf).reinterpret_as_uint(),
  )
  at
}

///|
fn patch_b_cond(
  emitter : Arm64Emitter,
  at_ : Int,
  target_ : Int,
  cond : Int,
) -> Unit raise {
  let at = at_
  let target = target_
  let diff = target - at
  if (diff & 3) != 0 {
    fail("codegen: unaligned b.cond target")
  }
  let imm = diff >> 2
  let limit = 1 << 18
  if imm < -limit || imm >= limit {
    fail("codegen: conditional branch out of range")
  }
  let imm19 = imm & ((1 << 19) - 1)
  emitter.code[at >> 2] = (0x54000000 : Int)
    .lor((imm19 & 0x7ffff) << 5)
    .lor(cond & 0xf)
    .reinterpret_as_uint()
}

///|
fn emit_cset_from_tok(emitter : Arm64Emitter, tok : Int, dst : Int) -> Unit raise {
  let base : Int = match tok {
    TOK_EQ => 0x1a9f17e0
    TOK_NE => 0x1a9f07e0
    TOK_LT => 0x1a9fa7e0
    TOK_LE => 0x1a9fc7e0
    TOK_GT => 0x1a9fd7e0
    TOK_GE => 0x1a9fb7e0
    _ => fail("codegen: unsupported comparison token")
  }
  emit32(emitter, base.lor(dst).reinterpret_as_uint())
}

///|
fn type_is_supported_int32(ty : CType) -> Bool {
  match strip_qualifiers(ty) {
    CType::Int(kind=CIntKind::Int, ..) => true
    _ => false
  }
}

///|
fn type_is_pointer_like(ty : CType) -> Bool {
  match strip_qualifiers(ty) {
    CType::Pointer(_) => true
    CType::Array(..) => true
    _ => false
  }
}

///|
fn scalar_size_signed_or_error(
  sem : SemContext,
  ty : CType,
  loc : SrcLoc,
) -> (Int, Bool)? {
  let (size, _) = match type_size_align_or_error(sem, ty, loc) {
    None => return None
    Some(v) => v
  }
  let signed = match strip_qualifiers(ty) {
    CType::Int(unsigned~, ..) => !unsigned
    _ => false
  }
  Some((size, signed))
}

///|
struct SymTable {
  names : Array[String]
  name_to_id : Map[String, Int]
}

///|
fn new_symtab() -> SymTable {
  { names: [], name_to_id: {} }
}

///|
fn sym_for_name(tab : SymTable, name : String) -> Sym {
  match tab.name_to_id.get(name) {
    Some(id) => { id }
    None => {
      let id = tab.names.length() + 1
      tab.names.push(name)
      tab.name_to_id.set(name, id)
      { id }
    }
  }
}

///|
fn link_name(name : String) -> String {
  if name.has_prefix("_") { name } else { "_\{name}" }
}

///|
fn emit_load_local_int32(
  emitter : Arm64Emitter,
  dst : Int,
  off : Int,
) -> Unit {
  let off_u64 = off.to_int64().reinterpret_as_uint64()
  arm64_ldrx(emitter, false, 2, dst.to_uint(), (29 : UInt), off_u64)
}

///|
fn emit_store_local_int32(
  emitter : Arm64Emitter,
  src : Int,
  off : Int,
) -> Unit {
  let off_u64 = off.to_int64().reinterpret_as_uint64()
  arm64_strx(emitter, 2, src.to_uint(), (29 : UInt), off_u64)
}

///|
fn emit_load_local_scalar(
  emitter : Arm64Emitter,
  sem : SemContext,
  ty : CType,
  dst : Int,
  off : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let (size, signed) = match scalar_size_signed_or_error(sem, ty, loc) {
    None => return
    Some(v) => v
  }
  let sz = match arm64_sz_from_size(size) {
    None => {
      add_error(bag, loc, "codegen: unsupported scalar size")
      return
    }
    Some(v) => v
  }
  let off_u64 = off.to_int64().reinterpret_as_uint64()
  arm64_ldrx(emitter, signed, sz, dst.to_uint(), (29 : UInt), off_u64)
}

///|
fn emit_store_local_scalar(
  emitter : Arm64Emitter,
  sem : SemContext,
  ty : CType,
  src : Int,
  off : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let (size, _) = match scalar_size_signed_or_error(sem, ty, loc) {
    None => return
    Some(v) => v
  }
  let sz = match arm64_sz_from_size(size) {
    None => {
      add_error(bag, loc, "codegen: unsupported scalar size")
      return
    }
    Some(v) => v
  }
  let off_u64 = off.to_int64().reinterpret_as_uint64()
  arm64_strx(emitter, sz, src.to_uint(), (29 : UInt), off_u64)
}

///|
fn emit_addr_local(
  emitter : Arm64Emitter,
  dst : Int,
  off : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let imm = if off < 0 { -off } else { off }
  if imm > 0xfff {
    add_error(bag, loc, "codegen: large stack offsets not supported yet")
    return
  }
  if off < 0 {
    emit32(
      emitter,
      (0xd1000000 : Int)
      .lor(dst)
      .lor(29 << 5)
      .lor(imm << 10)
      .reinterpret_as_uint(),
    )
  } else {
    emit32(
      emitter,
      (0x91000000 : Int)
      .lor(dst)
      .lor(29 << 5)
      .lor(imm << 10)
      .reinterpret_as_uint(),
    )
  }
}

///|
fn emit_addr_global(emitter : Arm64Emitter, sym : Sym, dst : Int) -> Unit {
  let adrp_off = emitter_pc(emitter)
  greloca(emitter, sym, adrp_off, R_AARCH64_ADR_PREL_PG_HI21, 0)
  emit32(emitter, (0x90000000 : UInt64).lor(dst.to_uint64()).to_uint())
  let add_off = emitter_pc(emitter)
  greloca(emitter, sym, add_off, R_AARCH64_ADD_ABS_LO12_NC, 0)
  emit32(
    emitter,
    (0x91000000 : UInt64)
    .lor(dst.to_uint64())
    .lor(dst.to_uint64() << 5)
    .to_uint(),
  )
}

///|
fn emit_load_global_int32(emitter : Arm64Emitter, sym : Sym, dst : Int) -> Unit {
  let adrp_off = emitter_pc(emitter)
  greloca(emitter, sym, adrp_off, R_AARCH64_ADR_PREL_PG_HI21, 0)
  emit32(
    emitter,
    (0x90000000 : UInt64).lor(dst.to_uint64()).to_uint(),
  )
  let add_off = emitter_pc(emitter)
  greloca(emitter, sym, add_off, R_AARCH64_LDST8_ABS_LO12_NC, 0)
  emit32(
    emitter,
    (0x91000000 : UInt64)
    .lor(dst.to_uint64())
    .lor(dst.to_uint64() << 5)
    .to_uint(),
  )
  emit32(
    emitter,
    (0xb9400000 : UInt64)
    .lor(dst.to_uint64())
    .lor(dst.to_uint64() << 5)
    .to_uint(),
  )
}

///|
fn emit_store_global_int32(emitter : Arm64Emitter, sym : Sym, src : Int) -> Unit {
  let addr_reg : Int = 16
  let adrp_off = emitter_pc(emitter)
  greloca(emitter, sym, adrp_off, R_AARCH64_ADR_PREL_PG_HI21, 0)
  emit32(
    emitter,
    (0x90000000 : UInt64).lor(addr_reg.to_uint64()).to_uint(),
  )
  let add_off = emitter_pc(emitter)
  greloca(emitter, sym, add_off, R_AARCH64_LDST8_ABS_LO12_NC, 0)
  emit32(
    emitter,
    (0x91000000 : UInt64)
    .lor(addr_reg.to_uint64())
    .lor(addr_reg.to_uint64() << 5)
    .to_uint(),
  )
  emit32(
    emitter,
    (0xb9000000 : UInt64)
    .lor(src.to_uint64())
    .lor(addr_reg.to_uint64() << 5)
    .to_uint(),
  )
}

///|
fn emit_call(emitter : Arm64Emitter, sym : Sym) -> Unit {
  let ind = emitter_pc(emitter)
  greloca(emitter, sym, ind, R_AARCH64_CALL26, 0)
  emit32(emitter, (0x94000000 : UInt))
}

///|
fn gen_call_direct(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : Map[String, Sym],
  name : String,
  args : Array[Expr],
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let mut i = 0
  while i < args.length() {
    if i >= 8 {
      add_error(bag, loc, "codegen: only supports up to 8 args for now")
      return
    }
    let aty = type_of_expr(alloc.sem, args[i])
    if type_is_pointer_like(aty) {
      gen_expr_ptr(emitter, alloc, syms, pool, cstrings, args[i], i, bag)
    } else {
      gen_expr_int32(emitter, alloc, syms, pool, cstrings, args[i], i, bag)
    }
    i = i + 1
  }
  let sym = sym_for_name(syms, link_name(name))
  emit_call(emitter, sym)
}

///|
fn element_type_for_pointer_arith(ty : CType) -> CType? {
  match strip_qualifiers(ty) {
    CType::Pointer(inner) => Some(inner)
    CType::Array(elem~, ..) => Some(elem)
    _ => None
  }
}

///|
fn gen_lvalue_addr(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : Map[String, Sym],
  expr : Expr,
  dst : Int,
  bag : DiagBag,
) -> Unit {
  match expr {
    Expr::Ident(name~, loc~) =>
      match lookup_local(alloc, name) {
        Some(slot) => emit_addr_local(emitter, dst, slot.offset, loc, bag)
        None => {
          let sym = sym_for_name(syms, link_name(name))
          emit_addr_global(emitter, sym, dst)
        }
      }
    Expr::Unary(op=UnaryOp::Deref, expr=inner, ..) =>
      gen_expr_ptr(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
    Expr::Index(base~, index~, loc~) => {
      gen_expr_ptr(emitter, alloc, syms, pool, cstrings, base, dst, bag)
      let idx = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      gen_expr_int32(emitter, alloc, syms, pool, cstrings, index, idx, bag)
      emit_sxtw(emitter, idx, idx)
      let base_ty = type_of_expr(alloc.sem, base)
      let elem_ty = match element_type_for_pointer_arith(base_ty) {
        None => {
          add_error(bag, loc, "codegen: index base is not pointer/array")
          give_reg(pool, idx)
          return
        }
        Some(t) => t
      }
      let (elem_size, _) = match type_size_align_or_error(alloc.sem, elem_ty, loc) {
        None => {
          give_reg(pool, idx)
          return
        }
        Some(v) => v
      }
      if elem_size != 1 {
        let scale = take_reg(pool) catch {
          err => {
            add_error(bag, loc, err.to_string())
            give_reg(pool, idx)
            return
          }
        }
        arm64_movimm(emitter, scale.to_uint(), elem_size.to_uint64())
        emit32(
          emitter,
          (0x9b007c00 : Int)
          .lor(idx)
          .lor(idx << 5)
          .lor(scale << 16)
          .reinterpret_as_uint(),
        )
        give_reg(pool, scale)
      }
      emit32(
        emitter,
        (0x8b000000 : Int)
        .lor(dst)
        .lor(dst << 5)
        .lor(idx << 16)
        .reinterpret_as_uint(),
      )
      give_reg(pool, idx)
    }
    _ => add_error(bag, expr_loc(expr), "codegen: unsupported lvalue for now")
  }
}

///|
fn store_lvalue_scalar(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : Map[String, Sym],
  lvalue : Expr,
  value_reg : Int,
  value_ty : CType,
  bag : DiagBag,
) -> Unit {
  let loc = expr_loc(lvalue)
  match lvalue {
    Expr::Ident(name~, ..) =>
      match lookup_local(alloc, name) {
        Some(slot) =>
          emit_store_local_scalar(
            emitter,
            alloc.sem,
            slot.ty,
            value_reg,
            slot.offset,
            loc,
            bag,
          )
        None => {
          let sym = sym_for_name(syms, link_name(name))
          let addr_reg : Int = 16
          emit_addr_global(emitter, sym, addr_reg)
          let (size, _) = match scalar_size_signed_or_error(alloc.sem, value_ty, loc) {
            None => return
            Some(v) => v
          }
          let sz = match arm64_sz_from_size(size) {
            None => {
              add_error(bag, loc, "codegen: unsupported scalar size")
              return
            }
            Some(v) => v
          }
          arm64_strx(emitter, sz, value_reg.to_uint(), addr_reg.to_uint(), 0)
        }
      }
    _ => {
      let addr = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, lvalue, addr, bag)
      let (size, _) = match scalar_size_signed_or_error(alloc.sem, value_ty, loc) {
        None => {
          give_reg(pool, addr)
          return
        }
        Some(v) => v
      }
      let sz = match arm64_sz_from_size(size) {
        None => {
          add_error(bag, loc, "codegen: unsupported scalar size")
          give_reg(pool, addr)
          return
        }
        Some(v) => v
      }
      arm64_strx(emitter, sz, value_reg.to_uint(), addr.to_uint(), 0)
      give_reg(pool, addr)
    }
  }
}

///|
fn gen_expr_int32(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : Map[String, Sym],
  expr : Expr,
  dst : Int,
  bag : DiagBag,
) -> Unit {
  match expr {
    Expr::IntLit(value~, loc~) =>
      match parse_int64_literal(value) {
        None => add_error(bag, loc, "codegen: invalid integer literal")
        Some(v) => arm64_movimm(emitter, dst.to_uint(), v.to_uint64())
      }
    Expr::CharLit(value~, ..) =>
      arm64_movimm(emitter, dst.to_uint(), value.to_uint64())
    Expr::Ident(name~, loc~) =>
      match lookup_local(alloc, name) {
        Some(slot) =>
          emit_load_local_scalar(emitter, alloc.sem, slot.ty, dst, slot.offset, loc, bag)
        None => {
          let sym = sym_for_name(syms, link_name(name))
          emit_load_global_int32(emitter, sym, dst)
        }
      }
    Expr::Unary(op~, expr=inner, loc~) => {
      match op {
        UnaryOp::Plus =>
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
        UnaryOp::Minus => {
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
          emit32(
            emitter,
            (0x4b0003e0 : Int)
            .lor(dst)
            .lor(dst << 16)
            .reinterpret_as_uint(),
          )
        }
        UnaryOp::BitNot => {
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
          emit32(
            emitter,
            (0x2a2003e0 : Int)
            .lor(dst)
            .lor(dst << 16)
            .reinterpret_as_uint(),
          )
        }
        UnaryOp::Not => {
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
          emit_cmp(emitter, false, dst, 31)
          emit32(
            emitter,
            (0x1a9f17e0 : Int).lor(dst).reinterpret_as_uint(),
          )
        }
        UnaryOp::Deref => {
          let addr = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          gen_expr_ptr(emitter, alloc, syms, pool, cstrings, inner, addr, bag)
          let ty = type_of_expr(alloc.sem, expr)
          let (size, signed) = match scalar_size_signed_or_error(alloc.sem, ty, loc) {
            None => {
              give_reg(pool, addr)
              return
            }
            Some(v) => v
          }
          if size == 8 {
            add_error(bag, loc, "codegen: deref int32 path does not support 8-byte loads yet")
            give_reg(pool, addr)
            return
          }
          let sz = match arm64_sz_from_size(size) {
            None => {
              add_error(bag, loc, "codegen: unsupported scalar size")
              give_reg(pool, addr)
              return
            }
            Some(v) => v
          }
          arm64_ldrx(emitter, signed, sz, dst.to_uint(), addr.to_uint(), 0)
          give_reg(pool, addr)
        }
        _ => add_error(bag, loc, "codegen: unsupported unary operator")
      }
    }
    Expr::Binary(op~, left~, right~, loc~) =>
      match op {
        BinaryOp::Comma => {
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, left, dst, bag)
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, right, dst, bag)
        }
        BinaryOp::Assign =>
          match left {
            Expr::Ident(name~, ..) => {
              gen_expr_int32(emitter, alloc, syms, pool, cstrings, right, dst, bag)
              match lookup_local(alloc, name) {
                Some(slot) =>
                  if type_is_supported_int32(slot.ty) {
                    emit_store_local_int32(emitter, dst, slot.offset)
                  } else {
                    add_error(
                      bag,
                      loc,
                      "codegen: only int locals supported for now",
                    )
                  }
                None => {
                  let sym = sym_for_name(syms, link_name(name))
                  emit_store_global_int32(emitter, sym, dst)
                }
              }
            }
            Expr::Unary(op=UnaryOp::Deref, ..) | Expr::Index(..) => {
              gen_expr_int32(emitter, alloc, syms, pool, cstrings, right, dst, bag)
              store_lvalue_scalar(
                emitter,
                alloc,
                syms,
                pool,
                cstrings,
                left,
                dst,
                type_of_expr(alloc.sem, left),
                bag,
              )
            }
            _ => add_error(bag, loc, "codegen: unsupported assignment lhs for now")
          }
        BinaryOp::Add | BinaryOp::Sub | BinaryOp::Mul | BinaryOp::Div |
        BinaryOp::Mod | BinaryOp::BitAnd | BinaryOp::BitOr | BinaryOp::BitXor |
        BinaryOp::Eq | BinaryOp::Ne | BinaryOp::Lt | BinaryOp::Le | BinaryOp::Gt |
        BinaryOp::Ge | BinaryOp::Shl | BinaryOp::Shr => {
          let left_ty = type_of_expr(alloc.sem, left)
          let right_ty = type_of_expr(alloc.sem, right)
          let has_ptr = type_is_pointer_like(left_ty) || type_is_pointer_like(right_ty)
          if has_ptr {
            match op {
              BinaryOp::Eq | BinaryOp::Ne => ()
              _ => {
                add_error(
                  bag,
                  loc,
                  "codegen: only ==/!= supported for pointer comparisons for now",
                )
                return
              }
            }
            let tmp = take_reg(pool) catch {
              err => {
                add_error(bag, loc, err.to_string())
                return
              }
            }
            if type_is_pointer_like(left_ty) {
              gen_expr_ptr(emitter, alloc, syms, pool, cstrings, left, tmp, bag)
            } else {
              gen_expr_int32(emitter, alloc, syms, pool, cstrings, left, tmp, bag)
              emit_sxtw(emitter, tmp, tmp)
            }
            if type_is_pointer_like(right_ty) {
              gen_expr_ptr(emitter, alloc, syms, pool, cstrings, right, dst, bag)
            } else {
              gen_expr_int32(emitter, alloc, syms, pool, cstrings, right, dst, bag)
              emit_sxtw(emitter, dst, dst)
            }
            emit_cmp(emitter, true, tmp, dst)
            emit_cset_from_tok(
              emitter,
              if op == BinaryOp::Eq { TOK_EQ } else { TOK_NE },
              dst,
            )
            catch { err => add_error(bag, loc, err.to_string()) }
            give_reg(pool, tmp)
            return
          }
          let left_reg = dst
          gen_expr_int32(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            left,
            left_reg,
            bag,
          )
          let tmp = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          emit_mov(emitter, false, tmp, left_reg)
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, right, dst, bag)
          match op {
            BinaryOp::Add =>
              emit32(
                emitter,
                (0x0b000000 : Int)
                .lor(dst)
                .lor(tmp << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::Sub =>
              emit32(
                emitter,
                (0x4b000000 : Int)
                .lor(dst)
                .lor(tmp << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::Mul =>
              emit32(
                emitter,
                (0x1b007c00 : Int)
                .lor(dst)
                .lor(tmp << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::Div =>
              emit32(
                emitter,
                (0x1ac00c00 : Int)
                .lor(dst)
                .lor(tmp << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::Mod => {
              emit32(
                emitter,
                (0x1ac00c00 : Int)
                .lor(30)
                .lor(tmp << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
              emit32(
                emitter,
                (0x1b008000 : Int)
                .lor(dst)
                .lor(30 << 5)
                .lor(dst << 16)
                .lor(tmp << 10)
                .reinterpret_as_uint(),
              )
            }
            BinaryOp::BitAnd =>
              emit32(
                emitter,
                (0x0a000000 : Int)
                .lor(dst)
                .lor(tmp << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::BitOr =>
              emit32(
                emitter,
                (0x2a000000 : Int)
                .lor(dst)
                .lor(tmp << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::BitXor =>
              emit32(
                emitter,
                (0x4a000000 : Int)
                .lor(dst)
                .lor(tmp << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::Eq => {
              emit_cmp(emitter, false, tmp, dst)
              emit_cset_from_tok(emitter, TOK_EQ, dst) catch {
                err => add_error(bag, loc, err.to_string())
              }
            }
            BinaryOp::Ne => {
              emit_cmp(emitter, false, tmp, dst)
              emit_cset_from_tok(emitter, TOK_NE, dst) catch {
                err => add_error(bag, loc, err.to_string())
              }
            }
            BinaryOp::Lt => {
              emit_cmp(emitter, false, tmp, dst)
              emit_cset_from_tok(emitter, TOK_LT, dst) catch {
                err => add_error(bag, loc, err.to_string())
              }
            }
            BinaryOp::Le => {
              emit_cmp(emitter, false, tmp, dst)
              emit_cset_from_tok(emitter, TOK_LE, dst) catch {
                err => add_error(bag, loc, err.to_string())
              }
            }
            BinaryOp::Gt => {
              emit_cmp(emitter, false, tmp, dst)
              emit_cset_from_tok(emitter, TOK_GT, dst) catch {
                err => add_error(bag, loc, err.to_string())
              }
            }
            BinaryOp::Ge => {
              emit_cmp(emitter, false, tmp, dst)
              emit_cset_from_tok(emitter, TOK_GE, dst) catch {
                err => add_error(bag, loc, err.to_string())
              }
            }
            BinaryOp::Shl | BinaryOp::Shr =>
              {
                match const_i64_from_expr(right) {
                None =>
                  add_error(
                    bag,
                    loc,
                    "codegen: shift rhs must be constant for now",
                  )
                Some(v) => {
                  let ok = arm64_gen_opic(
                    emitter,
                    if op == BinaryOp::Shl { TOK_SHL } else { TOK_SHR },
                    0,
                    false,
                    v.to_uint64(),
                    dst,
                    tmp,
                  )
                  if !ok {
                    add_error(bag, loc, "codegen: unsupported shift immediate")
                  }
                }
                }
              }
            _ => ()
          }
          give_reg(pool, tmp)
        }
        _ =>
          add_error(
            bag,
            loc,
            "codegen: unsupported binary operator for now",
          )
      }
    Expr::Call(callee=Expr::Ident(name~, ..), args~, loc~) => {
      gen_call_direct(emitter, alloc, syms, pool, cstrings, name, args, loc, bag)
      if dst != 0 {
        emit_mov(emitter, true, dst, 0)
      }
    }
    Expr::Call(loc=call_loc, ..) =>
      add_error(
        bag,
        call_loc,
        "codegen: only supports direct calls to identifiers for now",
      )
    Expr::SizeofType(ty~, loc~) =>
      match type_size_align_or_error(alloc.sem, ty, loc) {
        None => ()
        Some((size, _)) => arm64_movimm(emitter, dst.to_uint(), size.to_uint64())
      }
    Expr::Cast(expr=inner, ..) =>
      gen_expr_int32(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
    Expr::Conditional(loc=cond_loc, ..) =>
      add_error(bag, cond_loc, "codegen: conditional operator not supported yet")
    Expr::StringLit(value=value, loc=loc, ..) =>
      match cstrings.get(value) {
        None =>
          add_error(bag, loc, "codegen: missing string literal in cstring pool")
        Some(sym) => {
          let adrp_off = emitter_pc(emitter)
          greloca(emitter, sym, adrp_off, R_AARCH64_ADR_PREL_PG_HI21, 0)
          emit32(
            emitter,
            (0x90000000 : UInt64).lor(dst.to_uint64()).to_uint(),
          )
          let add_off = emitter_pc(emitter)
          greloca(emitter, sym, add_off, R_AARCH64_ADD_ABS_LO12_NC, 0)
          emit32(
            emitter,
            (0x91000000 : UInt64)
            .lor(dst.to_uint64())
            .lor(dst.to_uint64() << 5)
            .to_uint(),
          )
        }
      }
    _ =>
      add_error(bag, expr_loc(expr), "codegen: unsupported expression")
  }
}

///|
fn gen_expr_ptr(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : Map[String, Sym],
  expr : Expr,
  dst : Int,
  bag : DiagBag,
) -> Unit {
  match expr {
    Expr::IntLit(value~, loc~) =>
      match parse_int64_literal(value) {
        None => add_error(bag, loc, "codegen: invalid integer literal")
        Some(v) => arm64_movimm(emitter, dst.to_uint(), v.to_uint64())
      }
    Expr::CharLit(value~, ..) =>
      arm64_movimm(emitter, dst.to_uint(), value.to_uint64())
    Expr::StringLit(value=value, loc=loc, ..) =>
      match cstrings.get(value) {
        None => add_error(bag, loc, "codegen: missing string literal in cstring pool")
        Some(sym) => emit_addr_global(emitter, sym, dst)
      }
    Expr::Ident(name~, loc~) =>
      match lookup_local(alloc, name) {
        Some(slot) =>
          match strip_qualifiers(slot.ty) {
            CType::Array(..) => emit_addr_local(emitter, dst, slot.offset, loc, bag)
            _ =>
              emit_load_local_scalar(emitter, alloc.sem, slot.ty, dst, slot.offset, loc, bag)
          }
        None => {
          let sym = sym_for_name(syms, link_name(name))
          emit_addr_global(emitter, sym, dst)
          arm64_ldrx(emitter, false, 3, dst.to_uint(), dst.to_uint(), 0)
        }
      }
    Expr::Unary(op=UnaryOp::Addr, expr=inner, ..) =>
      gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
    Expr::Unary(op=UnaryOp::Deref, expr=inner, loc~) => {
      gen_expr_ptr(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
      let ty = type_of_expr(alloc.sem, expr)
      let (size, signed) = match scalar_size_signed_or_error(alloc.sem, ty, loc) {
        None => return
        Some(v) => v
      }
      let sz = match arm64_sz_from_size(size) {
        None => {
          add_error(bag, loc, "codegen: unsupported scalar size")
          return
        }
        Some(v) => v
      }
      arm64_ldrx(emitter, signed, sz, dst.to_uint(), dst.to_uint(), 0)
    }
    Expr::Binary(op=BinaryOp::Assign, left~, right~, ..) => {
      gen_expr_ptr(emitter, alloc, syms, pool, cstrings, right, dst, bag)
      store_lvalue_scalar(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        left,
        dst,
        type_of_expr(alloc.sem, left),
        bag,
      )
    }
    Expr::Binary(op~, left~, right~, loc~) =>
      match op {
        BinaryOp::Add | BinaryOp::Sub => {
          let left_ty = type_of_expr(alloc.sem, left)
          let right_ty = type_of_expr(alloc.sem, right)
          if type_is_pointer_like(left_ty) && type_is_pointer_like(right_ty) {
            add_error(bag, loc, "codegen: pointer +/- pointer not supported yet")
            return
          }
          if op == BinaryOp::Sub && type_is_pointer_like(right_ty) && !type_is_pointer_like(left_ty) {
            add_error(bag, loc, "codegen: int - pointer not supported")
            return
          }
          let (ptr_expr, int_expr, ptr_ty) =
            if type_is_pointer_like(left_ty) { (left, right, left_ty) }
            else if type_is_pointer_like(right_ty) { (right, left, right_ty) }
            else {
              add_error(bag, loc, "codegen: pointer add/sub needs a pointer operand")
              return
            }
          gen_expr_ptr(emitter, alloc, syms, pool, cstrings, ptr_expr, dst, bag)
          let idx = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, int_expr, idx, bag)
          emit_sxtw(emitter, idx, idx)
          let elem_ty = match element_type_for_pointer_arith(ptr_ty) {
            None => {
              add_error(bag, loc, "codegen: pointer arithmetic missing element type")
              give_reg(pool, idx)
              return
            }
            Some(t) => t
          }
          let (elem_size, _) = match type_size_align_or_error(alloc.sem, elem_ty, loc) {
            None => {
              give_reg(pool, idx)
              return
            }
            Some(v) => v
          }
          if elem_size != 1 {
            let scale = take_reg(pool) catch {
              err => {
                add_error(bag, loc, err.to_string())
                give_reg(pool, idx)
                return
              }
            }
            arm64_movimm(emitter, scale.to_uint(), elem_size.to_uint64())
            emit32(
              emitter,
              (0x9b007c00 : Int)
              .lor(idx)
              .lor(idx << 5)
              .lor(scale << 16)
              .reinterpret_as_uint(),
            )
            give_reg(pool, scale)
          }
          let base = if op == BinaryOp::Add { 0x8b000000 } else { 0xcb000000 }
          emit32(
            emitter,
            (base : Int)
            .lor(dst)
            .lor(dst << 5)
            .lor(idx << 16)
            .reinterpret_as_uint(),
          )
          give_reg(pool, idx)
        }
        _ => add_error(bag, loc, "codegen: unsupported pointer expression")
      }
    Expr::Cast(expr=inner, ..) => {
      let inner_ty = type_of_expr(alloc.sem, inner)
      if type_is_pointer_like(inner_ty) {
        gen_expr_ptr(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
      } else {
        gen_expr_int32(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
        emit_sxtw(emitter, dst, dst)
      }
    }
    Expr::Call(callee=Expr::Ident(name~, ..), args~, loc~) => {
      gen_call_direct(emitter, alloc, syms, pool, cstrings, name, args, loc, bag)
      if dst != 0 {
        emit_mov(emitter, true, dst, 0)
      }
    }
    _ => add_error(bag, expr_loc(expr), "codegen: unsupported pointer expression")
  }
}

///|
fn gen_expr_any(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : Map[String, Sym],
  expr : Expr,
  dst : Int,
  bag : DiagBag,
) -> Unit {
  let ty = type_of_expr(alloc.sem, expr)
  if type_is_pointer_like(ty) {
    gen_expr_ptr(emitter, alloc, syms, pool, cstrings, expr, dst, bag)
  } else {
    gen_expr_int32(emitter, alloc, syms, pool, cstrings, expr, dst, bag)
  }
}

///|
fn stmt_loc(stmt : Stmt) -> SrcLoc {
  match stmt {
    Stmt::Compound(loc=loc, ..) => loc
    Stmt::If(loc=loc, ..) => loc
    Stmt::While(loc=loc, ..) => loc
    Stmt::DoWhile(loc=loc, ..) => loc
    Stmt::For(loc=loc, ..) => loc
    Stmt::Switch(loc=loc, ..) => loc
    Stmt::Case(loc=loc, ..) => loc
    Stmt::Default(loc=loc, ..) => loc
    Stmt::Label(loc=loc, ..) => loc
    Stmt::Goto(loc=loc, ..) => loc
    Stmt::Break(loc~) => loc
    Stmt::Continue(loc~) => loc
    Stmt::Return(loc=loc, ..) => loc
    Stmt::Asm(stmt) => stmt.loc
    Stmt::ExprStmt(loc=loc, ..) => loc
    Stmt::DeclStmt(loc=loc, ..) => loc
    Stmt::TagDef(loc=loc, ..) => loc
    Stmt::StaticAssert(v) => v.loc
    Stmt::Empty(loc~) => loc
  }
}

///|
struct LoopChains {
  break_chain : Int
  cont_chain : Int
}

///|
fn loop_append_break(
  loops : Array[LoopChains],
  emitter : Arm64Emitter,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let idx = loops.length() - 1
  match loops.get(idx) {
    None => add_error(bag, loc, "codegen: break outside of loop")
    Some(info) => {
      let chain = gjmp(emitter, info.break_chain)
      loops[idx] = { break_chain: chain, cont_chain: info.cont_chain }
    }
  }
}

///|
fn loop_append_continue(
  loops : Array[LoopChains],
  emitter : Arm64Emitter,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let idx = loops.length() - 1
  match loops.get(idx) {
    None => add_error(bag, loc, "codegen: continue outside of loop")
    Some(info) => {
      let chain = gjmp(emitter, info.cont_chain)
      loops[idx] = { break_chain: info.break_chain, cont_chain: chain }
    }
  }
}

///|
fn gen_stmt(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  loops : Array[LoopChains],
  cstrings : Map[String, Sym],
  stmt : Stmt,
  bag : DiagBag,
  return_chain : Int,
) -> Int {
  match stmt {
    Stmt::Compound(stmts~, ..) => {
      cg_push_scope(alloc)
      let mut chain = return_chain
      for s in stmts {
        chain = gen_stmt(emitter, alloc, syms, pool, loops, cstrings, s, bag, chain)
      }
      cg_pop_scope(alloc)
      chain
    }
    Stmt::DeclStmt(decls~, ..) => {
      for d in decls {
        match alloc_local(alloc, d.name, d.ty, d.loc) {
          None => ()
          Some(slot) =>
            match d.init {
              None => ()
              Some(init) =>
                match init {
                  Initializer::Expr(expr~, ..) => {
                    gen_expr_any(emitter, alloc, syms, pool, cstrings, expr, 0, bag)
                    emit_store_local_scalar(
                      emitter,
                      alloc.sem,
                      slot.ty,
                      0,
                      slot.offset,
                      d.loc,
                      bag,
                    )
                  }
                  _ =>
                    add_error(
                      bag,
                      d.loc,
                      "codegen: only scalar initializers supported for now",
                    )
                }
            }
        }
      }
      return_chain
    }
    Stmt::If(cond~, then_branch~, else_branch~, loc~) => {
      let cond_ty = type_of_expr(alloc.sem, cond)
      if type_is_pointer_like(cond_ty) {
        gen_expr_ptr(emitter, alloc, syms, pool, cstrings, cond, 0, bag)
        emit_cmp(emitter, true, 0, 31)
      } else {
        gen_expr_int32(emitter, alloc, syms, pool, cstrings, cond, 0, bag)
        emit_cmp(emitter, false, 0, 31)
      }
      let br_false = emit_b_cond_placeholder(emitter, ARM64_COND_EQ)
      let chain1 = gen_stmt(
        emitter,
        alloc,
        syms,
        pool,
        loops,
        cstrings,
        then_branch,
        bag,
        return_chain,
      )
      match else_branch {
        None => {
          let end_pc = emitter_pc(emitter)
          patch_b_cond(emitter, br_false, end_pc, ARM64_COND_EQ) catch {
            err => add_error(bag, loc, err.to_string())
          }
          chain1
        }
        Some(else_stmt) => {
          let after_then = gjmp(emitter, 0)
          let else_pc = emitter_pc(emitter)
          patch_b_cond(emitter, br_false, else_pc, ARM64_COND_EQ) catch {
            err => add_error(bag, loc, err.to_string())
          }
          let chain2 = gen_stmt(
            emitter,
            alloc,
            syms,
            pool,
            loops,
            cstrings,
            else_stmt,
            bag,
            chain1,
          )
          let end_pc = emitter_pc(emitter)
          gsym_addr(emitter, after_then, end_pc) catch {
            err => add_error(bag, loc, err.to_string())
          }
          chain2
        }
      }
    }
    Stmt::While(cond~, body~, loc~) => {
      let start_pc = emitter_pc(emitter)
      let cond_ty = type_of_expr(alloc.sem, cond)
      if type_is_pointer_like(cond_ty) {
        gen_expr_ptr(emitter, alloc, syms, pool, cstrings, cond, 0, bag)
        emit_cmp(emitter, true, 0, 31)
      } else {
        gen_expr_int32(emitter, alloc, syms, pool, cstrings, cond, 0, bag)
        emit_cmp(emitter, false, 0, 31)
      }
      let br_end = emit_b_cond_placeholder(emitter, ARM64_COND_EQ)

      loops.push({ break_chain: 0, cont_chain: 0 })
      let chain1 = gen_stmt(
        emitter,
        alloc,
        syms,
        pool,
        loops,
        cstrings,
        body,
        bag,
        return_chain,
      )
      let loop_info = loops.pop().unwrap_or({ break_chain: 0, cont_chain: 0 })

      gsym_addr(emitter, loop_info.cont_chain, start_pc) catch {
        err => add_error(bag, loc, err.to_string())
      }
      gjmp_addr(emitter, start_pc) catch {
        err => add_error(bag, loc, err.to_string())
      }
      let end_pc = emitter_pc(emitter)
      patch_b_cond(emitter, br_end, end_pc, ARM64_COND_EQ) catch {
        err => add_error(bag, loc, err.to_string())
      }
      gsym_addr(emitter, loop_info.break_chain, end_pc) catch {
        err => add_error(bag, loc, err.to_string())
      }
      chain1
    }
    Stmt::DoWhile(cond~, body~, loc~) => {
      let start_pc = emitter_pc(emitter)
      loops.push({ break_chain: 0, cont_chain: 0 })
      let chain1 = gen_stmt(
        emitter,
        alloc,
        syms,
        pool,
        loops,
        cstrings,
        body,
        bag,
        return_chain,
      )
      let cond_pc = emitter_pc(emitter)
      let loop_info = loops.pop().unwrap_or({ break_chain: 0, cont_chain: 0 })
      gsym_addr(emitter, loop_info.cont_chain, cond_pc) catch {
        err => add_error(bag, loc, err.to_string())
      }

      let cond_ty = type_of_expr(alloc.sem, cond)
      if type_is_pointer_like(cond_ty) {
        gen_expr_ptr(emitter, alloc, syms, pool, cstrings, cond, 0, bag)
        emit_cmp(emitter, true, 0, 31)
      } else {
        gen_expr_int32(emitter, alloc, syms, pool, cstrings, cond, 0, bag)
        emit_cmp(emitter, false, 0, 31)
      }
      let br_back = emit_b_cond_placeholder(emitter, ARM64_COND_NE)
      patch_b_cond(emitter, br_back, start_pc, ARM64_COND_NE) catch {
        err => add_error(bag, loc, err.to_string())
      }
      let end_pc = emitter_pc(emitter)
      gsym_addr(emitter, loop_info.break_chain, end_pc) catch {
        err => add_error(bag, loc, err.to_string())
      }
      chain1
    }
    Stmt::For(init~, cond~, step~, body~, loc~) => {
      cg_push_scope(alloc)
      let mut chain0 = return_chain
      match init {
        None => ()
        Some(s) =>
          chain0 = gen_stmt(
            emitter,
            alloc,
            syms,
            pool,
            loops,
            cstrings,
            s,
            bag,
            chain0,
          )
      }
      let cond_pc = emitter_pc(emitter)
      let br_end = match cond {
        None => None
        Some(e) => {
          let cond_ty = type_of_expr(alloc.sem, e)
          if type_is_pointer_like(cond_ty) {
            gen_expr_ptr(emitter, alloc, syms, pool, cstrings, e, 0, bag)
            emit_cmp(emitter, true, 0, 31)
          } else {
            gen_expr_int32(emitter, alloc, syms, pool, cstrings, e, 0, bag)
            emit_cmp(emitter, false, 0, 31)
          }
          Some(emit_b_cond_placeholder(emitter, ARM64_COND_EQ))
        }
      }

      loops.push({ break_chain: 0, cont_chain: 0 })
      let chain1 = gen_stmt(
        emitter,
        alloc,
        syms,
        pool,
        loops,
        cstrings,
        body,
        bag,
        chain0,
      )
      let step_pc = emitter_pc(emitter)
      let loop_info = loops.pop().unwrap_or({ break_chain: 0, cont_chain: 0 })
      let continue_target = if step is Some(_) { step_pc } else { cond_pc }
      gsym_addr(emitter, loop_info.cont_chain, continue_target) catch {
        err => add_error(bag, loc, err.to_string())
      }
      match step {
        None => ()
        Some(e) => gen_expr_any(emitter, alloc, syms, pool, cstrings, e, 0, bag)
      }
      gjmp_addr(emitter, cond_pc) catch {
        err => add_error(bag, loc, err.to_string())
      }
      let end_pc = emitter_pc(emitter)
      match br_end {
        None => ()
        Some(at) =>
          patch_b_cond(emitter, at, end_pc, ARM64_COND_EQ) catch {
            err => add_error(bag, loc, err.to_string())
          }
      }
      gsym_addr(emitter, loop_info.break_chain, end_pc) catch {
        err => add_error(bag, loc, err.to_string())
      }
      cg_pop_scope(alloc)
      chain1
    }
    Stmt::Break(loc~) => {
      loop_append_break(loops, emitter, loc, bag)
      return_chain
    }
    Stmt::Continue(loc~) => {
      loop_append_continue(loops, emitter, loc, bag)
      return_chain
    }
    Stmt::ExprStmt(expr~, ..) => {
      gen_expr_any(emitter, alloc, syms, pool, cstrings, expr, 0, bag)
      return_chain
    }
    Stmt::Return(value~, loc~) => {
      match value {
        None => arm64_movimm(emitter, (0 : UInt), 0)
        Some(expr) => gen_expr_any(emitter, alloc, syms, pool, cstrings, expr, 0, bag)
      }
      gjmp(emitter, return_chain)
    }
    Stmt::Empty(..) => return_chain
    _ => {
      add_error(bag, stmt_loc(stmt), "codegen: unsupported statement")
      return_chain
    }
  }
}

///|
fn compute_frame_size(sem : SemContext, func : FuncDef) -> Int {
  let alloc = new_local_alloc(sem)
  cg_push_scope(alloc)
  for p in func.params {
    alloc_local(alloc, p.name, p.ty, p.loc) |> ignore
  }
  layout_stmt(alloc, func.body)
  align_up(alloc.used_bytes, 16)
}

///|
fn emit_prologue(emitter : Arm64Emitter, frame_size : Int) -> Unit {
  emit32(emitter, (0xa9bf7bfd : UInt))
  emit32(emitter, (0x910003fd : UInt))
  if frame_size > 0 {
    let off = (0 : UInt64) - frame_size.to_uint64()
    arm64_spoff(emitter, (31 : UInt), off)
  }
}

///|
fn emit_epilogue(emitter : Arm64Emitter, frame_size : Int) -> Unit {
  if frame_size > 0 {
    arm64_spoff(emitter, (31 : UInt), frame_size.to_uint64())
  }
  emit32(emitter, (0xa8c17bfd : UInt))
  emit32(emitter, (0xd65f03c0 : UInt))
}

///|
fn gen_func_def(
  emitter : Arm64Emitter,
  sem : SemContext,
  syms : SymTable,
  func_offsets : Map[String, Int],
  cstrings : Map[String, Sym],
  func : FuncDef,
  bag : DiagBag,
) -> Unit {
  let link = link_name(func.name)
  sym_for_name(syms, link) |> ignore
  let start = emitter_pc(emitter)
  func_offsets.set(link, start)

  let frame_size = compute_frame_size(sem, func)
  let alloc = new_local_alloc(sem)
  cg_push_scope(alloc)
  emit_prologue(emitter, frame_size)

  let pool = new_reg_pool()
  let mut arg_i = 0
  for p in func.params {
    match alloc_local(alloc, p.name, p.ty, p.loc) {
      None => ()
      Some(slot) =>
        if arg_i < 8 {
          emit_store_local_scalar(
            emitter,
            alloc.sem,
            slot.ty,
            arg_i,
            slot.offset,
            p.loc,
            bag,
          )
        } else {
          add_error(bag, p.loc, "codegen: only supports up to 8 params for now")
        }
    }
    arg_i = arg_i + 1
  }

  let loops : Array[LoopChains] = []
  let return_chain = gen_stmt(
    emitter,
    alloc,
    syms,
    pool,
    loops,
    cstrings,
    func.body,
    bag,
    0,
  )
  cg_pop_scope(alloc)

  gsym(emitter, return_chain) catch {
    err => add_error(bag, func.loc, err.to_string())
  }
  emit_epilogue(emitter, frame_size)
}

///|
fn cstring_record(
  order : Array[String],
  seen : Map[String, Bool],
  value : String,
) -> Unit {
  if !seen.contains(value) {
    seen.set(value, true)
    order.push(value)
  }
}

///|
fn collect_cstring_expr(order : Array[String], seen : Map[String, Bool], expr : Expr) -> Unit {
  match expr {
    Expr::StringLit(value~, ..) => cstring_record(order, seen, value)
    Expr::Unary(expr=inner, ..) => collect_cstring_expr(order, seen, inner)
    Expr::Cast(expr=inner, ..) => collect_cstring_expr(order, seen, inner)
    Expr::SizeofExpr(expr=inner, ..) => collect_cstring_expr(order, seen, inner)
    Expr::AlignofExpr(expr=inner, ..) => collect_cstring_expr(order, seen, inner)
    Expr::Binary(left~, right~, ..) => {
      collect_cstring_expr(order, seen, left)
      collect_cstring_expr(order, seen, right)
    }
    Expr::Conditional(cond~, then_expr~, else_expr~, ..) => {
      collect_cstring_expr(order, seen, cond)
      collect_cstring_expr(order, seen, then_expr)
      collect_cstring_expr(order, seen, else_expr)
    }
    Expr::Call(callee~, args~, ..) => {
      collect_cstring_expr(order, seen, callee)
      for a in args {
        collect_cstring_expr(order, seen, a)
      }
    }
    Expr::Index(base~, index~, ..) => {
      collect_cstring_expr(order, seen, base)
      collect_cstring_expr(order, seen, index)
    }
    Expr::Member(base~, ..) => collect_cstring_expr(order, seen, base)
    Expr::BuiltinVaArg(list~, ..) => collect_cstring_expr(order, seen, list)
    _ => ()
  }
}

///|
fn collect_cstring_initializer(
  order : Array[String],
  seen : Map[String, Bool],
  init : Initializer,
) -> Unit {
  match init {
    Initializer::Expr(expr~, ..) => collect_cstring_expr(order, seen, expr)
    Initializer::List(items~, ..) =>
      for item in items {
        collect_cstring_initializer(order, seen, item.value)
      }
  }
}

///|
fn collect_cstring_stmt(order : Array[String], seen : Map[String, Bool], stmt : Stmt) -> Unit {
  match stmt {
    Stmt::Compound(stmts~, ..) =>
      for s in stmts {
        collect_cstring_stmt(order, seen, s)
      }
    Stmt::If(cond~, then_branch~, else_branch~, ..) => {
      collect_cstring_expr(order, seen, cond)
      collect_cstring_stmt(order, seen, then_branch)
      match else_branch {
        None => ()
        Some(s) => collect_cstring_stmt(order, seen, s)
      }
    }
    Stmt::While(cond~, body~, ..) => {
      collect_cstring_expr(order, seen, cond)
      collect_cstring_stmt(order, seen, body)
    }
    Stmt::DoWhile(cond~, body~, ..) => {
      collect_cstring_stmt(order, seen, body)
      collect_cstring_expr(order, seen, cond)
    }
    Stmt::For(init~, cond~, step~, body~, ..) => {
      match init {
        None => ()
        Some(s) => collect_cstring_stmt(order, seen, s)
      }
      match cond {
        None => ()
        Some(e) => collect_cstring_expr(order, seen, e)
      }
      match step {
        None => ()
        Some(e) => collect_cstring_expr(order, seen, e)
      }
      collect_cstring_stmt(order, seen, body)
    }
    Stmt::Return(value~, ..) =>
      match value {
        None => ()
        Some(e) => collect_cstring_expr(order, seen, e)
      }
    Stmt::ExprStmt(expr~, ..) => collect_cstring_expr(order, seen, expr)
    Stmt::DeclStmt(decls~, ..) =>
      for d in decls {
        match d.init {
          None => ()
          Some(init) => collect_cstring_initializer(order, seen, init)
        }
      }
    Stmt::Switch(cond~, body~, ..) => {
      collect_cstring_expr(order, seen, cond)
      collect_cstring_stmt(order, seen, body)
    }
    Stmt::Case(expr~, end_expr~, body~, ..) => {
      collect_cstring_expr(order, seen, expr)
      match end_expr {
        None => ()
        Some(e) => collect_cstring_expr(order, seen, e)
      }
      collect_cstring_stmt(order, seen, body)
    }
    Stmt::Default(body~, ..) => collect_cstring_stmt(order, seen, body)
    Stmt::Label(body=body, ..) => collect_cstring_stmt(order, seen, body)
    Stmt::Asm(_) |
    Stmt::Goto(name=_, loc=_) |
    Stmt::Break(_) |
    Stmt::Continue(_) |
    Stmt::TagDef(ty=_, loc=_) |
    Stmt::StaticAssert(_) |
    Stmt::Empty(_) => ()
  }
}

///|
fn build_cstring_pool(
  syms : SymTable,
  order : Array[String],
) -> (Map[String, Sym], Map[String, Int], Section?) {
  if order.length() == 0 {
    return ({}, {}, None)
  }
  let cstring_syms : Map[String, Sym] = {}
  let cstring_offsets : Map[String, Int] = {}
  let buf = @buffer.new()
  let mut i = 0
  while i < order.length() {
    let value = order[i]
    let sym_name = "_L_.str.\{i}"
    let sym = sym_for_name(syms, sym_name)
    cstring_syms.set(value, sym)
    let off = buf.length()
    cstring_offsets.set(value, off)
    buf.write_bytes(@encoding/utf8.encode(value))
    buf.write_byte(0)
    while (buf.length() & 3) != 0 {
      buf.write_byte(0)
    }
    i = i + 1
  }
  let bytes = buf.to_bytes()
  let size_bytes = bytes.length()
  let words : Array[UInt] = []
  let mut pos = 0
  while pos + 3 < size_bytes {
    let b0 = bytes[pos].to_uint()
    let b1 = bytes[pos + 1].to_uint() << 8
    let b2 = bytes[pos + 2].to_uint() << 16
    let b3 = bytes[pos + 3].to_uint() << 24
    words.push(b0 | b1 | b2 | b3)
    pos = pos + 4
  }
  let sec : Section = {
    name: ".cstring",
    data: words,
    relocs: [],
    align: 1,
    size_bytes,
  }
  (cstring_syms, cstring_offsets, Some(sec))
}

///|
fn codegen_arm64_object_bytes_from_ast(
  unit : TranslationUnit,
  bag : DiagBag,
) -> Bytes? {
  let sem = new_sem_context(bag)
  for decl in unit.decls {
    match decl {
      Decl::Var(var_decl) => register_type_defs(sem, var_decl.ty, var_decl.loc)
      Decl::FuncDecl(func_decl) => {
        register_type_defs(sem, func_decl.return_type, func_decl.loc)
        for p in func_decl.params {
          register_type_defs(sem, p.ty, p.loc)
        }
      }
      Decl::FuncDef(func_def) => {
        register_type_defs(sem, func_def.return_type, func_def.loc)
        for p in func_def.params {
          register_type_defs(sem, p.ty, p.loc)
        }
      }
      Decl::Typedef(ty=ty, loc=loc, ..) => register_type_defs(sem, ty, loc)
      Decl::TagDef(ty~, loc~) => register_type_defs(sem, ty, loc)
      Decl::StaticAssert(_) | Decl::Asm(_) => ()
    }
  }

  // Populate sem symbol tables so type_of_expr can resolve identifiers during codegen.
  for decl in unit.decls {
    match decl {
      Decl::Var(var_decl) => {
        sem.globals.set(var_decl.name, var_decl.ty)
      }
      Decl::FuncDecl(func_decl) => {
        let params : Array[CType] = []
        for p in func_decl.params {
          params.push(p.ty)
        }
        sem.functions.set(func_decl.name, {
          return_type: func_decl.return_type,
          params,
          varargs: func_decl.varargs,
          is_old_style: func_decl.is_old_style,
          call_conv: normalize_call_conv(func_decl.attrs.call_conv),
        })
      }
      Decl::FuncDef(func_def) => {
        let params : Array[CType] = []
        for p in func_def.params {
          params.push(p.ty)
        }
        sem.functions.set(func_def.name, {
          return_type: func_def.return_type,
          params,
          varargs: func_def.varargs,
          is_old_style: func_def.is_old_style,
          call_conv: normalize_call_conv(func_def.attrs.call_conv),
        })
        sem.function_defs.set(func_def.name, true)
      }
      _ => ()
    }
  }

  let emitter = new_arm64_emitter()
  let syms = new_symtab()
  let func_offsets : Map[String, Int] = {}

  let cstring_order : Array[String] = []
  let cstring_seen : Map[String, Bool] = {}
  for decl in unit.decls {
    match decl {
      Decl::FuncDef(func) => collect_cstring_stmt(cstring_order, cstring_seen, func.body)
      Decl::Var(var_decl) =>
        match var_decl.init {
          None => ()
          Some(init) => collect_cstring_initializer(cstring_order, cstring_seen, init)
        }
      _ => ()
    }
  }
  let (cstring_syms, cstring_offsets, cstring_section) = build_cstring_pool(
    syms,
    cstring_order,
  )

  let mut main_found = false
  for decl in unit.decls {
    match decl {
      Decl::FuncDef(func) =>
        if func.name == "main" {
          main_found = true
        }
      _ => ()
    }
  }
  if main_found {
    sym_for_name(syms, link_name("main")) |> ignore
  }

  for decl in unit.decls {
    match decl {
      Decl::FuncDef(func) =>
        if func.name == "main" {
          gen_func_def(
            emitter,
            sem,
            syms,
            func_offsets,
            cstring_syms,
            func,
            bag,
          )
        }
      _ => ()
    }
  }
  for decl in unit.decls {
    match decl {
      Decl::FuncDef(func) =>
        if func.name != "main" {
          gen_func_def(
            emitter,
            sem,
            syms,
            func_offsets,
            cstring_syms,
            func,
            bag,
          )
        }
      _ => ()
    }
  }

  if !main_found {
    add_error(bag, dummy_loc(0), "codegen: missing function definition 'main'")
    return None
  }
  if has_errors(bag) {
    return None
  }

  let data_words : Array[UInt] = []
  let mut bss_size = 0
  let def_symbols : Map[String, ObjSymbol] = {}

  if cstring_order.length() > 0 {
    let mut i = 0
    while i < cstring_order.length() {
      let value = cstring_order[i]
      let name = "_L_.str.\{i}"
      let off = cstring_offsets.get(value).unwrap_or(0)
      def_symbols.set(name, {
        id: syms.name_to_id.get(name).unwrap_or(0),
        name,
        section: Some(".cstring"),
        value: off,
        is_external: true,
      })
      i = i + 1
    }
  }

  for decl in unit.decls {
    match decl {
      Decl::Var(var_decl) => {
        let link = link_name(var_decl.name)
        sym_for_name(syms, link) |> ignore
        if var_decl.storage == StorageClass::Extern {
          def_symbols.set(link, {
            id: syms.name_to_id.get(link).unwrap_or(0),
            name: link,
            section: None,
            value: 0,
            is_external: true,
          })
        } else if !type_is_supported_int32(var_decl.ty) {
          add_error(bag, var_decl.loc, "codegen: only int globals supported for now")
        } else {
          match var_decl.init {
            None => {
              let off = bss_size
              bss_size = bss_size + 4
              def_symbols.set(link, {
                id: syms.name_to_id.get(link).unwrap_or(0),
                name: link,
                section: Some(".bss"),
                value: off,
                is_external: var_decl.storage != StorageClass::Static,
              })
            }
            Some(init) =>
              match const_u32_from_initializer(init) {
                None =>
                  add_error(
                    bag,
                    var_decl.loc,
                    "codegen: only constant int initializer for globals supported for now",
                  )
                Some(word) => {
                  let off = data_words.length() << 2
                  data_words.push(word)
                  def_symbols.set(link, {
                    id: syms.name_to_id.get(link).unwrap_or(0),
                    name: link,
                    section: Some(".data"),
                    value: off,
                    is_external: var_decl.storage != StorageClass::Static,
                  })
                }
              }
          }
        }
      }
      _ => ()
    }
  }

  for decl in unit.decls {
    match decl {
      Decl::FuncDef(func) => {
        let link = link_name(func.name)
        def_symbols.set(link, {
          id: syms.name_to_id.get(link).unwrap_or(0),
          name: link,
          section: Some(".text"),
          value: func_offsets.get(link).unwrap_or(0),
          is_external: func.storage != StorageClass::Static,
        })
      }
      _ => ()
    }
  }

  let symbols : Array[ObjSymbol] = []
  let mut i = 0
  while i < syms.names.length() {
    let name = syms.names[i]
    let id = i + 1
    match def_symbols.get(name) {
      None =>
        symbols.push({
          id,
          name,
          section: None,
          value: 0,
          is_external: true,
        })
      Some(sym) =>
        symbols.push({
          id,
          name,
          section: sym.section,
          value: sym.value,
          is_external: sym.is_external,
        })
    }
    i = i + 1
  }

  let text = section_from_emitter(".text", emitter)
  let sections : Array[Section] = [text]
  match cstring_section {
    None => ()
    Some(sec) => sections.push(sec)
  }
  if data_words.length() > 0 {
    sections.push({
      name: ".data",
      data: data_words,
      relocs: [],
      align: 4,
      size_bytes: data_words.length() << 2,
    })
  }
  if bss_size > 0 {
    sections.push({
      name: ".bss",
      data: [],
      relocs: [],
      align: 4,
      size_bytes: bss_size,
    })
  }

  Some(encode_macho_object(sections, symbols))
}
