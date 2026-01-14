///|
struct RegPool {
  free : Array[Int]
}

///|
fn new_reg_pool() -> RegPool {
  // Use callee-saved registers for temporaries so nested calls don't clobber
  // intermediate values (AArch64 ABI: x19-x28 are preserved by callees).
  { free: [19, 20, 21, 22, 23, 24, 25, 26] }
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
  vla_size_offset : Int?
}

///|
struct LocalAlloc {
  sem : SemContext
  ret_ty : CType
  mut used_bytes : Int
  scopes : Array[Map[String, LocalSlot]]
  vla_scopes : Array[VlaScopeInfo]
}

///|
struct VlaScopeInfo {
  num : Int
  loc : Int
  locorig : Int
}

///|
fn new_local_alloc(sem : SemContext, ret_ty : CType) -> LocalAlloc {
  { sem, ret_ty, used_bytes: 0, scopes: [], vla_scopes: [] }
}

///|
fn cg_push_scope(alloc : LocalAlloc) -> Unit {
  alloc.scopes.push({})
  alloc.vla_scopes.push({ num: 0, loc: 0, locorig: 0 })
  push_scope(alloc.sem)
}

///|
fn cg_pop_scope(alloc : LocalAlloc) -> Unit {
  alloc.scopes.pop() |> ignore
  alloc.vla_scopes.pop() |> ignore
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
fn strip_float_literal_suffix(text : String) -> String {
  let len = text.length()
  if len == 0 {
    return text
  }
  let last = text[len - 1]
  if last == 102 || last == 70 || last == 108 || last == 76 {
    slice_string(text, 0, len - 1)
  } else {
    text
  }
}

///|
fn parse_float_literal_bits(text : String, kind : CFloatKind) -> UInt64? {
  if !float_kind_supported(kind) {
    return None
  }
  let trimmed = strip_float_literal_suffix(text)
  let parsed = try @strconv.parse_double(trimmed) catch {
    _ => None
  } noraise {
    v => Some(v)
  }
  match parsed {
    None => None
    Some(d) =>
      if kind == CFloatKind::Float {
        let f = Float::from_double(d)
        Some(f.reinterpret_as_uint().to_uint64())
      } else {
        Some(d.reinterpret_as_uint64())
      }
  }
}

///|
fn alloc_local(
  alloc : LocalAlloc,
  name : String,
  ty : CType,
  loc : SrcLoc,
) -> LocalSlot? {
  let (size, align) = match strip_qual_attrs(ty) {
    CType::Array(size=None, size_expr=Some(_), ..) => (8, 8)
    _ =>
      match type_size_align_or_error(alloc.sem, ty, loc) {
        None => return None
        Some(v) => v
      }
  }
  let aligned = align_up(alloc.used_bytes, align)
  alloc.used_bytes = aligned + size
  let offset = -(aligned + size)
  let slot = { offset, ty, vla_size_offset: None }
  let idx = alloc.scopes.length() - 1
  alloc.scopes[idx].set(name, slot)
  let sem_idx = alloc.sem.locals.length() - 1
  alloc.sem.locals[sem_idx].set(name, ty)
  Some(slot)
}

///|
fn alloc_hidden_slot(alloc : LocalAlloc, size : Int, align : Int) -> Int {
  let aligned = align_up(alloc.used_bytes, align)
  alloc.used_bytes = aligned + size
  -(aligned + size)
}

///|
fn emit_vla_sp_save(emitter : Arm64Emitter, slot_offset : Int) -> Unit {
  emit32(emitter, (0x910003e0 : Int).lor(30).reinterpret_as_uint())
  arm64_strx(
    emitter,
    3,
    (30 : UInt),
    (29 : UInt),
    slot_offset.to_int64().reinterpret_as_uint64(),
  )
}

///|
fn emit_vla_sp_restore(emitter : Arm64Emitter, slot_offset : Int) -> Unit {
  arm64_ldrx(
    emitter,
    false,
    3,
    (30 : UInt),
    (29 : UInt),
    slot_offset.to_int64().reinterpret_as_uint64(),
  )
  emit32(emitter, (0x9100001f : Int).lor(30 << 5).reinterpret_as_uint())
}

///|
fn vla_record_decl(alloc : LocalAlloc, vla_slot_offset : Int) -> Int? {
  let idx = alloc.vla_scopes.length() - 1
  let cur = alloc.vla_scopes[idx]
  let mut locorig = cur.locorig
  let mut needs_save : Int? = None
  if cur.num == 0 {
    if idx > 0 {
      let parent = alloc.vla_scopes[idx - 1]
      if parent.num > 0 {
        locorig = parent.loc
      } else {
        let off = alloc_hidden_slot(alloc, 8, 8)
        locorig = off
        needs_save = Some(off)
      }
    } else {
      let off = alloc_hidden_slot(alloc, 8, 8)
      locorig = off
      needs_save = Some(off)
    }
  }
  alloc.vla_scopes[idx] = { num: cur.num + 1, loc: vla_slot_offset, locorig }
  needs_save
}

///|
fn emit_vla_leave(emitter : Arm64Emitter, alloc : LocalAlloc, target_depth : Int) -> Unit {
  let mut restore_off = 0
  let mut i = alloc.vla_scopes.length()
  while i > target_depth {
    i = i - 1
    let scope = alloc.vla_scopes[i]
    if scope.num > 0 {
      restore_off = scope.locorig
    }
  }
  if restore_off != 0 {
    emit_vla_sp_restore(emitter, restore_off)
  }
}

///|
fn current_scope_vla_loc(alloc : LocalAlloc) -> Int? {
  if alloc.vla_scopes.length() == 0 {
    return None
  }
  let idx = alloc.vla_scopes.length() - 1
  let scope = alloc.vla_scopes[idx]
  if scope.num > 0 { Some(scope.loc) } else { None }
}

///|
fn cg_pop_scope_codegen(emitter : Arm64Emitter, alloc : LocalAlloc) -> Unit {
  let target_depth = alloc.scopes.length() - 1
  emit_vla_leave(emitter, alloc, target_depth)
  cg_pop_scope(alloc)
}

///|
fn gen_type_size_bytes_to_reg(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : Map[String, Sym],
  ty : CType,
  dst : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  match type_size_align(alloc.sem, ty, loc) {
    Some((size, _)) => {
      arm64_movimm(emitter, dst.reinterpret_as_uint(), size.to_uint64())
      return
    }
    None => ()
  }

  match strip_qual_attrs(ty) {
    CType::Array(elem=elem_ty, size=Some(n), ..) => {
      gen_type_size_bytes_to_reg(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        elem_ty,
        dst,
        loc,
        bag,
      )
      if n != 1 {
        let scale = take_reg(pool) catch {
          err => {
            add_error(bag, loc, err.to_string())
            return
          }
        }
        arm64_movimm(emitter, scale.reinterpret_as_uint(), n.to_uint64())
        emit32(
          emitter,
          (0x9b007c00 : Int)
          .lor(dst)
          .lor(dst << 5)
          .lor(scale << 16)
          .reinterpret_as_uint(),
        )
        give_reg(pool, scale)
      }
    }
    CType::Array(elem=elem_ty, size=None, size_expr=Some(len_expr)) => {
      gen_expr_int32(emitter, alloc, syms, pool, cstrings, len_expr, dst, bag)
      emit_sxtw(emitter, dst, dst)
      let tmp = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      gen_type_size_bytes_to_reg(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        elem_ty,
        tmp,
        loc,
        bag,
      )
      emit32(
        emitter,
        (0x9b007c00 : Int)
        .lor(dst)
        .lor(dst << 5)
        .lor(tmp << 16)
        .reinterpret_as_uint(),
      )
      give_reg(pool, tmp)
    }
    _ =>
      add_error(
        bag,
        loc,
        "codegen: unsupported dynamic sizeof for type",
      )
  }
}

///|
fn gen_vla_alloc_to_local_slot(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : Map[String, Sym],
  slot_offset : Int,
  size_slot_offset : Int?,
  array_ty : CType,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let bytes_reg = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      return
    }
  }
  gen_type_size_bytes_to_reg(
    emitter,
    alloc,
    syms,
    pool,
    cstrings,
    array_ty,
    bytes_reg,
    loc,
    bag,
  )

  match size_slot_offset {
    None => ()
    Some(off) =>
      arm64_strx(
        emitter,
        3,
        bytes_reg.reinterpret_as_uint(),
        (29 : UInt),
        off.to_int64().reinterpret_as_uint64(),
      )
  }

  // Round allocation up to 16 to preserve AArch64 stack alignment.
  emit32(
    emitter,
    (0x91000000 : Int)
    .lor(bytes_reg)
    .lor(bytes_reg << 5)
    .lor(15 << 10)
    .reinterpret_as_uint(),
  )
  emit32(
    emitter,
    (0x927cec00 : Int)
    .lor(bytes_reg)
    .lor(bytes_reg << 5)
    .reinterpret_as_uint(),
  )
  emit32(
    emitter,
    (0xcb2063ff : Int).lor(bytes_reg << 16).reinterpret_as_uint(),
  )

  // Store the resulting base pointer (sp) into the fixed local slot.
  emit32(emitter, (0x910003e0 : Int).lor(bytes_reg).reinterpret_as_uint())
  arm64_strx(
    emitter,
    3,
    bytes_reg.reinterpret_as_uint(),
    (29 : UInt),
    slot_offset.to_int64().reinterpret_as_uint64(),
  )
  give_reg(pool, bytes_reg)
}

///|
fn gen_vla_size_bytes_to_reg(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : Map[String, Sym],
  elem_ty : CType,
  size_expr : Expr,
  dst : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  gen_type_size_bytes_to_reg(
    emitter,
    alloc,
    syms,
    pool,
    cstrings,
    CType::Array(elem=elem_ty, size=None, size_expr=Some(size_expr)),
    dst,
    loc,
    bag,
  )
}

