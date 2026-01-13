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
}

///|
fn cg_pop_scope(alloc : LocalAlloc) -> Unit {
  alloc.scopes.pop() |> ignore
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
fn gen_expr_int32(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
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
          if type_is_supported_int32(slot.ty) {
            emit_load_local_int32(emitter, dst, slot.offset)
          } else {
            add_error(
              bag,
              loc,
              "codegen: only int locals supported for now",
            )
          }
        None => {
          let sym = sym_for_name(syms, link_name(name))
          emit_load_global_int32(emitter, sym, dst)
        }
      }
    Expr::Unary(op~, expr=inner, loc~) => {
      match op {
        UnaryOp::Plus => gen_expr_int32(emitter, alloc, syms, pool, inner, dst, bag)
        UnaryOp::Minus => {
          gen_expr_int32(emitter, alloc, syms, pool, inner, dst, bag)
          emit32(
            emitter,
            (0x4b0003e0 : Int)
            .lor(dst)
            .lor(dst << 16)
            .reinterpret_as_uint(),
          )
        }
        UnaryOp::BitNot => {
          gen_expr_int32(emitter, alloc, syms, pool, inner, dst, bag)
          emit32(
            emitter,
            (0x2a2003e0 : Int)
            .lor(dst)
            .lor(dst << 16)
            .reinterpret_as_uint(),
          )
        }
        UnaryOp::Not => {
          gen_expr_int32(emitter, alloc, syms, pool, inner, dst, bag)
          emit_cmp(emitter, false, dst, 31)
          emit32(
            emitter,
            (0x1a9f17e0 : Int).lor(dst).reinterpret_as_uint(),
          )
        }
        _ => add_error(bag, loc, "codegen: unsupported unary operator")
      }
    }
    Expr::Binary(op~, left~, right~, loc~) =>
      match op {
        BinaryOp::Comma => {
          gen_expr_int32(emitter, alloc, syms, pool, left, dst, bag)
          gen_expr_int32(emitter, alloc, syms, pool, right, dst, bag)
        }
        BinaryOp::Assign =>
          match left {
            Expr::Ident(name~, ..) => {
              gen_expr_int32(emitter, alloc, syms, pool, right, dst, bag)
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
            _ => add_error(bag, loc, "codegen: assignment lhs must be an identifier for now")
          }
        BinaryOp::Add | BinaryOp::Sub | BinaryOp::Mul | BinaryOp::Div |
        BinaryOp::Mod | BinaryOp::BitAnd | BinaryOp::BitOr | BinaryOp::BitXor |
        BinaryOp::Eq | BinaryOp::Ne | BinaryOp::Lt | BinaryOp::Le | BinaryOp::Gt |
        BinaryOp::Ge | BinaryOp::Shl | BinaryOp::Shr => {
          let left_reg = dst
          gen_expr_int32(emitter, alloc, syms, pool, left, left_reg, bag)
          let tmp = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          emit_mov(emitter, false, tmp, left_reg)
          gen_expr_int32(emitter, alloc, syms, pool, right, dst, bag)
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
      let mut i = 0
      while i < args.length() {
        if i >= 8 {
          add_error(bag, loc, "codegen: only supports up to 8 int args for now")
          return
        }
        gen_expr_int32(emitter, alloc, syms, pool, args[i], i, bag)
        i = i + 1
      }
      let sym = sym_for_name(syms, link_name(name))
      emit_call(emitter, sym)
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
      gen_expr_int32(emitter, alloc, syms, pool, inner, dst, bag)
    Expr::Conditional(loc=cond_loc, ..) =>
      add_error(bag, cond_loc, "codegen: conditional operator not supported yet")
    _ =>
      add_error(bag, expr_loc(expr), "codegen: unsupported expression")
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
fn gen_stmt(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  stmt : Stmt,
  bag : DiagBag,
  return_chain : Int,
) -> Int {
  match stmt {
    Stmt::Compound(stmts~, ..) => {
      cg_push_scope(alloc)
      let mut chain = return_chain
      for s in stmts {
        chain = gen_stmt(emitter, alloc, syms, pool, s, bag, chain)
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
                    if type_is_supported_int32(slot.ty) {
                      gen_expr_int32(emitter, alloc, syms, pool, expr, 0, bag)
                      emit_store_local_int32(emitter, 0, slot.offset)
                    } else {
                      add_error(
                        bag,
                        d.loc,
                        "codegen: only int locals supported for now",
                      )
                    }
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
    Stmt::ExprStmt(expr~, ..) => {
      gen_expr_int32(emitter, alloc, syms, pool, expr, 0, bag)
      return_chain
    }
    Stmt::Return(value~, loc~) => {
      match value {
        None => arm64_movimm(emitter, (0 : UInt), 0)
        Some(expr) => gen_expr_int32(emitter, alloc, syms, pool, expr, 0, bag)
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
        if type_is_supported_int32(slot.ty) {
          if arg_i < 8 {
            emit_store_local_int32(emitter, arg_i, slot.offset)
          } else {
            add_error(bag, p.loc, "codegen: only supports up to 8 int params for now")
          }
        } else {
          add_error(bag, p.loc, "codegen: only int params supported for now")
        }
    }
    arg_i = arg_i + 1
  }

  let return_chain = gen_stmt(
    emitter,
    alloc,
    syms,
    pool,
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

  let emitter = new_arm64_emitter()
  let syms = new_symtab()
  let func_offsets : Map[String, Int] = {}

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
      Decl::FuncDef(func) => if func.name == "main" { gen_func_def(emitter, sem, syms, func_offsets, func, bag) }
      _ => ()
    }
  }
  for decl in unit.decls {
    match decl {
      Decl::FuncDef(func) => if func.name != "main" { gen_func_def(emitter, sem, syms, func_offsets, func, bag) }
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