///|
fn infer_array_size_from_init_items(items : Array[InitItem]) -> Int {
  let mut next_index = 0
  let mut max_index = -1
  for item in items {
    let mut idx = next_index
    let mut has_index = false
    if item.designators.length() > 0 {
      match item.designators[0] {
        InitDesignator::Index(expr~, ..) =>
          match const_i64_from_expr(expr) {
            None => ()
            Some(v) => {
              idx = v.to_int()
              has_index = true
            }
          }
        _ => ()
      }
    }
    if idx >= 0 && idx > max_index {
      max_index = idx
    }
    if has_index {
      if idx >= 0 {
        next_index = idx + 1
      }
    } else {
      next_index = next_index + 1
    }
  }
  if max_index < 0 { 0 } else { max_index + 1 }
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
        let mut decl_ty = d.ty
        match strip_qual_attrs(d.ty) {
          CType::Array(elem=elem_ty, size=None, size_expr=None) =>
            match d.init {
              Some(Initializer::Expr(expr=Expr::StringLit(length~, ..), ..)) =>
                if is_char_type(elem_ty) {
                  decl_ty = apply_inferred_array_size(d.ty, length)
                }
              Some(Initializer::List(items~, ..)) => {
                let len = infer_array_size_from_init_items(items)
                decl_ty = apply_inferred_array_size(d.ty, len)
              }
              _ => ()
            }
          _ => ()
        }
        match alloc_local(alloc, d.name, decl_ty, d.loc) {
          None => ()
          Some(slot) =>
            match strip_qual_attrs(slot.ty) {
              CType::Array(size=None, size_expr=Some(_), ..) => {
                let size_off = alloc_hidden_slot(alloc, 8, 8)
                let updated = {
                  offset: slot.offset,
                  ty: slot.ty,
                  vla_size_offset: Some(size_off),
                }
                let scope_idx = alloc.scopes.length() - 1
                alloc.scopes[scope_idx].set(d.name, updated)
                vla_record_decl(alloc, slot.offset) |> ignore
              }
              _ => ()
            }
        }
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
fn emit_fmov_w_to_s(emitter : Arm64Emitter, sdst : Int, wsrc : Int) -> Unit {
  emit32(
    emitter,
    (0x1e270000 : Int)
    .lor(sdst)
    .lor(wsrc << 5)
    .reinterpret_as_uint(),
  )
}

///|
fn emit_fmov_s_to_w(emitter : Arm64Emitter, wdst : Int, ssrc : Int) -> Unit {
  emit32(
    emitter,
    (0x1e260000 : Int)
    .lor(wdst)
    .lor(ssrc << 5)
    .reinterpret_as_uint(),
  )
}

///|
fn emit_fmov_x_to_d(emitter : Arm64Emitter, ddst : Int, xsrc : Int) -> Unit {
  emit32(
    emitter,
    (0x9e670000 : Int)
    .lor(ddst)
    .lor(xsrc << 5)
    .reinterpret_as_uint(),
  )
}

///|
fn emit_fmov_d_to_x(emitter : Arm64Emitter, xdst : Int, dsrc : Int) -> Unit {
  emit32(
    emitter,
    (0x9e660000 : Int)
    .lor(xdst)
    .lor(dsrc << 5)
    .reinterpret_as_uint(),
  )
}

///|
fn emit_fp_binop(
  emitter : Arm64Emitter,
  base_s : Int,
  base_d : Int,
  is_double : Bool,
  dst : Int,
  lhs : Int,
  rhs : Int,
) -> Unit {
  let base = if is_double { base_d } else { base_s }
  emit32(
    emitter,
    (base : Int)
    .lor(dst)
    .lor(lhs << 5)
    .lor(rhs << 16)
    .reinterpret_as_uint(),
  )
}

///|
fn emit_fadd(emitter : Arm64Emitter, is_double : Bool, dst : Int, lhs : Int, rhs : Int) -> Unit {
  emit_fp_binop(emitter, 0x1e202800, 0x1e602800, is_double, dst, lhs, rhs)
}

///|
fn emit_fsub(emitter : Arm64Emitter, is_double : Bool, dst : Int, lhs : Int, rhs : Int) -> Unit {
  emit_fp_binop(emitter, 0x1e203800, 0x1e603800, is_double, dst, lhs, rhs)
}

///|
fn emit_fmul(emitter : Arm64Emitter, is_double : Bool, dst : Int, lhs : Int, rhs : Int) -> Unit {
  emit_fp_binop(emitter, 0x1e200800, 0x1e600800, is_double, dst, lhs, rhs)
}

///|
fn emit_fdiv(emitter : Arm64Emitter, is_double : Bool, dst : Int, lhs : Int, rhs : Int) -> Unit {
  emit_fp_binop(emitter, 0x1e201800, 0x1e601800, is_double, dst, lhs, rhs)
}

///|
fn emit_fneg(emitter : Arm64Emitter, is_double : Bool, dst : Int, src : Int) -> Unit {
  let base : Int = if is_double { 0x1e614000 } else { 0x1e214000 }
  emit32(emitter, base.lor(dst).lor(src << 5).reinterpret_as_uint())
}

///|
fn emit_fcmp(emitter : Arm64Emitter, is_double : Bool, lhs : Int, rhs : Int) -> Unit {
  let base : Int = if is_double { 0x1e602000 } else { 0x1e202000 }
  emit32(
    emitter,
    (base : Int)
    .lor(lhs << 5)
    .lor(rhs << 16)
    .reinterpret_as_uint(),
  )
}

///|
fn emit_fcmp_zero(emitter : Arm64Emitter, is_double : Bool, lhs : Int) -> Unit {
  let base : Int = if is_double { 0x1e602008 } else { 0x1e202008 }
  emit32(emitter, base.lor(lhs << 5).reinterpret_as_uint())
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
const ARM64_COND_LT : Int = 11

///|
const ARM64_COND_GT : Int = 12

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
fn emit_cset_from_fp_tok(emitter : Arm64Emitter, tok : Int, dst : Int) -> Unit raise {
  let base : Int = match tok {
    TOK_EQ => 0x1a9f17e0
    TOK_NE => 0x1a9f07e0
    // After FCMP on AArch64:
    //   LT => MI, LE => LS, GT/GE/EQ/NE use the same condition codes.
    TOK_LT => 0x1a9f57e0
    TOK_LE => 0x1a9f87e0
    TOK_GT => 0x1a9fd7e0
    TOK_GE => 0x1a9fb7e0
    _ => fail("codegen: unsupported fp comparison token")
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
fn float_kind_of_type(ty : CType) -> CFloatKind? {
  match strip_qual_attrs(ty) {
    CType::Float(kind~) => Some(kind)
    _ => None
  }
}

///|
fn gen_cond_expr_cmp_zero(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : Map[String, Sym],
  cond : Expr,
  bag : DiagBag,
) -> Unit {
  let cond_ty = type_of_expr(alloc.sem, cond)
  let tmp = take_reg(pool) catch {
    err => {
      add_error(bag, expr_loc(cond), err.to_string())
      return
    }
  }
  if type_is_pointer_like(cond_ty) {
    gen_expr_ptr(emitter, alloc, syms, pool, cstrings, cond, tmp, bag)
    emit_cmp(emitter, true, tmp, 31)
  } else {
    match float_kind_of_type(cond_ty) {
      Some(k) => {
        gen_expr_to_float_kind_bits(emitter, alloc, syms, pool, cstrings, cond, k, tmp, bag)
        if k == CFloatKind::Double {
          emit_fmov_x_to_d(emitter, 0, tmp)
          emit_fcmp_zero(emitter, true, 0)
        } else {
          emit_fmov_w_to_s(emitter, 0, tmp)
          emit_fcmp_zero(emitter, false, 0)
        }
      }
      None => {
        gen_expr_int32(emitter, alloc, syms, pool, cstrings, cond, tmp, bag)
        emit_cmp(emitter, false, tmp, 31)
      }
    }
  }
  give_reg(pool, tmp)
}

///|
fn float_kind_supported(kind : CFloatKind) -> Bool {
  kind == CFloatKind::Float || kind == CFloatKind::Double
}

///|
fn float_is_double(kind : CFloatKind) -> Bool {
  kind != CFloatKind::Float
}

///|
fn type_is_pointer_like(ty : CType) -> Bool {
  match strip_qual_attrs(ty) {
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
fn emit_zero_bytes(
  emitter : Arm64Emitter,
  base_reg : Int,
  base_off : Int,
  size_bytes : Int,
) -> Unit {
  let mut off = 0
  while off + 8 <= size_bytes {
    arm64_strx(
      emitter,
      3,
      (31 : UInt),
      base_reg.reinterpret_as_uint(),
      (base_off + off).to_int64().reinterpret_as_uint64(),
    )
    off = off + 8
  }
  if off + 4 <= size_bytes {
    arm64_strx(
      emitter,
      2,
      (31 : UInt),
      base_reg.reinterpret_as_uint(),
      (base_off + off).to_int64().reinterpret_as_uint64(),
    )
    off = off + 4
  }
  if off + 2 <= size_bytes {
    arm64_strx(
      emitter,
      1,
      (31 : UInt),
      base_reg.reinterpret_as_uint(),
      (base_off + off).to_int64().reinterpret_as_uint64(),
    )
    off = off + 2
  }
  while off < size_bytes {
    arm64_strx(
      emitter,
      0,
      (31 : UInt),
      base_reg.reinterpret_as_uint(),
      (base_off + off).to_int64().reinterpret_as_uint64(),
    )
    off = off + 1
  }
}

///|
fn emit_copy_bytes(
  emitter : Arm64Emitter,
  pool : RegPool,
  src_reg : Int,
  src_off : Int,
  dst_reg : Int,
  dst_off : Int,
  size_bytes : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let tmp = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      return
    }
  }
  let mut off = 0
  while off + 8 <= size_bytes {
    arm64_ldrx(
      emitter,
      false,
      3,
      tmp.reinterpret_as_uint(),
      src_reg.reinterpret_as_uint(),
      (src_off + off).to_int64().reinterpret_as_uint64(),
    )
    arm64_strx(
      emitter,
      3,
      tmp.reinterpret_as_uint(),
      dst_reg.reinterpret_as_uint(),
      (dst_off + off).to_int64().reinterpret_as_uint64(),
    )
    off = off + 8
  }
  if off + 4 <= size_bytes {
    arm64_ldrx(
      emitter,
      false,
      2,
      tmp.reinterpret_as_uint(),
      src_reg.reinterpret_as_uint(),
      (src_off + off).to_int64().reinterpret_as_uint64(),
    )
    arm64_strx(
      emitter,
      2,
      tmp.reinterpret_as_uint(),
      dst_reg.reinterpret_as_uint(),
      (dst_off + off).to_int64().reinterpret_as_uint64(),
    )
    off = off + 4
  }
  if off + 2 <= size_bytes {
    arm64_ldrx(
      emitter,
      false,
      1,
      tmp.reinterpret_as_uint(),
      src_reg.reinterpret_as_uint(),
      (src_off + off).to_int64().reinterpret_as_uint64(),
    )
    arm64_strx(
      emitter,
      1,
      tmp.reinterpret_as_uint(),
      dst_reg.reinterpret_as_uint(),
      (dst_off + off).to_int64().reinterpret_as_uint64(),
    )
    off = off + 2
  }
  while off < size_bytes {
    arm64_ldrx(
      emitter,
      false,
      0,
      tmp.reinterpret_as_uint(),
      src_reg.reinterpret_as_uint(),
      (src_off + off).to_int64().reinterpret_as_uint64(),
    )
    arm64_strx(
      emitter,
      0,
      tmp.reinterpret_as_uint(),
      dst_reg.reinterpret_as_uint(),
      (dst_off + off).to_int64().reinterpret_as_uint64(),
    )
    off = off + 1
  }
  give_reg(pool, tmp)
}

///|
fn emit_store_agg_return_gp_to_addr(
  emitter : Arm64Emitter,
  size : Int,
  base_reg : Int,
  base_off : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  if size <= 0 {
    return
  }
  if size <= 8 {
    let sz = match arm64_sz_from_size(size) {
      None => {
        add_error(bag, loc, "codegen: unsupported scalar size")
        return
      }
      Some(v) => v
    }
    arm64_strx(
      emitter,
      sz,
      (0 : UInt),
      base_reg.reinterpret_as_uint(),
      base_off.to_int64().reinterpret_as_uint64(),
    )
    return
  }
  if size <= 16 {
    arm64_strx(
      emitter,
      3,
      (0 : UInt),
      base_reg.reinterpret_as_uint(),
      base_off.to_int64().reinterpret_as_uint64(),
    )
    let rest = size - 8
    let sz1 = match arm64_sz_from_size(rest) {
      None => {
        add_error(bag, loc, "codegen: unsupported scalar size")
        return
      }
      Some(v) => v
    }
    arm64_strx(
      emitter,
      sz1,
      (1 : UInt),
      base_reg.reinterpret_as_uint(),
      (base_off + 8).to_int64().reinterpret_as_uint64(),
    )
    return
  }
  add_error(bag, loc, "codegen: aggregate return >16 bytes not supported yet")
}

///|
fn emit_store_scalar_at(
  emitter : Arm64Emitter,
  sem : SemContext,
  ty : CType,
  value_reg : Int,
  base_reg : Int,
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
  arm64_strx(
    emitter,
    sz,
    value_reg.reinterpret_as_uint(),
    base_reg.reinterpret_as_uint(),
    off.to_int64().reinterpret_as_uint64(),
  )
}

///|
fn resolve_init_designator_offset_type(
  sem : SemContext,
  ty : CType,
  designators : Array[InitDesignator],
  _loc : SrcLoc,
  bag : DiagBag,
) -> (CType, Int)? {
  let mut current = strip_qual_attrs(ty)
  let mut off = 0
  for des in designators {
    match des {
      InitDesignator::Index(expr~, loc=des_loc) =>
        match strip_qual_attrs(current) {
          CType::Array(elem~, size~, ..) => {
            let idx_i64 = const_i64_from_expr(expr)
            let idx = match idx_i64 {
              None => {
                add_error(bag, des_loc, "codegen: array designator must be constant")
                0
              }
              Some(v) => v.to_int()
            }
            match size {
              None => ()
              Some(n) =>
                if idx < 0 || idx >= n {
                  add_error(bag, des_loc, "codegen: array designator out of bounds")
                }
            }
            let (elem_size, _) = match type_size_align_or_error(sem, elem, des_loc) {
              None => return None
              Some(v) => v
            }
            off = off + (idx * elem_size)
            current = strip_qual_attrs(elem)
          }
          _ => {
            add_error(bag, des_loc, "codegen: array designator on non-array")
            return None
          }
        }
      InitDesignator::Field(name~, loc=des_loc) =>
        match strip_qual_attrs(current) {
          CType::Struct(name=tag, fields=field_list, attrs=_) => {
            let fields = match field_list {
              Some(list) => Some(record_items_to_fields(list))
              None => lookup_struct_fields(sem, tag, is_union=false)
            }
            match fields {
              None => {
                add_error(bag, des_loc, "codegen: incomplete struct '\{tag}'")
                return None
              }
              Some(list) =>
                match find_field(list, name) {
                  None => {
                    add_error(bag, des_loc, "codegen: unknown field '\{name}'")
                    return None
                  }
                  Some(field) => {
                    let field_off = match eval_builtin_offsetof(sem, current, [name], des_loc) {
                      None => 0
                      Some(v) => v
                    }
                    off = off + field_off
                    current = strip_qual_attrs(field.ty)
                  }
                }
            }
          }
          CType::Union(name=tag, fields=field_list, attrs=_) => {
            let fields = match field_list {
              Some(list) => Some(record_items_to_fields(list))
              None => lookup_struct_fields(sem, tag, is_union=true)
            }
            match fields {
              None => {
                add_error(bag, des_loc, "codegen: incomplete union '\{tag}'")
                return None
              }
              Some(list) =>
                match find_field(list, name) {
                  None => {
                    add_error(bag, des_loc, "codegen: unknown field '\{name}'")
                    return None
                  }
                  Some(field) => {
                    // Union fields always start at offset 0.
                    current = strip_qual_attrs(field.ty)
                  }
                }
            }
          }
          _ => {
            add_error(bag, des_loc, "codegen: field designator on non-record")
            return None
          }
        }
    }
  }
  Some((current, off))
}

///|
fn gen_string_init_to_addr(
  emitter : Arm64Emitter,
  pool : RegPool,
  cstrings : Map[String, Sym],
  value : String,
  length : Int,
  dst_reg : Int,
  dst_off : Int,
  bag : DiagBag,
  loc : SrcLoc,
) -> Unit {
  let sym = match cstrings.get(value) {
    None => {
      add_error(bag, loc, "codegen: missing string literal in cstring pool")
      return
    }
    Some(s) => s
  }
  let src_reg = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      return
    }
  }
  emit_addr_global(emitter, sym, src_reg)
  let mut i = 0
  while i < length {
    arm64_ldrx(
      emitter,
      false,
      0,
      (0 : UInt),
      src_reg.reinterpret_as_uint(),
      i.to_uint64(),
    )
    arm64_strx(
      emitter,
      0,
      (0 : UInt),
      dst_reg.reinterpret_as_uint(),
      (dst_off + i).to_int64().reinterpret_as_uint64(),
    )
    i = i + 1
  }
  give_reg(pool, src_reg)
}

///|
fn gen_initializer_to_addr(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : Map[String, Sym],
  base_reg : Int,
  base_off : Int,
  ty : CType,
  init : Initializer,
  bag : DiagBag,
) -> Unit {
  match init {
    Initializer::Expr(expr~, loc~) =>
      match strip_qual_attrs(ty) {
        CType::Array(elem~, size~, ..) =>
          match expr {
            Expr::StringLit(value=value, length=length, ..) =>
              if is_char_type(elem) {
                match size {
                  None =>
                    add_error(bag, loc, "codegen: incomplete array type")
                  Some(n) => {
                    let copy_len = if length > n { n } else { length }
                    gen_string_init_to_addr(
                      emitter,
                      pool,
                      cstrings,
                      value,
                      copy_len,
                      base_reg,
                      base_off,
                      bag,
                      loc,
                    )
                  }
                }
              } else {
                add_error(bag, loc, "codegen: string initializer for non-char array")
              }
            _ =>
              add_error(bag, loc, "codegen: scalar initializer for array not supported")
          }
        CType::Struct(..) | CType::Union(..) => {
          let (size, _) = match type_size_align_or_error(alloc.sem, ty, loc) {
            None => return
            Some(v) => v
          }
          if size <= 0 {
            return
          }
          match expr {
            Expr::Call(callee~, args~, ..) => {
              gen_call_expr(emitter, alloc, syms, pool, cstrings, callee, args, loc, bag)
              emit_store_agg_return_gp_to_addr(
                emitter,
                size,
                base_reg,
                base_off,
                loc,
                bag,
              )
            }
            _ => {
              let src = take_reg(pool) catch {
                err => {
                  add_error(bag, loc, err.to_string())
                  return
                }
              }
              gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, expr, src, bag)
              emit_copy_bytes(
                emitter,
                pool,
                src,
                0,
                base_reg,
                base_off,
                size,
                loc,
                bag,
              )
              give_reg(pool, src)
            }
          }
        }
        _ => {
          match float_kind_of_type(ty) {
            Some(k) =>
              gen_expr_to_float_kind_bits(
                emitter,
                alloc,
                syms,
                pool,
                cstrings,
                expr,
                k,
                0,
                bag,
              )
            None =>
              if type_is_pointer_like(ty) {
                gen_expr_ptr(emitter, alloc, syms, pool, cstrings, expr, 0, bag)
              } else {
                gen_expr_int32(emitter, alloc, syms, pool, cstrings, expr, 0, bag)
              }
          }
          emit_store_scalar_at(
            emitter,
            alloc.sem,
            ty,
            0,
            base_reg,
            base_off,
            loc,
            bag,
          )
        }
      }
    Initializer::List(items~, loc~) =>
      match strip_qual_attrs(ty) {
        CType::Array(elem=elem_ty, size=size_opt, ..) => {
          let n = match size_opt {
            None => {
              add_error(bag, loc, "codegen: incomplete array type")
              return
            }
            Some(v) => v
          }
          let (elem_size, _) = match type_size_align_or_error(alloc.sem, elem_ty, loc) {
            None => return
            Some(v) => v
          }
          let mut next_index = 0
          for item in items {
            let mut idx = next_index
            let mut has_index = false
            if item.designators.length() > 0 {
              match item.designators[0] {
                InitDesignator::Index(expr~, loc=des_loc) =>
                  match const_i64_from_expr(expr) {
                    None => ()
                    Some(v) => {
                      idx = v.to_int()
                      has_index = true
                      if idx < 0 || idx >= n {
                        add_error(bag, des_loc, "codegen: array designator out of bounds")
                      }
                    }
                  }
                _ => ()
              }
            }
            if !has_index {
              if idx >= n {
                add_error(bag, item.loc, "codegen: too many initializers for array")
                break
              }
            }
            let (target_ty, rel_off) = if item.designators.length() > 0 {
              match resolve_init_designator_offset_type(
                alloc.sem,
                ty,
                item.designators,
                item.loc,
                bag,
              ) {
                None => (elem_ty, idx * elem_size)
                Some((t, o)) => (t, o)
              }
            } else {
              (elem_ty, idx * elem_size)
            }
            gen_initializer_to_addr(
              emitter,
              alloc,
              syms,
              pool,
              cstrings,
              base_reg,
              base_off + rel_off,
              target_ty,
              item.value,
              bag,
            )
            if has_index {
              if idx >= 0 {
                next_index = idx + 1
              }
            } else {
              next_index = next_index + 1
            }
          }
        }
        CType::Struct(name=tag, fields=field_list, attrs=_) => {
          let fields = match field_list {
            Some(list) => Some(record_items_to_fields(list))
            None => lookup_struct_fields(alloc.sem, tag, is_union=false)
          }
          let list = match fields {
            None => {
              add_error(bag, loc, "codegen: incomplete struct '\{tag}'")
              return
            }
            Some(v) => v
          }
          let mut index = 0
          for item in items {
            if item.designators.length() > 0 {
              match item.designators[0] {
                InitDesignator::Field(name~, ..) =>
                  match find_field_index(list, name) {
                    None => ()
                    Some(idx) => index = idx + 1
                  }
                _ => ()
              }
              match resolve_init_designator_offset_type(
                alloc.sem,
                ty,
                item.designators,
                item.loc,
                bag,
              ) {
                None => ()
                Some((target_ty, rel_off)) =>
                  gen_initializer_to_addr(
                    emitter,
                    alloc,
                    syms,
                    pool,
                    cstrings,
                    base_reg,
                    base_off + rel_off,
                    target_ty,
                    item.value,
                    bag,
                  )
              }
            } else {
              match next_init_field(list, index) {
                None => add_error(bag, item.loc, "codegen: too many initializers for aggregate")
                Some((field, next_idx)) => {
                  let field_off = match eval_builtin_offsetof(alloc.sem, ty, [field.name], item.loc) {
                    None => 0
                    Some(v) => v
                  }
                  gen_initializer_to_addr(
                    emitter,
                    alloc,
                    syms,
                    pool,
                    cstrings,
                    base_reg,
                    base_off + field_off,
                    field.ty,
                    item.value,
                    bag,
                  )
                  index = next_idx
                }
              }
            }
          }
        }
        CType::Union(name=tag, fields=field_list, attrs=_) => {
          let fields = match field_list {
            Some(list) => Some(record_items_to_fields(list))
            None => lookup_struct_fields(alloc.sem, tag, is_union=true)
          }
          let list = match fields {
            None => {
              add_error(bag, loc, "codegen: incomplete union '\{tag}'")
              return
            }
            Some(v) => v
          }
          if items.length() == 0 {
            return
          }
          let first = items[0]
          if first.designators.length() > 0 {
            match resolve_init_designator_offset_type(
              alloc.sem,
              ty,
              first.designators,
              first.loc,
              bag,
            ) {
              None => ()
              Some((target_ty, rel_off)) =>
                gen_initializer_to_addr(
                  emitter,
                  alloc,
                  syms,
                  pool,
                  cstrings,
                  base_reg,
                  base_off + rel_off,
                  target_ty,
                  first.value,
                  bag,
                )
            }
          } else if list.length() > 0 {
            let field = list[0]
            gen_initializer_to_addr(
              emitter,
              alloc,
              syms,
              pool,
              cstrings,
              base_reg,
              base_off,
              field.ty,
              first.value,
              bag,
            )
          }
        }
        _ => add_error(bag, loc, "codegen: initializer list for non-aggregate")
      }
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
    Some(id) => Sym::{ id }
    None => {
      let id = tab.names.length() + 1
      tab.names.push(name)
      tab.name_to_id.set(name, id)
      Sym::{ id }
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
  arm64_ldrx(emitter, false, 2, dst.reinterpret_as_uint(), (29 : UInt), off_u64)
}

///|
fn emit_store_local_int32(
  emitter : Arm64Emitter,
  src : Int,
  off : Int,
) -> Unit {
  let off_u64 = off.to_int64().reinterpret_as_uint64()
  arm64_strx(emitter, 2, src.reinterpret_as_uint(), (29 : UInt), off_u64)
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
  arm64_ldrx(emitter, signed, sz, dst.reinterpret_as_uint(), (29 : UInt), off_u64)
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
  arm64_strx(emitter, sz, src.reinterpret_as_uint(), (29 : UInt), off_u64)
}

///|
fn emit_addr_local(
  emitter : Arm64Emitter,
  dst : Int,
  off : Int,
  _loc : SrcLoc,
  _bag : DiagBag,
) -> Unit {
  let imm = if off < 0 { -off } else { off }
  if imm <= 0xfff {
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
    return
  }

  arm64_movimm(emitter, dst.reinterpret_as_uint(), imm.to_uint64())
  let base = if off < 0 { 0xcb000000 } else { 0x8b000000 }
  emit32(
    emitter,
    (base : Int)
    .lor(dst)
    .lor(29 << 5)
    .lor(dst << 16)
    .reinterpret_as_uint(),
  )
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
  let sig = alloc.sem.functions.get(name)
  let (fixed_count, is_varargs) = match sig {
    None => (0, false)
    Some(s) => (s.params.length(), s.varargs)
  }
  let is_varargs_call = is_varargs && args.length() > fixed_count

  if is_varargs_call {
    if fixed_count > 8 {
      add_error(bag, loc, "codegen: too many fixed args for varargs call")
      return
    }

    let vararg_count = args.length() - fixed_count
    let raw_bytes = vararg_count * 8
    let stack_bytes = align_up(raw_bytes, 16)
    if stack_bytes > 0 {
      let off = (0 : UInt64) - stack_bytes.to_uint64()
      arm64_spoff(emitter, (31 : UInt), off)
    }

    let mut j = 0
    while j < vararg_count {
      let arg = args[fixed_count + j]
      let aty = type_of_expr(alloc.sem, arg)
      match float_kind_of_type(aty) {
        Some(_) =>
          gen_expr_to_float_kind_bits(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            arg,
            CFloatKind::Double,
            8,
            bag,
          )
        None =>
          if type_is_pointer_like(aty) {
            gen_expr_ptr(emitter, alloc, syms, pool, cstrings, arg, 8, bag)
          } else {
            gen_expr_int32(emitter, alloc, syms, pool, cstrings, arg, 8, bag)
            match strip_qualifiers(aty) {
              CType::Int(kind~, unsigned~) =>
                if int_size(kind) < 8 && !unsigned {
                  emit_sxtw(emitter, 8, 8)
                }
              _ => ()
            }
          }
      }
      arm64_strx(
        emitter,
        3,
        (8 : UInt),
        (31 : UInt),
        (j * 8).to_uint64(),
      )
      j = j + 1
    }

    let mut gp = 0
    let mut fp = 0
    let mut i = 0
    while i < fixed_count && i < args.length() {
      let arg = args[i]
      let param_ty = match sig {
        None => type_of_expr(alloc.sem, arg)
        Some(s) => s.params[i]
      }
      match float_kind_of_type(param_ty) {
        Some(k) => {
          if fp >= 8 {
            add_error(bag, loc, "codegen: only supports up to 8 float args for now")
            return
          }
          let tmp = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          gen_expr_to_float_kind_bits(emitter, alloc, syms, pool, cstrings, arg, k, tmp, bag)
          if k == CFloatKind::Double {
            emit_fmov_x_to_d(emitter, fp, tmp)
          } else {
            emit_fmov_w_to_s(emitter, fp, tmp)
          }
          give_reg(pool, tmp)
          fp = fp + 1
        }
        None => {
          if gp >= 8 {
            add_error(bag, loc, "codegen: only supports up to 8 args for now")
            return
          }
          match strip_qual_attrs(param_ty) {
            CType::Struct(..) | CType::Union(..) =>
              match type_size_align_or_error(alloc.sem, param_ty, loc) {
                None => ()
                Some((size, _)) => {
                  let addr = take_reg(pool) catch {
                    err => {
                      add_error(bag, loc, err.to_string())
                      return
                    }
                  }
                  gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, arg, addr, bag)
                  if size <= 8 {
                    match arm64_sz_from_size(size) {
                      None => add_error(bag, loc, "codegen: unsupported scalar size")
                      Some(v) =>
                        arm64_ldrx(
                          emitter,
                          false,
                          v,
                          gp.reinterpret_as_uint(),
                          addr.reinterpret_as_uint(),
                          0,
                        )
                    }
                  } else if size <= 16 {
                    if gp + 1 >= 8 {
                      add_error(bag, loc, "codegen: only supports up to 8 args for now")
                      give_reg(pool, addr)
                      return
                    }
                    arm64_ldrx(
                      emitter,
                      false,
                      3,
                      gp.reinterpret_as_uint(),
                      addr.reinterpret_as_uint(),
                      0,
                    )
                    let rest = size - 8
                    match arm64_sz_from_size(rest) {
                      None => add_error(bag, loc, "codegen: unsupported scalar size")
                      Some(v) =>
                        arm64_ldrx(
                          emitter,
                          false,
                          v,
                          (gp + 1).reinterpret_as_uint(),
                          addr.reinterpret_as_uint(),
                          8,
                        )
                    }
                    gp = gp + 1
                  } else {
                    add_error(bag, loc, "codegen: struct args >16 bytes not supported yet")
                  }
                  give_reg(pool, addr)
                  gp = gp + 1
                }
              }
            _ =>
              if type_is_pointer_like(param_ty) {
                gen_expr_ptr(emitter, alloc, syms, pool, cstrings, arg, gp, bag)
                gp = gp + 1
              } else {
                gen_expr_int32(emitter, alloc, syms, pool, cstrings, arg, gp, bag)
                gp = gp + 1
              }
          }
        }
      }
      i = i + 1
    }

    let sym = sym_for_name(syms, link_name(name))
    emit_call(emitter, sym)

    if stack_bytes > 0 {
      arm64_spoff(emitter, (31 : UInt), stack_bytes.to_uint64())
    }
    return
  }

  let mut gp = 0
  let mut fp = 0
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    let param_ty = match sig {
      None => type_of_expr(alloc.sem, arg)
      Some(s) =>
        if i < s.params.length() {
          s.params[i]
        } else {
          type_of_expr(alloc.sem, arg)
        }
    }
    match float_kind_of_type(param_ty) {
      Some(k) => {
        if fp >= 8 {
          add_error(bag, loc, "codegen: only supports up to 8 float args for now")
          return
        }
        let tmp = take_reg(pool) catch {
          err => {
            add_error(bag, loc, err.to_string())
            return
          }
        }
        gen_expr_to_float_kind_bits(emitter, alloc, syms, pool, cstrings, arg, k, tmp, bag)
        if k == CFloatKind::Double {
          emit_fmov_x_to_d(emitter, fp, tmp)
        } else {
          emit_fmov_w_to_s(emitter, fp, tmp)
        }
        give_reg(pool, tmp)
        fp = fp + 1
      }
      None => {
        if gp >= 8 {
          add_error(bag, loc, "codegen: only supports up to 8 args for now")
          return
        }
        match strip_qual_attrs(param_ty) {
          CType::Struct(..) | CType::Union(..) =>
            match type_size_align_or_error(alloc.sem, param_ty, loc) {
              None => ()
              Some((size, _)) => {
                let addr = take_reg(pool) catch {
                  err => {
                    add_error(bag, loc, err.to_string())
                    return
                  }
                }
                gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, arg, addr, bag)
                if size <= 8 {
                  match arm64_sz_from_size(size) {
                    None => add_error(bag, loc, "codegen: unsupported scalar size")
                    Some(v) =>
                      arm64_ldrx(
                        emitter,
                        false,
                        v,
                        gp.reinterpret_as_uint(),
                        addr.reinterpret_as_uint(),
                        0,
                      )
                  }
                } else if size <= 16 {
                  if gp + 1 >= 8 {
                    add_error(bag, loc, "codegen: only supports up to 8 args for now")
                    give_reg(pool, addr)
                    return
                  }
                  arm64_ldrx(
                    emitter,
                    false,
                    3,
                    gp.reinterpret_as_uint(),
                    addr.reinterpret_as_uint(),
                    0,
                  )
                  let rest = size - 8
                  match arm64_sz_from_size(rest) {
                    None => add_error(bag, loc, "codegen: unsupported scalar size")
                    Some(v) =>
                      arm64_ldrx(
                        emitter,
                        false,
                        v,
                        (gp + 1).reinterpret_as_uint(),
                        addr.reinterpret_as_uint(),
                        8,
                      )
                  }
                  gp = gp + 1
                } else {
                  add_error(bag, loc, "codegen: struct args >16 bytes not supported yet")
                }
                give_reg(pool, addr)
                gp = gp + 1
              }
            }
          _ =>
            if type_is_pointer_like(param_ty) {
              gen_expr_ptr(emitter, alloc, syms, pool, cstrings, arg, gp, bag)
              gp = gp + 1
            } else {
              gen_expr_int32(emitter, alloc, syms, pool, cstrings, arg, gp, bag)
              gp = gp + 1
            }
        }
      }
    }
    i = i + 1
  }
  let sym = sym_for_name(syms, link_name(name))
  emit_call(emitter, sym)
}

///|
fn emit_blr(emitter : Arm64Emitter, reg : Int) -> Unit {
  emit32(
    emitter,
    (0xd63f0000 : Int)
    .lor(reg << 5)
    .reinterpret_as_uint(),
  )
}

///|
fn gen_call_expr(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : Map[String, Sym],
  callee : Expr,
  args : Array[Expr],
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  if callee is Expr::Ident(name~, ..) {
    if lookup_local(alloc, name) is None && alloc.sem.functions.contains(name) {
      gen_call_direct(emitter, alloc, syms, pool, cstrings, name, args, loc, bag)
      let call_ty = type_of_expr(alloc.sem, Expr::Call(callee~, args~, loc~))
      match float_kind_of_type(call_ty) {
        Some(k) =>
          if k == CFloatKind::Double {
            emit_fmov_d_to_x(emitter, 0, 0)
          } else {
            emit_fmov_s_to_w(emitter, 0, 0)
          }
        None => ()
      }
      return
    }
  }

  // Indirect call via function pointer expression.
  let fn_reg = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      return
    }
  }
  gen_expr_ptr(emitter, alloc, syms, pool, cstrings, callee, fn_reg, bag)
  let mut i = 0
  while i < args.length() {
    if i >= 8 {
      add_error(bag, loc, "codegen: only supports up to 8 args for now")
      give_reg(pool, fn_reg)
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
  emit_blr(emitter, fn_reg)
  give_reg(pool, fn_reg)

  let call_ty = type_of_expr(alloc.sem, Expr::Call(callee~, args~, loc~))
  match float_kind_of_type(call_ty) {
    Some(k) =>
      if k == CFloatKind::Double {
        emit_fmov_d_to_x(emitter, 0, 0)
      } else {
        emit_fmov_s_to_w(emitter, 0, 0)
      }
    None => ()
  }
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
        Some(slot) =>
          match strip_qual_attrs(slot.ty) {
            CType::Array(size=None, size_expr=Some(_), ..) =>
              arm64_ldrx(
                emitter,
                false,
                3,
                dst.reinterpret_as_uint(),
                (29 : UInt),
                slot.offset.to_int64().reinterpret_as_uint64(),
              )
            _ => emit_addr_local(emitter, dst, slot.offset, loc, bag)
          }
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
        arm64_movimm(emitter, scale.reinterpret_as_uint(), elem_size.to_uint64())
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
    Expr::Member(base~, name~, is_arrow~, loc~) => {
      if is_arrow {
        gen_expr_ptr(emitter, alloc, syms, pool, cstrings, base, dst, bag)
      } else {
        gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, base, dst, bag)
      }

      let base_ty = type_of_expr(alloc.sem, base)
      let record_ty = if is_arrow {
        match strip_qual_attrs(base_ty) {
          CType::Pointer(pointee) => pointee
          _ => base_ty
        }
      } else {
        base_ty
      }
      let off = match eval_builtin_offsetof(alloc.sem, record_ty, [name], loc) {
        None => 0
        Some(v) => v
      }
      if off != 0 {
        if off >= 0 && off <= 0xfff {
          emit32(
            emitter,
            (0x91000000 : Int)
            .lor(dst)
            .lor(dst << 5)
            .lor(off << 10)
            .reinterpret_as_uint(),
          )
        } else {
          let tmp = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          let imm = if off < 0 { -off } else { off }
          arm64_movimm(emitter, tmp.reinterpret_as_uint(), imm.to_uint64())
          let base = if off < 0 { 0xcb000000 } else { 0x8b000000 }
          emit32(
            emitter,
            (base : Int)
            .lor(dst)
            .lor(dst << 5)
            .lor(tmp << 16)
            .reinterpret_as_uint(),
          )
          give_reg(pool, tmp)
        }
      }
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
          arm64_strx(
            emitter,
            sz,
            value_reg.reinterpret_as_uint(),
            addr_reg.reinterpret_as_uint(),
            0,
          )
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
      arm64_strx(
        emitter,
        sz,
        value_reg.reinterpret_as_uint(),
        addr.reinterpret_as_uint(),
        0,
      )
      give_reg(pool, addr)
    }
  }
}

///|
fn gen_expr_to_float_kind_bits(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : Map[String, Sym],
  expr : Expr,
  target_kind : CFloatKind,
  dst : Int,
  bag : DiagBag,
) -> Unit {
  if !float_kind_supported(target_kind) {
    add_error(bag, expr_loc(expr), "codegen: unsupported float type")
    return
  }
  let src_ty = type_of_expr(alloc.sem, expr)
  match float_kind_of_type(src_ty) {
    Some(src_kind) => {
      gen_expr_floatbits(emitter, alloc, syms, pool, cstrings, expr, dst, bag)
      if src_kind == target_kind {
        return
      }
      if src_kind == CFloatKind::Float && target_kind == CFloatKind::Double {
        // float -> double
        emit_fmov_w_to_s(emitter, 0, dst)
        emit32(emitter, (0x1e22c000 : UInt))
        emit_fmov_d_to_x(emitter, dst, 0)
      } else if src_kind == CFloatKind::Double && target_kind == CFloatKind::Float {
        // double -> float
        emit_fmov_x_to_d(emitter, 0, dst)
        emit32(emitter, (0x1e624000 : UInt))
        emit_fmov_s_to_w(emitter, dst, 0)
      } else {
        add_error(bag, expr_loc(expr), "codegen: unsupported float conversion")
      }
    }
    None => {
      // int -> float/double
      gen_expr_int32(emitter, alloc, syms, pool, cstrings, expr, dst, bag)
      let is_unsigned = match strip_qualifiers(src_ty) {
        CType::Int(unsigned~, ..) => unsigned
        _ => false
      }
      if target_kind == CFloatKind::Float {
        let base : Int = if is_unsigned { 0x1e230000 } else { 0x1e220000 }
        emit32(
          emitter,
          base
          .lor(0)
          .lor(dst << 5)
          .reinterpret_as_uint(),
        )
        emit_fmov_s_to_w(emitter, dst, 0)
      } else {
        let base : Int = if is_unsigned { 0x1e630000 } else { 0x1e620000 }
        emit32(
          emitter,
          base
          .lor(0)
          .lor(dst << 5)
          .reinterpret_as_uint(),
        )
        emit_fmov_d_to_x(emitter, dst, 0)
      }
    }
  }
}

///|
fn gen_expr_floatbits(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : Map[String, Sym],
  expr : Expr,
  dst : Int,
  bag : DiagBag,
) -> Unit {
  let kind = match float_kind_of_type(type_of_expr(alloc.sem, expr)) {
    None => {
      add_error(bag, expr_loc(expr), "codegen: expected float expression")
      return
    }
    Some(k) => k
  }
  if !float_kind_supported(kind) {
    add_error(bag, expr_loc(expr), "codegen: unsupported float type")
    return
  }
  let is_double = float_is_double(kind)
  match expr {
    Expr::FloatLit(value~, loc~) =>
      match parse_float_literal_bits(value, kind) {
        None => add_error(bag, loc, "codegen: invalid float literal")
        Some(bits) => arm64_movimm(emitter, dst.reinterpret_as_uint(), bits)
      }
    Expr::Ident(name~, loc~) =>
      match lookup_local(alloc, name) {
        Some(slot) =>
          emit_load_local_scalar(emitter, alloc.sem, slot.ty, dst, slot.offset, loc, bag)
        None => {
          let sym = sym_for_name(syms, link_name(name))
          let addr_reg : Int = 16
          emit_addr_global(emitter, sym, addr_reg)
          let size = if is_double { 8 } else { 4 }
          let sz = match arm64_sz_from_size(size) {
            None => {
              add_error(bag, loc, "codegen: unsupported float size")
              return
            }
            Some(v) => v
          }
          arm64_ldrx(
            emitter,
            false,
            sz,
            dst.reinterpret_as_uint(),
            addr_reg.reinterpret_as_uint(),
            0,
          )
        }
      }
    Expr::Index(base=_, index=_, loc~) | Expr::Member(loc=loc, ..) | Expr::Unary(op=UnaryOp::Deref, loc=loc, ..) => {
      let addr = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, expr, addr, bag)
      let size = if is_double { 8 } else { 4 }
      let sz = match arm64_sz_from_size(size) {
        None => {
          add_error(bag, loc, "codegen: unsupported float size")
          give_reg(pool, addr)
          return
        }
        Some(v) => v
      }
       arm64_ldrx(
         emitter,
         false,
         sz,
         dst.reinterpret_as_uint(),
         addr.reinterpret_as_uint(),
         0,
       )
      give_reg(pool, addr)
    }
    Expr::Unary(op=UnaryOp::Plus, expr=inner, ..) =>
      gen_expr_to_float_kind_bits(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        inner,
        kind,
        dst,
        bag,
      )
    Expr::Unary(op=UnaryOp::Minus, expr=inner, loc=_) => {
      gen_expr_to_float_kind_bits(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        inner,
        kind,
        dst,
        bag,
      )
      if is_double {
        emit_fmov_x_to_d(emitter, 0, dst)
        emit_fneg(emitter, true, 0, 0)
        emit_fmov_d_to_x(emitter, dst, 0)
      } else {
        emit_fmov_w_to_s(emitter, 0, dst)
        emit_fneg(emitter, false, 0, 0)
        emit_fmov_s_to_w(emitter, dst, 0)
      }
    }
    Expr::Binary(op=BinaryOp::Comma, left~, right~, ..) => {
      gen_expr_any(emitter, alloc, syms, pool, cstrings, left, 0, bag)
      gen_expr_to_float_kind_bits(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        right,
        kind,
        dst,
        bag,
      )
    }
    Expr::Binary(op=BinaryOp::Assign, left~, right~, ..) => {
      let lhs_ty = type_of_expr(alloc.sem, left)
      let lhs_kind = float_kind_of_type(lhs_ty).unwrap_or(kind)
      gen_expr_to_float_kind_bits(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        right,
        lhs_kind,
        dst,
        bag,
      )
      store_lvalue_scalar(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        left,
        dst,
        lhs_ty,
        bag,
      )
      if lhs_kind != kind {
        gen_expr_to_float_kind_bits(
          emitter,
          alloc,
          syms,
          pool,
          cstrings,
          right,
          kind,
          dst,
          bag,
        )
      }
    }
    Expr::Binary(op~, left~, right~, loc~) =>
      match op {
        BinaryOp::Add | BinaryOp::Sub | BinaryOp::Mul | BinaryOp::Div => {
          let tmp = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          gen_expr_to_float_kind_bits(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            left,
            kind,
            tmp,
            bag,
          )
          gen_expr_to_float_kind_bits(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            right,
            kind,
            dst,
            bag,
          )
          if is_double {
            emit_fmov_x_to_d(emitter, 0, tmp)
            emit_fmov_x_to_d(emitter, 1, dst)
          } else {
            emit_fmov_w_to_s(emitter, 0, tmp)
            emit_fmov_w_to_s(emitter, 1, dst)
          }
          match op {
            BinaryOp::Add => emit_fadd(emitter, is_double, 0, 0, 1)
            BinaryOp::Sub => emit_fsub(emitter, is_double, 0, 0, 1)
            BinaryOp::Mul => emit_fmul(emitter, is_double, 0, 0, 1)
            BinaryOp::Div => emit_fdiv(emitter, is_double, 0, 0, 1)
            _ => ()
          }
          if is_double {
            emit_fmov_d_to_x(emitter, dst, 0)
          } else {
            emit_fmov_s_to_w(emitter, dst, 0)
          }
          give_reg(pool, tmp)
        }
        BinaryOp::AddAssign | BinaryOp::SubAssign | BinaryOp::MulAssign | BinaryOp::DivAssign => {
          let addr = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, left, addr, bag)
          let old = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              give_reg(pool, addr)
              return
            }
          }
          let size = if is_double { 8 } else { 4 }
          let sz = match arm64_sz_from_size(size) {
            None => {
              add_error(bag, loc, "codegen: unsupported float size")
              give_reg(pool, old)
              give_reg(pool, addr)
              return
            }
            Some(v) => v
          }
          arm64_ldrx(
            emitter,
            false,
            sz,
            old.reinterpret_as_uint(),
            addr.reinterpret_as_uint(),
            0,
          )
          gen_expr_to_float_kind_bits(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            right,
            kind,
            dst,
            bag,
          )
          if is_double {
            emit_fmov_x_to_d(emitter, 0, old)
            emit_fmov_x_to_d(emitter, 1, dst)
          } else {
            emit_fmov_w_to_s(emitter, 0, old)
            emit_fmov_w_to_s(emitter, 1, dst)
          }
          match op {
            BinaryOp::AddAssign => emit_fadd(emitter, is_double, 0, 0, 1)
            BinaryOp::SubAssign => emit_fsub(emitter, is_double, 0, 0, 1)
            BinaryOp::MulAssign => emit_fmul(emitter, is_double, 0, 0, 1)
            BinaryOp::DivAssign => emit_fdiv(emitter, is_double, 0, 0, 1)
            _ => ()
          }
          if is_double {
            emit_fmov_d_to_x(emitter, dst, 0)
          } else {
            emit_fmov_s_to_w(emitter, dst, 0)
          }
          arm64_strx(
            emitter,
            sz,
            dst.reinterpret_as_uint(),
            addr.reinterpret_as_uint(),
            0,
          )
          give_reg(pool, old)
          give_reg(pool, addr)
        }
        _ =>
          add_error(
            bag,
            loc,
            "codegen: unsupported float binary operator",
          )
      }
    Expr::Cast(ty=to_ty, expr=inner, loc=_) => {
      let target_kind = match float_kind_of_type(to_ty) {
        None => kind
        Some(k) => k
      }
      gen_expr_to_float_kind_bits(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        inner,
        target_kind,
        dst,
        bag,
      )
    }
    Expr::Call(callee~, args~, loc~) => {
      gen_call_expr(emitter, alloc, syms, pool, cstrings, callee, args, loc, bag)
      if dst != 0 {
        emit_mov(emitter, true, dst, 0)
      }
    }
    Expr::Conditional(cond~, then_expr~, else_expr~, loc~) => {
      gen_cond_expr_cmp_zero(emitter, alloc, syms, pool, cstrings, cond, bag)
      let br_else = emit_b_cond_placeholder(emitter, ARM64_COND_EQ)
      gen_expr_to_float_kind_bits(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        then_expr,
        kind,
        dst,
        bag,
      )
      let br_end = gjmp(emitter, 0)
      let else_pc = emitter_pc(emitter)
      patch_b_cond(emitter, br_else, else_pc, ARM64_COND_EQ) catch {
        err => add_error(bag, loc, err.to_string())
      }
      gen_expr_to_float_kind_bits(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        else_expr,
        kind,
        dst,
        bag,
      )
      let end_pc = emitter_pc(emitter)
      gsym_addr(emitter, br_end, end_pc) catch {
        err => add_error(bag, loc, err.to_string())
      }
    }
    _ => add_error(bag, expr_loc(expr), "codegen: unsupported float expression")
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
        Some(v) => arm64_movimm(emitter, dst.reinterpret_as_uint(), v.reinterpret_as_uint64())
      }
    Expr::CharLit(value~, ..) =>
      arm64_movimm(emitter, dst.reinterpret_as_uint(), value.to_uint64())
    Expr::Ident(name~, loc~) =>
      match lookup_local(alloc, name) {
        Some(slot) =>
          emit_load_local_scalar(emitter, alloc.sem, slot.ty, dst, slot.offset, loc, bag)
        None => {
          let sym = sym_for_name(syms, link_name(name))
          emit_load_global_int32(emitter, sym, dst)
        }
      }
    Expr::Index(base=_, index=_, loc~) => {
      let addr = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, expr, addr, bag)
      let ty = type_of_expr(alloc.sem, expr)
      let (size, signed) = match scalar_size_signed_or_error(alloc.sem, ty, loc) {
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
      arm64_ldrx(
        emitter,
        signed,
        sz,
        dst.reinterpret_as_uint(),
        addr.reinterpret_as_uint(),
        0,
      )
      give_reg(pool, addr)
    }
    Expr::Member(base=_, name=_, is_arrow=_, loc~) => {
      let addr = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, expr, addr, bag)
      let ty = type_of_expr(alloc.sem, expr)
      let (size, signed) = match scalar_size_signed_or_error(alloc.sem, ty, loc) {
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
      arm64_ldrx(
        emitter,
        signed,
        sz,
        dst.reinterpret_as_uint(),
        addr.reinterpret_as_uint(),
        0,
      )
      give_reg(pool, addr)
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
          gen_cond_expr_cmp_zero(emitter, alloc, syms, pool, cstrings, inner, bag)
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
          let sz = match arm64_sz_from_size(size) {
            None => {
              add_error(bag, loc, "codegen: unsupported scalar size")
              give_reg(pool, addr)
              return
            }
            Some(v) => v
          }
          arm64_ldrx(
            emitter,
            signed,
            sz,
            dst.reinterpret_as_uint(),
            addr.reinterpret_as_uint(),
            0,
          )
          give_reg(pool, addr)
        }
        UnaryOp::PreInc | UnaryOp::PreDec | UnaryOp::PostInc | UnaryOp::PostDec => {
          let ty = type_of_expr(alloc.sem, inner)
          if type_is_pointer_like(ty) {
            add_error(bag, loc, "codegen: pointer inc/dec not supported yet")
            return
          }
          if !type_is_supported_int32(ty) {
            add_error(bag, loc, "codegen: inc/dec only supported for int for now")
            return
          }
          let addr = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, inner, addr, bag)
          arm64_ldrx(
            emitter,
            false,
            2,
            dst.reinterpret_as_uint(),
            addr.reinterpret_as_uint(),
            0,
          )
          let one = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              give_reg(pool, addr)
              return
            }
          }
          arm64_movimm(emitter, one.reinterpret_as_uint(), 1)
          if op == UnaryOp::PostInc || op == UnaryOp::PostDec {
            let updated = take_reg(pool) catch {
              err => {
                add_error(bag, loc, err.to_string())
                give_reg(pool, one)
                give_reg(pool, addr)
                return
              }
            }
            emit_mov(emitter, false, updated, dst)
            if op == UnaryOp::PostInc {
              emit32(
                emitter,
                (0x0b000000 : Int)
                .lor(updated)
                .lor(updated << 5)
                .lor(one << 16)
                .reinterpret_as_uint(),
              )
            } else {
              emit32(
                emitter,
                (0x4b000000 : Int)
                .lor(updated)
                .lor(updated << 5)
                .lor(one << 16)
                .reinterpret_as_uint(),
              )
            }
            arm64_strx(
              emitter,
              2,
              updated.reinterpret_as_uint(),
              addr.reinterpret_as_uint(),
              0,
            )
            give_reg(pool, updated)
          } else {
            if op == UnaryOp::PreInc {
              emit32(
                emitter,
                (0x0b000000 : Int)
                .lor(dst)
                .lor(dst << 5)
                .lor(one << 16)
                .reinterpret_as_uint(),
              )
            } else {
              emit32(
                emitter,
                (0x4b000000 : Int)
                .lor(dst)
                .lor(dst << 5)
                .lor(one << 16)
                .reinterpret_as_uint(),
              )
            }
            arm64_strx(
              emitter,
              2,
              dst.reinterpret_as_uint(),
              addr.reinterpret_as_uint(),
              0,
            )
          }
          give_reg(pool, one)
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
        BinaryOp::Assign => {
          let lhs_ty = type_of_expr(alloc.sem, left)
          match strip_qual_attrs(lhs_ty) {
            CType::Struct(..) | CType::Union(..) => {
              match type_size_align_or_error(alloc.sem, lhs_ty, loc) {
                None => ()
                Some((size, _)) => {
                  if size <= 0 {
                    return
                  }
                  let dst_addr = take_reg(pool) catch {
                    err => {
                      add_error(bag, loc, err.to_string())
                      return
                    }
                  }
                  gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, left, dst_addr, bag)
                  match right {
                    Expr::Call(callee~, args~, ..) => {
                      gen_call_expr(emitter, alloc, syms, pool, cstrings, callee, args, loc, bag)
                      emit_store_agg_return_gp_to_addr(
                        emitter,
                        size,
                        dst_addr,
                        0,
                        loc,
                        bag,
                      )
                    }
                    _ => {
                      let src_addr = take_reg(pool) catch {
                        err => {
                          add_error(bag, loc, err.to_string())
                          give_reg(pool, dst_addr)
                          return
                        }
                      }
                      gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, right, src_addr, bag)
                      emit_copy_bytes(
                        emitter,
                        pool,
                        src_addr,
                        0,
                        dst_addr,
                        0,
                        size,
                        loc,
                        bag,
                      )
                      give_reg(pool, src_addr)
                    }
                  }
                  give_reg(pool, dst_addr)
                }
              }
            }
            _ =>
              match left {
                Expr::Ident(name=_, ..) => {
                  gen_expr_any(emitter, alloc, syms, pool, cstrings, right, dst, bag)
                  store_lvalue_scalar(
                    emitter,
                    alloc,
                    syms,
                    pool,
                    cstrings,
                    left,
                    dst,
                    lhs_ty,
                    bag,
                  )
                }
                Expr::Unary(op=UnaryOp::Deref, ..) | Expr::Index(..) | Expr::Member(..) => {
                  gen_expr_any(emitter, alloc, syms, pool, cstrings, right, dst, bag)
                  store_lvalue_scalar(
                    emitter,
                    alloc,
                    syms,
                    pool,
                    cstrings,
                    left,
                    dst,
                    lhs_ty,
                    bag,
                  )
                }
                _ => add_error(bag, loc, "codegen: unsupported assignment lhs for now")
              }
          }
        }
        BinaryOp::AddAssign | BinaryOp::SubAssign | BinaryOp::MulAssign |
        BinaryOp::DivAssign | BinaryOp::ModAssign | BinaryOp::ShlAssign |
        BinaryOp::ShrAssign | BinaryOp::BitAndAssign | BinaryOp::BitOrAssign |
        BinaryOp::BitXorAssign => {
          let left_ty = type_of_expr(alloc.sem, left)
          if type_is_pointer_like(left_ty) {
            match op {
              BinaryOp::AddAssign | BinaryOp::SubAssign => {
                let addr = take_reg(pool) catch {
                  err => {
                    add_error(bag, loc, err.to_string())
                    return
                  }
                }
                gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, left, addr, bag)
                arm64_ldrx(
                  emitter,
                  false,
                  3,
                  dst.reinterpret_as_uint(),
                  addr.reinterpret_as_uint(),
                  0,
                )
                let idx = take_reg(pool) catch {
                  err => {
                    add_error(bag, loc, err.to_string())
                    give_reg(pool, addr)
                    return
                  }
                }
                gen_expr_int32(emitter, alloc, syms, pool, cstrings, right, idx, bag)
                emit_sxtw(emitter, idx, idx)
                let elem_ty = match element_type_for_pointer_arith(left_ty) {
                  None => {
                    add_error(bag, loc, "codegen: pointer arithmetic missing element type")
                    give_reg(pool, idx)
                    give_reg(pool, addr)
                    return
                  }
                  Some(t) => t
                }
                let (elem_size, _) = match type_size_align_or_error(alloc.sem, elem_ty, loc) {
                  None => {
                    give_reg(pool, idx)
                    give_reg(pool, addr)
                    return
                  }
                  Some(v) => v
                }
                if elem_size != 1 {
                  let scale = take_reg(pool) catch {
                    err => {
                      add_error(bag, loc, err.to_string())
                      give_reg(pool, idx)
                      give_reg(pool, addr)
                      return
                    }
                  }
                  arm64_movimm(
                    emitter,
                    scale.reinterpret_as_uint(),
                    elem_size.to_uint64(),
                  )
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
                let base : Int = if op == BinaryOp::AddAssign { 0x8b000000 } else { 0xcb000000 }
                emit32(
                  emitter,
                  (base : Int)
                  .lor(dst)
                  .lor(dst << 5)
                  .lor(idx << 16)
                  .reinterpret_as_uint(),
                )
                arm64_strx(
                  emitter,
                  3,
                  dst.reinterpret_as_uint(),
                  addr.reinterpret_as_uint(),
                  0,
                )
                give_reg(pool, idx)
                give_reg(pool, addr)
              }
              _ => add_error(bag, loc, "codegen: compound assign pointer lhs not supported yet")
            }
            return
          }
          if !type_is_supported_int32(left_ty) {
            add_error(bag, loc, "codegen: compound assign only supported for int for now")
            return
          }
          let is_unsigned = match strip_qualifiers(left_ty) {
            CType::Int(unsigned~, ..) => unsigned
            _ => false
          }
          let addr = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, left, addr, bag)
          arm64_ldrx(
            emitter,
            false,
            2,
            dst.reinterpret_as_uint(),
            addr.reinterpret_as_uint(),
            0,
          )
          let tmp_old = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              give_reg(pool, addr)
              return
            }
          }
          emit_mov(emitter, false, tmp_old, dst)
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, right, dst, bag)
          match op {
            BinaryOp::AddAssign =>
              emit32(
                emitter,
                (0x0b000000 : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::SubAssign =>
              emit32(
                emitter,
                (0x4b000000 : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::MulAssign =>
              emit32(
                emitter,
                (0x1b007c00 : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::DivAssign =>
              emit32(
                emitter,
                (0x1ac00c00 : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::ModAssign => {
              emit32(
                emitter,
                (0x1ac00c00 : Int)
                .lor(30)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
              emit32(
                emitter,
                (0x1b008000 : Int)
                .lor(dst)
                .lor(30 << 5)
                .lor(dst << 16)
                .lor(tmp_old << 10)
                .reinterpret_as_uint(),
              )
            }
            BinaryOp::ShlAssign =>
              emit32(
                emitter,
                (0x1ac02000 : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::ShrAssign => {
              let base : Int = if is_unsigned { 0x1ac02400 } else { 0x1ac02800 }
              emit32(
                emitter,
                base
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            }
            BinaryOp::BitAndAssign =>
              emit32(
                emitter,
                (0x0a000000 : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::BitOrAssign =>
              emit32(
                emitter,
                (0x2a000000 : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::BitXorAssign =>
              emit32(
                emitter,
                (0x4a000000 : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            _ => ()
          }
          arm64_strx(
            emitter,
            2,
            dst.reinterpret_as_uint(),
            addr.reinterpret_as_uint(),
            0,
          )
          give_reg(pool, tmp_old)
          give_reg(pool, addr)
        }
        BinaryOp::LogAnd | BinaryOp::LogOr => {
          let left_ty = type_of_expr(alloc.sem, left)
          if type_is_pointer_like(left_ty) {
            gen_expr_ptr(emitter, alloc, syms, pool, cstrings, left, dst, bag)
            emit_cmp(emitter, true, dst, 31)
          } else {
            gen_expr_int32(emitter, alloc, syms, pool, cstrings, left, dst, bag)
            emit_cmp(emitter, false, dst, 31)
          }
          let br_short = emit_b_cond_placeholder(
            emitter,
            if op == BinaryOp::LogAnd { ARM64_COND_EQ } else { ARM64_COND_NE },
          )

          let right_ty = type_of_expr(alloc.sem, right)
          if type_is_pointer_like(right_ty) {
            gen_expr_ptr(emitter, alloc, syms, pool, cstrings, right, dst, bag)
            emit_cmp(emitter, true, dst, 31)
          } else {
            gen_expr_int32(emitter, alloc, syms, pool, cstrings, right, dst, bag)
            emit_cmp(emitter, false, dst, 31)
          }
          emit_cset_from_tok(emitter, TOK_NE, dst) catch {
            err => add_error(bag, loc, err.to_string())
          }

          let br_end = gjmp(emitter, 0)
          let short_pc = emitter_pc(emitter)
          patch_b_cond(
            emitter,
            br_short,
            short_pc,
            if op == BinaryOp::LogAnd { ARM64_COND_EQ } else { ARM64_COND_NE },
          )
          catch { err => add_error(bag, loc, err.to_string()) }

          arm64_movimm(
            emitter,
            dst.reinterpret_as_uint(),
            if op == BinaryOp::LogAnd { 0 } else { 1 },
          )

          let end_pc = emitter_pc(emitter)
          gsym_addr(emitter, br_end, end_pc) catch {
            err => add_error(bag, loc, err.to_string())
          }
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
                  {
                    let is_unsigned = match strip_qualifiers(left_ty) {
                      CType::Int(unsigned~, ..) => unsigned
                      _ => false
                    }
                    let base : Int =
                      if op == BinaryOp::Shl {
                        0x1ac02000
                      } else if is_unsigned {
                        0x1ac02400
                      } else {
                        0x1ac02800
                      }
                    emit32(
                      emitter,
                      base
                      .lor(dst)
                      .lor(tmp << 5)
                      .lor(dst << 16)
                      .reinterpret_as_uint(),
                    )
                  }
                Some(v) => {
                  let is_unsigned = match strip_qualifiers(left_ty) {
                    CType::Int(unsigned~, ..) => unsigned
                    _ => false
                  }
                  let shift_tok : Int =
                    if op == BinaryOp::Shl {
                      TOK_SHL
                    } else if is_unsigned {
                      TOK_SHR
                    } else {
                      TOK_SAR
                    }
                  let _ = arm64_gen_opic(
                    emitter,
                    shift_tok,
                    0,
                    false,
                    v.reinterpret_as_uint64(),
                    dst,
                    tmp,
                  )
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
    Expr::Call(callee~, args~, loc~) => {
      gen_call_expr(emitter, alloc, syms, pool, cstrings, callee, args, loc, bag)
      if dst != 0 {
        emit_mov(emitter, true, dst, 0)
      }
    }
	    Expr::SizeofExpr(expr=inner, loc~) => {
	      match inner {
	        Expr::Ident(name~, ..) =>
	          match lookup_local(alloc, name) {
	            None => ()
	            Some(slot) =>
	              match strip_qual_attrs(slot.ty) {
	                CType::Array(size=None, size_expr=Some(_), ..) =>
	                  match slot.vla_size_offset {
	                    None => add_error(bag, loc, "codegen: missing VLA byte size slot")
	                    Some(off) => {
	                      arm64_ldrx(
	                        emitter,
	                        false,
	                        3,
	                        dst.reinterpret_as_uint(),
	                        (29 : UInt),
	                        off.to_int64().reinterpret_as_uint64(),
	                      )
	                      return
	                    }
	                  }
	                _ => ()
	              }
	          }
	        _ => ()
	      }
	      let ty = type_for_sizeof(alloc.sem, inner)
	      match strip_qual_attrs(ty) {
	        CType::Array(elem=elem_ty, size=None, size_expr=Some(expr)) =>
	          gen_vla_size_bytes_to_reg(
	            emitter,
	            alloc,
	            syms,
	            pool,
	            cstrings,
	            elem_ty,
	            expr,
	            dst,
	            loc,
	            bag,
	          )
	        _ =>
	          match type_size_align_or_error(alloc.sem, ty, loc) {
	            None => ()
	            Some((size, _)) =>
	              arm64_movimm(
	                emitter,
	                dst.reinterpret_as_uint(),
	                size.to_uint64(),
	              )
	          }
	      }
	    }
	    Expr::SizeofType(ty~, loc~) =>
	      match strip_qual_attrs(ty) {
	        CType::Array(elem=elem_ty, size=None, size_expr=Some(expr)) =>
	          gen_vla_size_bytes_to_reg(
	            emitter,
	            alloc,
	            syms,
	            pool,
	            cstrings,
	            elem_ty,
	            expr,
	            dst,
	            loc,
	            bag,
	          )
	        _ =>
	          match type_size_align_or_error(alloc.sem, ty, loc) {
	            None => ()
	            Some((size, _)) =>
	              arm64_movimm(
	                emitter,
	                dst.reinterpret_as_uint(),
	                size.to_uint64(),
	              )
	          }
	      }
	    Expr::Cast(ty=to_ty, expr=inner, loc=cast_loc) => {
	      let from_ty = type_of_expr(alloc.sem, inner)
	      match (strip_qualifiers(to_ty), strip_qualifiers(from_ty)) {
        (CType::Int(kind=to_kind, unsigned=to_unsigned), CType::Float(kind=from_kind)) => {
          if !float_kind_supported(from_kind) {
            add_error(bag, cast_loc, "codegen: unsupported float type")
            gen_expr_int32(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
            return
          }
          gen_expr_to_float_kind_bits(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            inner,
            from_kind,
            dst,
            bag,
          )
          if from_kind == CFloatKind::Double {
            emit_fmov_x_to_d(emitter, 0, dst)
          } else {
            emit_fmov_w_to_s(emitter, 0, dst)
          }
          let mut inst : Int = 0x1e380000
          if to_unsigned {
            inst = inst.lor(0x00010000)
          }
          if int_size(to_kind) == 8 {
            inst = inst.lor(0x80000000)
          }
          if from_kind != CFloatKind::Float {
            inst = inst.lor(0x00400000)
          }
          emit32(
            emitter,
            inst
            .lor(dst)
            .lor(0 << 5)
            .reinterpret_as_uint(),
          )
        }
        _ => gen_expr_int32(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
      }
    }
    Expr::Conditional(cond~, then_expr~, else_expr~, loc~) => {
      gen_cond_expr_cmp_zero(emitter, alloc, syms, pool, cstrings, cond, bag)
      let br_else = emit_b_cond_placeholder(emitter, ARM64_COND_EQ)
      gen_expr_int32(emitter, alloc, syms, pool, cstrings, then_expr, dst, bag)
      let br_end = gjmp(emitter, 0)
      let else_pc = emitter_pc(emitter)
      patch_b_cond(emitter, br_else, else_pc, ARM64_COND_EQ) catch {
        err => add_error(bag, loc, err.to_string())
      }
      gen_expr_int32(emitter, alloc, syms, pool, cstrings, else_expr, dst, bag)
      let end_pc = emitter_pc(emitter)
      gsym_addr(emitter, br_end, end_pc) catch {
        err => add_error(bag, loc, err.to_string())
      }
    }
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
        Some(v) =>
          arm64_movimm(emitter, dst.reinterpret_as_uint(), v.reinterpret_as_uint64())
      }
    Expr::CharLit(value~, ..) =>
      arm64_movimm(emitter, dst.reinterpret_as_uint(), value.to_uint64())
    Expr::StringLit(value=value, loc=loc, ..) =>
      match cstrings.get(value) {
        None => add_error(bag, loc, "codegen: missing string literal in cstring pool")
        Some(sym) => emit_addr_global(emitter, sym, dst)
      }
    Expr::Ident(name~, loc~) =>
      match lookup_local(alloc, name) {
        Some(slot) =>
          match strip_qual_attrs(slot.ty) {
            CType::Array(size=None, size_expr=Some(_), ..) =>
              arm64_ldrx(
                emitter,
                false,
                3,
                dst.reinterpret_as_uint(),
                (29 : UInt),
                slot.offset.to_int64().reinterpret_as_uint64(),
              )
            CType::Array(..) => emit_addr_local(emitter, dst, slot.offset, loc, bag)
            _ =>
              emit_load_local_scalar(
                emitter,
                alloc.sem,
                slot.ty,
                dst,
                slot.offset,
                loc,
                bag,
              )
          }
        None => {
          let sym = sym_for_name(syms, link_name(name))
          emit_addr_global(emitter, sym, dst)
          if alloc.sem.functions.contains(name) {
            return
          }
          match alloc.sem.globals.get(name) {
            Some(gty) =>
              match strip_qual_attrs(gty) {
                CType::Array(..) => return
                _ => ()
              }
            None => ()
          }
          arm64_ldrx(
            emitter,
            false,
            3,
            dst.reinterpret_as_uint(),
            dst.reinterpret_as_uint(),
            0,
          )
        }
      }
    Expr::Member(base=_, name=_, is_arrow=_, loc~) => {
      let addr = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, expr, addr, bag)
      match type_of_lvalue(alloc.sem, expr) {
        None => ()
        Some(lty) =>
          match strip_qual_attrs(lty) {
            CType::Array(..) | CType::Function(..) =>
              if dst != addr {
                emit_mov(emitter, true, dst, addr)
              }
            _ =>
              arm64_ldrx(
                emitter,
                false,
                3,
                dst.reinterpret_as_uint(),
                addr.reinterpret_as_uint(),
                0,
              )
          }
      }
      give_reg(pool, addr)
    }
    Expr::Index(base=_, index=_, loc~) => {
      let addr = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, expr, addr, bag)
      match type_of_lvalue(alloc.sem, expr) {
        None => ()
        Some(lty) =>
          match strip_qual_attrs(lty) {
            CType::Array(..) | CType::Function(..) =>
              if dst != addr {
                emit_mov(emitter, true, dst, addr)
              }
            _ =>
              arm64_ldrx(
                emitter,
                false,
                3,
                dst.reinterpret_as_uint(),
                addr.reinterpret_as_uint(),
                0,
              )
          }
      }
      give_reg(pool, addr)
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
          arm64_ldrx(
            emitter,
            signed,
            sz,
            dst.reinterpret_as_uint(),
            dst.reinterpret_as_uint(),
            0,
          )
    }
    Expr::Unary(op~, expr=inner, loc~) =>
      match op {
        UnaryOp::PreInc | UnaryOp::PreDec | UnaryOp::PostInc | UnaryOp::PostDec => {
          let ty = type_of_expr(alloc.sem, inner)
          let elem_ty = match element_type_for_pointer_arith(ty) {
            None => {
              add_error(bag, loc, "codegen: pointer inc/dec missing element type")
              return
            }
            Some(t) => t
          }
          let elem_size = match strip_qual_attrs(elem_ty) {
            CType::Void | CType::Function(..) => 1
            _ =>
              match type_size_align_or_error(alloc.sem, elem_ty, loc) {
                None => return
                Some((sz, _)) => sz
              }
          }

          let addr = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, inner, addr, bag)

          let value_reg = if dst == addr {
            let tmp = take_reg(pool) catch {
              err => {
                add_error(bag, loc, err.to_string())
                give_reg(pool, addr)
                return
              }
            }
            tmp
          } else {
            dst
          }
          arm64_ldrx(
            emitter,
            false,
            3,
            value_reg.reinterpret_as_uint(),
            addr.reinterpret_as_uint(),
            0,
          )

          let is_add = op == UnaryOp::PreInc || op == UnaryOp::PostInc
          let is_post = op == UnaryOp::PostInc || op == UnaryOp::PostDec
          let imm = elem_size

          if is_post {
            let updated = take_reg(pool) catch {
              err => {
                add_error(bag, loc, err.to_string())
                if value_reg != dst {
                  give_reg(pool, value_reg)
                }
                give_reg(pool, addr)
                return
              }
            }
            emit_mov(emitter, true, updated, value_reg)
            if imm != 0 {
              if imm <= 0xfff {
                let base : Int = if is_add { 0x91000000 } else { 0xd1000000 }
                emit32(
                  emitter,
                  (base : Int)
                  .lor(updated)
                  .lor(updated << 5)
                  .lor(imm << 10)
                  .reinterpret_as_uint(),
                )
              } else {
                let scale = take_reg(pool) catch {
                  err => {
                    add_error(bag, loc, err.to_string())
                    give_reg(pool, updated)
                    if value_reg != dst {
                      give_reg(pool, value_reg)
                    }
                    give_reg(pool, addr)
                    return
                  }
                }
                arm64_movimm(
                  emitter,
                  scale.reinterpret_as_uint(),
                  imm.to_uint64(),
                )
                let base : Int = if is_add { 0x8b000000 } else { 0xcb000000 }
                emit32(
                  emitter,
                  (base : Int)
                  .lor(updated)
                  .lor(updated << 5)
                  .lor(scale << 16)
                  .reinterpret_as_uint(),
                )
                give_reg(pool, scale)
              }
            }
            arm64_strx(
              emitter,
              3,
              updated.reinterpret_as_uint(),
              addr.reinterpret_as_uint(),
              0,
            )
            if value_reg != dst {
              emit_mov(emitter, true, dst, value_reg)
              give_reg(pool, value_reg)
            }
            give_reg(pool, updated)
          } else {
            if imm != 0 {
              if imm <= 0xfff {
                let base : Int = if is_add { 0x91000000 } else { 0xd1000000 }
                emit32(
                  emitter,
                  (base : Int)
                  .lor(value_reg)
                  .lor(value_reg << 5)
                  .lor(imm << 10)
                  .reinterpret_as_uint(),
                )
              } else {
                let scale = take_reg(pool) catch {
                  err => {
                    add_error(bag, loc, err.to_string())
                    if value_reg != dst {
                      give_reg(pool, value_reg)
                    }
                    give_reg(pool, addr)
                    return
                  }
                }
                arm64_movimm(
                  emitter,
                  scale.reinterpret_as_uint(),
                  imm.to_uint64(),
                )
                let base : Int = if is_add { 0x8b000000 } else { 0xcb000000 }
                emit32(
                  emitter,
                  (base : Int)
                  .lor(value_reg)
                  .lor(value_reg << 5)
                  .lor(scale << 16)
                  .reinterpret_as_uint(),
                )
                give_reg(pool, scale)
              }
            }
            arm64_strx(
              emitter,
              3,
              value_reg.reinterpret_as_uint(),
              addr.reinterpret_as_uint(),
              0,
            )
            if value_reg != dst {
              emit_mov(emitter, true, dst, value_reg)
              give_reg(pool, value_reg)
            }
          }
          give_reg(pool, addr)
        }
        _ => add_error(bag, loc, "codegen: unsupported pointer unary operator")
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
        BinaryOp::AddAssign | BinaryOp::SubAssign => {
          let lhs_ty = type_of_expr(alloc.sem, left)
          if !type_is_pointer_like(lhs_ty) {
            add_error(bag, loc, "codegen: compound assign pointer op needs pointer lhs")
            return
          }

          let elem_ty = match element_type_for_pointer_arith(lhs_ty) {
            None => {
              add_error(bag, loc, "codegen: pointer arithmetic missing element type")
              return
            }
            Some(t) => t
          }
          let elem_size = match strip_qual_attrs(elem_ty) {
            CType::Void | CType::Function(..) => 1
            _ =>
              match type_size_align_or_error(alloc.sem, elem_ty, loc) {
                None => return
                Some((sz, _)) => sz
              }
          }

          let addr = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, left, addr, bag)

          let value_reg = if dst == addr {
            let tmp = take_reg(pool) catch {
              err => {
                add_error(bag, loc, err.to_string())
                give_reg(pool, addr)
                return
              }
            }
            tmp
          } else {
            dst
          }
          arm64_ldrx(
            emitter,
            false,
            3,
            value_reg.reinterpret_as_uint(),
            addr.reinterpret_as_uint(),
            0,
          )

          let idx = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              if value_reg != dst {
                give_reg(pool, value_reg)
              }
              give_reg(pool, addr)
              return
            }
          }
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, right, idx, bag)
          emit_sxtw(emitter, idx, idx)
          if elem_size != 1 {
            let scale = take_reg(pool) catch {
              err => {
                add_error(bag, loc, err.to_string())
                give_reg(pool, idx)
                if value_reg != dst {
                  give_reg(pool, value_reg)
                }
                give_reg(pool, addr)
                return
              }
            }
            arm64_movimm(
              emitter,
              scale.reinterpret_as_uint(),
              elem_size.to_uint64(),
            )
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

          let base : Int = if op == BinaryOp::AddAssign { 0x8b000000 } else { 0xcb000000 }
          emit32(
            emitter,
            (base : Int)
            .lor(value_reg)
            .lor(value_reg << 5)
            .lor(idx << 16)
            .reinterpret_as_uint(),
          )
          arm64_strx(
            emitter,
            3,
            value_reg.reinterpret_as_uint(),
            addr.reinterpret_as_uint(),
            0,
          )
          if value_reg != dst {
            emit_mov(emitter, true, dst, value_reg)
            give_reg(pool, value_reg)
          }

          give_reg(pool, idx)
          give_reg(pool, addr)
        }
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
            arm64_movimm(
              emitter,
              scale.reinterpret_as_uint(),
              elem_size.to_uint64(),
            )
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
    Expr::Call(callee~, args~, loc~) => {
      gen_call_expr(emitter, alloc, syms, pool, cstrings, callee, args, loc, bag)
      if dst != 0 {
        emit_mov(emitter, true, dst, 0)
      }
    }
    Expr::Conditional(cond~, then_expr~, else_expr~, loc~) => {
      gen_cond_expr_cmp_zero(emitter, alloc, syms, pool, cstrings, cond, bag)
      let br_else = emit_b_cond_placeholder(emitter, ARM64_COND_EQ)
      gen_expr_ptr(emitter, alloc, syms, pool, cstrings, then_expr, dst, bag)
      let br_end = gjmp(emitter, 0)
      let else_pc = emitter_pc(emitter)
      patch_b_cond(emitter, br_else, else_pc, ARM64_COND_EQ) catch {
        err => add_error(bag, loc, err.to_string())
      }
      gen_expr_ptr(emitter, alloc, syms, pool, cstrings, else_expr, dst, bag)
      let end_pc = emitter_pc(emitter)
      gsym_addr(emitter, br_end, end_pc) catch {
        err => add_error(bag, loc, err.to_string())
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
  match float_kind_of_type(ty) {
    Some(k) => gen_expr_to_float_kind_bits(emitter, alloc, syms, pool, cstrings, expr, k, dst, bag)
    None =>
      if type_is_pointer_like(ty) {
        gen_expr_ptr(emitter, alloc, syms, pool, cstrings, expr, dst, bag)
      } else {
        gen_expr_int32(emitter, alloc, syms, pool, cstrings, expr, dst, bag)
      }
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
  break_depth : Int
  cont_depth : Int
}

///|
struct SwitchChains {
  break_chain : Int
  break_depth : Int
}

///|
struct LabelCtx {
  addrs : Map[String, Int]
  chains : Map[String, Int]
}

///|
fn new_label_ctx() -> LabelCtx {
  { addrs: {}, chains: {} }
}

///|
const BREAKABLE_LOOP : Int = 0

///|
const BREAKABLE_SWITCH : Int = 1

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
      loops[idx] = {
        break_chain: chain,
        cont_chain: info.cont_chain,
        break_depth: info.break_depth,
        cont_depth: info.cont_depth,
      }
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
      loops[idx] = {
        break_chain: info.break_chain,
        cont_chain: chain,
        break_depth: info.break_depth,
        cont_depth: info.cont_depth,
      }
    }
  }
}

///|
fn switch_append_break(
  switches : Array[SwitchChains],
  emitter : Arm64Emitter,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let idx = switches.length() - 1
  match switches.get(idx) {
    None => add_error(bag, loc, "codegen: break outside of loop/switch")
    Some(info) => {
      let chain = gjmp(emitter, info.break_chain)
      switches[idx] = { break_chain: chain, break_depth: info.break_depth }
    }
  }
}

///|
struct SwitchCaseInfo {
  start : Int
  end : Int
}

///|
fn collect_switch_labels(
  sem : SemContext,
  stmt : Stmt,
) -> (Array[SwitchCaseInfo], Bool) {
  let cases : Array[SwitchCaseInfo] = []

  fn walk(
    sem : SemContext,
    stmt : Stmt,
    cases : Array[SwitchCaseInfo],
    has_default : Bool,
  ) -> Bool {
    match stmt {
      Stmt::Case(expr~, end_expr~, ..) => {
        let start = const_int_from_expr(sem, expr, expr_loc(expr)).unwrap_or(0)
        let end = match end_expr {
          None => start
          Some(e) => const_int_from_expr(sem, e, expr_loc(e)).unwrap_or(start)
        }
        cases.push({ start, end })
        has_default
      }
      Stmt::Default(..) => true
      Stmt::Switch(..) => has_default
      Stmt::Compound(stmts~, ..) => {
        let mut flag = has_default
        for s in stmts {
          flag = walk(sem, s, cases, flag)
        }
        flag
      }
      Stmt::If(then_branch~, else_branch~, ..) => {
        let flag = walk(sem, then_branch, cases, has_default)
        match else_branch {
          None => flag
          Some(e) => walk(sem, e, cases, flag)
        }
      }
      Stmt::While(body~, ..) => walk(sem, body, cases, has_default)
      Stmt::DoWhile(body~, ..) => walk(sem, body, cases, has_default)
      Stmt::For(init~, body~, ..) =>
        match init {
          None => walk(sem, body, cases, has_default)
          Some(s) => {
            let flag = walk(sem, s, cases, has_default)
            walk(sem, body, cases, flag)
          }
        }
      Stmt::Label(body~, ..) => walk(sem, body, cases, has_default)
      _ => has_default
    }
  }

  let has_default = walk(sem, stmt, cases, false)
  (cases, has_default)
}

///|
fn gen_switch_body(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  loops : Array[LoopChains],
  switches : Array[SwitchChains],
  breakables : Array[Int],
  labels : LabelCtx,
  cstrings : Map[String, Sym],
  stmt : Stmt,
  bag : DiagBag,
  return_chain : Int,
  case_addrs : Array[Int],
  default_addr : Int?,
  next_case : Int,
) -> (Int, Int?, Int) {
  let mut default_addr0 = default_addr
  let mut next_case0 = next_case
  match stmt {
    Stmt::Case(body=case_body, ..) => {
      if next_case0 < case_addrs.length() {
        case_addrs[next_case0] = emitter_pc(emitter)
        next_case0 = next_case0 + 1
      }
      let chain = gen_stmt(
        emitter,
        alloc,
        syms,
        pool,
        loops,
        switches,
        breakables,
        labels,
        cstrings,
        case_body,
        bag,
        return_chain,
      )
      (chain, default_addr0, next_case0)
    }
    Stmt::Default(body=def_body, ..) => {
      default_addr0 = Some(emitter_pc(emitter))
      let chain = gen_stmt(
        emitter,
        alloc,
        syms,
        pool,
        loops,
        switches,
        breakables,
        labels,
        cstrings,
        def_body,
        bag,
        return_chain,
      )
      (chain, default_addr0, next_case0)
    }
	    Stmt::Compound(stmts~, ..) => {
	      cg_push_scope(alloc)
	      let mut chain = return_chain
      for s in stmts {
        let (new_chain, new_default, new_next) = gen_switch_body(
          emitter,
        alloc,
        syms,
        pool,
        loops,
        switches,
        breakables,
        labels,
        cstrings,
        s,
        bag,
        chain,
        case_addrs,
          default_addr0,
          next_case0,
        )
        chain = new_chain
        default_addr0 = new_default
        next_case0 = new_next
      }
	      cg_pop_scope_codegen(emitter, alloc)
	      (chain, default_addr0, next_case0)
	    }
    Stmt::Switch(..) => {
      let chain = gen_stmt(
        emitter,
        alloc,
        syms,
        pool,
        loops,
        switches,
        breakables,
        labels,
        cstrings,
        stmt,
        bag,
        return_chain,
      )
      (chain, default_addr0, next_case0)
    }
    _ => {
      let chain = gen_stmt(
        emitter,
        alloc,
        syms,
        pool,
        loops,
        switches,
        breakables,
        labels,
        cstrings,
        stmt,
        bag,
        return_chain,
      )
      (chain, default_addr0, next_case0)
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
  switches : Array[SwitchChains],
  breakables : Array[Int],
  labels : LabelCtx,
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
        chain = gen_stmt(
          emitter,
          alloc,
          syms,
          pool,
          loops,
          switches,
          breakables,
          labels,
          cstrings,
          s,
          bag,
          chain,
        )
      }
	      cg_pop_scope_codegen(emitter, alloc)
	      chain
	    }
    Stmt::DeclStmt(decls~, ..) => {
      for d in decls {
        let mut decl_ty = d.ty
        match strip_qual_attrs(d.ty) {
          CType::Array(elem=elem_ty, size=None, size_expr=None) =>
            match d.init {
              Some(Initializer::Expr(expr=Expr::StringLit(length~, ..), ..)) =>
                if is_char_type(elem_ty) {
                  decl_ty = apply_inferred_array_size(d.ty, length)
                }
              Some(Initializer::List(items~, ..)) => {
                let len = infer_array_size_from_init_items(items)
                decl_ty = apply_inferred_array_size(d.ty, len)
              }
              _ => ()
            }
          _ => ()
        }
        match alloc_local(alloc, d.name, decl_ty, d.loc) {
          None => ()
          Some(slot) => {
            let mut slot0 = slot
            match strip_qual_attrs(slot0.ty) {
              CType::Array(size=None, size_expr=Some(_), ..) => {
                let size_off = alloc_hidden_slot(alloc, 8, 8)
                let updated = {
                  offset: slot0.offset,
                  ty: slot0.ty,
                  vla_size_offset: Some(size_off),
                }
                let scope_idx = alloc.scopes.length() - 1
                alloc.scopes[scope_idx].set(d.name, updated)
                slot0 = updated
                match vla_record_decl(alloc, slot0.offset) {
                  None => ()
                  Some(off) => emit_vla_sp_save(emitter, off)
                }
              }
              _ => ()
            }
            match strip_qual_attrs(slot0.ty) {
              CType::Array(elem=_elem_ty, size=None, size_expr=Some(_expr)) =>
                gen_vla_alloc_to_local_slot(
                  emitter,
                  alloc,
                  syms,
                  pool,
                  cstrings,
                  slot0.offset,
                  slot0.vla_size_offset,
                  slot0.ty,
                  d.loc,
                  bag,
                )
              _ => ()
            }
            match d.init {
              None => ()
              Some(init) => {
                match type_size_align_or_error(alloc.sem, slot0.ty, d.loc) {
                  None => ()
                  Some((size, _)) =>
                    if size > 0 {
                      emit_zero_bytes(emitter, 29, slot0.offset, size)
                    }
                }
                gen_initializer_to_addr(
                  emitter,
                  alloc,
                  syms,
                  pool,
                  cstrings,
                  29,
                  slot0.offset,
                  slot0.ty,
                  init,
                  bag,
                )
              }
            }
          }
        }
      }
      return_chain
    }
    Stmt::If(cond~, then_branch~, else_branch~, loc~) => {
      gen_cond_expr_cmp_zero(emitter, alloc, syms, pool, cstrings, cond, bag)
      let br_false = emit_b_cond_placeholder(emitter, ARM64_COND_EQ)
      let chain1 = gen_stmt(
        emitter,
        alloc,
        syms,
        pool,
        loops,
        switches,
        breakables,
        labels,
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
            switches,
            breakables,
            labels,
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
	      gen_cond_expr_cmp_zero(emitter, alloc, syms, pool, cstrings, cond, bag)
	      let br_end = emit_b_cond_placeholder(emitter, ARM64_COND_EQ)
	
	      let loop_depth = alloc.scopes.length()
	      loops.push({
	        break_chain: 0,
	        cont_chain: 0,
	        break_depth: loop_depth,
	        cont_depth: loop_depth,
	      })
	      breakables.push(BREAKABLE_LOOP)
	      let chain1 = gen_stmt(
	        emitter,
        alloc,
        syms,
        pool,
        loops,
        switches,
        breakables,
        labels,
        cstrings,
        body,
        bag,
        return_chain,
	      )
	      breakables.pop() |> ignore
	      let loop_info = loops.pop().unwrap_or({
	        break_chain: 0,
	        cont_chain: 0,
	        break_depth: 0,
	        cont_depth: 0,
	      })
	
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
	      let loop_depth = alloc.scopes.length()
	      loops.push({
	        break_chain: 0,
	        cont_chain: 0,
	        break_depth: loop_depth,
	        cont_depth: loop_depth,
	      })
	      breakables.push(BREAKABLE_LOOP)
	      let chain1 = gen_stmt(
        emitter,
        alloc,
        syms,
        pool,
        loops,
        switches,
        breakables,
        labels,
        cstrings,
        body,
        bag,
        return_chain,
	      )
	      breakables.pop() |> ignore
	      let cond_pc = emitter_pc(emitter)
	      let loop_info = loops.pop().unwrap_or({
	        break_chain: 0,
	        cont_chain: 0,
	        break_depth: 0,
	        cont_depth: 0,
	      })
	      gsym_addr(emitter, loop_info.cont_chain, cond_pc) catch {
	        err => add_error(bag, loc, err.to_string())
      }

      gen_cond_expr_cmp_zero(emitter, alloc, syms, pool, cstrings, cond, bag)
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
	      let cont_depth = alloc.scopes.length()
	      let break_depth = cont_depth - 1
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
            switches,
            breakables,
            labels,
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
          gen_cond_expr_cmp_zero(emitter, alloc, syms, pool, cstrings, e, bag)
          Some(emit_b_cond_placeholder(emitter, ARM64_COND_EQ))
        }
	      }
	
	      loops.push({
	        break_chain: 0,
	        cont_chain: 0,
	        break_depth,
	        cont_depth,
	      })
	      breakables.push(BREAKABLE_LOOP)
	      let chain1 = gen_stmt(
        emitter,
        alloc,
        syms,
        pool,
        loops,
        switches,
        breakables,
        labels,
        cstrings,
        body,
        bag,
        chain0,
      )
	      let step_pc = emitter_pc(emitter)
	      breakables.pop() |> ignore
	      let loop_info = loops.pop().unwrap_or({
	        break_chain: 0,
	        cont_chain: 0,
	        break_depth: 0,
	        cont_depth: 0,
	      })
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
	      cg_pop_scope_codegen(emitter, alloc)
	      chain1
	    }
    Stmt::Switch(cond~, body~, loc~) => {
      let (cases, _has_default) = collect_switch_labels(alloc.sem, body)
      let case_addrs : Array[Int] = []
      for _ in cases {
        case_addrs.push(0)
      }
      let mut default_addr : Int? = None

      gen_expr_int32(emitter, alloc, syms, pool, cstrings, cond, 0, bag)

      let eq_branches : Array[(Int, Int)] = []
      let range_jmps : Array[(Int, Int)] = []
      for i = 0; i < cases.length(); i = i + 1 {
        let info = cases[i]
        if info.start == info.end {
          let tmp = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              9
            }
          }
          arm64_movimm(
            emitter,
            tmp.reinterpret_as_uint(),
            info.start.to_uint64(),
          )
          emit_cmp(emitter, false, 0, tmp)
          give_reg(pool, tmp)
          let at = emit_b_cond_placeholder(emitter, ARM64_COND_EQ)
          eq_branches.push((at, i))
        } else {
          let tmp = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              9
            }
          }
          arm64_movimm(
            emitter,
            tmp.reinterpret_as_uint(),
            info.start.to_uint64(),
          )
          emit_cmp(emitter, false, 0, tmp)
          let skip1 = emit_b_cond_placeholder(emitter, ARM64_COND_LT)
          arm64_movimm(
            emitter,
            tmp.reinterpret_as_uint(),
            info.end.to_uint64(),
          )
          emit_cmp(emitter, false, 0, tmp)
          let skip2 = emit_b_cond_placeholder(emitter, ARM64_COND_GT)
          give_reg(pool, tmp)

          let jmp = gjmp(emitter, 0)
          range_jmps.push((jmp, i))
          let next_pc = emitter_pc(emitter)
          patch_b_cond(emitter, skip1, next_pc, ARM64_COND_LT) catch {
            err => add_error(bag, loc, err.to_string())
          }
          patch_b_cond(emitter, skip2, next_pc, ARM64_COND_GT) catch {
            err => add_error(bag, loc, err.to_string())
          }
        }
      }

      let default_jmp = gjmp(emitter, 0)

      let break_depth = alloc.scopes.length()
      switches.push({ break_chain: 0, break_depth })
      breakables.push(BREAKABLE_SWITCH)
      let (chain1, new_default, _next_case) = gen_switch_body(
        emitter,
        alloc,
        syms,
        pool,
        loops,
        switches,
        breakables,
        labels,
        cstrings,
        body,
        bag,
        return_chain,
        case_addrs,
        default_addr,
        0,
      )
      default_addr = new_default

      let end_pc = emitter_pc(emitter)
      breakables.pop() |> ignore
      let sw_info = switches.pop().unwrap_or({ break_chain: 0, break_depth: 0 })
      gsym_addr(emitter, sw_info.break_chain, end_pc) catch {
        err => add_error(bag, loc, err.to_string())
      }

      let default_target = default_addr.unwrap_or(end_pc)
      gsym_addr(emitter, default_jmp, default_target) catch {
        err => add_error(bag, loc, err.to_string())
      }

      for item in eq_branches {
        let (at, idx) = item
        if idx < case_addrs.length() {
          patch_b_cond(emitter, at, case_addrs[idx], ARM64_COND_EQ) catch {
            err => add_error(bag, loc, err.to_string())
          }
        }
      }
      for item in range_jmps {
        let (jmp, idx) = item
        if idx < case_addrs.length() {
          gsym_addr(emitter, jmp, case_addrs[idx]) catch {
            err => add_error(bag, loc, err.to_string())
          }
        }
      }
      chain1
    }
    Stmt::Goto(name~, loc~) => {
      emit_vla_leave(emitter, alloc, 0)
      match labels.addrs.get(name) {
        Some(addr) =>
          gjmp_addr(emitter, addr) catch {
            err => add_error(bag, loc, err.to_string())
          }
        None => {
          let chain = labels.chains.get(name).unwrap_or(0)
          let new_chain = gjmp(emitter, chain)
          labels.chains.set(name, new_chain)
        }
      }
      return_chain
    }
    Stmt::Label(name~, body~, loc~) => {
      let addr = emitter_pc(emitter)
      if labels.addrs.contains(name) {
        add_error(bag, loc, "codegen: duplicate label")
      }
      match labels.chains.get(name) {
        None => ()
        Some(chain) =>
          if chain != 0 {
            gsym_addr(emitter, chain, addr) catch {
              err => add_error(bag, loc, err.to_string())
            }
          }
      }
      labels.addrs.set(name, addr)
      labels.chains.set(name, 0)
      match current_scope_vla_loc(alloc) {
        None => ()
        Some(off) => emit_vla_sp_restore(emitter, off)
      }
      gen_stmt(
        emitter,
        alloc,
        syms,
        pool,
        loops,
        switches,
        breakables,
        labels,
        cstrings,
        body,
        bag,
        return_chain,
      )
    }
	    Stmt::Break(loc~) => {
	      let idx = breakables.length() - 1
	      match breakables.get(idx) {
	        None => add_error(bag, loc, "codegen: break outside of loop/switch")
	        Some(kind) =>
	          if kind == BREAKABLE_LOOP {
	            match loops.get(loops.length() - 1) {
	              None => add_error(bag, loc, "codegen: break outside of loop")
	              Some(info) => emit_vla_leave(emitter, alloc, info.break_depth)
	            }
	            loop_append_break(loops, emitter, loc, bag)
	          } else {
	            match switches.get(switches.length() - 1) {
	              None => add_error(bag, loc, "codegen: break outside of switch")
	              Some(info) => emit_vla_leave(emitter, alloc, info.break_depth)
	            }
	            switch_append_break(switches, emitter, loc, bag)
	          }
	      }
	      return_chain
	    }
	    Stmt::Continue(loc~) => {
	      match loops.get(loops.length() - 1) {
	        None => add_error(bag, loc, "codegen: continue outside of loop")
	        Some(info) => emit_vla_leave(emitter, alloc, info.cont_depth)
	      }
	      loop_append_continue(loops, emitter, loc, bag)
	      return_chain
	    }
    Stmt::ExprStmt(expr~, ..) => {
      gen_expr_any(emitter, alloc, syms, pool, cstrings, expr, 0, bag)
      return_chain
    }
    Stmt::Return(value~, loc~) => {
      let rt = strip_qual_attrs(alloc.ret_ty)
      match value {
        None =>
          match float_kind_of_type(rt) {
            Some(k) => {
              arm64_movimm(emitter, (0 : UInt), 0)
              if k == CFloatKind::Double {
                emit_fmov_x_to_d(emitter, 0, 0)
              } else {
                emit_fmov_w_to_s(emitter, 0, 0)
              }
            }
            None => arm64_movimm(emitter, (0 : UInt), 0)
          }
        Some(expr) =>
          match float_kind_of_type(rt) {
            Some(k) => {
              gen_expr_to_float_kind_bits(emitter, alloc, syms, pool, cstrings, expr, k, 0, bag)
              if k == CFloatKind::Double {
                emit_fmov_x_to_d(emitter, 0, 0)
              } else {
                emit_fmov_w_to_s(emitter, 0, 0)
              }
            }
            None =>
              match rt {
                CType::Struct(..) | CType::Union(..) =>
                  match type_size_align_or_error(alloc.sem, rt, loc) {
                    None => ()
                    Some((size, _)) =>
                      if size == 0 {
                        ()
                      } else if expr is Expr::Call(callee~, args~, ..) {
                        gen_call_expr(emitter, alloc, syms, pool, cstrings, callee, args, loc, bag)
                      } else {
                        let addr = take_reg(pool) catch {
                          err => {
                            add_error(bag, loc, err.to_string())
                            return gjmp(emitter, return_chain)
                          }
                        }
                        gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, expr, addr, bag)
                        if size <= 8 {
                          let sz = match arm64_sz_from_size(size) {
                            None => {
                              add_error(bag, loc, "codegen: unsupported scalar size")
                              give_reg(pool, addr)
                              return gjmp(emitter, return_chain)
                            }
                            Some(v) => v
                          }
                          arm64_ldrx(
                            emitter,
                            false,
                            sz,
                            (0 : UInt),
                            addr.reinterpret_as_uint(),
                            0,
                          )
                        } else {
                          arm64_ldrx(
                            emitter,
                            false,
                            3,
                            (0 : UInt),
                            addr.reinterpret_as_uint(),
                            0,
                          )
                          let rest = size - 8
                          let sz1 = match arm64_sz_from_size(rest) {
                            None => {
                              add_error(bag, loc, "codegen: unsupported scalar size")
                              give_reg(pool, addr)
                              return gjmp(emitter, return_chain)
                            }
                            Some(v) => v
                          }
                          arm64_ldrx(
                            emitter,
                            false,
                            sz1,
                            (1 : UInt),
                            addr.reinterpret_as_uint(),
                            8,
                          )
                        }
                        give_reg(pool, addr)
                      }
                  }
                _ => gen_expr_any(emitter, alloc, syms, pool, cstrings, expr, 0, bag)
              }
          }
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
  let alloc = new_local_alloc(sem, func.return_type)
  cg_push_scope(alloc)
  for p in func.params {
    let param_ty = adjust_param_type_for_local(p.ty)
    alloc_local(alloc, p.name, param_ty, p.loc) |> ignore
  }
  layout_stmt(alloc, func.body)
  let size = align_up(alloc.used_bytes, 16)
  cg_pop_scope(alloc)
  size
}

///|
fn emit_prologue(emitter : Arm64Emitter, frame_size : Int) -> Unit {
  emit32(emitter, (0xa9bf7bfd : UInt))
  emit32(emitter, (0x910003fd : UInt))
  let callee_save_bytes = 64
  let total_size = frame_size + callee_save_bytes
  if total_size > 0 {
    let off = (0 : UInt64) - total_size.to_uint64()
    arm64_spoff(emitter, (31 : UInt), off)
  }
  // Save callee-saved registers used for temporaries at the bottom of the frame
  // (below locals) so local slots (fp-relative negatives) remain unchanged.
  let base_off = -total_size
  let regs : Array[Int] = [19, 20, 21, 22, 23, 24, 25, 26]
  let mut i = 0
  while i < regs.length() {
    let off = base_off + (i * 8)
    arm64_strx(
      emitter,
      3,
      regs[i].reinterpret_as_uint(),
      (29 : UInt),
      off.to_int64().reinterpret_as_uint64(),
    )
    i = i + 1
  }
}

///|
fn emit_epilogue(emitter : Arm64Emitter, frame_size : Int) -> Unit {
  let callee_save_bytes = 64
  let total_size = frame_size + callee_save_bytes
  // Restore callee-saved temporaries from the bottom of the frame.
  let base_off = -total_size
  let regs : Array[Int] = [19, 20, 21, 22, 23, 24, 25, 26]
  let mut i = 0
  while i < regs.length() {
    let off = base_off + (i * 8)
    arm64_ldrx(
      emitter,
      false,
      3,
      regs[i].reinterpret_as_uint(),
      (29 : UInt),
      off.to_int64().reinterpret_as_uint64(),
    )
    i = i + 1
  }
  if total_size > 0 {
    arm64_spoff(emitter, (31 : UInt), total_size.to_uint64())
  }
  emit32(emitter, (0xa8c17bfd : UInt))
  emit32(emitter, (0xd65f03c0 : UInt))
}

///|
fn emit_restore_sp_to_frame_base(emitter : Arm64Emitter, frame_size : Int) -> Unit {
  let callee_save_bytes = 64
  let total_size = frame_size + callee_save_bytes
  if total_size <= 0 {
    return
  }
  // mov sp,fp; sub sp,sp,#total_size
  emit32(emitter, (0x9100001f : Int).lor(29 << 5).reinterpret_as_uint())
  let off = (0 : UInt64) - total_size.to_uint64()
  arm64_spoff(emitter, (31 : UInt), off)
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
  let alloc = new_local_alloc(sem, func.return_type)
  cg_push_scope(alloc)
  emit_prologue(emitter, frame_size)

  let pool = new_reg_pool()
  let mut gp = 0
  let mut fp = 0
  for p in func.params {
    let param_ty = adjust_param_type_for_local(p.ty)
    match alloc_local(alloc, p.name, param_ty, p.loc) {
      None => ()
      Some(slot) =>
        match float_kind_of_type(slot.ty) {
          Some(k) => {
            if fp >= 8 {
              add_error(bag, p.loc, "codegen: only supports up to 8 float params for now")
              continue
            }
            let tmp_reg : Int = 16
            if k == CFloatKind::Double {
              emit_fmov_d_to_x(emitter, tmp_reg, fp)
            } else {
              emit_fmov_s_to_w(emitter, tmp_reg, fp)
            }
            emit_store_local_scalar(
              emitter,
              alloc.sem,
              slot.ty,
              tmp_reg,
              slot.offset,
              p.loc,
              bag,
            )
            fp = fp + 1
          }
          None =>
            match strip_qual_attrs(slot.ty) {
              CType::Struct(..) | CType::Union(..) =>
                match type_size_align_or_error(alloc.sem, slot.ty, p.loc) {
                  None => ()
                  Some((size, _)) =>
                    if size <= 8 {
                      if gp >= 8 {
                        add_error(bag, p.loc, "codegen: only supports up to 8 params for now")
                        continue
                      }
                      let sz = match arm64_sz_from_size(size) {
                        None => {
                          add_error(bag, p.loc, "codegen: unsupported scalar size")
                          continue
                        }
                        Some(v) => v
                      }
                      arm64_strx(
                        emitter,
                        sz,
                        gp.reinterpret_as_uint(),
                        (29 : UInt),
                        slot.offset.to_int64().reinterpret_as_uint64(),
                      )
                      gp = gp + 1
                    } else if size <= 16 {
                      if gp + 1 >= 8 {
                        add_error(bag, p.loc, "codegen: only supports up to 8 params for now")
                        continue
                      }
                      arm64_strx(
                        emitter,
                        3,
                        gp.reinterpret_as_uint(),
                        (29 : UInt),
                        slot.offset.to_int64().reinterpret_as_uint64(),
                      )
                      let rest = size - 8
                      let sz1 = match arm64_sz_from_size(rest) {
                        None => {
                          add_error(bag, p.loc, "codegen: unsupported scalar size")
                          gp = gp + 2
                          continue
                        }
                        Some(v) => v
                      }
                      arm64_strx(
                        emitter,
                        sz1,
                        (gp + 1).reinterpret_as_uint(),
                        (29 : UInt),
                        (slot.offset + 8).to_int64().reinterpret_as_uint64(),
                      )
                      gp = gp + 2
                    } else {
                      add_error(bag, p.loc, "codegen: struct params >16 bytes not supported yet")
                    }
                }
              _ =>
                if gp < 8 {
                  emit_store_local_scalar(
                    emitter,
                    alloc.sem,
                    slot.ty,
                    gp,
                    slot.offset,
                    p.loc,
                    bag,
                  )
                  gp = gp + 1
                } else {
                  add_error(bag, p.loc, "codegen: only supports up to 8 params for now")
                }
            }
        }
    }
  }

  let loops : Array[LoopChains] = []
  let switches : Array[SwitchChains] = []
  let breakables : Array[Int] = []
  let labels = new_label_ctx()
  let return_chain = gen_stmt(
    emitter,
    alloc,
    syms,
    pool,
    loops,
    switches,
    breakables,
    labels,
    cstrings,
    func.body,
    bag,
    0,
  )
  cg_pop_scope(alloc)

  gsym(emitter, return_chain) catch {
    err => add_error(bag, func.loc, err.to_string())
  }
  emit_restore_sp_to_frame_base(emitter, frame_size)
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
  let sem = check_translation_unit(unit, bag)
  if has_errors(bag) {
    return None
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
      Decl::FuncDef(func) => if func.name == "main" { main_found = true }
      _ => ()
    }
  }

  // Generate `main` first when present for stable layout, but allow objects without `main`.
  if main_found {
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
  }
  for decl in unit.decls {
    match decl {
      Decl::FuncDef(func) =>
        if !main_found || func.name != "main" {
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
  if has_errors(bag) {
    return None
  }

  let data_words : Array[UInt] = []
  let mut bss_size = 0
  let mut bss_align = 4
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
        } else {
          let (size, align) = match type_size_align_or_error(sem, var_decl.ty, var_decl.loc) {
            None => continue
            Some(v) => v
          }
          match var_decl.init {
            None => {
              let aligned = align_up(bss_size, align)
              bss_size = aligned + size
              if align > bss_align {
                bss_align = align
              }
              def_symbols.set(link, {
                id: syms.name_to_id.get(link).unwrap_or(0),
                name: link,
                section: Some(".bss"),
                value: aligned,
                is_external: var_decl.storage != StorageClass::Static,
              })
            }
            Some(init) =>
              if type_is_supported_int32(var_decl.ty) {
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
              } else {
                add_error(
                  bag,
                  var_decl.loc,
                  "codegen: global initializer not supported for this type yet",
                )
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
      align: bss_align,
      size_bytes: bss_size,
    })
  }

  Some(encode_macho_object(sections, symbols))
}
