///|
struct RegPool {
  free : Array[Int]
}

///|
let caller_saved_regs_list : Array[Int] = [9, 10, 11, 12, 13, 14, 15]

///|
let callee_saved_regs_list : Array[Int] = [19, 20, 21, 22, 23, 24, 25, 26, 27, 28]

///|
fn new_reg_pool() -> RegPool {
  // Use callee-saved registers for temporaries so nested calls don't clobber
  // intermediate values (AArch64 ABI: x19-x28 are preserved by callees).
  // Spill into caller-saved regs only after exhausting callee-saved regs.
  { free: [9, 10, 11, 12, 13, 14, 15, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28] }
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
  byref : Bool
  type_size : Int?
  type_align : Int?
}

///|
struct StaticLocalInfo {
  name : String
  ty : CType
}

///|
struct FieldAccessInfo {
  offset : Int
  ty : CType
  bit_offset : Int?
  bit_width : Int?
  bit_unit_size : Int?
}

///|
struct LocalAlloc {
  sem : SemContext
  ret_ty : CType
  mut ret_loc : Int?
  mut used_bytes : Int
  mut varargs_stack_size : Int
  scopes : Array[FastMap[Int, LocalSlot]]
  vla_scopes : Array[VlaScopeInfo]
  local_values : FastMap[String, LocalSlot]
  local_overrides : Array[Array[(String, LocalSlot?)]]
  local_id_values : FastMap[Int, LocalSlot]
  local_id_overrides : Array[Array[(Int, LocalSlot?)]]
  static_locals : FastMap[Int, StaticLocalInfo]
  func_name : String
  labels : LabelCtx
  compound_literal_slots : FastMap[Int, Int]
  mut agg_temp_offset : Int?
  mut agg_temp_size : Int
  mut agg_temp_align : Int
  mut sret_offset : Int?
}

///|
struct VlaScopeInfo {
  num : Int
  loc : Int
  locorig : Int
}

///|
fn new_local_alloc(
  sem : SemContext,
  ret_ty : CType,
  func_name : String,
  static_locals : FastMap[Int, StaticLocalInfo],
) -> LocalAlloc {
  {
    sem,
    ret_ty,
    ret_loc: None,
    used_bytes: 0,
    varargs_stack_size: 0,
    scopes: [],
    vla_scopes: [],
    local_values: fast_map_new(),
    local_overrides: [],
    local_id_values: fast_map_new(),
    local_id_overrides: [],
    static_locals,
    func_name,
    labels: new_label_ctx(),
    compound_literal_slots: fast_map_new(),
    agg_temp_offset: None,
    agg_temp_size: 0,
    agg_temp_align: 1,
    sret_offset: None,
  }
}

///|
fn new_local_alloc_with_compound_slots(
  sem : SemContext,
  ret_ty : CType,
  func_name : String,
  static_locals : FastMap[Int, StaticLocalInfo],
  compound_literal_slots : FastMap[Int, Int],
) -> LocalAlloc {
  {
    sem,
    ret_ty,
    ret_loc: None,
    used_bytes: 0,
    varargs_stack_size: 0,
    scopes: [],
    vla_scopes: [],
    local_values: fast_map_new(),
    local_overrides: [],
    local_id_values: fast_map_new(),
    local_id_overrides: [],
    static_locals,
    func_name,
    labels: new_label_ctx(),
    compound_literal_slots,
    agg_temp_offset: None,
    agg_temp_size: 0,
    agg_temp_align: 1,
    sret_offset: None,
  }
}

///|
fn cg_push_scope(alloc : LocalAlloc) -> Unit {
  alloc.scopes.push(fast_map_new())
  alloc.vla_scopes.push({ num: 0, loc: 0, locorig: 0 })
  alloc.local_overrides.push([])
  alloc.local_id_overrides.push([])
  push_scope(alloc.sem)
}

///|
fn cg_pop_scope(alloc : LocalAlloc) -> Unit {
  alloc.scopes.pop() |> ignore
  alloc.vla_scopes.pop() |> ignore
  if alloc.local_overrides.pop() is Some(overrides) {
    let mut i = overrides.length()
    while i > 0 {
      i = i - 1
      let (name, prev) = overrides[i]
      match prev {
        Some(slot) => alloc.local_values.set(name, slot)
        None => alloc.local_values.remove(name)
      }
    }
  }
  if alloc.local_id_overrides.pop() is Some(overrides) {
    let mut i = overrides.length()
    while i > 0 {
      i = i - 1
      let (id, prev) = overrides[i]
      match prev {
        Some(slot) => alloc.local_id_values.set(id, slot)
        None => alloc.local_id_values.remove(id)
      }
    }
  }
  pop_scope(alloc.sem)
}

///|
fn lookup_local(alloc : LocalAlloc, name : String, id : Int) -> LocalSlot? {
  if id > 0 {
    return alloc.local_id_values.get(id)
  }
  alloc.local_values.get(name)
}

///|
fn lookup_static_local(alloc : LocalAlloc, id : Int) -> StaticLocalInfo? {
  if id <= 0 {
    return None
  }
  alloc.static_locals.get(id)
}

///|
fn record_local_slot(
  alloc : LocalAlloc,
  name : String,
  id : Int,
  slot : LocalSlot,
) -> Unit {
  if id <= 0 {
    if alloc.local_overrides.length() == 0 {
      alloc.local_values.set(name, slot)
      return
    }
    let idx = alloc.local_overrides.length() - 1
    let overrides = alloc.local_overrides[idx]
    overrides.push((name, alloc.local_values.get(name)))
    alloc.local_overrides[idx] = overrides
    alloc.local_values.set(name, slot)
    return
  }
  if alloc.local_id_overrides.length() == 0 {
    alloc.local_id_values.set(id, slot)
    return
  }
  let idx = alloc.local_id_overrides.length() - 1
  let id_overrides = alloc.local_id_overrides[idx]
  id_overrides.push((id, alloc.local_id_values.get(id)))
  alloc.local_id_overrides[idx] = id_overrides
  alloc.local_id_values.set(id, slot)
}

///|
fn update_local_slot(
  alloc : LocalAlloc,
  name : String,
  id : Int,
  slot : LocalSlot,
) -> Unit {
  if id > 0 {
    alloc.local_id_values.set(id, slot)
  } else {
    alloc.local_values.set(name, slot)
  }
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
fn slot_type_size_align(
  alloc : LocalAlloc,
  slot : LocalSlot,
  loc : SrcLoc,
) -> (Int, Int)? {
  match (slot.type_size, slot.type_align) {
    (Some(size), Some(align)) => Some((size, align))
    _ => type_size_align_or_error(alloc.sem, slot.ty, loc)
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
fn arm64_add_imm(emitter : Arm64Emitter, dst : Int, src : Int, imm : Int) ->
  Unit {
  if imm < 0 || imm > 4095 {
    return
  }
  emit32(
    emitter,
    (0x91000000 : Int)
    .lor((imm << 10))
    .lor(src << 5)
    .lor(dst)
    .reinterpret_as_uint(),
  )
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
fn parse_hex_float_literal_value(text : String) -> Double? {
  let len = text.length()
  if len == 0 {
    return None
  }
  let mut sign : Double = 1.0
  let mut idx = 0
  let first = text[0]
  if first == 43 {
    idx = 1
  } else if first == 45 {
    sign = -1.0
    idx = 1
  }
  if idx + 2 > len {
    return None
  }
  if text[idx] != 48 {
    return None
  }
  let prefix = text[idx + 1]
  if prefix != 120 && prefix != 88 {
    return None
  }
  idx = idx + 2
  let mut p_index = -1
  let mut i = idx
  while i < len {
    let code = text[i]
    if code == 112 || code == 80 {
      p_index = i
      break
    }
    i = i + 1
  }
  if p_index < 0 {
    return None
  }
  let mantissa = slice_string(text, idx, p_index)
  let exp_str = slice_string(text, p_index + 1, len)
  if exp_str.length() == 0 {
    return None
  }
  let exp = try @strconv.parse_int(exp_str, base=10) catch {
    _ => return None
  } noraise {
    v => v
  }
  let mut int_value : Double = 0.0
  let mut frac_value : Double = 0.0
  let mut frac_scale : Double = 1.0
  let mut seen_dot = false
  let mut seen_digit = false
  let mut j = 0
  while j < mantissa.length() {
    let code = mantissa[j]
    if code == 46 {
      if seen_dot {
        return None
      }
      seen_dot = true
      j = j + 1
      continue
    }
    let digit = match hex_digit_value(code) {
      None => return None
      Some(v) => v
    }
    seen_digit = true
    if seen_dot {
      frac_scale = frac_scale / 16.0
      frac_value = frac_value + Double::from_int(digit) * frac_scale
    } else {
      int_value = int_value * 16.0 + Double::from_int(digit)
    }
    j = j + 1
  }
  if !seen_digit {
    return None
  }
  let mant = int_value + frac_value
  let scaled = @math.scalbn(mant, exp)
  Some(scaled * sign)
}

///|
fn parse_float_literal_bits(text : String, kind : CFloatKind) -> UInt64? {
  if !float_kind_supported(kind) {
    return None
  }
  match parse_float_literal_value(text) {
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
fn parse_float_literal_value(text : String) -> Double? {
  let trimmed = strip_float_literal_suffix(text)
  let parsed = try @strconv.parse_double(trimmed) catch {
    _ => None
  } noraise {
    v => Some(v)
  }
  match parsed {
    Some(v) => Some(v)
    None => parse_hex_float_literal_value(trimmed)
  }
}

///|
fn float_bits_from_double(kind : CFloatKind, value : Double) -> UInt64? {
  if !float_kind_supported(kind) {
    return None
  }
  if kind == CFloatKind::Float {
    let f = Float::from_double(value)
    Some(f.reinterpret_as_uint().to_uint64())
  } else {
    Some(value.reinterpret_as_uint64())
  }
}

///|
fn cast_float_value(kind : CFloatKind, value : Double) -> Double {
  if kind == CFloatKind::Float {
    Float::from_double(value).to_double()
  } else {
    value
  }
}

///|
fn eval_float_const_value(
  sem : SemContext,
  expr : Expr,
  loc : SrcLoc,
) -> Double? {
  match expr {
    Expr::FloatLit(value~, ..) => parse_float_literal_value(value)
    Expr::Unary(op=UnaryOp::Plus, expr=inner, ..) =>
      eval_float_const_value(sem, inner, loc)
    Expr::Unary(op=UnaryOp::Minus, expr=inner, ..) =>
      match eval_float_const_value(sem, inner, loc) {
        None => None
        Some(v) => Some(0.0 - v)
      }
    Expr::Binary(op=BinaryOp::Comma, left=_, right~, ..) =>
      eval_float_const_value(sem, right, loc)
    Expr::Binary(op=BinaryOp::Add, left~, right~, ..) =>
      match (eval_float_const_value(sem, left, loc), eval_float_const_value(sem, right, loc)) {
        (Some(lv), Some(rv)) => Some(lv + rv)
        _ => None
      }
    Expr::Binary(op=BinaryOp::Sub, left~, right~, ..) =>
      match (eval_float_const_value(sem, left, loc), eval_float_const_value(sem, right, loc)) {
        (Some(lv), Some(rv)) => Some(lv - rv)
        _ => None
      }
    Expr::Binary(op=BinaryOp::Mul, left~, right~, ..) =>
      match (eval_float_const_value(sem, left, loc), eval_float_const_value(sem, right, loc)) {
        (Some(lv), Some(rv)) => Some(lv * rv)
        _ => None
      }
    Expr::Binary(op=BinaryOp::Div, left~, right~, ..) =>
      match (eval_float_const_value(sem, left, loc), eval_float_const_value(sem, right, loc)) {
        (Some(lv), Some(rv)) => Some(lv / rv)
        _ => None
      }
    Expr::Cast(ty~, expr=inner, ..) => {
      let cast_ty = strip_top_qualifiers(ty)
      match float_kind_of_type(cast_ty) {
        Some(k_raw) => {
          let k = normalize_float_kind(k_raw)
          match eval_float_const_value(sem, inner, loc) {
            None => None
            Some(v) => Some(cast_float_value(k, v))
          }
        }
        None =>
          if is_int_like(cast_ty) {
            match eval_float_const_value(sem, inner, loc) {
              None => None
              Some(v) => Some(Double::from_int(v.to_int()))
            }
          } else {
            eval_float_const_value(sem, inner, loc)
          }
      }
    }
    _ =>
      match const_int_from_expr(sem, expr, loc) {
        None => None
        Some(v) => Some(Double::from_int(v))
      }
  }
}

///|
fn const_float_bits_from_expr(
  sem : SemContext,
  expr : Expr,
  kind : CFloatKind,
  loc : SrcLoc,
) -> UInt64? {
  match eval_float_const_value(sem, expr, loc) {
    None => None
    Some(v) => float_bits_from_double(kind, v)
  }
}

///|
fn alloc_local(
  alloc : LocalAlloc,
  name : String,
  id : Int,
  ty : CType,
  loc : SrcLoc,
) -> LocalSlot? {
  let (slot_size, slot_align, type_size, type_align) =
    match strip_top_qualifiers(ty) {
      CType::Array(size=None, size_expr=Some(_), ..) => (8, 8, None, None)
      _ =>
        match type_size_align_or_error(alloc.sem, ty, loc) {
          None => return None
          Some((size, align)) => (size, align, Some(size), Some(align))
        }
    }
  let aligned = align_up(alloc.used_bytes, slot_align)
  alloc.used_bytes = aligned + slot_size
  let offset = -(aligned + slot_size)
  let slot = {
    offset,
    ty,
    vla_size_offset: None,
    byref: false,
    type_size,
    type_align,
  }
  let idx = alloc.scopes.length() - 1
  let scope = alloc.scopes[idx]
  let already = id > 0 && scope.contains(id)
  if id > 0 {
    scope.set(id, slot)
  }
  if !already {
    record_local_slot(alloc, name, id, slot)
  } else {
    update_local_slot(alloc, name, id, slot)
  }
  record_local_binding(alloc.sem, id, ty)
  Some(slot)
}

///|
fn alloc_local_byref(
  alloc : LocalAlloc,
  name : String,
  id : Int,
  ty : CType,
) -> LocalSlot {
  let size = 8
  let align = 8
  let aligned = align_up(alloc.used_bytes, align)
  alloc.used_bytes = aligned + size
  let offset = -(aligned + size)
  let slot = {
    offset,
    ty,
    vla_size_offset: None,
    byref: true,
    type_size: None,
    type_align: None,
  }
  let idx = alloc.scopes.length() - 1
  let scope = alloc.scopes[idx]
  let already = id > 0 && scope.contains(id)
  if id > 0 {
    scope.set(id, slot)
  }
  if !already {
    record_local_slot(alloc, name, id, slot)
  } else {
    update_local_slot(alloc, name, id, slot)
  }
  record_local_binding(alloc.sem, id, ty)
  slot
}

///|
fn record_static_local_binding(alloc : LocalAlloc, decl : VarDecl) -> Unit {
  if decl.id <= 0 || current_local_scope_id(alloc.sem) == 0 {
    return
  }
  let ty = match alloc.static_locals.get(decl.id) {
    None => decl.ty
    Some(info) => info.ty
  }
  record_local_binding(alloc.sem, decl.id, ty)
}

///|
fn alloc_hidden_slot(alloc : LocalAlloc, size : Int, align : Int) -> Int {
  let aligned = align_up(alloc.used_bytes, align)
  alloc.used_bytes = aligned + size
  -(aligned + size)
}

///|
fn reserve_sret_slot(alloc : LocalAlloc, loc : SrcLoc, bag : DiagBag) -> Unit {
  if alloc.sret_offset is Some(_) {
    return
  }
  let ret_loc = cached_ret_loc(alloc, loc, bag)
  if ret_loc == 1 {
    let off = alloc_hidden_slot(alloc, 8, 8)
    alloc.sret_offset = Some(off)
  }
}

///|
fn cached_ret_loc(alloc : LocalAlloc, loc : SrcLoc, bag : DiagBag) -> Int {
  match alloc.ret_loc {
    Some(v) => v
    None => {
      let ret_loc = arm64_pcs(alloc.sem, 0, alloc.ret_ty, [], loc, bag).ret_loc
      alloc.ret_loc = Some(ret_loc)
      ret_loc
    }
  }
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
  cstrings : CstringPool,
  ty : CType,
  dst : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  match strip_top_qualifiers(ty) {
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
      return
    }
    _ => ()
  }

  if type_size_align(alloc.sem, ty, loc) is Some((size, _)) {
    arm64_movimm(emitter, dst.reinterpret_as_uint(), size.to_uint64())
    return
  }

  match strip_top_qualifiers(ty) {
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
  cstrings : CstringPool,
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

  if size_slot_offset is Some(off) {
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
  cstrings : CstringPool,
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
    let mut range_end : Int? = None
    if item.designators.length() > 0 {
      match item.designators[0] {
        InitDesignator::Index(expr~, ..) =>
          if const_i64_from_expr(expr) is Some(v) {
            idx = v.to_int()
            has_index = true
          }
        InitDesignator::IndexRange(start~, end~, ..) =>
          match (const_i64_from_expr(start), const_i64_from_expr(end)) {
            (Some(start_val), Some(end_val)) => {
              idx = start_val.to_int()
              has_index = true
              range_end = Some(end_val.to_int())
            }
            _ => ()
          }
        _ => ()
      }
    }
    let last_idx = range_end.unwrap_or(idx)
    if last_idx >= 0 && last_idx > max_index {
      max_index = last_idx
    }
    if has_index {
      if last_idx >= 0 {
        next_index = last_idx + 1
      }
    } else {
      next_index = next_index + 1
    }
  }
  if max_index < 0 { 0 } else { max_index + 1 }
}

///|
fn static_local_base_name(func_name : String, local_name : String, id : Int) -> String {
  let func_part = if func_name == "" { "anonymous" } else { func_name }
  "__local_static.\{func_part}.\{local_name}.\{id}"
}

///|
fn static_local_func_name(base_name : String) -> String? {
  let prefix = "__local_static."
  if !base_name.has_prefix(prefix) {
    return None
  }
  let start = prefix.length()
  let len = base_name.length()
  let mut i = start
  while i < len {
    if base_name[i] == 46 {
      return Some(base_name.view(start_offset=start, end_offset=i).to_string())
    }
    i = i + 1
  }
  None
}

///|
fn collect_static_local_decl(
  func_name : String,
  decl : VarDecl,
  locals : FastMap[Int, StaticLocalInfo],
  decls : Array[VarDecl],
  init_maps : FastMap[String, FastMap[Int, StaticLocalInfo]],
) -> Unit {
  if decl.storage != StorageClass::Static {
    return
  }
  let stripped = strip_top_qualifiers(decl.ty)
  match stripped {
    CType::Function(..) => return
    _ => ()
  }
  if decl.id <= 0 {
    return
  }
  if locals.contains(decl.id) {
    return
  }
  let mut decl_ty = decl.ty
  match stripped {
    CType::Array(elem=elem_ty, size=None, size_expr=None) =>
      match decl.init {
        Some(Initializer::Expr(expr=Expr::StringLit(length~, ..), ..)) =>
          if is_char_type(elem_ty) {
            decl_ty = apply_inferred_array_size(decl.ty, length)
          }
        Some(Initializer::List(items~, ..)) => {
          let len = infer_array_size_from_init_items(items)
          decl_ty = apply_inferred_array_size(decl.ty, len)
        }
        _ => ()
      }
    _ => ()
  }
  let base_name = static_local_base_name(func_name, decl.name, decl.id)
  locals.set(decl.id, { name: base_name, ty: decl_ty })
  init_maps.set(base_name, locals)
  decls.push({
    name: base_name,
    id: 0,
    ty: decl_ty,
    init: decl.init,
    storage: StorageClass::Static,
    attrs: decl.attrs,
    loc: decl.loc,
  })
}

///|
fn collect_static_locals_in_expr(
  func_name : String,
  expr : Expr,
  locals : FastMap[Int, StaticLocalInfo],
  decls : Array[VarDecl],
  init_maps : FastMap[String, FastMap[Int, StaticLocalInfo]],
) -> Unit {
  match expr {
    Expr::Unary(expr=inner, ..) =>
      collect_static_locals_in_expr(func_name, inner, locals, decls, init_maps)
    Expr::Cast(expr=inner, ..) =>
      collect_static_locals_in_expr(func_name, inner, locals, decls, init_maps)
    Expr::StmtExpr(stmts~, ..) =>
      for s in stmts {
        collect_static_locals_in_stmt(func_name, s, locals, decls, init_maps)
      }
    Expr::SizeofExpr(expr=inner, ..) =>
      collect_static_locals_in_expr(func_name, inner, locals, decls, init_maps)
    Expr::AlignofExpr(expr=inner, ..) =>
      collect_static_locals_in_expr(func_name, inner, locals, decls, init_maps)
    Expr::CompoundLiteral(init~, ..) =>
      collect_static_locals_in_initializer(func_name, init, locals, decls, init_maps)
    Expr::Binary(left~, right~, ..) => {
      collect_static_locals_in_expr(func_name, left, locals, decls, init_maps)
      collect_static_locals_in_expr(func_name, right, locals, decls, init_maps)
    }
    Expr::Conditional(cond~, then_expr~, else_expr~, ..) => {
      collect_static_locals_in_expr(func_name, cond, locals, decls, init_maps)
      collect_static_locals_in_expr(func_name, then_expr, locals, decls, init_maps)
      collect_static_locals_in_expr(func_name, else_expr, locals, decls, init_maps)
    }
    Expr::Call(callee~, args~, ..) => {
      collect_static_locals_in_expr(func_name, callee, locals, decls, init_maps)
      for a in args {
        collect_static_locals_in_expr(func_name, a, locals, decls, init_maps)
      }
    }
    Expr::Index(base~, index~, ..) => {
      collect_static_locals_in_expr(func_name, base, locals, decls, init_maps)
      collect_static_locals_in_expr(func_name, index, locals, decls, init_maps)
    }
    Expr::Member(base~, ..) =>
      collect_static_locals_in_expr(func_name, base, locals, decls, init_maps)
    Expr::BuiltinVaArg(list~, ..) =>
      collect_static_locals_in_expr(func_name, list, locals, decls, init_maps)
    _ => ()
  }
}

///|
fn collect_static_locals_in_initializer(
  func_name : String,
  init : Initializer,
  locals : FastMap[Int, StaticLocalInfo],
  decls : Array[VarDecl],
  init_maps : FastMap[String, FastMap[Int, StaticLocalInfo]],
) -> Unit {
  match init {
    Initializer::Expr(expr~, ..) =>
      collect_static_locals_in_expr(func_name, expr, locals, decls, init_maps)
    Initializer::List(items~, ..) =>
      for item in items {
        collect_static_locals_in_initializer(func_name, item.value, locals, decls, init_maps)
      }
  }
}

///|
fn collect_static_locals_in_stmt(
  func_name : String,
  stmt : Stmt,
  locals : FastMap[Int, StaticLocalInfo],
  decls : Array[VarDecl],
  init_maps : FastMap[String, FastMap[Int, StaticLocalInfo]],
) -> Unit {
  match stmt {
    Stmt::Compound(stmts~, ..) =>
      for s in stmts {
        collect_static_locals_in_stmt(func_name, s, locals, decls, init_maps)
      }
    Stmt::If(cond~, then_branch~, else_branch~, ..) => {
      collect_static_locals_in_expr(func_name, cond, locals, decls, init_maps)
      collect_static_locals_in_stmt(func_name, then_branch, locals, decls, init_maps)
      if else_branch is Some(s) {
        collect_static_locals_in_stmt(func_name, s, locals, decls, init_maps)
      }
    }
    Stmt::While(cond~, body~, ..) => {
      collect_static_locals_in_expr(func_name, cond, locals, decls, init_maps)
      collect_static_locals_in_stmt(func_name, body, locals, decls, init_maps)
    }
    Stmt::DoWhile(cond~, body~, ..) => {
      collect_static_locals_in_stmt(func_name, body, locals, decls, init_maps)
      collect_static_locals_in_expr(func_name, cond, locals, decls, init_maps)
    }
    Stmt::For(init~, cond~, step~, body~, ..) => {
      if init is Some(s) {
        collect_static_locals_in_stmt(func_name, s, locals, decls, init_maps)
      }
      if cond is Some(e) {
        collect_static_locals_in_expr(func_name, e, locals, decls, init_maps)
      }
      if step is Some(e) {
        collect_static_locals_in_expr(func_name, e, locals, decls, init_maps)
      }
      collect_static_locals_in_stmt(func_name, body, locals, decls, init_maps)
    }
    Stmt::Switch(cond~, body~, ..) => {
      collect_static_locals_in_expr(func_name, cond, locals, decls, init_maps)
      collect_static_locals_in_stmt(func_name, body, locals, decls, init_maps)
    }
    Stmt::Case(expr~, end_expr~, body~, ..) => {
      collect_static_locals_in_expr(func_name, expr, locals, decls, init_maps)
      if end_expr is Some(e) {
        collect_static_locals_in_expr(func_name, e, locals, decls, init_maps)
      }
      collect_static_locals_in_stmt(func_name, body, locals, decls, init_maps)
    }
    Stmt::Default(body~, ..) =>
      collect_static_locals_in_stmt(func_name, body, locals, decls, init_maps)
    Stmt::Label(body=body, ..) =>
      collect_static_locals_in_stmt(func_name, body, locals, decls, init_maps)
    Stmt::Return(value~, ..) =>
      if value is Some(expr) {
        collect_static_locals_in_expr(func_name, expr, locals, decls, init_maps)
      }
    Stmt::Asm(asm_stmt) => {
      for op in asm_stmt.outputs {
        collect_static_locals_in_expr(func_name, op.expr, locals, decls, init_maps)
      }
      for op in asm_stmt.inputs {
        collect_static_locals_in_expr(func_name, op.expr, locals, decls, init_maps)
      }
    }
    Stmt::ExprStmt(expr~, ..) =>
      collect_static_locals_in_expr(func_name, expr, locals, decls, init_maps)
    Stmt::DeclStmt(decls=items, ..) =>
      for d in items {
        collect_static_local_decl(func_name, d, locals, decls, init_maps)
      }
    Stmt::TagDef(..) | Stmt::StaticAssert(_) | Stmt::Empty(..) |
    Stmt::Goto(..) | Stmt::GotoExpr(..) | Stmt::Break(..) | Stmt::Continue(..) => ()
  }
}

///|
fn layout_stmt(alloc : LocalAlloc, stmt : Stmt, walk_exprs : Bool) -> Unit {
  match stmt {
    Stmt::Compound(stmts~, ..) => {
      let mut did_scope = false
      for s in stmts {
        if !did_scope && s is Stmt::DeclStmt(..) {
          cg_push_scope(alloc)
          did_scope = true
        }
        layout_stmt(alloc, s, walk_exprs)
      }
      if did_scope {
        cg_pop_scope(alloc)
      }
    }
    Stmt::DeclStmt(decls~, ..) => {
      for d in decls {
        let stripped = strip_top_qualifiers(d.ty)
        match stripped {
          CType::Function(..) => continue
          _ => ()
        }
        if d.storage == StorageClass::Extern {
          continue
        }
        if d.storage == StorageClass::Static {
          record_static_local_binding(alloc, d)
          continue
        }
        let mut decl_ty = d.ty
        match stripped {
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
        if alloc_local(alloc, d.name, d.id, decl_ty, d.loc) is Some(slot) {
          match strip_top_qualifiers(slot.ty) {
            CType::Array(size=None, size_expr=Some(_), ..) => {
              let size_off = alloc_hidden_slot(alloc, 8, 8)
              let updated = {
                offset: slot.offset,
                ty: slot.ty,
                vla_size_offset: Some(size_off),
                byref: slot.byref,
                type_size: slot.type_size,
                type_align: slot.type_align,
              }
              if d.id > 0 {
                let scope_idx = alloc.scopes.length() - 1
                alloc.scopes[scope_idx].set(d.id, updated)
              }
              update_local_slot(alloc, d.name, d.id, updated)
              vla_record_decl(alloc, slot.offset) |> ignore
            }
            _ => ()
          }
        }
        if d.init is Some(init) {
          layout_initializer(alloc, init, walk_exprs)
        }
      }
    }
    Stmt::If(cond~, then_branch~, else_branch~, ..) => {
      layout_expr(alloc, cond, walk_exprs)
      layout_stmt(alloc, then_branch, walk_exprs)
      if else_branch is Some(s) {
        layout_stmt(alloc, s, walk_exprs)
      }
    }
    Stmt::While(cond~, body~, ..) => {
      layout_expr(alloc, cond, walk_exprs)
      layout_stmt(alloc, body, walk_exprs)
    }
    Stmt::DoWhile(cond~, body~, ..) => {
      layout_stmt(alloc, body, walk_exprs)
      layout_expr(alloc, cond, walk_exprs)
    }
    Stmt::For(init~, cond~, step~, body~, ..) => {
      let needs_scope = match init {
        Some(Stmt::DeclStmt(..)) => true
        _ => false
      }
      if needs_scope {
        cg_push_scope(alloc)
      }
      if init is Some(s) {
        layout_stmt(alloc, s, walk_exprs)
      }
      if cond is Some(e) {
        layout_expr(alloc, e, walk_exprs)
      }
      if step is Some(e) {
        layout_expr(alloc, e, walk_exprs)
      }
      layout_stmt(alloc, body, walk_exprs)
      if needs_scope {
        cg_pop_scope(alloc)
      }
    }
    Stmt::Switch(cond~, body~, ..) => {
      layout_expr(alloc, cond, walk_exprs)
      layout_stmt(alloc, body, walk_exprs)
    }
    Stmt::Case(expr~, end_expr~, body~, ..) => {
      layout_expr(alloc, expr, walk_exprs)
      if end_expr is Some(e) {
        layout_expr(alloc, e, walk_exprs)
      }
      layout_stmt(alloc, body, walk_exprs)
    }
    Stmt::Default(body~, ..) => layout_stmt(alloc, body, walk_exprs)
    Stmt::Label(body=body, ..) => layout_stmt(alloc, body, walk_exprs)
    Stmt::Return(value~, ..) =>
      if value is Some(e) {
        layout_expr(alloc, e, walk_exprs)
      }
    Stmt::ExprStmt(expr~, ..) => layout_expr(alloc, expr, walk_exprs)
    Stmt::Asm(_) |
    Stmt::Goto(name=_, loc=_) |
    Stmt::GotoExpr(..) |
    Stmt::Break(_) |
    Stmt::Continue(_) |
    Stmt::TagDef(ty=_, loc=_) |
    Stmt::StaticAssert(_) |
    Stmt::Empty(_) => ()
  }
}

///|
fn layout_initializer(alloc : LocalAlloc, init : Initializer, walk_exprs : Bool) -> Unit {
  if !walk_exprs {
    return
  }
  match init {
    Initializer::Expr(expr~, ..) => layout_expr(alloc, expr, walk_exprs)
    Initializer::List(items~, ..) =>
      for item in items {
        layout_initializer(alloc, item.value, walk_exprs)
      }
  }
}

///|
fn reserve_compound_literal_slot(
  alloc : LocalAlloc,
  ty : CType,
  init : Initializer,
  loc : SrcLoc,
  node_id : Int,
) -> Unit {
  let key = compound_literal_key(node_id)
  if alloc.compound_literal_slots.get(key) is Some(_) {
    return
  }
  let resolved = compound_literal_type(alloc.sem, ty, init, loc, node_id)
  let size_align = match alloc.sem.compound_literal_sizes.get(key) {
    Some(value) => Some(value)
    None => type_size_align_or_error(alloc.sem, resolved, loc)
  }
  if size_align is Some((size, align)) {
    if size > 0 {
      let offset = alloc_hidden_slot(alloc, size, align)
      alloc.compound_literal_slots.set(key, offset)
    }
  }
}

///|
fn reserve_compound_literals_initializer(
  alloc : LocalAlloc,
  init : Initializer,
) -> Unit {
  match init {
    Initializer::Expr(expr~, ..) => reserve_compound_literals_expr(alloc, expr)
    Initializer::List(items~, ..) =>
      for item in items {
        reserve_compound_literals_initializer(alloc, item.value)
      }
  }
}

///|
fn reserve_compound_literals_expr(alloc : LocalAlloc, expr : Expr) -> Unit {
  match expr {
    Expr::CompoundLiteral(ty~, init~, node_id~, loc~, ..) => {
      reserve_compound_literal_slot(alloc, ty, init, loc, node_id)
      reserve_compound_literals_initializer(alloc, init)
    }
    Expr::Unary(expr=inner, ..) => reserve_compound_literals_expr(alloc, inner)
    Expr::Cast(expr=inner, ..) => reserve_compound_literals_expr(alloc, inner)
    Expr::SizeofExpr(..) | Expr::AlignofExpr(..) => ()
    Expr::Binary(left~, right~, ..) => {
      reserve_compound_literals_expr(alloc, left)
      reserve_compound_literals_expr(alloc, right)
    }
    Expr::Conditional(cond~, then_expr~, else_expr~, ..) => {
      reserve_compound_literals_expr(alloc, cond)
      reserve_compound_literals_expr(alloc, then_expr)
      reserve_compound_literals_expr(alloc, else_expr)
    }
    Expr::Call(callee~, args~, ..) => {
      reserve_compound_literals_expr(alloc, callee)
      for a in args {
        reserve_compound_literals_expr(alloc, a)
      }
    }
    Expr::StmtExpr(stmts~, ..) =>
      for s in stmts {
        reserve_compound_literals_stmt(alloc, s)
      }
    Expr::Index(base~, index~, ..) => {
      reserve_compound_literals_expr(alloc, base)
      reserve_compound_literals_expr(alloc, index)
    }
    Expr::Member(base~, ..) => reserve_compound_literals_expr(alloc, base)
    Expr::BuiltinVaArg(list~, ..) => reserve_compound_literals_expr(alloc, list)
    _ => ()
  }
}

///|
fn reserve_compound_literals_stmt(alloc : LocalAlloc, stmt : Stmt) -> Unit {
  match stmt {
    Stmt::Compound(stmts~, ..) =>
      for s in stmts {
        reserve_compound_literals_stmt(alloc, s)
      }
    Stmt::DeclStmt(decls~, ..) =>
      for d in decls {
        if d.init is Some(init) {
          reserve_compound_literals_initializer(alloc, init)
        }
      }
    Stmt::If(cond~, then_branch~, else_branch~, ..) => {
      reserve_compound_literals_expr(alloc, cond)
      reserve_compound_literals_stmt(alloc, then_branch)
      if else_branch is Some(s) {
        reserve_compound_literals_stmt(alloc, s)
      }
    }
    Stmt::While(cond~, body~, ..) => {
      reserve_compound_literals_expr(alloc, cond)
      reserve_compound_literals_stmt(alloc, body)
    }
    Stmt::DoWhile(cond~, body~, ..) => {
      reserve_compound_literals_stmt(alloc, body)
      reserve_compound_literals_expr(alloc, cond)
    }
    Stmt::For(init~, cond~, step~, body~, ..) => {
      if init is Some(s) {
        reserve_compound_literals_stmt(alloc, s)
      }
      if cond is Some(e) {
        reserve_compound_literals_expr(alloc, e)
      }
      if step is Some(e) {
        reserve_compound_literals_expr(alloc, e)
      }
      reserve_compound_literals_stmt(alloc, body)
    }
    Stmt::Switch(cond~, body~, ..) => {
      reserve_compound_literals_expr(alloc, cond)
      reserve_compound_literals_stmt(alloc, body)
    }
    Stmt::Case(expr~, end_expr~, body~, ..) => {
      reserve_compound_literals_expr(alloc, expr)
      if end_expr is Some(e) {
        reserve_compound_literals_expr(alloc, e)
      }
      reserve_compound_literals_stmt(alloc, body)
    }
    Stmt::Default(body~, ..) => reserve_compound_literals_stmt(alloc, body)
    Stmt::Label(body=body, ..) => reserve_compound_literals_stmt(alloc, body)
    Stmt::Return(value~, ..) =>
      if value is Some(e) {
        reserve_compound_literals_expr(alloc, e)
      }
    Stmt::Asm(stmt) => {
      for op in stmt.outputs {
        reserve_compound_literals_expr(alloc, op.expr)
      }
      for op in stmt.inputs {
        reserve_compound_literals_expr(alloc, op.expr)
      }
    }
    Stmt::ExprStmt(expr~, ..) => reserve_compound_literals_expr(alloc, expr)
    Stmt::TagDef(..) | Stmt::StaticAssert(_) | Stmt::Empty(..) | Stmt::Goto(..) |
    Stmt::GotoExpr(..) | Stmt::Break(..) | Stmt::Continue(..) => ()
  }
}

///|
fn layout_expr(alloc : LocalAlloc, expr : Expr, walk_exprs : Bool) -> Unit {
  if !walk_exprs {
    return
  }
  match expr {
    Expr::Unary(expr=inner, ..) => layout_expr(alloc, inner, walk_exprs)
    Expr::Cast(expr=inner, ..) => layout_expr(alloc, inner, walk_exprs)
    Expr::CompoundLiteral(init~, ..) => layout_initializer(alloc, init, walk_exprs)
    Expr::SizeofExpr(..) | Expr::AlignofExpr(..) => ()
    Expr::Binary(left~, right~, ..) => {
      layout_expr(alloc, left, walk_exprs)
      layout_expr(alloc, right, walk_exprs)
    }
    Expr::Conditional(cond~, then_expr~, else_expr~, ..) => {
      layout_expr(alloc, cond, walk_exprs)
      layout_expr(alloc, then_expr, walk_exprs)
      layout_expr(alloc, else_expr, walk_exprs)
    }
    Expr::Call(callee~, args~, ..) => {
      layout_expr(alloc, callee, walk_exprs)
      for a in args {
        layout_expr(alloc, a, walk_exprs)
      }
    }
    Expr::StmtExpr(stmts~, ..) => {
      let mut did_scope = false
      for s in stmts {
        if !did_scope && s is Stmt::DeclStmt(..) {
          cg_push_scope(alloc)
          did_scope = true
        }
        layout_stmt(alloc, s, walk_exprs)
      }
      if did_scope {
        cg_pop_scope(alloc)
      }
    }
    Expr::Index(base~, index~, ..) => {
      layout_expr(alloc, base, walk_exprs)
      layout_expr(alloc, index, walk_exprs)
    }
    Expr::Member(base~, ..) => layout_expr(alloc, base, walk_exprs)
    Expr::BuiltinVaArg(list~, ..) => layout_expr(alloc, list, walk_exprs)
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
fn emit_int_extend_to_64(
  emitter : Arm64Emitter,
  sem : SemContext,
  from_ty : CType,
  reg : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let (from_size, from_signed) = match scalar_size_signed_or_error(sem, from_ty, loc) {
    None => return
    Some(v) => v
  }
  if from_size >= 8 {
    return
  }
  let shift = (8 - from_size) * 8
  if shift <= 0 {
    return
  }
  if !arm64_gen_opic(
    emitter,
    TOK_SHL,
    1,
    false,
    shift.to_uint64(),
    reg,
    reg,
  ) {
    add_error(bag, loc, "codegen: unsupported integer extension")
    return
  }
  let tok = if from_signed { TOK_SAR } else { TOK_SHR }
  if !arm64_gen_opic(
    emitter,
    tok,
    1,
    false,
    shift.to_uint64(),
    reg,
    reg,
  ) {
    add_error(bag, loc, "codegen: unsupported integer extension")
  }
}

///|
fn emit_int_cast(
  emitter : Arm64Emitter,
  sem : SemContext,
  from_ty : CType,
  to_ty : CType,
  reg : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let (to_size, to_signed) = match scalar_size_signed_or_error(sem, to_ty, loc) {
    None => return
    Some(v) => v
  }
  if to_size >= 8 {
    emit_int_extend_to_64(emitter, sem, from_ty, reg, loc, bag)
    return
  }
  let shift = (8 - to_size) * 8
  if shift <= 0 {
    return
  }
  if !arm64_gen_opic(
    emitter,
    TOK_SHL,
    1,
    false,
    shift.to_uint64(),
    reg,
    reg,
  ) {
    add_error(bag, loc, "codegen: unsupported integer cast")
    return
  }
  let tok = if to_signed { TOK_SAR } else { TOK_SHR }
  if !arm64_gen_opic(
    emitter,
    tok,
    1,
    false,
    shift.to_uint64(),
    reg,
    reg,
  ) {
    add_error(bag, loc, "codegen: unsupported integer cast")
  }
}

///|
fn emit_cast_value(
  emitter : Arm64Emitter,
  sem : SemContext,
  from_ty : CType,
  to_ty : CType,
  reg : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let from_float = float_kind_of_type(from_ty)
  let to_float = float_kind_of_type(to_ty)
  match (from_float, to_float) {
    (Some(from_kind_raw), Some(to_kind_raw)) => {
      let from_kind = normalize_float_kind(from_kind_raw)
      let to_kind = normalize_float_kind(to_kind_raw)
      if from_kind == to_kind {
        return
      }
      if from_kind == CFloatKind::Float && to_kind == CFloatKind::Double {
        emit_fmov_w_to_s(emitter, 0, reg)
        emit32(emitter, (0x1e22c000 : UInt))
        emit_fmov_d_to_x(emitter, reg, 0)
      } else if from_kind == CFloatKind::Double && to_kind == CFloatKind::Float {
        emit_fmov_x_to_d(emitter, 0, reg)
        emit32(emitter, (0x1e624000 : UInt))
        emit_fmov_s_to_w(emitter, reg, 0)
      } else {
        add_error(bag, loc, "codegen: unsupported float conversion")
      }
    }
    (Some(from_kind_raw), None) => {
      if !is_int_like(to_ty) && !type_is_pointer_like(to_ty) {
        return
      }
      if !float_kind_supported(from_kind_raw) {
        add_error(bag, loc, "codegen: unsupported float type")
        return
      }
      if from_kind_raw == CFloatKind::Double {
        emit_fmov_x_to_d(emitter, 0, reg)
      } else {
        emit_fmov_w_to_s(emitter, 0, reg)
      }
      let to_unsigned = match strip_top_qualifiers_keep_attrs(to_ty) {
        CType::Int(unsigned~, ..) => unsigned
        _ => false
      }
      let is64 = match scalar_size_signed_or_error(sem, to_ty, loc) {
        None => false
        Some((size, _)) => size == 8
      }
      let mut inst : Int = 0x1e380000
      if to_unsigned {
        inst = inst.lor(0x00010000)
      }
      if is64 {
        inst = inst.lor(0x80000000)
      }
      if from_kind_raw != CFloatKind::Float {
        inst = inst.lor(0x00400000)
      }
      emit32(
        emitter,
        inst
        .lor(reg)
        .lor(0 << 5)
        .reinterpret_as_uint(),
      )
      emit_int_cast(emitter, sem, to_ty, to_ty, reg, loc, bag)
    }
    (None, Some(to_kind_raw)) => {
      if !float_kind_supported(to_kind_raw) {
        add_error(bag, loc, "codegen: unsupported float type")
        return
      }
      let is_unsigned = match strip_top_qualifiers_keep_attrs(from_ty) {
        CType::Int(unsigned~, ..) => unsigned
        _ => false
      }
      let from_size = match scalar_size_signed_or_error(sem, from_ty, loc) {
        None => return
        Some((size, _)) => size
      }
      let sf_bit : Int = if from_size == 8 { 0x80000000 } else { 0 }
      let norm_target = normalize_float_kind(to_kind_raw)
      if norm_target == CFloatKind::Float {
        let base : Int = if is_unsigned { 0x1e230000 } else { 0x1e220000 }
        emit32(
          emitter,
          base
          .lor(sf_bit)
          .lor(0)
          .lor(reg << 5)
          .reinterpret_as_uint(),
        )
        emit_fmov_s_to_w(emitter, reg, 0)
      } else {
        let base : Int = if is_unsigned { 0x1e630000 } else { 0x1e620000 }
        emit32(
          emitter,
          base
          .lor(sf_bit)
          .lor(0)
          .lor(reg << 5)
          .reinterpret_as_uint(),
        )
        emit_fmov_d_to_x(emitter, reg, 0)
      }
    }
    (None, None) =>
      if is_int_like(to_ty) || type_is_pointer_like(to_ty) {
        emit_int_cast(emitter, sem, from_ty, to_ty, reg, loc, bag)
      }
  }
}

///|
const ARM64_COND_EQ : Int = 0

///|
const ARM64_COND_NE : Int = 1

///|
const ARM64_COND_HS : Int = 2

///|
const ARM64_COND_LO : Int = 3

///|
const ARM64_COND_HI : Int = 8

///|
const ARM64_COND_LS : Int = 9

///|
const ARM64_COND_GE : Int = 10

///|
const ARM64_COND_LT : Int = 11

///|
const ARM64_COND_GT : Int = 12

///|
const ARM64_COND_LE : Int = 13

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
fn emit_cset(emitter : Arm64Emitter, cond : Int, dst : Int) -> Unit {
  let cond_inv = cond ^ 1
  emit32(
    emitter,
    (0x1a9f07e0 : Int)
    .lor(dst)
    .lor(cond_inv << 12)
    .reinterpret_as_uint(),
  )
}

///|
fn emit_cset_from_tok(
  emitter : Arm64Emitter,
  tok : Int,
  dst : Int,
  is_unsigned : Bool,
) -> Unit raise {
  let cond = match tok {
    TOK_EQ => ARM64_COND_EQ
    TOK_NE => ARM64_COND_NE
    TOK_LT => if is_unsigned { ARM64_COND_LO } else { ARM64_COND_LT }
    TOK_LE => if is_unsigned { ARM64_COND_LS } else { ARM64_COND_LE }
    TOK_GT => if is_unsigned { ARM64_COND_HI } else { ARM64_COND_GT }
    TOK_GE => if is_unsigned { ARM64_COND_HS } else { ARM64_COND_GE }
    _ => fail("codegen: unsupported comparison token")
  }
  emit_cset(emitter, cond, dst)
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
///|
fn float_kind_of_type(ty : CType) -> CFloatKind? {
  match strip_top_qualifiers(ty) {
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
  cstrings : CstringPool,
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
        gen_expr_to_float_kind_bits_with_type(
          emitter,
          alloc,
          syms,
          pool,
          cstrings,
          cond,
          cond_ty,
          k,
          tmp,
          bag,
        )
        if k == CFloatKind::Double {
          emit_fmov_x_to_d(emitter, 0, tmp)
          emit_fcmp_zero(emitter, true, 0)
        } else {
          emit_fmov_w_to_s(emitter, 0, tmp)
          emit_fcmp_zero(emitter, false, 0)
        }
      }
      None => {
        gen_expr_int32(
          emitter,
          alloc,
          syms,
          pool,
          cstrings,
          cond,
          tmp,
          bag,
          expr_ty=cond_ty,
        )
        let is64 = match scalar_size_signed_or_error(alloc.sem, cond_ty, expr_loc(cond)) {
          None => false
          Some((size, _)) => size == 8
        }
        emit_cmp(emitter, is64, tmp, 31)
      }
    }
  }
  give_reg(pool, tmp)
}

///|
fn float_kind_supported(kind : CFloatKind) -> Bool {
  kind == CFloatKind::Float || kind == CFloatKind::Double || kind == CFloatKind::LongDouble
}

///|
fn float_is_double(kind : CFloatKind) -> Bool {
  kind != CFloatKind::Float
}

///|
fn normalize_float_kind(kind : CFloatKind) -> CFloatKind {
  match kind {
    CFloatKind::LongDouble => CFloatKind::Double
    _ => kind
  }
}

///|
fn type_is_pointer_like(ty : CType) -> Bool {
  match ty {
    CType::Qualified(base~, ..) => type_is_pointer_like(base)
    CType::Attributed(base~, ..) => type_is_pointer_like(base)
    CType::Pointer(_) => true
    CType::Array(..) => true
    _ => false
  }
}

///|
fn type_is_aggregate(ty : CType) -> Bool {
  match ty {
    CType::Qualified(base~, ..) => type_is_aggregate(base)
    CType::Attributed(base~, ..) => type_is_aggregate(base)
    CType::Struct(..) => true
    CType::Union(..) => true
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
  let mut base = strip_top_qualifiers_keep_attrs(ty)
  while true {
    match base {
      CType::Attributed(base=inner, ..) => base = inner
      _ => break
    }
  }
  match base {
    CType::Bool => return Some((1, false))
    CType::Int(kind~, unsigned~) => return Some((int_size(kind), !unsigned))
    CType::Float(kind~) => return Some((float_size(kind), false))
    CType::Pointer(_) | CType::Function(..) => return Some((8, false))
    _ => ()
  }
  let (size, _) = match type_size_align_or_error(sem, ty, loc) {
    None => return None
    Some(v) => v
  }
  let signed = match strip_top_qualifiers_keep_attrs(ty) {
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
  emit_store_gp_regs_to_addr(
    emitter,
    (0 : Int),
    (1 : Int),
    size,
    base_reg,
    base_off,
    loc,
    bag,
  )
}

///|
fn emit_store_gp_regs_to_addr(
  emitter : Arm64Emitter,
  reg0 : Int,
  reg1 : Int,
  size : Int,
  base_reg : Int,
  base_off : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let emit_store_reg_bytes = fn(
    reg : Int,
    dst_reg : Int,
    dst_off : Int,
    len : Int,
  ) -> Unit {
    let mut off = 0
    if len <= 0 {
      return
    }
    if off + 8 <= len {
      arm64_strx(
        emitter,
        3,
        reg.reinterpret_as_uint(),
        dst_reg.reinterpret_as_uint(),
        (dst_off + off).to_int64().reinterpret_as_uint64(),
      )
      off = off + 8
    }
    if off + 4 <= len {
      arm64_strx(
        emitter,
        2,
        reg.reinterpret_as_uint(),
        dst_reg.reinterpret_as_uint(),
        (dst_off + off).to_int64().reinterpret_as_uint64(),
      )
      off = off + 4
    }
    if off + 2 <= len {
      arm64_strx(
        emitter,
        1,
        reg.reinterpret_as_uint(),
        dst_reg.reinterpret_as_uint(),
        (dst_off + off).to_int64().reinterpret_as_uint64(),
      )
      off = off + 2
    }
    while off < len {
      arm64_strx(
        emitter,
        0,
        reg.reinterpret_as_uint(),
        dst_reg.reinterpret_as_uint(),
        (dst_off + off).to_int64().reinterpret_as_uint64(),
      )
      off = off + 1
    }
  }
  if size <= 0 {
    return
  }
  if size <= 8 {
    emit_store_reg_bytes(reg0, base_reg, base_off, size)
    return
  }
  if size <= 16 {
    let rest = size - 8
    emit_store_reg_bytes(reg0, base_reg, base_off, 8)
    emit_store_reg_bytes(reg1, base_reg, base_off + 8, rest)
    return
  }
  add_error(bag, loc, "codegen: aggregate return >16 bytes not supported yet")
}

///|
fn gen_agg_expr_to_addr(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  expr : Expr,
  dst_reg : Int,
  dst_off : Int,
  ty : CType,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let (size, _) = match type_size_align_or_error(alloc.sem, ty, loc) {
    None => return
    Some(v) => v
  }
  if size <= 0 {
    return
  }
  match expr {
    Expr::Call(callee~, args~, ..) => {
      let ret_loc = arm64_pcs(alloc.sem, 0, ty, [], loc, bag).ret_loc
      if ret_loc == 1 {
        gen_call_expr_with_sret(
          emitter,
          alloc,
          syms,
          pool,
          cstrings,
          callee,
          args,
          dst_reg,
          dst_off,
          loc,
          bag,
        )
        return
      }
      gen_call_expr(emitter, alloc, syms, pool, cstrings, callee, args, loc, bag)
      if size <= 0 {
        return
      }
      if ret_loc == 16 {
        match arm64_hfa(alloc.sem, ty, loc, bag) {
          None => emit_store_agg_return_gp_to_addr(emitter, size, dst_reg, dst_off, loc, bag)
          Some((count, fsize)) => {
            let mut i = 0
            while i < count {
              let tmp = take_reg(pool) catch {
                err => {
                  add_error(bag, loc, err.to_string())
                  return
                }
              }
              if fsize == 8 {
                emit_fmov_d_to_x(emitter, tmp, i)
                arm64_strx(
                  emitter,
                  3,
                  tmp.reinterpret_as_uint(),
                  dst_reg.reinterpret_as_uint(),
                  (dst_off + i * 8).to_int64().reinterpret_as_uint64(),
                )
              } else {
                emit_fmov_s_to_w(emitter, tmp, i)
                arm64_strx(
                  emitter,
                  2,
                  tmp.reinterpret_as_uint(),
                  dst_reg.reinterpret_as_uint(),
                  (dst_off + i * 4).to_int64().reinterpret_as_uint64(),
                )
              }
              give_reg(pool, tmp)
              i = i + 1
            }
          }
        }
      } else {
        emit_store_agg_return_gp_to_addr(emitter, size, dst_reg, dst_off, loc, bag)
      }
    }
    Expr::Binary(op=BinaryOp::Assign, left~, right~, loc~, ..) => {
      let lhs_ty = type_of_expr(alloc.sem, left)
      match strip_top_qualifiers(lhs_ty) {
        CType::Struct(..) | CType::Union(..) => {
          let lhs_addr = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, left, lhs_addr, bag)
          gen_agg_expr_to_addr(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            right,
            lhs_addr,
            0,
            lhs_ty,
            loc,
            bag,
          )
          emit_copy_bytes(
            emitter,
            pool,
            lhs_addr,
            0,
            dst_reg,
            dst_off,
            size,
            loc,
            bag,
          )
          give_reg(pool, lhs_addr)
        }
        _ => add_error(bag, loc, "codegen: aggregate assignment expects record lhs")
      }
    }
    Expr::Cast(expr=inner, ..) =>
      gen_agg_expr_to_addr(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        inner,
        dst_reg,
        dst_off,
        ty,
        loc,
        bag,
      )
    Expr::IntLit(value~, loc~, ..) =>
      match parse_int64_literal(value) {
        Some(v) =>
          if v == 0 {
            emit_zero_bytes(emitter, dst_reg, dst_off, size)
          } else {
            add_error(bag, loc, "codegen: non-zero scalar for aggregate")
          }
        None => add_error(bag, loc, "codegen: invalid integer literal")
      }
    Expr::Binary(op=BinaryOp::Comma, left~, right~, ..) => {
      gen_expr_discard(emitter, alloc, syms, pool, cstrings, left, bag)
      gen_agg_expr_to_addr(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        right,
        dst_reg,
        dst_off,
        ty,
        loc,
        bag,
      )
    }
    Expr::Conditional(cond~, then_expr~, else_expr~, loc~, ..) => {
      gen_cond_expr_cmp_zero(emitter, alloc, syms, pool, cstrings, cond, bag)
      let br_else = emit_b_cond_placeholder(emitter, ARM64_COND_EQ)
      gen_agg_expr_to_addr(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        then_expr,
        dst_reg,
        dst_off,
        ty,
        loc,
        bag,
      )
      let br_end = gjmp(emitter, 0)
      let else_pc = emitter_pc(emitter)
      patch_b_cond(emitter, br_else, else_pc, ARM64_COND_EQ) catch {
        err => add_error(bag, loc, err.to_string())
      }
      gen_agg_expr_to_addr(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        else_expr,
        dst_reg,
        dst_off,
        ty,
        loc,
        bag,
      )
      let end_pc = emitter_pc(emitter)
      gsym_addr(emitter, br_end, end_pc) catch {
        err => add_error(bag, loc, err.to_string())
      }
    }
    Expr::StmtExpr(stmts~, loc~, ..) =>
      gen_stmt_expr_with(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        stmts,
        0,
        true,
        loc,
        bag,
        (expr, _) =>
          gen_agg_expr_to_addr(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            expr,
            dst_reg,
            dst_off,
            ty,
            loc,
            bag,
          ),
      )
    _ => {
      let src_addr = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, expr, src_addr, bag)
      emit_copy_bytes(
        emitter,
        pool,
        src_addr,
        0,
        dst_reg,
        dst_off,
        size,
        loc,
        bag,
      )
      give_reg(pool, src_addr)
    }
  }
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
  let mut current = strip_top_qualifiers(ty)
  let mut off = 0
  for des in designators {
    match des {
      InitDesignator::Index(expr~, loc=des_loc) =>
        match strip_top_qualifiers(current) {
          CType::Array(elem~, size~, ..) => {
            let idx = match const_int_from_expr(sem, expr, des_loc) {
              None => {
                add_error(bag, des_loc, "codegen: array designator must be constant")
                0
              }
              Some(v) => v
            }
            if size is Some(n) {
              if idx < 0 || idx >= n {
                add_error(bag, des_loc, "codegen: array designator out of bounds")
              }
            }
            let (elem_size, _) = match type_size_align_or_error(sem, elem, des_loc) {
              None => return None
              Some(v) => v
            }
            off = off + (idx * elem_size)
            current = strip_top_qualifiers(elem)
          }
          _ => {
            add_error(bag, des_loc, "codegen: array designator on non-array")
            return None
          }
        }
      InitDesignator::IndexRange(loc=des_loc, ..) => {
        add_error(bag, des_loc, "codegen: array range designator must be expanded")
        return None
      }
      InitDesignator::Field(name~, id~, loc=des_loc) =>
        match strip_top_qualifiers(current) {
          CType::Struct(name=tag, id=tag_id, fields=field_list, attrs=_) => {
            let fields = resolve_struct_fields(
              sem,
              tag,
              tag_id,
              field_list,
              is_union=false,
            )
            match fields {
              None => {
                add_error(bag, des_loc, "codegen: incomplete struct '\{tag}'")
                return None
              }
              Some(_) => ()
            }
            match record_field_access_info(sem, current, name, id, des_loc) {
              None => {
                add_error(bag, des_loc, "codegen: unknown field '\{name}'")
                return None
              }
              Some(info) => {
                off = off + info.offset
                current = strip_top_qualifiers(info.ty)
              }
            }
          }
          CType::Union(name=tag, id=tag_id, fields=field_list, attrs=_) => {
            let fields = resolve_struct_fields(
              sem,
              tag,
              tag_id,
              field_list,
              is_union=true,
            )
            match fields {
              None => {
                add_error(bag, des_loc, "codegen: incomplete union '\{tag}'")
                return None
              }
              Some(_) => ()
            }
            match record_field_access_info(sem, current, name, id, des_loc) {
              None => {
                add_error(bag, des_loc, "codegen: unknown field '\{name}'")
                return None
              }
              Some(info) => {
                off = off + info.offset
                current = strip_top_qualifiers(info.ty)
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
fn designators_with_range_index(
  designators : Array[InitDesignator],
  idx : Int,
) -> Array[InitDesignator] {
  let result : Array[InitDesignator] = Array::new(capacity=designators.length())
  let mut replaced = false
  for des in designators {
    match des {
      InitDesignator::IndexRange(loc=des_loc, ..) =>
        if !replaced {
          let expr =
            Expr::IntLit(value=idx.to_string(), node_id=0, loc=des_loc)
          result.push(InitDesignator::Index(expr=expr, loc=des_loc))
          replaced = true
        } else {
          result.push(des)
        }
      _ => result.push(des)
    }
  }
  result
}

///|
fn resolve_init_designator_access_info(
  sem : SemContext,
  ty : CType,
  designators : Array[InitDesignator],
  loc : SrcLoc,
  bag : DiagBag,
) -> FieldAccessInfo? {
  if designators.length() == 0 {
    add_error(bag, loc, "codegen: missing designator")
    return None
  }
  let mut current = strip_top_qualifiers(ty)
  let mut off = 0
  let mut result_ty = ty
  let mut bit_off : Int? = None
  let mut bit_width : Int? = None
  let mut bit_unit_size : Int? = None
  for i = 0; i < designators.length(); i = i + 1 {
    let des = designators[i]
    let is_last = i == designators.length() - 1
    match des {
      InitDesignator::Index(expr~, loc=des_loc) =>
        match strip_top_qualifiers(current) {
          CType::Array(elem~, size~, ..) => {
            let idx = match const_int_from_expr(sem, expr, des_loc) {
              None => {
                add_error(bag, des_loc, "codegen: array designator must be constant")
                0
              }
              Some(v) => v
            }
            if size is Some(n) {
              if idx < 0 || idx >= n {
                add_error(bag, des_loc, "codegen: array designator out of bounds")
              }
            }
            let (elem_size, _) = match type_size_align_or_error(sem, elem, des_loc) {
              None => return None
              Some(v) => v
            }
            off = off + (idx * elem_size)
            current = strip_top_qualifiers(elem)
            result_ty = elem
            bit_off = None
            bit_width = None
            bit_unit_size = None
          }
          _ => {
            add_error(bag, des_loc, "codegen: array designator on non-array")
            return None
          }
        }
      InitDesignator::IndexRange(loc=des_loc, ..) => {
        add_error(bag, des_loc, "codegen: array range designator must be expanded")
        return None
      }
      InitDesignator::Field(name~, id~, loc=des_loc) =>
        match strip_top_qualifiers(current) {
          CType::Struct(..) | CType::Union(..) => {
            match record_field_access_info(sem, current, name, id, des_loc) {
              None => {
                add_error(bag, des_loc, "codegen: unknown field '\{name}'")
                return None
              }
              Some(info) => {
                off = off + info.offset
                result_ty = info.ty
                if is_last {
                  bit_off = info.bit_offset
                  bit_width = info.bit_width
                  bit_unit_size = info.bit_unit_size
                } else {
                  if info.bit_width is Some(_) {
                    add_error(bag, des_loc, "codegen: designator into bitfield")
                    return None
                  }
                  bit_off = None
                  bit_width = None
                  bit_unit_size = None
                }
                current = strip_top_qualifiers(info.ty)
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
  Some({
    offset: off,
    ty: result_ty,
    bit_offset: bit_off,
    bit_width: bit_width,
    bit_unit_size: bit_unit_size,
  })
}

///|
fn gen_string_init_to_addr(
  emitter : Arm64Emitter,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  value : String,
  length : Int,
  dst_reg : Int,
  dst_off : Int,
  bag : DiagBag,
  loc : SrcLoc,
) -> Unit {
  let sym = cstring_sym_or_add(cstrings, syms, value)
  let src_reg = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      return
    }
  }
  emit_addr_global(emitter, syms, sym, src_reg)
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
fn array_len_from_type_for_init(
  sem : SemContext,
  ty : CType,
  loc : SrcLoc,
) -> Int? {
  match strip_top_qualifiers(ty) {
    CType::Array(size=Some(n), ..) => Some(n)
    CType::Array(size=None, size_expr=Some(expr), ..) =>
      match const_int_from_expr(sem, expr, loc) {
        Some(v) if v >= 0 => Some(v)
        _ => None
      }
    _ => None
  }
}

///|
fn collect_elided_array_items_codegen(
  items : Array[InitItem],
  start : Int,
  max_count : Int?,
) -> (Array[InitItem], Int) {
  let limit = match max_count {
    None => items.length()
    Some(n) => if n < 0 { 0 } else { start + n }
  }
  let max_items = if limit <= start { 0 } else { limit - start }
  let collected : Array[InitItem] = Array::new(capacity=max_items)
  let mut idx = start
  while idx < items.length() && idx < limit {
    let item = items[idx]
    if item.designators.length() > 0 {
      break
    }
    collected.push({
      designators: [],
      value: item.value,
      loc: item.loc,
    })
    idx = idx + 1
  }
  (collected, idx - start)
}

///|
fn has_single_init_field_codegen(sem : SemContext, ty : CType) -> Bool {
  match strip_top_qualifiers(ty) {
    CType::Struct(name=tag, id=tag_id, fields=field_list, attrs=_) => {
      let fields = resolve_struct_fields(
        sem,
        tag,
        tag_id,
        field_list,
        is_union=false,
      )
      match fields {
        None => false
        Some(list) =>
          match next_init_field(list, 0) {
            None => false
            Some((_, next_idx)) => next_init_field(list, next_idx) is None
          }
      }
    }
    CType::Union(name=tag, id=tag_id, fields=field_list, attrs=_) => {
      let fields = resolve_struct_fields(
        sem,
        tag,
        tag_id,
        field_list,
        is_union=true,
      )
      match fields {
        None => false
        Some(list) =>
          match next_init_field(list, 0) {
            None => false
            Some((_, next_idx)) => next_init_field(list, next_idx) is None
          }
      }
    }
    _ => false
  }
}

///|
fn gen_initializer_to_addr(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  base_reg : Int,
  base_off : Int,
  ty : CType,
  init : Initializer,
  bag : DiagBag,
) -> Unit {
  match init {
    Initializer::Expr(expr~, loc~) =>
      match strip_top_qualifiers(ty) {
        CType::Array(elem~, ..) =>
          if try_eval_int_const(alloc.sem, expr) is Some(0) {
            match array_len_from_type_for_init(alloc.sem, ty, loc) {
              None => add_error(bag, loc, "codegen: incomplete array type")
              Some(n) => {
                let (elem_size, _) = match type_size_align_or_error(alloc.sem, elem, loc) {
                  None => return
                  Some(v) => v
                }
                if elem_size > 0 {
                  emit_zero_bytes(emitter, base_reg, base_off, n * elem_size)
                }
              }
            }
          } else {
            match expr {
              Expr::StringLit(value=value, length=length, ..) =>
                if is_char_type(elem) {
                  match array_len_from_type_for_init(alloc.sem, ty, loc) {
                    None => add_error(bag, loc, "codegen: incomplete array type")
                    Some(n) => {
                      let copy_len = if length > n { n } else { length }
                      gen_string_init_to_addr(
                        emitter,
                        syms,
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
          }
        CType::Struct(..) | CType::Union(..) => {
          let (size, _) = match type_size_align_or_error(alloc.sem, ty, loc) {
            None => return
            Some(v) => v
          }
          if size <= 0 {
            return
          }
          gen_agg_expr_to_addr(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            expr,
            base_reg,
            base_off,
            ty,
            loc,
            bag,
          )
        }
        _ => {
          let expr_ty = type_of_expr(alloc.sem, expr)
          gen_expr_any_with_type(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            expr,
            expr_ty,
            0,
            bag,
          )
          emit_cast_value(emitter, alloc.sem, expr_ty, ty, 0, loc, bag)
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
      match strip_top_qualifiers(ty) {
        CType::Array(elem=elem_ty, ..) => {
          let n = match array_len_from_type_for_init(alloc.sem, ty, loc) {
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
            let mut range_pos = -1
            let mut range_start : Int? = None
            let mut range_end : Int? = None
            let mut range_loc = item.loc
            if item.designators.length() > 0 {
              match item.designators[0] {
                InitDesignator::Index(expr~, loc=des_loc) =>
                  if const_int_from_expr(alloc.sem, expr, des_loc) is Some(v) {
                    idx = v
                    has_index = true
                    if idx < 0 || idx >= n {
                      add_error(bag, des_loc, "codegen: array designator out of bounds")
                    }
                  }
                InitDesignator::IndexRange(start~, end~, loc=des_loc) =>
                  match (
                    const_int_from_expr(alloc.sem, start, des_loc),
                    const_int_from_expr(alloc.sem, end, des_loc),
                  ) {
                    (Some(start_val), Some(end_val)) => {
                      idx = start_val
                      has_index = true
                      range_start = Some(start_val)
                      range_end = Some(end_val)
                      range_loc = des_loc
                      if idx < 0 || idx >= n {
                        add_error(bag, des_loc, "codegen: array designator out of bounds")
                      }
                    }
                    _ => {
                      add_error(
                        bag,
                        des_loc,
                        "codegen: array designator must be constant",
                      )
                    }
                  }
                _ => ()
              }
              let mut i = 0
              while i < item.designators.length() {
                match item.designators[i] {
                  InitDesignator::IndexRange(start~, end~, loc=des_loc) => {
                    range_pos = i
                    range_loc = des_loc
                    if range_start is None {
                        range_start = const_int_from_expr(alloc.sem, start, des_loc)
                        range_end = const_int_from_expr(alloc.sem, end, des_loc)
                    }
                    break
                  }
                  _ => ()
                }
                i = i + 1
              }
            }
            if range_pos >= 0 {
              if range_pos != item.designators.length() - 1 {
                add_error(bag, range_loc, "codegen: array range designator must be last")
              } else {
                match (range_start, range_end) {
                  (Some(start_idx), Some(end_idx)) => {
                    if end_idx < start_idx {
                      add_error(bag, range_loc, "codegen: array designator range is empty")
                    } else {
                      if range_pos == 0 &&
                        (start_idx < 0 || end_idx < 0 || start_idx >= n || end_idx >= n) {
                        add_error(bag, range_loc, "codegen: array designator out of bounds")
                      }
                      let mut cur = start_idx
                      while cur <= end_idx {
                        if range_pos == 0 && (cur < 0 || cur >= n) {
                          cur = cur + 1
                          continue
                        }
                        let designators = designators_with_range_index(
                          item.designators,
                          cur,
                        )
                        let (target_ty, rel_off) = match resolve_init_designator_offset_type(
                          alloc.sem,
                          ty,
                          designators,
                          item.loc,
                          bag,
                        ) {
                          None => (elem_ty, cur * elem_size)
                          Some((t, o)) => (t, o)
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
                        cur = cur + 1
                      }
                    }
                  }
                  _ =>
                    add_error(
                      bag,
                      range_loc,
                      "codegen: array designator must be constant",
                    )
                }
              }
              if range_pos == 0 {
                match range_end {
                  Some(end_idx) if end_idx >= 0 => next_index = end_idx + 1
                  _ => ()
                }
              } else if has_index {
                if idx >= 0 {
                  next_index = idx + 1
                }
              } else {
                next_index = next_index + 1
              }
              continue
            }
            if !has_index {
              if idx >= n {
                // TCC accepts excess array initializers and truncates them.
                continue
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
        CType::Struct(name=tag, id=tag_id, fields=field_list, attrs=_) => {
          let fields = resolve_struct_fields(
            alloc.sem,
            tag,
            tag_id,
            field_list,
            is_union=false,
          )
          let list = match fields {
            None => {
              add_error(bag, loc, "codegen: incomplete struct '\{tag}'")
              return
            }
            Some(v) => v
          }
          let mut index = 0
          let mut item_idx = 0
          while item_idx < items.length() {
            let item = items[item_idx]
            if item.designators.length() > 0 {
              match item.designators[0] {
                InitDesignator::Field(name~, id~, ..) =>
                  if find_field_index_cached(alloc.sem, ty, name, id, item.loc) is Some(idx) {
                    index = idx + 1
                  }
                _ => ()
              }
              if resolve_init_designator_access_info(
                alloc.sem,
                ty,
                item.designators,
                item.loc,
                bag,
              ) is Some(info) {
                match info.bit_width {
                  Some(_) => {
                    let info_at = {
                      offset: base_off + info.offset,
                      ty: info.ty,
                      bit_offset: info.bit_offset,
                      bit_width: info.bit_width,
                      bit_unit_size: info.bit_unit_size,
                    }
                    match item.value {
                      Initializer::Expr(expr~, ..) => {
                        let tmp = take_reg(pool) catch {
                          err => {
                            add_error(bag, item.loc, err.to_string())
                            return
                          }
                        }
                        gen_expr_int32(
                          emitter,
                          alloc,
                          syms,
                          pool,
                          cstrings,
                          expr,
                          tmp,
                          bag,
                        )
                        emit_bitfield_store(
                          emitter,
                          alloc,
                          pool,
                          base_reg,
                          info_at,
                          tmp,
                          item.loc,
                          bag,
                        )
                        give_reg(pool, tmp)
                      }
                      _ => add_error(bag, item.loc, "codegen: bitfield initializer must be scalar")
                    }
                  }
                  None =>
                    gen_initializer_to_addr(
                      emitter,
                      alloc,
                      syms,
                      pool,
                      cstrings,
                      base_reg,
                      base_off + info.offset,
                      info.ty,
                      item.value,
                      bag,
                    )
                }
              }
              item_idx = item_idx + 1
            } else {
              match next_init_field(list, index) {
                None => {
                  add_error(bag, item.loc, "codegen: too many initializers for aggregate")
                  item_idx = item_idx + 1
                }
                Some((field, next_idx)) => {
                  let field_off =
                    if field.bit_width is Some(_) {
                      0
                    } else {
                      match eval_builtin_offsetof(alloc.sem, ty, [field.name], item.loc) {
                        None => 0
                        Some(v) => v
                      }
                    }
                  let mut consumed = 1
                  let mut used_elision = false
                  match (strip_top_qualifiers(field.ty), item.value) {
                    (CType::Array(..), Initializer::Expr(expr~, ..)) =>
                      match expr {
                        Expr::StringLit(..) => ()
                        _ => {
                          let n = array_len_from_type_for_init(alloc.sem, field.ty, item.loc)
                          let (elided_items, count) = collect_elided_array_items_codegen(items, item_idx, n)
                          let init = Initializer::List(items=elided_items, loc=item.loc)
                          gen_initializer_to_addr(
                            emitter,
                            alloc,
                            syms,
                            pool,
                            cstrings,
                            base_reg,
                            base_off + field_off,
                            field.ty,
                            init,
                            bag,
                          )
                          consumed = count
                          used_elision = true
                        }
                      }
                    (CType::Struct(..) | CType::Union(..), Initializer::Expr(..)) =>
                      if has_single_init_field_codegen(alloc.sem, field.ty) {
                        let init = Initializer::List(
                          items=[{
                            designators: [],
                            value: item.value,
                            loc: item.loc,
                          }],
                          loc=item.loc,
                        )
                        gen_initializer_to_addr(
                          emitter,
                          alloc,
                          syms,
                          pool,
                          cstrings,
                          base_reg,
                          base_off + field_off,
                          field.ty,
                          init,
                          bag,
                        )
                        used_elision = true
                      }
                    _ => ()
                  }
                  if !used_elision {
                    if field.bit_width is Some(_) {
                      match record_field_access_info(
                        alloc.sem,
                        ty,
                        field.name,
                        field.id,
                        item.loc,
                      ) {
                        None => add_error(bag, item.loc, "codegen: missing bitfield info")
                        Some(info) => {
                          let info_at = {
                            offset: base_off + info.offset,
                            ty: info.ty,
                            bit_offset: info.bit_offset,
                            bit_width: info.bit_width,
                            bit_unit_size: info.bit_unit_size,
                          }
                          match item.value {
                            Initializer::Expr(expr~, ..) => {
                              let tmp = take_reg(pool) catch {
                                err => {
                                  add_error(bag, item.loc, err.to_string())
                                  return
                                }
                              }
                              gen_expr_int32(
                                emitter,
                                alloc,
                                syms,
                                pool,
                                cstrings,
                                expr,
                                tmp,
                                bag,
                              )
                              emit_bitfield_store(
                                emitter,
                                alloc,
                                pool,
                                base_reg,
                                info_at,
                                tmp,
                                item.loc,
                                bag,
                              )
                              give_reg(pool, tmp)
                            }
                            _ =>
                              add_error(bag, item.loc, "codegen: bitfield initializer must be scalar")
                          }
                        }
                      }
                    } else {
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
                    }
                  }
                  index = next_idx
                  item_idx = item_idx + consumed
                }
              }
            }
          }
        }
        CType::Union(name=tag, id=tag_id, fields=field_list, attrs=_) => {
          let fields = resolve_struct_fields(
            alloc.sem,
            tag,
            tag_id,
            field_list,
            is_union=true,
          )
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
            if resolve_init_designator_access_info(
              alloc.sem,
              ty,
              first.designators,
              first.loc,
              bag,
            ) is Some(info) {
              match info.bit_width {
                Some(_) => {
                  let info_at = {
                    offset: base_off + info.offset,
                    ty: info.ty,
                    bit_offset: info.bit_offset,
                    bit_width: info.bit_width,
                    bit_unit_size: info.bit_unit_size,
                  }
                  match first.value {
                    Initializer::Expr(expr~, ..) => {
                      let tmp = take_reg(pool) catch {
                        err => {
                          add_error(bag, first.loc, err.to_string())
                          return
                        }
                      }
                      gen_expr_int32(
                        emitter,
                        alloc,
                        syms,
                        pool,
                        cstrings,
                        expr,
                        tmp,
                        bag,
                      )
                      emit_bitfield_store(
                        emitter,
                        alloc,
                        pool,
                        base_reg,
                        info_at,
                        tmp,
                        first.loc,
                        bag,
                      )
                      give_reg(pool, tmp)
                    }
                    _ =>
                      add_error(bag, first.loc, "codegen: bitfield initializer must be scalar")
                  }
                }
                None =>
                  gen_initializer_to_addr(
                    emitter,
                    alloc,
                    syms,
                    pool,
                    cstrings,
                    base_reg,
                    base_off + info.offset,
                    info.ty,
                    first.value,
                    bag,
                  )
              }
            }
          } else if list.length() > 0 {
            let field = list[0]
            if field.bit_width is Some(_) {
              match record_field_access_info(
                alloc.sem,
                ty,
                field.name,
                field.id,
                first.loc,
              ) {
                None => add_error(bag, first.loc, "codegen: missing bitfield info")
                Some(info) => {
                  let info_at = {
                    offset: base_off + info.offset,
                    ty: info.ty,
                    bit_offset: info.bit_offset,
                    bit_width: info.bit_width,
                    bit_unit_size: info.bit_unit_size,
                  }
                  match first.value {
                    Initializer::Expr(expr~, ..) => {
                      let tmp = take_reg(pool) catch {
                        err => {
                          add_error(bag, first.loc, err.to_string())
                          return
                        }
                      }
                      gen_expr_int32(
                        emitter,
                        alloc,
                        syms,
                        pool,
                        cstrings,
                        expr,
                        tmp,
                        bag,
                      )
                      emit_bitfield_store(
                        emitter,
                        alloc,
                        pool,
                        base_reg,
                        info_at,
                        tmp,
                        first.loc,
                        bag,
                      )
                      give_reg(pool, tmp)
                    }
                    _ =>
                      add_error(bag, first.loc, "codegen: bitfield initializer must be scalar")
                  }
                }
              }
            } else {
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
        }
        _ => add_error(bag, loc, "codegen: initializer list for non-aggregate")
      }
  }
}

///|
struct SymTable {
  names : Array[String]
  name_to_id : FastMap[String, Int]
  externals : FastMap[Int, Bool]
  link_cache : FastMap[String, String]
  ident_syms : Array[Sym?]
  call_layout_cache : Array[Arm64PcsLayout?]
}

///|
fn new_symtab_with_capacity(capacity : Int) -> SymTable {
  let cap = if capacity > 0 { capacity } else { 0 }
  {
    names: Array::new(capacity=cap),
    name_to_id: fast_map_new(capacity=cap),
    externals: fast_map_new(capacity=cap),
    link_cache: fast_map_new(capacity=cap),
    ident_syms: Array::new(capacity=cap),
    call_layout_cache: Array::new(capacity=cap),
  }
}

///|
fn ensure_ident_syms_capacity(tab : SymTable, id : Int) -> Unit {
  if id <= 0 {
    return
  }
  let idx = id - 1
  let len = tab.ident_syms.length()
  if idx < len {
    return
  }
  let mut i = len
  while i <= idx {
    tab.ident_syms.push(None)
    i = i + 1
  }
}

///|
fn ensure_call_layout_capacity(tab : SymTable, id : Int) -> Unit {
  if id <= 0 {
    return
  }
  let idx = id - 1
  let len = tab.call_layout_cache.length()
  if idx < len {
    return
  }
  let mut i = len
  while i <= idx {
    tab.call_layout_cache.push(None)
    i = i + 1
  }
}

///|
fn sym_for_name(tab : SymTable, name : String) -> Sym {
  match tab.name_to_id.get(name) {
    Some(id) => Sym::{ id }
    None => {
      let id = tab.names.length() + 1
      tab.names.push(name)
      tab.name_to_id.set(name, id)
      tab.externals.set(id, true)
      Sym::{ id }
    }
  }
}

///|
fn sym_for_static_local(syms : SymTable, info : StaticLocalInfo) -> Sym {
  sym_for_name(syms, link_name(info.name))
}

///|
fn link_name(name : String) -> String {
  "_\{name}"
}

///|
fn sym_for_ident(tab : SymTable, name : String, id? : Int = 0) -> Sym {
  if id > 0 {
    ensure_ident_syms_capacity(tab, id)
    let idx = id - 1
    match tab.ident_syms[idx] {
      Some(sym) => sym
      None => {
        let link = link_name(name)
        let sym = sym_for_name(tab, link)
        tab.ident_syms[idx] = Some(sym)
        sym
      }
    }
  } else {
    match tab.link_cache.get(name) {
      Some(link) => sym_for_name(tab, link)
      None => {
        let link = link_name(name)
        tab.link_cache.set(name, link)
        sym_for_name(tab, link)
      }
    }
  }
}

///|
fn sym_is_external(syms : SymTable, sym : Sym) -> Bool {
  match syms.externals.get(sym.id) {
    Some(v) => v
    None => true
  }
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
fn emit_addr_global(
  emitter : Arm64Emitter,
  syms : SymTable,
  sym : Sym,
  dst : Int,
) -> Unit {
  if sym_is_external(syms, sym) {
    let ind0 = emitter_pc(emitter)
    greloca(emitter, sym, ind0, R_AARCH64_ADR_GOT_PAGE, 0)
    emit32(emitter, (0x90000000 : UInt64).lor(dst.to_uint64()).to_uint())
    let ind1 = emitter_pc(emitter)
    greloca(emitter, sym, ind1, R_AARCH64_LD64_GOT_LO12_NC, 0)
    emit32(
      emitter,
      (0xf9400000 : UInt64)
      .lor(dst.to_uint64())
      .lor(dst.to_uint64() << 5)
      .to_uint(),
    )
  } else {
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
}

///|
fn emit_addr_sp(
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
        .lor(31 << 5)
        .lor(imm << 10)
        .reinterpret_as_uint(),
      )
    } else {
      arm64_add_imm(emitter, dst, 31, imm)
    }
  } else {
    arm64_movimm(emitter, dst.reinterpret_as_uint(), imm.to_uint64())
    let base : Int = if off < 0 { 0xcb000000 } else { 0x8b000000 }
    emit32(
      emitter,
      (base : Int)
      .lor(dst)
      .lor(31 << 5)
      .lor(dst << 16)
      .reinterpret_as_uint(),
    )
  }
}

///|
fn emit_addr_reg(
  emitter : Arm64Emitter,
  dst : Int,
  base_reg : Int,
  off : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  if base_reg == 29 {
    emit_addr_local(emitter, dst, off, loc, bag)
    return
  }
  if base_reg == 31 {
    emit_addr_sp(emitter, dst, off, loc, bag)
    return
  }
  let imm = if off < 0 { -off } else { off }
  if imm <= 0xfff {
    let base : Int = if off < 0 { 0xd1000000 } else { 0x91000000 }
    emit32(
      emitter,
      (base : Int)
      .lor(dst)
      .lor(base_reg << 5)
      .lor(imm << 10)
      .reinterpret_as_uint(),
    )
  } else {
    arm64_movimm(emitter, dst.reinterpret_as_uint(), imm.to_uint64())
    let base : Int = if off < 0 { 0xcb000000 } else { 0x8b000000 }
    emit32(
      emitter,
      (base : Int)
      .lor(dst)
      .lor(base_reg << 5)
      .lor(dst << 16)
      .reinterpret_as_uint(),
    )
  }
}

///|
///|
fn emit_call(emitter : Arm64Emitter, sym : Sym) -> Unit {
  let ind = emitter_pc(emitter)
  greloca(emitter, sym, ind, R_AARCH64_CALL26, 0)
  emit32(emitter, (0x94000000 : UInt))
}

///|
fn gen_builtin_va_start(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  args : Array[Expr],
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  if args.length() < 1 {
    add_error(bag, loc, "__builtin_va_start expects an ap argument")
    return
  }
  let ap_addr = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      return
    }
  }
  gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, args[0], ap_addr, bag)
  let base = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      give_reg(pool, ap_addr)
      return
    }
  }
  let stack_offset = 16 + alloc.varargs_stack_size
  emit_addr_reg(emitter, base, 29, stack_offset, loc, bag)
  arm64_strx(
    emitter,
    3,
    base.reinterpret_as_uint(),
    ap_addr.reinterpret_as_uint(),
    0,
  )
  give_reg(pool, base)
  give_reg(pool, ap_addr)
}

///|
fn gen_builtin_va_copy(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  args : Array[Expr],
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  if args.length() < 2 {
    add_error(bag, loc, "__builtin_va_copy expects 2 arguments")
    return
  }
  let src_addr = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      return
    }
  }
  gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, args[1], src_addr, bag)
  let tmp = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      give_reg(pool, src_addr)
      return
    }
  }
  arm64_ldrx(
    emitter,
    false,
    3,
    tmp.reinterpret_as_uint(),
    src_addr.reinterpret_as_uint(),
    0,
  )
  let dst_addr = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      give_reg(pool, tmp)
      give_reg(pool, src_addr)
      return
    }
  }
  gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, args[0], dst_addr, bag)
  arm64_strx(
    emitter,
    3,
    tmp.reinterpret_as_uint(),
    dst_addr.reinterpret_as_uint(),
    0,
  )
  give_reg(pool, dst_addr)
  give_reg(pool, tmp)
  give_reg(pool, src_addr)
}

///|
fn gen_builtin_alloca(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  args : Array[Expr],
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  if args.length() != 1 {
    add_error(bag, loc, "__builtin_alloca expects 1 argument")
    return
  }
  let size_reg = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      return
    }
  }
  gen_expr_int32(emitter, alloc, syms, pool, cstrings, args[0], size_reg, bag)

  // Round allocation up to 16 to preserve AArch64 stack alignment.
  emit32(
    emitter,
    (0x91000000 : Int)
    .lor(size_reg)
    .lor(size_reg << 5)
    .lor(15 << 10)
    .reinterpret_as_uint(),
  )
  emit32(
    emitter,
    (0x927cec00 : Int)
    .lor(size_reg)
    .lor(size_reg << 5)
    .reinterpret_as_uint(),
  )
  emit32(
    emitter,
    (0xcb2063ff : Int).lor(size_reg << 16).reinterpret_as_uint(),
  )
  emit32(emitter, (0x910003e0 : Int).lor(0).reinterpret_as_uint())
  give_reg(pool, size_reg)
}

///|
fn gen_builtin_va_arg_load(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  list_expr : Expr,
  ty : CType,
  dst : Int,
  bag : DiagBag,
) -> Bool {
  let loc = expr_loc(list_expr)
  let ap_addr = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      return false
    }
  }
  gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, list_expr, ap_addr, bag)
  let cur = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      give_reg(pool, ap_addr)
      return false
    }
  }
  arm64_ldrx(
    emitter,
    false,
    3,
    cur.reinterpret_as_uint(),
    ap_addr.reinterpret_as_uint(),
    0,
  )

  let base_ty = strip_top_qualifiers(ty)
  let (size, signed) = match float_kind_of_type(base_ty) {
    Some(k) => {
      let sz = if k == CFloatKind::Double { 8 } else { 4 }
      (sz, false)
    }
    None =>
      if type_is_pointer_like(base_ty) {
        (8, false)
      } else {
        match scalar_size_signed_or_error(alloc.sem, base_ty, loc) {
          None => {
            give_reg(pool, cur)
            give_reg(pool, ap_addr)
            return false
          }
          Some(v) => v
        }
      }
  }
  let load_sz = match arm64_sz_from_size(size) {
    None => {
      add_error(bag, loc, "codegen: unsupported va_arg size")
      give_reg(pool, cur)
      give_reg(pool, ap_addr)
      return false
    }
    Some(v) => v
  }
  arm64_ldrx(
    emitter,
    signed,
    load_sz,
    dst.reinterpret_as_uint(),
    cur.reinterpret_as_uint(),
    0,
  )
  let bump = align_up(size, 8)
  arm64_add_imm(emitter, cur, cur, bump)
  arm64_strx(
    emitter,
    3,
    cur.reinterpret_as_uint(),
    ap_addr.reinterpret_as_uint(),
    0,
  )
  give_reg(pool, cur)
  give_reg(pool, ap_addr)
  true
}

///|
struct Arm64PcsLayout {
  ret_loc : Int
  arg_locs : Array[Int]
  stack_size : Int
  arg_sizes : Array[Int]
  arg_aligns : Array[Int]
  arg_hfa_counts : Array[Int]
  arg_hfa_sizes : Array[Int]
  arg_is_agg : Array[Bool]
}

///|
struct Arm64PcsAuxInfo {
  locs : Array[Int]
  stack_size : Int
  sizes : Array[Int]
  aligns : Array[Int]
  hfa_counts : Array[Int]
  hfa_sizes : Array[Int]
  is_agg : Array[Bool]
}

///|
struct SRetAddr {
  base_reg : Int
  off : Int
}

///|
fn arm64_hfa_aux(
  sem : SemContext,
  ty : CType,
  fsize : Int,
  num : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> (Int, Int)? {
  if float_kind_of_type(ty) is Some(_) {
    match type_size_align_or_error(sem, ty, loc) {
      None => return None
      Some((size, _)) =>
        if num >= 4 || (fsize != 0 && fsize != size) {
          return None
        } else {
          let next_size = if fsize == 0 { size } else { fsize }
          return Some((num + 1, next_size))
        }
    }
  }
  match strip_top_qualifiers(ty) {
    CType::Struct(name=tag, id=tag_id, fields=field_list, attrs=struct_attrs) =>
      match ensure_struct_fields(
        sem,
        tag,
        tag_id,
        field_list,
        is_union=false,
        loc,
      ) {
        None => None
        Some(def) => {
          for field in def.fields {
            if field.bit_width is Some(_) {
              return None
            }
          }
          let mut num_cur = num
          let mut fsize_cur = fsize
          for field in def.fields {
            match arm64_hfa_aux(sem, field.ty, fsize_cur, num_cur, loc, bag) {
              None => return None
              Some((n1, s1)) => {
                num_cur = n1
                fsize_cur = s1
              }
            }
          }
          let merged = merge_attrs(def.attrs, struct_attrs)
          let (struct_size, _) = struct_size_align(sem, def.fields, merged, loc)
          if fsize_cur == 0 || struct_size != (num_cur - num) * fsize_cur {
            None
          } else {
            Some((num_cur, fsize_cur))
          }
        }
      }
    CType::Union(name=tag, id=tag_id, fields=field_list, attrs=union_attrs) =>
      match ensure_struct_fields(
        sem,
        tag,
        tag_id,
        field_list,
        is_union=true,
        loc,
      ) {
        None => None
        Some(def) => {
          for field in def.fields {
            if field.bit_width is Some(_) {
              return None
            }
          }
          let mut best_num : Int? = None
          let mut best_size : Int = 0
          for field in def.fields {
            match arm64_hfa_aux(sem, field.ty, fsize, num, loc, bag) {
              None => return None
              Some((n1, s1)) =>
                match best_num {
                  None => {
                    best_num = Some(n1)
                    best_size = s1
                  }
                  Some(prev) =>
                    if n1 < prev {
                      best_num = Some(n1)
                      best_size = s1
                    }
                }
            }
          }
          match best_num {
            None => None
            Some(num_best) => {
              let merged = merge_attrs(def.attrs, union_attrs)
              let (union_size, _) = union_size_align(sem, def.fields, merged, loc)
              if best_size == 0 || union_size != (num_best - num) * best_size {
                None
              } else {
                Some((num_best, best_size))
              }
            }
          }
        }
      }
    CType::Array(elem~, size~, ..) =>
      match size {
        None => None
        Some(count) =>
          if count == 0 {
            Some((num, fsize))
          } else {
            match arm64_hfa_aux(sem, elem, fsize, num, loc, bag) {
              None => None
              Some((num1, fsize1)) => {
                let elem_count = num1 - num
                if elem_count == 0 || (elem_count != 0 && count > 4) {
                  None
                } else {
                  let total = num + count * elem_count
                  if total > 4 {
                    None
                  } else {
                    Some((total, fsize1))
                  }
                }
              }
            }
          }
      }
    _ => None
  }
}

///|
fn arm64_hfa(
  sem : SemContext,
  ty : CType,
  loc : SrcLoc,
  bag : DiagBag,
) -> (Int, Int)? {
  match arm64_hfa_aux(sem, ty, 0, 0, loc, bag) {
    None => None
    Some((num, fsize)) =>
      if num > 0 && num <= 4 && fsize > 0 {
        Some((num, fsize))
      } else {
        None
      }
  }
}

///|
fn arm64_pcs_size_align(
  sem : SemContext,
  ty : CType,
  loc : SrcLoc,
  _bag : DiagBag,
) -> (Int, Int)? {
  match strip_top_qualifiers(ty) {
    CType::Array(..) | CType::Function(..) => Some((8, 8))
    _ => type_size_align_or_error(sem, ty, loc)
  }
}

///|
fn arm64_pcs_aux(
  sem : SemContext,
  variadic_index : Int,
  types : Array[CType],
  loc : SrcLoc,
  bag : DiagBag,
) -> Arm64PcsAuxInfo {
  let mut nx = 0
  let mut nv = 0
  let mut ns = 32
  let locs : Array[Int] = Array::new(capacity=types.length())
  let sizes : Array[Int] = Array::new(capacity=types.length())
  let aligns : Array[Int] = Array::new(capacity=types.length())
  let hfa_counts : Array[Int] = Array::new(capacity=types.length())
  let hfa_sizes : Array[Int] = Array::new(capacity=types.length())
  let is_agg_list : Array[Bool] = Array::new(capacity=types.length())
  let is_macho = true
  for i = 0; i < types.length(); i = i + 1 {
    let ty = types[i]
    let (hfa_count, hfa_size) = match arm64_hfa(sem, ty, loc, bag) {
      None => (0, 0)
      Some(v) => v
    }
    let (size0, align0) = match arm64_pcs_size_align(sem, ty, loc, bag) {
      None => (0, 1)
      Some(v) => v
    }
    let is_agg = match strip_top_qualifiers(ty) {
      CType::Struct(..) | CType::Union(..) => true
      _ => false
    }
    sizes.push(size0)
    aligns.push(align0)
    hfa_counts.push(hfa_count)
    hfa_sizes.push(hfa_size)
    is_agg_list.push(is_agg)
    let is_float = float_kind_of_type(ty) is Some(_)
    let is_long_double = match strip_top_qualifiers(ty) {
      CType::Float(kind=CFloatKind::LongDouble) => true
      _ => false
    }
    let mut size = size0
    let align = align0

    if is_macho && variadic_index > 0 && i == variadic_index {
      nx = 8
      nv = 8
    }

    if hfa_count == 0 && size > 16 {
      if nx < 8 {
        locs.push((nx << 1) | 1)
        nx = nx + 1
      } else {
        ns = align_up(ns, 8)
        locs.push(ns | 1)
        ns = ns + 8
      }
      continue
    } else if is_agg {
      size = align_up(size, 8)
    }

    if is_float && nv < 8 {
      locs.push(16 + (nv << 1))
      nv = nv + 1
      continue
    }

    if hfa_count > 0 && nv + hfa_count <= 8 {
      locs.push(16 + (nv << 1))
      nv = nv + hfa_count
      continue
    }

    if hfa_count > 0 {
      nv = 8
      size = align_up(size, 8)
    }

    if hfa_count > 0 || is_long_double {
      ns = align_up(ns, 8)
      ns = align_up(ns, align)
    }

    if is_float {
      size = 8
    }

    if hfa_count > 0 || is_float {
      locs.push(ns)
      ns = ns + size
      continue
    }

    if !is_agg && size <= 8 && nx < 8 {
      locs.push(nx << 1)
      nx = nx + 1
      continue
    }

    if align == 16 {
      nx = (nx + 1) & (0xfffffffe : Int)
    }

    if !is_agg && size == 16 && nx < 7 {
      locs.push(nx << 1)
      nx = nx + 2
      continue
    }

    if is_agg && size <= (8 - nx) * 8 {
      locs.push(nx << 1)
      nx = nx + ((size + 7) >> 3)
      continue
    }

    nx = 8

    ns = align_up(ns, 8)
    ns = align_up(ns, align)

    if is_agg {
      locs.push(ns)
      ns = ns + size
      continue
    }

    if size < 8 {
      size = 8
    }
    locs.push(ns)
    ns = ns + size
  }
  {
    locs,
    stack_size: ns - 32,
    sizes,
    aligns,
    hfa_counts,
    hfa_sizes,
    is_agg: is_agg_list,
  }
}

///|
fn arm64_pcs(
  sem : SemContext,
  variadic_index : Int,
  ret_ty : CType,
  arg_tys : Array[CType],
  loc : SrcLoc,
  bag : DiagBag,
) -> Arm64PcsLayout {
  let ret_loc = match strip_top_qualifiers(ret_ty) {
    CType::Void => -1
    _ => {
      let ret_info = arm64_pcs_aux(sem, 0, [ret_ty], loc, bag)
      match ret_info.locs.get(0) {
        None => -1
        Some(v) => v
      }
    }
  }
  let arg_info = arm64_pcs_aux(sem, variadic_index, arg_tys, loc, bag)
  {
    ret_loc,
    arg_locs: arg_info.locs,
    stack_size: arg_info.stack_size,
    arg_sizes: arg_info.sizes,
    arg_aligns: arg_info.aligns,
    arg_hfa_counts: arg_info.hfa_counts,
    arg_hfa_sizes: arg_info.hfa_sizes,
    arg_is_agg: arg_info.is_agg,
  }
}

///|
fn call_arg_slot_count(
  alloc : LocalAlloc,
  ty : CType,
  loc : SrcLoc,
  bag : DiagBag,
) -> Int? {
  match strip_top_qualifiers(ty) {
    CType::Struct(..) | CType::Union(..) =>
      if type_size_align_or_error(alloc.sem, ty, loc) is Some((size, _)) {
        if size <= 8 {
          Some(1)
        } else if size <= 16 {
          Some(2)
        } else {
          add_error(bag, loc, "codegen: struct args >16 bytes not supported yet")
          None
        }
      } else {
        None
      }
    _ => Some(1)
  }
}

///|
fn store_call_arg_to_slot(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  arg : Expr,
  ty : CType,
  slot_off : UInt64,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  match float_kind_of_type(ty) {
    Some(k) => {
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
        arg,
        k,
        tmp,
        bag,
      )
      if k == CFloatKind::Double {
        arm64_strx(emitter, 3, tmp.reinterpret_as_uint(), (31 : UInt), slot_off)
      } else {
        arm64_strx(emitter, 2, tmp.reinterpret_as_uint(), (31 : UInt), slot_off)
      }
      give_reg(pool, tmp)
    }
    None =>
      match strip_top_qualifiers(ty) {
        CType::Struct(..) | CType::Union(..) =>
          if type_size_align_or_error(alloc.sem, ty, loc) is Some((size, _)) {
            if size <= 16 {
              gen_agg_expr_to_addr(
                emitter,
                alloc,
                syms,
                pool,
                cstrings,
                arg,
                31,
                slot_off.to_int(),
                ty,
                loc,
                bag,
              )
            } else {
              add_error(bag, loc, "codegen: struct args >16 bytes not supported yet")
            }
          }
        _ => {
          let tmp = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          if type_is_pointer_like(ty) {
            gen_expr_ptr(emitter, alloc, syms, pool, cstrings, arg, tmp, bag)
          } else {
            let from_ty = type_of_expr(alloc.sem, arg)
            gen_expr_int32(
              emitter,
              alloc,
              syms,
              pool,
              cstrings,
              arg,
              tmp,
              bag,
              expr_ty=from_ty,
            )
            emit_int_cast(emitter, alloc.sem, from_ty, ty, tmp, loc, bag)
          }
          arm64_strx(emitter, 3, tmp.reinterpret_as_uint(), (31 : UInt), slot_off)
          give_reg(pool, tmp)
        }
      }
  }
}

///|
fn promote_vararg_type(ty : CType) -> CType {
  match strip_top_qualifiers(ty) {
    CType::Float(kind~) =>
      if kind == CFloatKind::Float {
        CType::Float(kind=CFloatKind::Double)
      } else {
        ty
      }
    _ => ty
  }
}

///|
fn gen_call_direct(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  name : String,
  id? : Int = 0,
  args : Array[Expr],
  sret : SRetAddr?,
  loc : SrcLoc,
  bag : DiagBag,
) -> CType {
  let sig = if id > 0 {
    match get_function_by_id(alloc.sem, id) {
      Some(found) => Some(found)
      None => alloc.sem.functions.get(name)
    }
  } else {
    alloc.sem.functions.get(name)
  }
  let mut fixed_count = 0
  let mut is_varargs = false
  let mut ret_ty = default_int_type()
  match sig {
    None => {
      ret_ty =
        type_of_expr(
          alloc.sem,
          Expr::Call(
            callee=Expr::Ident(name=name, id=id, node_id=0, loc=loc),
            args=args,
            node_id=0,
            loc=loc,
          ),
        )
    }
    Some(s) => {
      fixed_count = s.params.length()
      is_varargs = s.varargs
      ret_ty = s.return_type
    }
  }
  let is_varargs_call = is_varargs && args.length() > fixed_count
  let variadic_index = if is_varargs_call { fixed_count } else { 0 }

  let mut arg_tys : Array[CType] = []
  let mut use_sig_params = false
  match sig {
    Some(s) =>
      if !s.varargs && !s.is_old_style && args.length() == s.params.length() {
        arg_tys = s.params
        use_sig_params = true
      } else {
        let built : Array[CType] = Array::new(capacity=args.length())
        let mut i = 0
        while i < args.length() {
          let arg = args[i]
          let param_ty =
            if i < s.params.length() {
              s.params[i]
            } else {
              type_of_expr(alloc.sem, arg)
            }
          let store_ty =
            if is_varargs_call && i >= fixed_count {
              promote_vararg_type(param_ty)
            } else {
              param_ty
            }
          built.push(store_ty)
          i = i + 1
        }
        arg_tys = built
      }
    None => {
      let built : Array[CType] = Array::new(capacity=args.length())
      let mut i = 0
      while i < args.length() {
        let arg = args[i]
        let param_ty = type_of_expr(alloc.sem, arg)
        let store_ty =
          if is_varargs_call && i >= fixed_count {
            promote_vararg_type(param_ty)
          } else {
            param_ty
          }
        built.push(store_ty)
        i = i + 1
      }
      arg_tys = built
    }
  }

  let sym = sym_for_ident(syms, name, id=id)
  let emit_call_fn = fn() { emit_call(emitter, sym) }
  let mut cached_layout : Arm64PcsLayout? = None
  if use_sig_params && id > 0 {
    ensure_call_layout_capacity(syms, id)
    let idx = id - 1
    match syms.call_layout_cache[idx] {
      Some(layout) => cached_layout = Some(layout)
      None => {
        let layout = arm64_pcs(
          alloc.sem,
          variadic_index,
          ret_ty,
          arg_tys,
          loc,
          bag,
        )
        syms.call_layout_cache[idx] = Some(layout)
        cached_layout = Some(layout)
      }
    }
  }
  gen_call_with_layout(
    emitter,
    alloc,
    syms,
    pool,
    cstrings,
    args,
    arg_tys,
    ret_ty,
    variadic_index,
    sret,
    loc,
    bag,
    emit_call_fn,
    layout=cached_layout,
  )
  ret_ty
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
fn emit_br(emitter : Arm64Emitter, reg : Int) -> Unit {
  emit32(
    emitter,
    (0xd61f0000 : Int)
    .lor(reg << 5)
    .reinterpret_as_uint(),
  )
}

///|
fn encode_adr(rd : Int, diff : Int) -> UInt? {
  let max = 1 << 20
  if diff < -max || diff >= max {
    return None
  }
  let immlo = diff & 0x3
  let immhi = (diff >> 2) & 0x7ffff
  Some(
    (0x10000000 : Int)
    .lor(immlo << 29)
    .lor(immhi << 5)
    .lor(rd)
    .reinterpret_as_uint(),
  )
}

///|
fn emit_adr(
  emitter : Arm64Emitter,
  rd : Int,
  diff : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  match encode_adr(rd, diff) {
    Some(insn) => emit32(emitter, insn)
    None => add_error(bag, loc, "codegen: label address out of range")
  }
}

///|
fn patch_adr(
  emitter : Arm64Emitter,
  at : Int,
  target : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let idx = at >> 2
  if idx < 0 || idx >= emitter.code_len {
    add_error(bag, loc, "codegen: invalid label address patch")
    return
  }
  let rd = emitter.code[idx].reinterpret_as_int() & 0x1f
  let diff = target - at
  match encode_adr(rd, diff) {
    Some(insn) => emitter.code[idx] = insn
    None => add_error(bag, loc, "codegen: label address out of range")
  }
}

///|
fn gen_call_with_layout(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  args : Array[Expr],
  arg_tys : Array[CType],
  ret_ty : CType,
  variadic_index : Int,
  sret : SRetAddr?,
  loc : SrcLoc,
  bag : DiagBag,
  emit_call : () -> Unit,
  layout~ : Arm64PcsLayout?,
) -> Unit {
  let layout = match layout {
    Some(found) => found
    None => arm64_pcs(alloc.sem, variadic_index, ret_ty, arg_tys, loc, bag)
  }
  let arg_locs = layout.arg_locs
  let arg_sizes = layout.arg_sizes
  let arg_aligns = layout.arg_aligns
  let arg_hfa_counts = layout.arg_hfa_counts
  let arg_hfa_sizes = layout.arg_hfa_sizes
  let arg_is_agg = layout.arg_is_agg
  let stack_args_size = align_up(layout.stack_size, 16)
  let caller_saved_regs = caller_saved_regs_list

  let spill_offs : Array[Int?] = Array::new(capacity=args.length())
  let copy_offs : Array[Int?] = Array::new(capacity=args.length())
  let mut scratch_off = stack_args_size

  let mut i = 0
  while i < args.length() {
    let loc_i = arg_locs.get(i).unwrap_or(0)
    let byref = (loc_i & 1) != 0
    let is_stack = loc_i >= 32
    let is_agg = arg_is_agg[i]
    let needs_copy = byref || (is_agg && !is_stack)

    if needs_copy {
      let align = arg_aligns[i]
      let size = arg_sizes[i]
      let aligned = align_up(scratch_off, align)
      copy_offs.push(Some(aligned))
      scratch_off = aligned + size
    } else {
      copy_offs.push(None)
    }

    if !is_stack {
      if needs_copy && !byref {
        spill_offs.push(copy_offs[i])
      } else {
        let spill_size =
          if byref {
            8
          } else {
            match float_kind_of_type(arg_tys[i]) {
              Some(k) =>
                if k == CFloatKind::Float {
                  4
                } else {
                  8
                }
              None => 8
            }
          }
        let spill_align = if spill_size < 8 { 4 } else { 8 }
        let aligned = align_up(scratch_off, spill_align)
        spill_offs.push(Some(aligned))
        scratch_off = aligned + spill_size
      }
    } else {
      spill_offs.push(None)
    }
    i = i + 1
  }

  let mut sret_addr = sret
  if layout.ret_loc == 1 {
    match sret_addr {
      None =>
        if type_size_align_or_error(alloc.sem, ret_ty, loc) is Some((ret_size, ret_align)) {
          let aligned = align_up(scratch_off, ret_align)
          sret_addr = Some({ base_reg: 31, off: aligned })
          scratch_off = aligned + ret_size
        }
      Some(_) => ()
    }
  }

  let caller_save_off = align_up(scratch_off, 8)
  scratch_off = caller_save_off + caller_saved_regs.length() * 8
  let total_stack = align_up(scratch_off, 16)
  if total_stack > 0 {
    let off = (0 : UInt64) - total_stack.to_uint64()
    arm64_spoff(emitter, (31 : UInt), off)
  }

  if layout.ret_loc == 1 {
    if sret_addr is Some(addr) {
      let base = addr.base_reg
      let mut off = addr.off
      if base == 31 {
        off = off + total_stack
      }
      emit_addr_reg(emitter, 8, base, off, loc, bag)
    }
  }

  i = 0
  while i < args.length() {
    let loc_i = arg_locs.get(i).unwrap_or(0)
    let byref = (loc_i & 1) != 0
    let is_stack = loc_i >= 32
    let stack_off = if is_stack { (loc_i & (0xfffffffe : Int)) - 32 } else { 0 }
    if byref {
      let copy_off = copy_offs[i].unwrap_or(0)
      gen_agg_expr_to_addr(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        args[i],
        31,
        copy_off,
        arg_tys[i],
        loc,
        bag,
      )
      let tmp = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      emit_addr_sp(emitter, tmp, copy_off, loc, bag)
      if is_stack {
        arm64_strx(
          emitter,
          3,
          tmp.reinterpret_as_uint(),
          (31 : UInt),
          stack_off.to_int64().reinterpret_as_uint64(),
        )
      } else {
        let spill = spill_offs[i].unwrap_or(0)
        arm64_strx(
          emitter,
          3,
          tmp.reinterpret_as_uint(),
          (31 : UInt),
          spill.to_int64().reinterpret_as_uint64(),
        )
      }
      give_reg(pool, tmp)
    } else {
      let slot_off =
        if is_stack {
          stack_off
        } else {
          spill_offs[i].unwrap_or(0)
        }
      store_call_arg_to_slot(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        args[i],
        arg_tys[i],
        slot_off.to_uint64(),
        loc,
        bag,
      )
    }
    i = i + 1
  }

  i = 0
  while i < args.length() {
    let loc_i = arg_locs.get(i).unwrap_or(0)
    if loc_i < 16 {
      let spill_off = spill_offs[i].unwrap_or(0)
      let reg = loc_i >> 1
      if arg_is_agg[i] {
        let size = arg_sizes[i]
        emit_addr_sp(emitter, reg, spill_off, loc, bag)
        arm64_ldrs(emitter, reg.reinterpret_as_uint(), size)
      } else {
        arm64_ldrx(
          emitter,
          false,
          3,
          reg.reinterpret_as_uint(),
          (31 : UInt),
          spill_off.to_int64().reinterpret_as_uint64(),
        )
      }
    } else if loc_i < 32 {
      let spill_off = spill_offs[i].unwrap_or(0)
      let fp_base = (loc_i >> 1) - 8
      let hfa_count = arg_hfa_counts[i]
      let hfa_size = arg_hfa_sizes[i]
      if hfa_count > 0 {
        let mut j = 0
        while j < hfa_count {
          let tmp = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          if hfa_size == 8 {
            arm64_ldrx(
              emitter,
              false,
              3,
              tmp.reinterpret_as_uint(),
              (31 : UInt),
              (spill_off + j * 8).to_int64().reinterpret_as_uint64(),
            )
            emit_fmov_x_to_d(emitter, fp_base + j, tmp)
          } else {
            arm64_ldrx(
              emitter,
              false,
              2,
              tmp.reinterpret_as_uint(),
              (31 : UInt),
              (spill_off + j * 4).to_int64().reinterpret_as_uint64(),
            )
            emit_fmov_w_to_s(emitter, fp_base + j, tmp)
          }
          give_reg(pool, tmp)
          j = j + 1
        }
      } else {
        let tmp = take_reg(pool) catch {
          err => {
            add_error(bag, loc, err.to_string())
            return
          }
        }
        if float_kind_of_type(arg_tys[i]) is Some(k) {
          if k == CFloatKind::Double || k == CFloatKind::LongDouble {
            arm64_ldrx(
              emitter,
              false,
              3,
              tmp.reinterpret_as_uint(),
              (31 : UInt),
              spill_off.to_int64().reinterpret_as_uint64(),
            )
            emit_fmov_x_to_d(emitter, fp_base, tmp)
          } else {
            arm64_ldrx(
              emitter,
              false,
              2,
              tmp.reinterpret_as_uint(),
              (31 : UInt),
              spill_off.to_int64().reinterpret_as_uint64(),
            )
            emit_fmov_w_to_s(emitter, fp_base, tmp)
          }
        }
        give_reg(pool, tmp)
      }
    }
    i = i + 1
  }

  let used_caller_regs : Array[(Int, Int)] = Array::new(capacity=caller_saved_regs.length())
  i = 0
  while i < caller_saved_regs.length() {
    let reg = caller_saved_regs[i]
    if !pool.free.contains(reg) {
      let off = caller_save_off + i * 8
      arm64_strx(
        emitter,
        3,
        reg.reinterpret_as_uint(),
        (31 : UInt),
        off.to_int64().reinterpret_as_uint64(),
      )
      used_caller_regs.push((reg, off))
    }
    i = i + 1
  }

  emit_call()

  i = 0
  while i < used_caller_regs.length() {
    let (reg, off) = used_caller_regs[i]
    arm64_ldrx(
      emitter,
      false,
      3,
      reg.reinterpret_as_uint(),
      (31 : UInt),
      off.to_int64().reinterpret_as_uint64(),
    )
    i = i + 1
  }

  if total_stack > 0 {
    arm64_spoff(emitter, (31 : UInt), total_stack.to_uint64())
  }
}

///|
fn gen_builtin_frame_address(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  pool : RegPool,
  args : Array[Expr],
  is_return : Bool,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  if args.length() != 1 {
    let name = if is_return { "__builtin_return_address" } else { "__builtin_frame_address" }
    add_error(bag, loc, "\{name} expects 1 argument")
    return
  }
  let level = match const_int_from_expr(alloc.sem, args[0], loc) {
    None => {
      add_error(bag, loc, "codegen: builtin expects constant integer level")
      return
    }
    Some(v) => v
  }
  if level < 0 {
    let name = if is_return { "__builtin_return_address" } else { "__builtin_frame_address" }
    add_error(bag, loc, "\{name} only takes non-negative integers")
    return
  }
  let tmp = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      return
    }
  }
  emit_mov(emitter, true, tmp, 29)
  let mut i = 0
  while i < level {
    arm64_ldrx(
      emitter,
      false,
      3,
      tmp.reinterpret_as_uint(),
      tmp.reinterpret_as_uint(),
      0,
    )
    i = i + 1
  }
  if is_return {
    arm64_ldrx(
      emitter,
      false,
      3,
      tmp.reinterpret_as_uint(),
      tmp.reinterpret_as_uint(),
      8,
    )
  }
  emit_mov(emitter, true, 0, tmp)
  give_reg(pool, tmp)
}

///|
fn gen_atomic_builtin_call(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  name : String,
  id : Int,
  args : Array[Expr],
  loc : SrcLoc,
  bag : DiagBag,
) -> Bool {
  let template = match atomic_builtin_template_from_ident(alloc.sem, name, id) {
    None => return false
    Some(v) => v
  }
  let mut dot_index = 0
  while dot_index < template.length() && template[dot_index] != '.' {
    dot_index = dot_index + 1
  }
  if dot_index >= template.length() - 1 {
    return false
  }
  let arg_spec_len = dot_index
  if args.length() != arg_spec_len {
    add_error(bag, loc, "\{name} expects \{arg_spec_len} arguments")
  }
  let mut atom_type : CType? = None
  let mut atom_size = 0
  let call_args : Array[Expr] = Array::new(capacity=arg_spec_len)
  let call_arg_tys : Array[CType] = Array::new(capacity=arg_spec_len)
  let mut save_arg : Expr? = None
  let mut i = 0
  while i < arg_spec_len && i < args.length() {
    let spec = template[i]
    let arg = args[i]
    match spec {
      'a' | 'A' => {
        let ptr_ty = type_of_expr(alloc.sem, arg)
        match strip_top_qualifiers(ptr_ty) {
          CType::Pointer(pointee) => {
            if atom_type is None {
              atom_type = Some(pointee)
              if type_size_align(alloc.sem, pointee, loc) is Some((size, _)) {
                atom_size = size
              }
            }
          }
          _ => add_error(bag, loc, "\{name} expects pointer argument")
        }
        call_args.push(arg)
        call_arg_tys.push(ptr_ty)
      }
      'p' => {
        call_args.push(arg)
        call_arg_tys.push(type_of_expr(alloc.sem, arg))
      }
      'l' => {
        let deref = Expr::Unary(
          op=UnaryOp::Deref,
          expr=arg,
          node_id=0,
          loc=expr_loc(arg),
        )
        call_args.push(deref)
        let ty = match atom_type {
          Some(at) => at
          None => type_of_expr(alloc.sem, deref)
        }
        call_arg_tys.push(ty)
      }
      's' => save_arg = Some(arg)
      'v' => {
        call_args.push(arg)
        let ty = match atom_type {
          Some(at) => at
          None => type_of_expr(alloc.sem, arg)
        }
        call_arg_tys.push(ty)
      }
      'm' => {
        call_args.push(arg)
        call_arg_tys.push(default_int_type())
      }
      'b' => {
        call_args.push(arg)
        call_arg_tys.push(CType::Bool)
      }
      _ => ()
    }
    i = i + 1
  }
  if atom_size <= 0 {
    add_error(bag, loc, "codegen: atomic builtin requires 1/2/4/8-byte target type")
    return true
  }
  let helper_name = "\{name}_\{atom_size}"
  let ret_ty = match atomic_builtin_return_type(alloc.sem, name, id, args, loc) {
    Some(t) => t
    None => default_int_type()
  }
  let sym = sym_for_ident(syms, helper_name)
  let emit_call_fn = fn() { emit_call(emitter, sym) }
  gen_call_with_layout(
    emitter,
    alloc,
    syms,
    pool,
    cstrings,
    call_args,
    call_arg_tys,
    ret_ty,
    0,
    None,
    loc,
    bag,
    emit_call_fn,
    layout=None,
  )
  if save_arg is Some(dest) {
    let addr = take_reg(pool) catch {
      err => {
        add_error(bag, loc, err.to_string())
        return true
      }
    }
    gen_expr_ptr(emitter, alloc, syms, pool, cstrings, dest, addr, bag)
    let store_ty = match atom_type {
      Some(at) => at
      None => ret_ty
    }
    emit_store_scalar_at(emitter, alloc.sem, store_ty, 0, addr, 0, loc, bag)
    give_reg(pool, addr)
  }
  true
}

///|
fn gen_call_expr_impl(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  callee : Expr,
  args : Array[Expr],
  sret : SRetAddr?,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  if callee is Expr::Ident(name~, id~, ..) {
    if name == "__builtin_alloca" || name == "alloca" {
      gen_builtin_alloca(emitter, alloc, syms, pool, cstrings, args, loc, bag)
      return
    }
    match builtin_call_kind(alloc.sem, name, id) {
      Some(BuiltinCallKind::Expect) => {
        if args.length() != 2 {
          add_error(bag, loc, "__builtin_expect expects 2 arguments")
          return
        }
        let tmp = take_reg(pool) catch {
          err => {
            add_error(bag, loc, err.to_string())
            return
          }
        }
        let ret_ty = type_of_expr(alloc.sem, args[0])
        match float_kind_of_type(ret_ty) {
          Some(k) =>
            gen_expr_to_float_kind_bits_with_type(
              emitter,
              alloc,
              syms,
              pool,
              cstrings,
              args[0],
              ret_ty,
              k,
              tmp,
              bag,
            )
          None =>
            if type_is_pointer_like(ret_ty) {
              gen_expr_ptr(emitter, alloc, syms, pool, cstrings, args[0], tmp, bag)
            } else {
              gen_expr_int32(
                emitter,
                alloc,
                syms,
                pool,
                cstrings,
                args[0],
                tmp,
                bag,
                expr_ty=ret_ty,
              )
            }
        }
        gen_expr_discard(emitter, alloc, syms, pool, cstrings, args[1], bag)
        emit_mov(emitter, true, 0, tmp)
        give_reg(pool, tmp)
        return
      }
      Some(BuiltinCallKind::VaStart) => {
        gen_builtin_va_start(emitter, alloc, syms, pool, cstrings, args, loc, bag)
        return
      }
      Some(BuiltinCallKind::VaCopy) => {
        gen_builtin_va_copy(emitter, alloc, syms, pool, cstrings, args, loc, bag)
        return
      }
      Some(BuiltinCallKind::VaEnd) => return
      Some(BuiltinCallKind::SyncSynchronize) => {
        if args.length() != 0 {
          add_error(bag, loc, "__sync_synchronize expects no args")
        }
        emit32(emitter, (0xd5033bbf : UInt))
        return
      }
      Some(BuiltinCallKind::FrameAddress) => {
        gen_builtin_frame_address(emitter, alloc, pool, args, false, loc, bag)
        return
      }
      Some(BuiltinCallKind::ReturnAddress) => {
        gen_builtin_frame_address(emitter, alloc, pool, args, true, loc, bag)
        return
      }
      _ => ()
    }
    if gen_atomic_builtin_call(
      emitter,
      alloc,
      syms,
      pool,
      cstrings,
      name,
      id,
      args,
      loc,
      bag,
    ) {
      return
    }
    let has_func = if id > 0 {
      has_function_by_id(alloc.sem, id)
    } else {
      alloc.sem.functions.contains(name)
    }
    if lookup_local(alloc, name, id) is None && lookup_static_local(alloc, id) is None &&
      has_func {
      let ret_ty =
        gen_call_direct(
          emitter,
          alloc,
          syms,
          pool,
          cstrings,
          name,
          id=id,
          args,
          sret,
          loc,
          bag,
        )
      if float_kind_of_type(ret_ty) is Some(k) {
        if k == CFloatKind::Double {
          emit_fmov_d_to_x(emitter, 0, 0)
        } else {
          emit_fmov_s_to_w(emitter, 0, 0)
        }
      }
      return
    }
  }

  // Indirect call via function pointer expression.
  let callee_ty = type_of_expr(alloc.sem, callee)
  let mut param_tys : Array[CType] = []
  let mut is_varargs = false
  let mut ret_ty = default_int_type()
  match strip_top_qualifiers(callee_ty) {
    CType::Pointer(inner) =>
      match strip_top_qualifiers(inner) {
        CType::Function(return_type~, params~, varargs~, ..) => {
          param_tys = params
          is_varargs = varargs
          ret_ty = return_type
        }
        _ => ()
      }
    CType::Function(return_type~, params~, varargs~, ..) => {
      param_tys = params
      is_varargs = varargs
      ret_ty = return_type
    }
    _ => ()
  }

  let mut arg_tys : Array[CType] = []
  if !is_varargs && args.length() == param_tys.length() {
    arg_tys = param_tys
  } else {
    let built : Array[CType] = Array::new(capacity=args.length())
    let mut i = 0
    while i < args.length() {
      let param_ty =
        if i < param_tys.length() {
          param_tys[i]
        } else {
          type_of_expr(alloc.sem, args[i])
        }
      let store_ty =
        if is_varargs && i >= param_tys.length() {
          promote_vararg_type(param_ty)
        } else {
          param_ty
        }
      built.push(store_ty)
      i = i + 1
    }
    arg_tys = built
  }
  let variadic_index = if is_varargs { param_tys.length() } else { 0 }

  let fn_reg = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      return
    }
  }
  gen_expr_ptr(emitter, alloc, syms, pool, cstrings, callee, fn_reg, bag)
  let emit_call_fn = fn() { emit_blr(emitter, fn_reg) }
  gen_call_with_layout(
    emitter,
    alloc,
    syms,
    pool,
    cstrings,
    args,
    arg_tys,
    ret_ty,
    variadic_index,
    sret,
    loc,
    bag,
    emit_call_fn,
    layout=None,
  )
  give_reg(pool, fn_reg)

  if float_kind_of_type(ret_ty) is Some(k) {
    if k == CFloatKind::Double {
      emit_fmov_d_to_x(emitter, 0, 0)
    } else {
      emit_fmov_s_to_w(emitter, 0, 0)
    }
  }
  if float_kind_of_type(ret_ty) is None && is_int_like(ret_ty) {
    if scalar_size_signed_or_error(alloc.sem, ret_ty, loc) is Some((size, _)) {
      if size > 0 && size < 8 {
        emit_int_cast(emitter, alloc.sem, ret_ty, ret_ty, 0, loc, bag)
      }
    }
  }
}

///|
fn gen_call_expr(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  callee : Expr,
  args : Array[Expr],
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  gen_call_expr_impl(
    emitter,
    alloc,
    syms,
    pool,
    cstrings,
    callee,
    args,
    None,
    loc,
    bag,
  )
}

///|
fn gen_call_expr_with_sret(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  callee : Expr,
  args : Array[Expr],
  sret_reg : Int,
  sret_off : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  gen_call_expr_impl(
    emitter,
    alloc,
    syms,
    pool,
    cstrings,
    callee,
    args,
    Some({ base_reg: sret_reg, off: sret_off }),
    loc,
    bag,
  )
}

///|
fn element_type_for_pointer_arith(ty : CType) -> CType? {
  match strip_top_qualifiers_keep_attrs(ty) {
    CType::Pointer(inner) => Some(inner)
    CType::Array(elem~, ..) => Some(elem)
    _ => None
  }
}

///|
fn gen_func_name_addr(
  emitter : Arm64Emitter,
  syms : SymTable,
  cstrings : CstringPool,
  alloc : LocalAlloc,
  dst : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Bool {
  if alloc.func_name == "" {
    add_error(bag, loc, "codegen: missing __func__ string literal")
    return false
  }
  let sym = cstring_sym_or_add(cstrings, syms, alloc.func_name)
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
  true
}

///|
fn is_func_name_ident(name : String) -> Bool {
  name == "__func__" || name == "__FUNCTION__" || name == "__PRETTY_FUNCTION__"
}

///|
fn gen_index_addr_with_elem_type(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  base : Expr,
  index : Expr,
  dst : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> CType? {
  gen_expr_ptr(emitter, alloc, syms, pool, cstrings, base, dst, bag)
  let mut base_reg = dst
  let mut saved_reg : Int? = None
  if expr_may_call(index) && dst < 19 {
    let tmp = take_reg(pool) catch {
      err => {
        add_error(bag, loc, err.to_string())
        return None
      }
    }
    emit_mov(emitter, true, tmp, dst)
    base_reg = tmp
    saved_reg = Some(tmp)
  }
  let idx = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      if saved_reg is Some(r) {
        give_reg(pool, r)
      }
      return None
    }
  }
  gen_expr_int32(emitter, alloc, syms, pool, cstrings, index, idx, bag)
  let idx_ty = type_of_expr(alloc.sem, index)
  emit_int_extend_to_64(emitter, alloc.sem, idx_ty, idx, loc, bag)
  let base_ty = type_of_expr(alloc.sem, base)
  let elem_ty = match element_type_for_pointer_arith(base_ty) {
    None => {
      add_error(bag, loc, "codegen: index base is not pointer/array")
      give_reg(pool, idx)
      if saved_reg is Some(r) {
        give_reg(pool, r)
      }
      return None
    }
    Some(t) => t
  }
  let mut elem_size_reg : Int? = None
  let mut elem_size_const : Int? = None
  match strip_top_qualifiers(elem_ty) {
    CType::Array(size=None, size_expr=Some(_), ..) => {
      let scale = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          give_reg(pool, idx)
          if saved_reg is Some(r) {
            give_reg(pool, r)
          }
          return None
        }
      }
      gen_type_size_bytes_to_reg(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        elem_ty,
        scale,
        loc,
        bag,
      )
      elem_size_reg = Some(scale)
    }
    _ =>
      match type_size_align_or_error(alloc.sem, elem_ty, loc) {
        None => {
          give_reg(pool, idx)
          if saved_reg is Some(r) {
            give_reg(pool, r)
          }
          return None
        }
        Some((sz, _)) => elem_size_const = Some(sz)
      }
  }
  match elem_size_reg {
    Some(scale) => {
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
    None =>
      if elem_size_const is Some(elem_size) {
        if elem_size != 1 {
          let scale = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              give_reg(pool, idx)
              if saved_reg is Some(r) {
                give_reg(pool, r)
              }
              return None
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
      }
  }
  emit32(
    emitter,
    (0x8b000000 : Int)
    .lor(base_reg)
    .lor(base_reg << 5)
    .lor(idx << 16)
    .reinterpret_as_uint(),
  )
  give_reg(pool, idx)
  if saved_reg is Some(r) {
    if base_reg != dst {
      emit_mov(emitter, true, dst, base_reg)
    }
    give_reg(pool, r)
  }
  Some(elem_ty)
}

///|
fn gen_compound_literal_addr_with_type(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  ty : CType,
  init : Initializer,
  loc : SrcLoc,
  node_id : Int,
  dst : Int,
  bag : DiagBag,
) -> CType? {
  let key = compound_literal_key(node_id)
  match alloc.compound_literal_slots.get(key) {
    None => {
      add_error(bag, loc, "codegen: missing compound literal slot")
      None
    }
    Some(off) => {
      let resolved = compound_literal_type(alloc.sem, ty, init, loc, node_id)
      let size_align = match alloc.sem.compound_literal_sizes.get(key) {
        Some(value) => Some(value)
        None => type_size_align_or_error(alloc.sem, resolved, loc)
      }
      if size_align is Some((size, _)) {
        if size > 0 {
          emit_zero_bytes(emitter, 29, off, size)
        }
      }
      gen_initializer_to_addr(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        29,
        off,
        resolved,
        init,
        bag,
      )
      emit_addr_local(emitter, dst, off, loc, bag)
      Some(resolved)
    }
  }
}

///|
fn gen_lvalue_addr(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  expr : Expr,
  dst : Int,
  bag : DiagBag,
) -> Unit {
  match expr {
    Expr::Ident(name~, id~, loc~, ..) => {
      if is_func_name_ident(name) {
        if gen_func_name_addr(emitter, syms, cstrings, alloc, dst, loc, bag) {
          return
        }
      }
      match lookup_local(alloc, name, id) {
        Some(slot) =>
          if slot.byref {
            arm64_ldrx(
              emitter,
              false,
              3,
              dst.reinterpret_as_uint(),
              (29 : UInt),
              slot.offset.to_int64().reinterpret_as_uint64(),
            )
          } else {
            match strip_top_qualifiers(slot.ty) {
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
          }
        None => {
          let sym = match lookup_static_local(alloc, id) {
            Some(info) => sym_for_static_local(syms, info)
            None => sym_for_ident(syms, name, id=id)
          }
          emit_addr_global(emitter, syms, sym, dst)
        }
      }
    }
    Expr::CompoundLiteral(ty~, init~, node_id~, loc~, ..) => {
      ignore(
        gen_compound_literal_addr_with_type(
          emitter,
          alloc,
          syms,
          pool,
          cstrings,
          ty,
          init,
          loc,
          node_id,
          dst,
          bag,
        ),
      )
    }
    Expr::StmtExpr(stmts~, loc~, ..) => {
      let mut last_is_expr = false
      if stmts.length() > 0 {
        match stmts[stmts.length() - 1] {
          Stmt::ExprStmt(..) => last_is_expr = true
          _ => ()
        }
      }
      gen_stmt_expr_with(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        stmts,
        dst,
        true,
        loc,
        bag,
        (expr, dst) =>
          gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, expr, dst, bag),
      )
      if !last_is_expr {
        add_error(bag, loc, "codegen: statement expression is not assignable")
      }
    }
    Expr::Unary(op=UnaryOp::Deref, expr=inner, ..) =>
      gen_expr_ptr(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
    Expr::Index(base~, index~, loc~, ..) => {
      ignore(
        gen_index_addr_with_elem_type(
          emitter,
          alloc,
          syms,
          pool,
          cstrings,
          base,
          index,
          dst,
          loc,
          bag,
        ),
      )
    }
    Expr::Member(base~, name~, id~, is_arrow~, loc~, ..) => {
      let base_ty = type_of_expr(alloc.sem, base)
      if is_arrow {
        gen_expr_ptr(emitter, alloc, syms, pool, cstrings, base, dst, bag)
      } else if !expr_is_lvalue_simple(base) {
        match strip_top_qualifiers(base_ty) {
          CType::Struct(..) | CType::Union(..) =>
            if type_size_align_or_error(alloc.sem, base_ty, loc) is Some((size, _)) {
              match alloc.agg_temp_offset {
                None => add_error(bag, loc, "codegen: missing aggregate temp slot")
                Some(tmp_off) => {
                  if size > alloc.agg_temp_size {
                    add_error(bag, loc, "codegen: aggregate temp too small")
                    return
                  }
                  gen_agg_expr_to_addr(
                    emitter,
                    alloc,
                    syms,
                    pool,
                    cstrings,
                    base,
                    29,
                    tmp_off,
                    base_ty,
                    loc,
                    bag,
                  )
                  emit_addr_local(emitter, dst, tmp_off, loc, bag)
                }
              }
            }
          _ => gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, base, dst, bag)
        }
      } else {
        gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, base, dst, bag)
      }

      let record_ty = if is_arrow {
        match strip_top_qualifiers(base_ty) {
          CType::Pointer(pointee) => pointee
          _ => base_ty
        }
      } else {
        base_ty
      }
      let off = match record_field_access_info(alloc.sem, record_ty, name, id, loc) {
        None => 0
        Some(info) => info.offset
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
fn struct_field_access_info(
  ctx : SemContext,
  def : RecordDef,
  struct_attrs : Attributes,
  name : String,
  id : Int,
  loc : SrcLoc,
) -> FieldAccessInfo? {
  let fields = def.fields
  let attrs = merge_attrs(def.attrs, struct_attrs)
  let (struct_size, _) = struct_size_align(ctx, fields, attrs, loc)
  let mut size = 0
  let mut bit_pos = 0
  for field in fields {
    let packed = attrs.packed || field.attrs.packed
    let field_align_override = attr_align_value(ctx, field.attrs, field.loc)
    match field.bit_width {
      Some(expr) => {
        let width = const_int_from_expr(ctx, expr, field.loc).unwrap_or(0)
        let base = strip_top_qualifiers_keep_attrs(field.ty)
        let (base_size, base_align) = type_size_align(ctx, base, loc).unwrap_or((0, 1))
        let mut field_align = base_align
        if field_align_override is Some(value) {
          field_align = value
        }
        if width == 0 {
          let used_bytes = (bit_pos + 7) / 8
          size = align_to(size + used_bytes, field_align)
          bit_pos = 0
          continue
        }
        if packed && width != 0 {
          field_align = 1
        }
        if field_align_override is Some(value) {
          field_align = value
        }
        if field_align_override is Some(_) {
          let used_bytes = (bit_pos + 7) / 8
          size = align_to(size + used_bytes, field_align)
          bit_pos = 0
        } else if !packed {
          let a8 = field_align * 8
          let max_units = if field_align > 0 {
            base_size / field_align
          } else {
            0
          }
          if a8 > 0 {
            let ofs = ((size * 8 + bit_pos) % a8 + width + a8 - 1) / a8
            if ofs > max_units {
              let used_bytes = (bit_pos + 7) / 8
              size = align_to(size + used_bytes, field_align)
              bit_pos = 0
            }
          }
        }
        while bit_pos >= field_align * 8 {
          size = size + field_align
          bit_pos = bit_pos - field_align * 8
        }
        if (id > 0 && field.id == id) || field.name == name {
          let info = {
            offset: size,
            ty: field.ty,
            bit_offset: Some(bit_pos),
            bit_width: Some(width),
            bit_unit_size: None,
          }
          return Some(adjust_bitfield_access_info(ctx, struct_size, info, loc))
        }
        bit_pos = bit_pos + width
      }
      None => {
        if bit_pos != 0 {
          size = size + (bit_pos + 7) / 8
          bit_pos = 0
        }
        let (field_size, field_align) = match strip_top_qualifiers_keep_attrs(field.ty) {
          CType::Array(elem~, size=None, size_expr=size_expr, ..) =>
            match size_expr {
              None => {
                let (_elem_size, elem_align) = match
                  type_size_align(ctx, elem, field.loc) {
                  None => (0, 1)
                  Some(v) => v
                }
                (0, elem_align)
              }
              Some(_) =>
                match type_size_align(ctx, field.ty, field.loc) {
                  None => {
                    add_sem_error(
                      ctx,
                      field.loc,
                      "variable length array not allowed in struct",
                    )
                    (0, 1)
                  }
                  Some(v) => v
                }
            }
          _ =>
            match type_size_align(ctx, field.ty, loc) {
              None => (0, 1)
              Some(v) => v
            }
        }
        let mut adjusted_align = if packed { 1 } else { field_align }
        if field_align_override is Some(value) {
          adjusted_align = value
        }
        size = align_to(size, adjusted_align)
        if (id > 0 && field.id == id) || field.name == name {
          return Some({
            offset: size,
            ty: field.ty,
            bit_offset: None,
            bit_width: None,
            bit_unit_size: None,
          })
        }
        if field.name == "" {
          match strip_top_qualifiers(field.ty) {
            CType::Struct(..) | CType::Union(..) =>
              if record_field_access_info(ctx, field.ty, name, id, loc) is Some(inner) {
                return Some({
                  offset: size + inner.offset,
                  ty: inner.ty,
                  bit_offset: inner.bit_offset,
                  bit_width: inner.bit_width,
                  bit_unit_size: inner.bit_unit_size,
                })
              }
            _ => ()
          }
        }
        size = size + field_size
      }
    }
  }
  None
}

///|
fn union_field_access_info(
  ctx : SemContext,
  def : RecordDef,
  union_attrs : Attributes,
  name : String,
  id : Int,
  loc : SrcLoc,
) -> FieldAccessInfo? {
  let fields = def.fields
  let attrs = merge_attrs(def.attrs, union_attrs)
  let (union_size, _) = union_size_align(ctx, fields, attrs, loc)
  for field in fields {
    if field.bit_width is Some(expr) {
      if (id > 0 && field.id == id) || field.name == name {
        let width = match const_int_from_expr(ctx, expr, field.loc) {
          Some(v) => v
          None => 0
        }
        if width > 0 {
          let info = {
            offset: 0,
            ty: field.ty,
            bit_offset: Some(0),
            bit_width: Some(width),
            bit_unit_size: None,
          }
          return Some(adjust_bitfield_access_info(ctx, union_size, info, loc))
        }
      }
    }
    if (id > 0 && field.id == id) || field.name == name {
      return Some({
        offset: 0,
        ty: field.ty,
        bit_offset: None,
        bit_width: None,
        bit_unit_size: None,
      })
    }
    if field.name == "" {
      match strip_top_qualifiers(field.ty) {
        CType::Struct(..) | CType::Union(..) =>
          if record_field_access_info(ctx, field.ty, name, id, loc) is Some(inner) {
            return Some({
              offset: inner.offset,
              ty: inner.ty,
              bit_offset: inner.bit_offset,
              bit_width: inner.bit_width,
              bit_unit_size: inner.bit_unit_size,
            })
          }
        _ => ()
      }
    }
  }
  None
}

///|
fn add_field_access_entry(
  cache : FastMap[String, FieldAccessInfo],
  name : String,
  info : FieldAccessInfo,
) -> Unit {
  if name == "" || cache.contains(name) {
    return
  }
  cache.set(name, info)
}

///|
fn add_field_access_entry_by_id(
  cache : FastMap[Int, FieldAccessInfo],
  id : Int,
  info : FieldAccessInfo,
) -> Unit {
  if id <= 0 || cache.contains(id) {
    return
  }
  cache.set(id, info)
}

///|
fn collect_struct_field_access_cache(
  ctx : SemContext,
  fields : Array[Field],
  attrs : Attributes,
  loc : SrcLoc,
  cache : FastMap[String, FieldAccessInfo],
  cache_by_id : FastMap[Int, FieldAccessInfo],
) -> Unit {
  let (struct_size, _) = struct_size_align(ctx, fields, attrs, loc)
  let mut size = 0
  let mut bit_pos = 0
  for field in fields {
    let packed = attrs.packed || field.attrs.packed
    let field_align_override = attr_align_value(ctx, field.attrs, field.loc)
    match field.bit_width {
      Some(expr) => {
        let width = match const_int_from_expr(ctx, expr, field.loc) {
          Some(v) => v
          None => 0
        }
        let base = strip_top_qualifiers_keep_attrs(field.ty)
        let (base_size, base_align) = match type_size_align(ctx, base, loc) {
          None => (0, 1)
          Some(v) => v
        }
        let mut field_align = base_align
        if field_align_override is Some(value) {
          field_align = value
        }
        if width == 0 {
          let used_bytes = (bit_pos + 7) / 8
          size = align_to(size + used_bytes, field_align)
          bit_pos = 0
          continue
        }
        if packed && width != 0 {
          field_align = 1
        }
        if field_align_override is Some(value) {
          field_align = value
        }
        if field_align_override is Some(_) {
          let used_bytes = (bit_pos + 7) / 8
          size = align_to(size + used_bytes, field_align)
          bit_pos = 0
        } else if !packed {
          let a8 = field_align * 8
          let max_units = if field_align > 0 {
            base_size / field_align
          } else {
            0
          }
          if a8 > 0 {
            let ofs = ((size * 8 + bit_pos) % a8 + width + a8 - 1) / a8
            if ofs > max_units {
              let used_bytes = (bit_pos + 7) / 8
              size = align_to(size + used_bytes, field_align)
              bit_pos = 0
            }
          }
        }
        while bit_pos >= field_align * 8 {
          size = size + field_align
          bit_pos = bit_pos - field_align * 8
        }
        let info = adjust_bitfield_access_info(ctx, struct_size, {
          offset: size,
          ty: field.ty,
          bit_offset: Some(bit_pos),
          bit_width: Some(width),
          bit_unit_size: None,
        }, loc)
        add_field_access_entry(cache, field.name, info)
        add_field_access_entry_by_id(cache_by_id, field.id, info)
        bit_pos = bit_pos + width
      }
      None => {
        if bit_pos != 0 {
          size = size + (bit_pos + 7) / 8
          bit_pos = 0
        }
        let (field_size, field_align) = match strip_top_qualifiers_keep_attrs(field.ty) {
          CType::Array(elem~, size=None, size_expr=size_expr, ..) =>
            match size_expr {
              None => {
                let (_elem_size, elem_align) = match
                  type_size_align(ctx, elem, field.loc) {
                  None => (0, 1)
                  Some(v) => v
                }
                (0, elem_align)
              }
              Some(_) =>
                match type_size_align(ctx, field.ty, field.loc) {
                  None => {
                    add_sem_error(
                      ctx,
                      field.loc,
                      "variable length array not allowed in struct",
                    )
                    (0, 1)
                  }
                  Some(v) => v
                }
            }
          _ =>
            match type_size_align(ctx, field.ty, loc) {
              None => (0, 1)
              Some(v) => v
            }
        }
        let mut adjusted_align = if packed { 1 } else { field_align }
        if field_align_override is Some(value) {
          adjusted_align = value
        }
        size = align_to(size, adjusted_align)
        let info = {
          offset: size,
          ty: field.ty,
          bit_offset: None,
          bit_width: None,
          bit_unit_size: None,
        }
        add_field_access_entry(cache, field.name, info)
        add_field_access_entry_by_id(cache_by_id, field.id, info)
        if field.name == "" {
          match strip_top_qualifiers(field.ty) {
            CType::Struct(..) | CType::Union(..) => {
              let (nested_by_name, nested_by_id) = build_record_field_access_caches(
                ctx,
                field.ty,
                loc,
              )
              for nested_name, nested_info in nested_by_name {
                add_field_access_entry(cache, nested_name, {
                  offset: size + nested_info.offset,
                  ty: nested_info.ty,
                  bit_offset: nested_info.bit_offset,
                  bit_width: nested_info.bit_width,
                  bit_unit_size: nested_info.bit_unit_size,
                })
              }
              for nested_id, nested_info in nested_by_id {
                add_field_access_entry_by_id(cache_by_id, nested_id, {
                  offset: size + nested_info.offset,
                  ty: nested_info.ty,
                  bit_offset: nested_info.bit_offset,
                  bit_width: nested_info.bit_width,
                  bit_unit_size: nested_info.bit_unit_size,
                })
              }
            }
            _ => ()
          }
        }
        size = size + field_size
      }
    }
  }
}

///|
fn collect_union_field_access_cache(
  ctx : SemContext,
  fields : Array[Field],
  attrs : Attributes,
  loc : SrcLoc,
  cache : FastMap[String, FieldAccessInfo],
  cache_by_id : FastMap[Int, FieldAccessInfo],
) -> Unit {
  let (union_size, _) = union_size_align(ctx, fields, attrs, loc)
  for field in fields {
    if field.bit_width is Some(expr) {
      let width = match const_int_from_expr(ctx, expr, field.loc) {
        Some(v) => v
        None => 0
      }
      if width > 0 {
        let info = adjust_bitfield_access_info(ctx, union_size, {
          offset: 0,
          ty: field.ty,
          bit_offset: Some(0),
          bit_width: Some(width),
          bit_unit_size: None,
        }, loc)
        add_field_access_entry(cache, field.name, info)
        add_field_access_entry_by_id(cache_by_id, field.id, info)
      }
      continue
    }
    let info = {
      offset: 0,
      ty: field.ty,
      bit_offset: None,
      bit_width: None,
      bit_unit_size: None,
    }
    add_field_access_entry(cache, field.name, info)
    add_field_access_entry_by_id(cache_by_id, field.id, info)
    if field.name == "" {
      match strip_top_qualifiers(field.ty) {
        CType::Struct(..) | CType::Union(..) => {
          let (nested_by_name, nested_by_id) = build_record_field_access_caches(
            ctx,
            field.ty,
            loc,
          )
          for nested_name, nested_info in nested_by_name {
            add_field_access_entry(cache, nested_name, {
              offset: nested_info.offset,
              ty: nested_info.ty,
              bit_offset: nested_info.bit_offset,
              bit_width: nested_info.bit_width,
              bit_unit_size: nested_info.bit_unit_size,
            })
          }
          for nested_id, nested_info in nested_by_id {
            add_field_access_entry_by_id(cache_by_id, nested_id, {
              offset: nested_info.offset,
              ty: nested_info.ty,
              bit_offset: nested_info.bit_offset,
              bit_width: nested_info.bit_width,
              bit_unit_size: nested_info.bit_unit_size,
            })
          }
        }
        _ => ()
      }
    }
  }
}

///|
fn build_struct_field_access_caches(
  ctx : SemContext,
  def : RecordDef,
  struct_attrs : Attributes,
  loc : SrcLoc,
) -> (FastMap[String, FieldAccessInfo], FastMap[Int, FieldAccessInfo]) {
  let cache_by_name : FastMap[String, FieldAccessInfo] = fast_map_new()
  let cache_by_id : FastMap[Int, FieldAccessInfo] = fast_map_new()
  let attrs = merge_attrs(def.attrs, struct_attrs)
  collect_struct_field_access_cache(ctx, def.fields, attrs, loc, cache_by_name, cache_by_id)
  (cache_by_name, cache_by_id)
}

///|
fn build_union_field_access_caches(
  ctx : SemContext,
  def : RecordDef,
  union_attrs : Attributes,
  loc : SrcLoc,
) -> (FastMap[String, FieldAccessInfo], FastMap[Int, FieldAccessInfo]) {
  let cache_by_name : FastMap[String, FieldAccessInfo] = fast_map_new()
  let cache_by_id : FastMap[Int, FieldAccessInfo] = fast_map_new()
  let attrs = merge_attrs(def.attrs, union_attrs)
  collect_union_field_access_cache(ctx, def.fields, attrs, loc, cache_by_name, cache_by_id)
  (cache_by_name, cache_by_id)
}

///|
fn record_field_access_info(
  ctx : SemContext,
  record_ty : CType,
  name : String,
  id : Int,
  loc : SrcLoc,
) -> FieldAccessInfo? {
  let resolved = resolve_type(ctx, record_ty, loc) |> strip_top_qualifiers
  match resolved {
    CType::Struct(name=tag, id=tag_id, fields=field_list, attrs=struct_attrs) =>
      match ensure_struct_fields(
        ctx,
        tag,
        tag_id,
        field_list,
        is_union=false,
        loc,
      ) {
        None => None
        Some(def) =>
          if tag != "" &&
            attrs_layout_empty(struct_attrs) &&
            (if tag_id != 0 {
              has_opt_by_id(ctx.struct_defs_by_id, tag_id)
            } else {
              ctx.struct_defs.contains(tag)
            }) {
            if id > 0 && tag_id != 0 {
              let cache = match get_opt_by_id(ctx.struct_field_access_cache_by_id, tag_id) {
                Some(existing) => existing
                None => {
                  let (built_name, built_id) = build_struct_field_access_caches(
                    ctx,
                    def,
                    struct_attrs,
                    loc,
                  )
                  set_opt_by_id(ctx.struct_field_access_cache_by_id, tag_id, built_id)
                  ctx.struct_field_access_cache.set(tag, built_name)
                  built_id
                }
              }
              match cache.get(id) {
                Some(info) => Some(info)
                None =>
                  if name == "" {
                    None
                  } else {
                    match ctx.struct_field_access_cache.get(tag) {
                      Some(by_name) => by_name.get(name)
                      None => None
                    }
                  }
              }
            } else {
              let cache = match ctx.struct_field_access_cache.get(tag) {
                Some(existing) => existing
                None => {
                  let (built_name, built_id) = build_struct_field_access_caches(
                    ctx,
                    def,
                    struct_attrs,
                    loc,
                  )
                  ctx.struct_field_access_cache.set(tag, built_name)
                  if tag_id != 0 {
                    set_opt_by_id(ctx.struct_field_access_cache_by_id, tag_id, built_id)
                  }
                  built_name
                }
              }
              cache.get(name)
            }
          } else {
            struct_field_access_info(ctx, def, struct_attrs, name, id, loc)
          }
      }
    CType::Union(name=tag, id=tag_id, fields=field_list, attrs=union_attrs) =>
      match ensure_struct_fields(
        ctx,
        tag,
        tag_id,
        field_list,
        is_union=true,
        loc,
      ) {
        None => None
        Some(def) =>
          if tag != "" &&
            attrs_layout_empty(union_attrs) &&
            (if tag_id != 0 {
              has_opt_by_id(ctx.union_defs_by_id, tag_id)
            } else {
              ctx.union_defs.contains(tag)
            }) {
            if id > 0 && tag_id != 0 {
              let cache = match get_opt_by_id(ctx.union_field_access_cache_by_id, tag_id) {
                Some(existing) => existing
                None => {
                  let (built_name, built_id) = build_union_field_access_caches(
                    ctx,
                    def,
                    union_attrs,
                    loc,
                  )
                  set_opt_by_id(ctx.union_field_access_cache_by_id, tag_id, built_id)
                  ctx.union_field_access_cache.set(tag, built_name)
                  built_id
                }
              }
              match cache.get(id) {
                Some(info) => Some(info)
                None =>
                  if name == "" {
                    None
                  } else {
                    match ctx.union_field_access_cache.get(tag) {
                      Some(by_name) => by_name.get(name)
                      None => None
                    }
                  }
              }
            } else {
              let cache = match ctx.union_field_access_cache.get(tag) {
                Some(existing) => existing
                None => {
                  let (built_name, built_id) = build_union_field_access_caches(
                    ctx,
                    def,
                    union_attrs,
                    loc,
                  )
                  ctx.union_field_access_cache.set(tag, built_name)
                  if tag_id != 0 {
                    set_opt_by_id(ctx.union_field_access_cache_by_id, tag_id, built_id)
                  }
                  built_name
                }
              }
              cache.get(name)
            }
          } else {
            union_field_access_info(ctx, def, union_attrs, name, id, loc)
          }
      }
    _ => None
  }
}

///|
fn build_record_field_access_caches(
  ctx : SemContext,
  record_ty : CType,
  loc : SrcLoc,
) -> (FastMap[String, FieldAccessInfo], FastMap[Int, FieldAccessInfo]) {
  let resolved = resolve_type(ctx, record_ty, loc) |> strip_top_qualifiers
  match resolved {
    CType::Struct(name=tag, id=tag_id, fields=field_list, attrs=struct_attrs) =>
      match ensure_struct_fields(
        ctx,
        tag,
        tag_id,
        field_list,
        is_union=false,
        loc,
      ) {
        None => (fast_map_new(), fast_map_new())
        Some(def) =>
          if tag != "" &&
            attrs_layout_empty(struct_attrs) &&
            (if tag_id != 0 {
              has_opt_by_id(ctx.struct_defs_by_id, tag_id)
            } else {
              ctx.struct_defs.contains(tag)
            }) {
            let by_name = ctx.struct_field_access_cache.get(tag)
            let by_id = if tag_id != 0 {
              get_opt_by_id(ctx.struct_field_access_cache_by_id, tag_id)
            } else {
              None
            }
            match (by_name, by_id) {
              (Some(name_cache), Some(id_cache)) => (name_cache, id_cache)
              _ => {
                let (built_name, built_id) = build_struct_field_access_caches(
                  ctx,
                  def,
                  struct_attrs,
                  loc,
                )
                ctx.struct_field_access_cache.set(tag, built_name)
                if tag_id != 0 {
                  set_opt_by_id(ctx.struct_field_access_cache_by_id, tag_id, built_id)
                }
                (built_name, built_id)
              }
            }
          } else {
            build_struct_field_access_caches(ctx, def, struct_attrs, loc)
          }
      }
    CType::Union(name=tag, id=tag_id, fields=field_list, attrs=union_attrs) =>
      match ensure_struct_fields(
        ctx,
        tag,
        tag_id,
        field_list,
        is_union=true,
        loc,
      ) {
        None => (fast_map_new(), fast_map_new())
        Some(def) =>
          if tag != "" &&
            attrs_layout_empty(union_attrs) &&
            (if tag_id != 0 {
              has_opt_by_id(ctx.union_defs_by_id, tag_id)
            } else {
              ctx.union_defs.contains(tag)
            }) {
            let by_name = ctx.union_field_access_cache.get(tag)
            let by_id = if tag_id != 0 {
              get_opt_by_id(ctx.union_field_access_cache_by_id, tag_id)
            } else {
              None
            }
            match (by_name, by_id) {
              (Some(name_cache), Some(id_cache)) => (name_cache, id_cache)
              _ => {
                let (built_name, built_id) = build_union_field_access_caches(
                  ctx,
                  def,
                  union_attrs,
                  loc,
                )
                ctx.union_field_access_cache.set(tag, built_name)
                if tag_id != 0 {
                  set_opt_by_id(ctx.union_field_access_cache_by_id, tag_id, built_id)
                }
                (built_name, built_id)
              }
            }
          } else {
            build_union_field_access_caches(ctx, def, union_attrs, loc)
          }
      }
    _ => (fast_map_new(), fast_map_new())
  }
}

///|
fn member_access_info(
  sem : SemContext,
  base : Expr,
  name : String,
  id : Int,
  is_arrow : Bool,
  loc : SrcLoc,
) -> FieldAccessInfo? {
  let base_ty = type_of_expr(sem, base)
  let record_ty = if is_arrow {
    match strip_top_qualifiers(base_ty) {
      CType::Pointer(pointee) => pointee
      _ => base_ty
    }
  } else {
    base_ty
  }
  record_field_access_info(sem, record_ty, name, id, loc)
}

///|
fn member_access_info_from_base_type(
  sem : SemContext,
  base_ty : CType,
  name : String,
  id : Int,
  is_arrow : Bool,
  loc : SrcLoc,
) -> FieldAccessInfo? {
  let record_ty = if is_arrow {
    match strip_top_qualifiers(base_ty) {
      CType::Pointer(pointee) => pointee
      _ => base_ty
    }
  } else {
    base_ty
  }
  record_field_access_info(sem, record_ty, name, id, loc)
}

///|
fn member_bitfield_info(
  alloc : LocalAlloc,
  expr : Expr,
) -> (Expr, Bool, FieldAccessInfo)? {
  match expr {
    Expr::Member(base~, name~, id~, is_arrow~, loc~, ..) =>
      match member_access_info(alloc.sem, base, name, id, is_arrow, loc) {
        Some(info) =>
          match info.bit_width {
            Some(_) => Some((base, is_arrow, info))
            None => None
          }
        None => None
      }
    _ => None
  }
}

///|
fn gen_member_base_addr(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  base : Expr,
  is_arrow : Bool,
  dst : Int,
  bag : DiagBag,
) -> Unit {
  if is_arrow {
    gen_expr_ptr(emitter, alloc, syms, pool, cstrings, base, dst, bag)
  } else {
    gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, base, dst, bag)
  }
}

///|
fn gen_member_addr_with_info(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  base : Expr,
  base_ty : CType,
  is_arrow : Bool,
  info : FieldAccessInfo,
  dst : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  if is_arrow {
    gen_expr_ptr(emitter, alloc, syms, pool, cstrings, base, dst, bag)
  } else if !expr_is_lvalue_simple(base) {
    match strip_top_qualifiers(base_ty) {
      CType::Struct(..) | CType::Union(..) =>
        if type_size_align_or_error(alloc.sem, base_ty, loc) is Some((size, _)) {
          match alloc.agg_temp_offset {
            None => add_error(bag, loc, "codegen: missing aggregate temp slot")
            Some(tmp_off) => {
              if size > alloc.agg_temp_size {
                add_error(bag, loc, "codegen: aggregate temp too small")
                return
              }
              gen_agg_expr_to_addr(
                emitter,
                alloc,
                syms,
                pool,
                cstrings,
                base,
                29,
                tmp_off,
                base_ty,
                loc,
                bag,
              )
              emit_addr_local(emitter, dst, tmp_off, loc, bag)
            }
          }
        }
      _ => gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, base, dst, bag)
    }
  } else {
    gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, base, dst, bag)
  }

  let off = info.offset
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
      let base_inst = if off < 0 { 0xcb000000 } else { 0x8b000000 }
      emit32(
        emitter,
        (base_inst : Int)
        .lor(dst)
        .lor(dst << 5)
        .lor(tmp << 16)
        .reinterpret_as_uint(),
      )
      give_reg(pool, tmp)
    }
  }
}

///|
fn bitfield_access_size_for_bytes(bytes : Int) -> Int {
  if bytes <= 1 {
    1
  } else if bytes <= 2 {
    2
  } else if bytes <= 4 {
    4
  } else {
    8
  }
}

///|
fn adjust_bitfield_access_info(
  ctx : SemContext,
  struct_size : Int,
  info : FieldAccessInfo,
  loc : SrcLoc,
) -> FieldAccessInfo {
  match info.bit_width {
    None => info
    Some(width) => {
      let bit_off = match info.bit_offset {
        None => 0
        Some(v) => v
      }
      let (base_size, _base_align) = match type_size_align(ctx, info.ty, loc) {
        None => return info
        Some(v) => v
      }
      if base_size > 0 {
        let unit_bits = base_size * 8
        if bit_off + width <= unit_bits && info.offset + base_size <= struct_size {
          return {
            offset: info.offset,
            ty: info.ty,
            bit_offset: Some(bit_off),
            bit_width: Some(width),
            bit_unit_size: Some(base_size),
          }
        }
      }
      let overall = info.offset * 8 + bit_off
      let mut last_cx = -1
      let mut size = 1
      let mut align = 1
      let mut bit_pos = 0
      let mut cx = 0
      while true {
        let candidate_cx = ((overall >> 3) & -align)
        bit_pos = overall - candidate_cx * 8
        if candidate_cx == last_cx {
          cx = candidate_cx
          break
        }
        let bytes_needed = (bit_pos + width + 7) / 8
        size = bitfield_access_size_for_bytes(bytes_needed)
        align = size
        last_cx = candidate_cx
      }
      if bit_pos + width <= size * 8 && cx + size <= struct_size {
        return {
          offset: cx,
          ty: info.ty,
          bit_offset: Some(bit_pos),
          bit_width: Some(width),
          bit_unit_size: Some(size),
        }
      }
      {
        offset: info.offset,
        ty: info.ty,
        bit_offset: Some(bit_off),
        bit_width: Some(width),
        bit_unit_size: None,
      }
    }
  }
}

///|
fn emit_and_reg(emitter : Arm64Emitter, is64 : Bool, dst : Int, lhs : Int, rhs : Int) -> Unit {
  let base : Int = if is64 { 0x8a000000 } else { 0x0a000000 }
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
fn emit_or_reg(emitter : Arm64Emitter, is64 : Bool, dst : Int, lhs : Int, rhs : Int) -> Unit {
  let base : Int = if is64 { 0xaa000000 } else { 0x2a000000 }
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
fn emit_bitfield_load_packed(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  pool : RegPool,
  addr_reg : Int,
  info : FieldAccessInfo,
  dst : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let width = match info.bit_width {
    None => 0
    Some(v) => v
  }
  let bit_off = match info.bit_offset {
    None => 0
    Some(v) => v
  }
  if width <= 0 {
    arm64_movimm(emitter, dst.reinterpret_as_uint(), 0)
    return
  }
  let (_decl_size, signed) = match scalar_size_signed_or_error(alloc.sem, info.ty, loc) {
    None => return
    Some(v) => v
  }
  let is64 = _decl_size == 8 || width > 32
  let l = if is64 { 1 } else { 0 }
  let unit_bits = if is64 { 64 } else { 32 }
  arm64_movimm(emitter, dst.reinterpret_as_uint(), 0)
  let tmp = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      return
    }
  }
  let mut remaining = width
  let mut bits_collected = 0
  let mut bit_in = bit_off & 7
  let mut byte_off = bit_off / 8
  while remaining > 0 {
    arm64_ldrx(
      emitter,
      false,
      0,
      tmp.reinterpret_as_uint(),
      addr_reg.reinterpret_as_uint(),
      (info.offset + byte_off).to_int64().reinterpret_as_uint64(),
    )
    if bit_in > 0 {
      arm64_gen_opic(
        emitter,
        TOK_SHR,
        l,
        false,
        bit_in.to_uint64(),
        tmp,
        tmp,
      ) |> ignore
    }
    let n = if remaining < 8 - bit_in { remaining } else { 8 - bit_in }
    if n < 8 {
      let mask : UInt64 = ((1 : UInt64) << n) - (1 : UInt64)
      if !arm64_gen_opic(emitter, TOK_AND, l, false, mask, tmp, tmp) {
        let mask_reg = take_reg(pool) catch {
          err => {
            add_error(bag, loc, err.to_string())
            give_reg(pool, tmp)
            return
          }
        }
        arm64_movimm(emitter, mask_reg.reinterpret_as_uint(), mask)
        emit_and_reg(emitter, is64, tmp, tmp, mask_reg)
        give_reg(pool, mask_reg)
      }
    }
    if bits_collected > 0 {
      arm64_gen_opic(
        emitter,
        TOK_SHL,
        l,
        false,
        bits_collected.to_uint64(),
        tmp,
        tmp,
      ) |> ignore
    }
    emit_or_reg(emitter, is64, dst, dst, tmp)
    remaining = remaining - n
    bits_collected = bits_collected + n
    bit_in = 0
    byte_off = byte_off + 1
  }
  give_reg(pool, tmp)
  if signed && width < unit_bits {
    let shift = unit_bits - width
    arm64_gen_opic(
      emitter,
      TOK_SHL,
      l,
      false,
      shift.to_uint64(),
      dst,
      dst,
    ) |> ignore
    arm64_gen_opic(
      emitter,
      TOK_SAR,
      l,
      false,
      shift.to_uint64(),
      dst,
      dst,
    ) |> ignore
  }
}

///|
fn emit_bitfield_store_packed(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  pool : RegPool,
  addr_reg : Int,
  info : FieldAccessInfo,
  value_reg : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let width = match info.bit_width {
    None => 0
    Some(v) => v
  }
  let bit_off = match info.bit_offset {
    None => 0
    Some(v) => v
  }
  if width <= 0 {
    return
  }
  let (decl_size, _) = match scalar_size_signed_or_error(alloc.sem, info.ty, loc) {
    None => return
    Some(v) => v
  }
  let is64 = decl_size == 8 || width > 32
  let l = if is64 { 1 } else { 0 }
  let tmp = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      return
    }
  }
  let chunk = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      give_reg(pool, tmp)
      return
    }
  }
  let mut remaining = width
  let mut bits_used = 0
  let mut bit_in = bit_off & 7
  let mut byte_off = bit_off / 8
  while remaining > 0 {
    let n = if remaining < 8 - bit_in { remaining } else { 8 - bit_in }
    emit_mov(emitter, is64, chunk, value_reg)
    if bits_used > 0 {
      arm64_gen_opic(
        emitter,
        TOK_SHR,
        l,
        false,
        bits_used.to_uint64(),
        chunk,
        chunk,
      ) |> ignore
    }
    if bit_in > 0 {
      arm64_gen_opic(
        emitter,
        TOK_SHL,
        l,
        false,
        bit_in.to_uint64(),
        chunk,
        chunk,
      ) |> ignore
    }
    let mask : UInt64 = (((1 : UInt64) << n) - (1 : UInt64)) << bit_in
    if n < 8 {
      if !arm64_gen_opic(emitter, TOK_AND, l, false, mask, chunk, chunk) {
        let mask_reg = take_reg(pool) catch {
          err => {
            add_error(bag, loc, err.to_string())
            give_reg(pool, chunk)
            give_reg(pool, tmp)
            return
          }
        }
        arm64_movimm(emitter, mask_reg.reinterpret_as_uint(), mask)
        emit_and_reg(emitter, is64, chunk, chunk, mask_reg)
        give_reg(pool, mask_reg)
      }
    }
    if n == 8 && bit_in == 0 {
      arm64_strx(
        emitter,
        0,
        chunk.reinterpret_as_uint(),
        addr_reg.reinterpret_as_uint(),
        (info.offset + byte_off).to_int64().reinterpret_as_uint64(),
      )
    } else {
      arm64_ldrx(
        emitter,
        false,
        0,
        tmp.reinterpret_as_uint(),
        addr_reg.reinterpret_as_uint(),
        (info.offset + byte_off).to_int64().reinterpret_as_uint64(),
      )
      let inv_mask : UInt64 = (0xff : UInt64) & mask.lnot()
      if !arm64_gen_opic(emitter, TOK_AND, l, false, inv_mask, tmp, tmp) {
        let mask_reg = take_reg(pool) catch {
          err => {
            add_error(bag, loc, err.to_string())
            give_reg(pool, chunk)
            give_reg(pool, tmp)
            return
          }
        }
        arm64_movimm(emitter, mask_reg.reinterpret_as_uint(), inv_mask)
        emit_and_reg(emitter, is64, tmp, tmp, mask_reg)
        give_reg(pool, mask_reg)
      }
      emit_or_reg(emitter, is64, tmp, tmp, chunk)
      arm64_strx(
        emitter,
        0,
        tmp.reinterpret_as_uint(),
        addr_reg.reinterpret_as_uint(),
        (info.offset + byte_off).to_int64().reinterpret_as_uint64(),
      )
    }
    remaining = remaining - n
    bits_used = bits_used + n
    bit_in = 0
    byte_off = byte_off + 1
  }
  give_reg(pool, chunk)
  give_reg(pool, tmp)
}

///|
fn emit_bitfield_load(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  pool : RegPool,
  addr_reg : Int,
  info : FieldAccessInfo,
  dst : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let width = match info.bit_width {
    None => 0
    Some(v) => v
  }
  let bit_off = match info.bit_offset {
    None => 0
    Some(v) => v
  }
  if width <= 0 {
    arm64_movimm(emitter, dst.reinterpret_as_uint(), 0)
    return
  }
  let (_decl_size, signed) = match scalar_size_signed_or_error(alloc.sem, info.ty, loc) {
    None => return
    Some(v) => v
  }
  let unit_size = match info.bit_unit_size {
    None => {
      emit_bitfield_load_packed(emitter, alloc, pool, addr_reg, info, dst, loc, bag)
      return
    }
    Some(v) => v
  }
  let unit_bits = unit_size * 8
  let sz = match arm64_sz_from_size(unit_size) {
    None => {
      add_error(bag, loc, "codegen: unsupported bitfield size")
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
    info.offset.to_int64().reinterpret_as_uint64(),
  )
  let l = if unit_size == 8 { 1 } else { 0 }
  if bit_off > 0 {
    arm64_gen_opic(
      emitter,
      TOK_SHR,
      l,
      false,
      bit_off.to_uint64(),
      dst,
      dst,
    ) |> ignore
  }
  if width < unit_bits {
    let mask : UInt64 = if width >= unit_bits {
      (0 : UInt64).lnot()
    } else {
      ((1 : UInt64) << width) - (1 : UInt64)
    }
    if !arm64_gen_opic(emitter, TOK_AND, l, false, mask, dst, dst) {
      let tmp = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      arm64_movimm(emitter, tmp.reinterpret_as_uint(), mask)
      emit_and_reg(emitter, l != 0, dst, dst, tmp)
      give_reg(pool, tmp)
    }
  }
  if signed && width < unit_bits {
    let shift = unit_bits - width
    arm64_gen_opic(
      emitter,
      TOK_SHL,
      l,
      false,
      shift.to_uint64(),
      dst,
      dst,
    ) |> ignore
    arm64_gen_opic(
      emitter,
      TOK_SAR,
      l,
      false,
      shift.to_uint64(),
      dst,
      dst,
    ) |> ignore
  }
}

///|
fn emit_bitfield_store(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  pool : RegPool,
  addr_reg : Int,
  info : FieldAccessInfo,
  value_reg : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  let width = match info.bit_width {
    None => 0
    Some(v) => v
  }
  let bit_off = match info.bit_offset {
    None => 0
    Some(v) => v
  }
  if width <= 0 {
    return
  }
  let (_decl_size, _) = match scalar_size_signed_or_error(alloc.sem, info.ty, loc) {
    None => return
    Some(v) => v
  }
  let unit_size = match info.bit_unit_size {
    None => {
      emit_bitfield_store_packed(emitter, alloc, pool, addr_reg, info, value_reg, loc, bag)
      return
    }
    Some(v) => v
  }
  let unit_bits = unit_size * 8
  let sz = match arm64_sz_from_size(unit_size) {
    None => {
      add_error(bag, loc, "codegen: unsupported bitfield size")
      return
    }
    Some(v) => v
  }
  let is64 = unit_size == 8
  if width == unit_bits && bit_off == 0 {
    arm64_strx(
      emitter,
      sz,
      value_reg.reinterpret_as_uint(),
      addr_reg.reinterpret_as_uint(),
      info.offset.to_int64().reinterpret_as_uint64(),
    )
    return
  }
  let unit_reg = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      return
    }
  }
  arm64_ldrx(
    emitter,
    false,
    sz,
    unit_reg.reinterpret_as_uint(),
    addr_reg.reinterpret_as_uint(),
    info.offset.to_int64().reinterpret_as_uint64(),
  )
  let val_reg = take_reg(pool) catch {
    err => {
      add_error(bag, loc, err.to_string())
      give_reg(pool, unit_reg)
      return
    }
  }
  emit_mov(emitter, is64, val_reg, value_reg)
  let l = if is64 { 1 } else { 0 }
  if width < unit_bits {
    let mask : UInt64 = if width >= unit_bits {
      (0 : UInt64).lnot()
    } else {
      ((1 : UInt64) << width) - (1 : UInt64)
    }
    if !arm64_gen_opic(emitter, TOK_AND, l, false, mask, val_reg, val_reg) {
      let tmp = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          give_reg(pool, val_reg)
          give_reg(pool, unit_reg)
          return
        }
      }
      arm64_movimm(emitter, tmp.reinterpret_as_uint(), mask)
      emit_and_reg(emitter, is64, val_reg, val_reg, tmp)
      give_reg(pool, tmp)
    }
  }
  if bit_off > 0 {
    arm64_gen_opic(
      emitter,
      TOK_SHL,
      l,
      false,
      bit_off.to_uint64(),
      val_reg,
      val_reg,
    ) |> ignore
  }
  if width < unit_bits {
    let mask : UInt64 = if width >= unit_bits {
      (0 : UInt64).lnot()
    } else {
      ((1 : UInt64) << width) - (1 : UInt64)
    }
    let mask_shift = mask << bit_off
    let unit_mask : UInt64 = if unit_bits == 64 {
      (0 : UInt64).lnot()
    } else {
      ((1 : UInt64) << unit_bits) - (1 : UInt64)
    }
    let inv_mask = unit_mask & (mask_shift.lnot())
    if !arm64_gen_opic(emitter, TOK_AND, l, false, inv_mask, unit_reg, unit_reg) {
      let tmp = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          give_reg(pool, val_reg)
          give_reg(pool, unit_reg)
          return
        }
      }
      arm64_movimm(emitter, tmp.reinterpret_as_uint(), inv_mask)
      emit_and_reg(emitter, is64, unit_reg, unit_reg, tmp)
      give_reg(pool, tmp)
    }
  }
  emit_or_reg(emitter, is64, unit_reg, unit_reg, val_reg)
  arm64_strx(
    emitter,
    sz,
    unit_reg.reinterpret_as_uint(),
    addr_reg.reinterpret_as_uint(),
    info.offset.to_int64().reinterpret_as_uint64(),
  )
  give_reg(pool, val_reg)
  give_reg(pool, unit_reg)
}

///|
fn store_lvalue_scalar(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  lvalue : Expr,
  value_reg : Int,
  value_ty : CType,
  bag : DiagBag,
) -> Unit {
  let loc = expr_loc(lvalue)
  let (value_size, _) = match scalar_size_signed_or_error(alloc.sem, value_ty, loc) {
    None => return
    Some(v) => v
  }
  let mut saved_reg : Int? = None
  let mut store_reg = value_reg
  if expr_may_call(lvalue) {
    let tmp = take_reg(pool) catch {
      err => {
        add_error(bag, loc, err.to_string())
        return
      }
    }
    emit_mov(emitter, value_size == 8, tmp, value_reg)
    saved_reg = Some(tmp)
    store_reg = tmp
  }
  if member_bitfield_info(alloc, lvalue) is Some((base, is_arrow, info)) {
    let addr = take_reg(pool) catch {
      err => {
        add_error(bag, loc, err.to_string())
        if saved_reg is Some(r) {
          give_reg(pool, r)
        }
        return
      }
    }
    gen_member_base_addr(emitter, alloc, syms, pool, cstrings, base, is_arrow, addr, bag)
    emit_bitfield_store(emitter, alloc, pool, addr, info, store_reg, loc, bag)
    give_reg(pool, addr)
    if saved_reg is Some(r) {
      give_reg(pool, r)
    }
    return
  }
  match lvalue {
    Expr::Ident(name~, id~, ..) =>
      match lookup_local(alloc, name, id) {
        Some(slot) =>
          emit_store_local_scalar(
            emitter,
            alloc.sem,
            slot.ty,
            store_reg,
            slot.offset,
            loc,
            bag,
          )
        None => {
          let sym = match lookup_static_local(alloc, id) {
            Some(info) => sym_for_static_local(syms, info)
            None => sym_for_ident(syms, name, id=id)
          }
          let addr_reg : Int = 16
          emit_addr_global(emitter, syms, sym, addr_reg)
          let sz = match arm64_sz_from_size(value_size) {
            None => {
              add_error(bag, loc, "codegen: unsupported scalar size")
              if saved_reg is Some(r) {
                give_reg(pool, r)
              }
              return
            }
            Some(v) => v
          }
          arm64_strx(
            emitter,
            sz,
            store_reg.reinterpret_as_uint(),
            addr_reg.reinterpret_as_uint(),
            0,
          )
        }
      }
    _ => {
      let addr = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          if saved_reg is Some(r) {
            give_reg(pool, r)
          }
          return
        }
      }
      gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, lvalue, addr, bag)
      let sz = match arm64_sz_from_size(value_size) {
        None => {
          add_error(bag, loc, "codegen: unsupported scalar size")
          give_reg(pool, addr)
          if saved_reg is Some(r) {
            give_reg(pool, r)
          }
          return
        }
        Some(v) => v
      }
      arm64_strx(
        emitter,
        sz,
        store_reg.reinterpret_as_uint(),
        addr.reinterpret_as_uint(),
        0,
      )
      give_reg(pool, addr)
    }
  }
  if saved_reg is Some(r) {
    give_reg(pool, r)
  }
}

///|
fn gen_expr_to_float_kind_bits_with_type(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  expr : Expr,
  src_ty : CType,
  target_kind : CFloatKind,
  dst : Int,
  bag : DiagBag,
) -> Unit {
  let norm_target = normalize_float_kind(target_kind)
  if !float_kind_supported(norm_target) {
    add_error(bag, expr_loc(expr), "codegen: unsupported float type")
    return
  }
  match float_kind_of_type(src_ty) {
    Some(src_kind_raw) => {
      let src_kind = normalize_float_kind(src_kind_raw)
      gen_expr_floatbits(emitter, alloc, syms, pool, cstrings, expr, src_kind_raw, dst, bag)
      if src_kind == norm_target {
        return
      }
      if src_kind == CFloatKind::Float && norm_target == CFloatKind::Double {
        // float -> double
        emit_fmov_w_to_s(emitter, 0, dst)
        emit32(emitter, (0x1e22c000 : UInt))
        emit_fmov_d_to_x(emitter, dst, 0)
      } else if src_kind == CFloatKind::Double && norm_target == CFloatKind::Float {
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
      gen_expr_int32(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        expr,
        dst,
        bag,
        expr_ty=src_ty,
      )
      let is_unsigned = match strip_top_qualifiers_keep_attrs(src_ty) {
        CType::Int(unsigned~, ..) => unsigned
        _ => false
      }
      let src_size = match scalar_size_signed_or_error(alloc.sem, src_ty, expr_loc(expr)) {
        None => return
        Some((size, _)) => size
      }
      let sf_bit : Int = if src_size == 8 { 0x80000000 } else { 0 }
      if norm_target == CFloatKind::Float {
        let base : Int = if is_unsigned { 0x1e230000 } else { 0x1e220000 }
        emit32(
          emitter,
          base
          .lor(sf_bit)
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
          .lor(sf_bit)
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
fn gen_expr_to_float_kind_bits(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  expr : Expr,
  target_kind : CFloatKind,
  dst : Int,
  bag : DiagBag,
) -> Unit {
  let src_ty = type_of_expr(alloc.sem, expr)
  gen_expr_to_float_kind_bits_with_type(
    emitter,
    alloc,
    syms,
    pool,
    cstrings,
    expr,
    src_ty,
    target_kind,
    dst,
    bag,
  )
}

///|
fn gen_expr_floatbits(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  expr : Expr,
  kind_raw : CFloatKind,
  dst : Int,
  bag : DiagBag,
) -> Unit {
  let kind = normalize_float_kind(kind_raw)
  if !float_kind_supported(kind) {
    add_error(bag, expr_loc(expr), "codegen: unsupported float type")
    return
  }
  let is_double = float_is_double(kind)
  match expr {
    Expr::FloatLit(value~, loc~, ..) =>
      match parse_float_literal_bits(value, kind) {
        None => add_error(bag, loc, "codegen: invalid float literal")
        Some(bits) => arm64_movimm(emitter, dst.reinterpret_as_uint(), bits)
      }
    Expr::StmtExpr(stmts~, loc~, ..) =>
      gen_stmt_expr_with(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        stmts,
        dst,
        true,
        loc,
        bag,
        (expr, dst) =>
          gen_expr_floatbits(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            expr,
            kind_raw,
            dst,
            bag,
          ),
      )
    Expr::BuiltinVaArg(list~, ty~, loc~, ..) => {
      match float_kind_of_type(strip_top_qualifiers(ty)) {
        Some(_) =>
          ignore(gen_builtin_va_arg_load(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            list,
            ty,
            dst,
            bag,
          ))
        None => add_error(bag, loc, "codegen: expected float type for va_arg")
      }
    }
    Expr::Ident(name~, id~, loc~, ..) =>
      match lookup_local(alloc, name, id) {
        Some(slot) =>
          emit_load_local_scalar(emitter, alloc.sem, slot.ty, dst, slot.offset, loc, bag)
        None => {
          let sym = match lookup_static_local(alloc, id) {
            Some(info) => sym_for_static_local(syms, info)
            None => sym_for_ident(syms, name, id=id)
          }
          let addr_reg : Int = 16
          emit_addr_global(emitter, syms, sym, addr_reg)
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
    Expr::Index(base=_, index=_, loc~, ..) | Expr::Member(loc=loc, ..) |
    Expr::Unary(op=UnaryOp::Deref, loc=loc, ..) | Expr::CompoundLiteral(loc=loc, ..) => {
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
    Expr::Unary(op=UnaryOp::Minus, expr=inner, loc=_, ..) => {
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
      gen_expr_discard(emitter, alloc, syms, pool, cstrings, left, bag)
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
    Expr::Binary(op~, left~, right~, loc~, ..) =>
      match op {
        BinaryOp::Comma => {
          gen_expr_discard(emitter, alloc, syms, pool, cstrings, left, bag)
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
    Expr::Cast(ty=to_ty, expr=inner, loc=_, ..) => {
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
    Expr::Call(callee~, args~, loc~, ..) => {
      gen_call_expr(emitter, alloc, syms, pool, cstrings, callee, args, loc, bag)
      if dst != 0 {
        emit_mov(emitter, true, dst, 0)
      }
    }
    Expr::Conditional(cond~, then_expr~, else_expr~, loc~, ..) => {
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
  cstrings : CstringPool,
  expr : Expr,
  dst : Int,
  bag : DiagBag,
  expr_ty? : CType,
) -> Unit {
  match expr {
    Expr::IntLit(value~, loc~, ..) =>
      match parse_int64_literal(value) {
        None => add_error(bag, loc, "codegen: invalid integer literal")
        Some(v) => arm64_movimm(emitter, dst.reinterpret_as_uint(), v.reinterpret_as_uint64())
      }
    Expr::CharLit(value~, ..) =>
      arm64_movimm(emitter, dst.reinterpret_as_uint(), value.to_uint64())
    Expr::StmtExpr(stmts~, loc~, ..) =>
      gen_stmt_expr_with(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        stmts,
        dst,
        false,
        loc,
        bag,
        (expr, dst) =>
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, expr, dst, bag),
      )
    Expr::Ident(name~, id~, loc~, ..) => {
      if enum_const_value(alloc.sem, name, id) is Some(v) {
        arm64_movimm(emitter, dst.reinterpret_as_uint(), v.to_uint64())
        return
      }
      if is_func_name_ident(name) {
        if gen_func_name_addr(emitter, syms, cstrings, alloc, dst, loc, bag) {
          return
        }
      }
      match lookup_local(alloc, name, id) {
        Some(slot) =>
          emit_load_local_scalar(emitter, alloc.sem, slot.ty, dst, slot.offset, loc, bag)
        None =>
          match lookup_static_local(alloc, id) {
            Some(info) => {
              let sym = sym_for_static_local(syms, info)
              let ty = decay_type(info.ty)
              emit_addr_global(emitter, syms, sym, dst)
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
            None => {
              let sym = sym_for_ident(syms, name, id=id)
              let global_ty = if id > 0 { get_global_by_id(alloc.sem, id) } else { None }
              let ty = match global_ty {
                Some(gty) => decay_type(gty)
                None =>
                  match alloc.sem.globals.get(name) {
                    Some(gty) => decay_type(gty)
                    None =>
                      match expr_ty {
                        Some(ty) => ty
                        None => type_of_expr(alloc.sem, expr)
                      }
                  }
              }
              emit_addr_global(emitter, syms, sym, dst)
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
          }
      }
    }
    Expr::Index(base~, index~, loc~, ..) => {
      let addr = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      let elem_ty = match gen_index_addr_with_elem_type(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        base,
        index,
        addr,
        loc,
        bag,
      ) {
        None => {
          give_reg(pool, addr)
          return
        }
        Some(ty) => ty
      }
      let (size, signed) = match scalar_size_signed_or_error(alloc.sem, elem_ty, loc) {
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
    Expr::Member(base~, name~, id~, is_arrow~, loc~, ..) => {
      let base_ty = type_of_expr(alloc.sem, base)
      let info = member_access_info_from_base_type(
        alloc.sem,
        base_ty,
        name,
        id,
        is_arrow,
        loc,
      )
      if info is Some(access_info) {
        if access_info.bit_width is Some(_) {
          let addr = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          gen_member_base_addr(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            base,
            is_arrow,
            addr,
            bag,
          )
          emit_bitfield_load(emitter, alloc, pool, addr, access_info, dst, loc, bag)
          give_reg(pool, addr)
          return
        }
      }
      let addr = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      match info {
        Some(info) => {
          gen_member_addr_with_info(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            base,
            base_ty,
            is_arrow,
            info,
            addr,
            loc,
            bag,
          )
          let (size, signed) = match scalar_size_signed_or_error(
            alloc.sem,
            info.ty,
            loc,
          ) {
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
        }
        None => {
          gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, expr, addr, bag)
          let ty = match expr_ty {
            Some(ty) => ty
            None => type_of_expr(alloc.sem, expr)
          }
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
        }
      }
      give_reg(pool, addr)
    }
    Expr::CompoundLiteral(ty~, init~, node_id~, loc~, ..) => {
      let addr = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      let resolved = match gen_compound_literal_addr_with_type(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        ty,
        init,
        loc,
        node_id,
        addr,
        bag,
      ) {
        None => {
          give_reg(pool, addr)
          return
        }
        Some(rt) => rt
      }
      let (size, signed) = match scalar_size_signed_or_error(
        alloc.sem,
        resolved,
        loc,
      ) {
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
    Expr::BuiltinVaArg(list~, ty~, loc~, ..) => {
      match float_kind_of_type(strip_top_qualifiers(ty)) {
        Some(_) => add_error(bag, loc, "codegen: va_arg for float handled elsewhere")
        None =>
          if !gen_builtin_va_arg_load(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            list,
            ty,
            dst,
            bag,
          ) {
            ()
          }
      }
    }
    Expr::BuiltinOffsetof(ty~, path~, loc~, ..) => {
      match eval_builtin_offsetof(alloc.sem, ty, path, loc) {
        None => add_error(bag, loc, "codegen: unsupported expression")
        Some(off) =>
          arm64_movimm(emitter, dst.reinterpret_as_uint(), off.to_uint64())
      }
    }
    Expr::Unary(op~, expr=inner, loc~, ..) => {
      match op {
        UnaryOp::Plus =>
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
        UnaryOp::Minus => {
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
          let ty = match expr_ty {
            Some(ty) => ty
            None => type_of_expr(alloc.sem, expr)
          }
          let (size, _) = match scalar_size_signed_or_error(alloc.sem, ty, loc) {
            None => return
            Some(v) => v
          }
          let base : Int = if size == 8 { 0xcb0003e0 } else { 0x4b0003e0 }
          emit32(
            emitter,
            base.lor(dst).lor(dst << 16).reinterpret_as_uint(),
          )
        }
        UnaryOp::BitNot => {
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
          let ty = match expr_ty {
            Some(ty) => ty
            None => type_of_expr(alloc.sem, expr)
          }
          let (size, _) = match scalar_size_signed_or_error(alloc.sem, ty, loc) {
            None => return
            Some(v) => v
          }
          let base : Int = if size == 8 { 0xaa2003e0 } else { 0x2a2003e0 }
          emit32(
            emitter,
            base.lor(dst).lor(dst << 16).reinterpret_as_uint(),
          )
        }
        UnaryOp::Not => {
          gen_cond_expr_cmp_zero(emitter, alloc, syms, pool, cstrings, inner, bag)
          emit32(
            emitter,
            (0x1a9f17e0 : Int).lor(dst).reinterpret_as_uint(),
          )
        }
        UnaryOp::Addr => {
          gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
        }
        UnaryOp::Deref => {
          let addr = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          gen_expr_ptr(emitter, alloc, syms, pool, cstrings, inner, addr, bag)
          let ty = match deref_pointee_type(alloc.sem, inner, loc, bag) {
            None => {
              give_reg(pool, addr)
              return
            }
            Some(t) => t
          }
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
          if member_bitfield_info(alloc, inner) is Some((base, is_arrow, info)) {
              let addr = take_reg(pool) catch {
                err => {
                  add_error(bag, loc, err.to_string())
                  return
                }
              }
              gen_member_base_addr(
                emitter,
                alloc,
                syms,
                pool,
                cstrings,
                base,
                is_arrow,
                addr,
                bag,
              )
              emit_bitfield_load(emitter, alloc, pool, addr, info, dst, loc, bag)
              let (size, _) = match scalar_size_signed_or_error(alloc.sem, info.ty, loc) {
                None => {
                  give_reg(pool, addr)
                  return
                }
                Some(v) => v
              }
              let is64 = size == 8
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
                emit_mov(emitter, is64, updated, dst)
                let base_post = if op == UnaryOp::PostDec {
                  if is64 { 0xcb000000 } else { 0x4b000000 }
                } else {
                  if is64 { 0x8b000000 } else { 0x0b000000 }
                }
                emit32(
                  emitter,
                  (base_post : Int)
                  .lor(updated)
                  .lor(updated << 5)
                  .lor(one << 16)
                  .reinterpret_as_uint(),
                )
                emit_bitfield_store(emitter, alloc, pool, addr, info, updated, loc, bag)
                give_reg(pool, updated)
              } else {
                let base_pre = if op == UnaryOp::PreDec {
                  if is64 { 0xcb000000 } else { 0x4b000000 }
                } else {
                  if is64 { 0x8b000000 } else { 0x0b000000 }
                }
                emit32(
                  emitter,
                  (base_pre : Int)
                  .lor(dst)
                  .lor(dst << 5)
                  .lor(one << 16)
                  .reinterpret_as_uint(),
                )
                emit_bitfield_store(emitter, alloc, pool, addr, info, dst, loc, bag)
                emit_bitfield_load(emitter, alloc, pool, addr, info, dst, loc, bag)
              }
              give_reg(pool, one)
              give_reg(pool, addr)
              return
            }
          let ty = type_of_expr(alloc.sem, inner)
          if type_is_pointer_like(ty) {
            let ptr_size = match type_size_align_or_error(alloc.sem, ty, loc) {
              None => return
              Some((size, _)) => size
            }
            let elem_ty = match element_type_for_pointer_arith(ty) {
              None => {
                add_error(bag, loc, "codegen: pointer inc/dec missing element type")
                return
              }
              Some(t) => t
            }
            let (elem_size, _) = match type_size_align_or_error(alloc.sem, elem_ty, loc) {
              None => return
              Some(v) => v
            }
            let addr = take_reg(pool) catch {
              err => {
                add_error(bag, loc, err.to_string())
                return
              }
            }
            gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, inner, addr, bag)
            let sz = match arm64_sz_from_size(ptr_size) {
              None => {
                add_error(bag, loc, "codegen: unsupported pointer size")
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
            let delta_reg = take_reg(pool) catch {
              err => {
                add_error(bag, loc, err.to_string())
                give_reg(pool, addr)
                return
              }
            }
            arm64_movimm(emitter, delta_reg.reinterpret_as_uint(), elem_size.to_uint64())
            let mut updated_reg = dst
            if op == UnaryOp::PostInc || op == UnaryOp::PostDec {
              updated_reg = take_reg(pool) catch {
                err => {
                  add_error(bag, loc, err.to_string())
                  give_reg(pool, delta_reg)
                  give_reg(pool, addr)
                  return
                }
              }
              emit_mov(emitter, true, updated_reg, dst)
            }
            let base : Int = if op == UnaryOp::PreDec || op == UnaryOp::PostDec {
              0xcb000000
            } else {
              0x8b000000
            }
            emit32(
              emitter,
              (base : Int)
              .lor(updated_reg)
              .lor(updated_reg << 5)
              .lor(delta_reg << 16)
              .reinterpret_as_uint(),
            )
            arm64_strx(
              emitter,
              sz,
              updated_reg.reinterpret_as_uint(),
              addr.reinterpret_as_uint(),
              0,
            )
            give_reg(pool, delta_reg)
            if updated_reg != dst {
              give_reg(pool, updated_reg)
            }
            give_reg(pool, addr)
            return
          }
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
          let is64 = size == 8
          let addr = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, inner, addr, bag)
          arm64_ldrx(
            emitter,
            signed,
            sz,
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
            emit_mov(emitter, is64, updated, dst)
            let base_post = if op == UnaryOp::PostInc {
              if is64 { 0x8b000000 } else { 0x0b000000 }
            } else {
              if is64 { 0xcb000000 } else { 0x4b000000 }
            }
            emit32(
              emitter,
              (base_post : Int)
              .lor(updated)
              .lor(updated << 5)
              .lor(one << 16)
              .reinterpret_as_uint(),
            )
            arm64_strx(
              emitter,
              sz,
              updated.reinterpret_as_uint(),
              addr.reinterpret_as_uint(),
              0,
            )
            give_reg(pool, updated)
          } else {
            let base_pre = if op == UnaryOp::PreInc {
              if is64 { 0x8b000000 } else { 0x0b000000 }
            } else {
              if is64 { 0xcb000000 } else { 0x4b000000 }
            }
            emit32(
              emitter,
              (base_pre : Int)
              .lor(dst)
              .lor(dst << 5)
              .lor(one << 16)
              .reinterpret_as_uint(),
            )
            arm64_strx(
              emitter,
              sz,
              dst.reinterpret_as_uint(),
              addr.reinterpret_as_uint(),
              0,
            )
            if size < 4 {
              emit_int_cast(emitter, alloc.sem, ty, ty, dst, loc, bag)
            }
          }
          give_reg(pool, one)
          give_reg(pool, addr)
        }
      }
    }
    Expr::Binary(op~, left~, right~, loc~, ..) =>
      match op {
        BinaryOp::Comma => {
          gen_expr_discard(emitter, alloc, syms, pool, cstrings, left, bag)
          match expr_ty {
            Some(ty) =>
              gen_expr_int32(
                emitter,
                alloc,
                syms,
                pool,
                cstrings,
                right,
                dst,
                bag,
                expr_ty=ty,
              )
            None => gen_expr_int32(emitter, alloc, syms, pool, cstrings, right, dst, bag)
          }
        }
        BinaryOp::Assign => {
          let lhs_ty = type_of_expr(alloc.sem, left)
          match strip_top_qualifiers(lhs_ty) {
            CType::Struct(..) | CType::Union(..) => {
              if type_size_align_or_error(alloc.sem, lhs_ty, loc) is Some((size, _)) {
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
                gen_agg_expr_to_addr(
                  emitter,
                  alloc,
                  syms,
                  pool,
                  cstrings,
                  right,
                  dst_addr,
                  0,
                  lhs_ty,
                  loc,
                  bag,
                )
                give_reg(pool, dst_addr)
              }
            }
            _ =>
              match left {
                Expr::Ident(name=_, ..) => {
                  let rhs_ty = type_of_expr(alloc.sem, right)
                  gen_expr_any_with_type(
                    emitter,
                    alloc,
                    syms,
                    pool,
                    cstrings,
                    right,
                    rhs_ty,
                    dst,
                    bag,
                  )
                  emit_cast_value(emitter, alloc.sem, rhs_ty, lhs_ty, dst, loc, bag)
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
                  let rhs_ty = type_of_expr(alloc.sem, right)
                  gen_expr_any_with_type(
                    emitter,
                    alloc,
                    syms,
                    pool,
                    cstrings,
                    right,
                    rhs_ty,
                    dst,
                    bag,
                  )
                  emit_cast_value(emitter, alloc.sem, rhs_ty, lhs_ty, dst, loc, bag)
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
                let base_reg = take_reg(pool) catch {
                  err => {
                    add_error(bag, loc, err.to_string())
                    give_reg(pool, addr)
                    return
                  }
                }
                arm64_ldrx(
                  emitter,
                  false,
                  3,
                  base_reg.reinterpret_as_uint(),
                  addr.reinterpret_as_uint(),
                  0,
                )
                let idx = take_reg(pool) catch {
                  err => {
                    add_error(bag, loc, err.to_string())
                    give_reg(pool, base_reg)
                    give_reg(pool, addr)
                    return
                  }
                }
                let idx_ty = type_of_expr(alloc.sem, right)
                gen_expr_int32(
                  emitter,
                  alloc,
                  syms,
                  pool,
                  cstrings,
                  right,
                  idx,
                  bag,
                  expr_ty=idx_ty,
                )
                emit_int_extend_to_64(emitter, alloc.sem, idx_ty, idx, loc, bag)
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
                  .lor(base_reg << 5)
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
                give_reg(pool, base_reg)
                give_reg(pool, addr)
              }
              _ => add_error(bag, loc, "codegen: compound assign pointer lhs not supported yet")
            }
            return
          }
          if member_bitfield_info(alloc, left) is Some((base, is_arrow, info)) {
              let (lhs_size, lhs_signed) = match scalar_size_signed_or_error(alloc.sem, info.ty, loc) {
                None => return
                Some(v) => v
              }
              let is_unsigned = !lhs_signed
              let is64 = lhs_size == 8
              let _ = match arm64_sz_from_size(lhs_size) {
                None => {
                  add_error(bag, loc, "codegen: unsupported scalar size")
                  return
                }
                Some(v) => v
              }
              let addr = take_reg(pool) catch {
                err => {
                  add_error(bag, loc, err.to_string())
                  return
                }
              }
              gen_member_base_addr(
                emitter,
                alloc,
                syms,
                pool,
                cstrings,
                base,
                is_arrow,
                addr,
                bag,
              )
              emit_bitfield_load(emitter, alloc, pool, addr, info, dst, loc, bag)
              let tmp_old = take_reg(pool) catch {
                err => {
                  add_error(bag, loc, err.to_string())
                  give_reg(pool, addr)
                  return
                }
              }
              emit_mov(emitter, is64, tmp_old, dst)
              let right_ty = type_of_expr(alloc.sem, right)
              gen_expr_int32(
                emitter,
                alloc,
                syms,
                pool,
                cstrings,
                right,
                dst,
                bag,
                expr_ty=right_ty,
              )
              if is64 {
                emit_int_extend_to_64(emitter, alloc.sem, right_ty, dst, loc, bag)
              }
              match op {
                BinaryOp::AddAssign =>
                  emit32(
                    emitter,
                    (if is64 { 0x8b000000 } else { 0x0b000000 } : Int)
                    .lor(dst)
                    .lor(tmp_old << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                BinaryOp::SubAssign =>
                  emit32(
                    emitter,
                    (if is64 { 0xcb000000 } else { 0x4b000000 } : Int)
                    .lor(dst)
                    .lor(tmp_old << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                BinaryOp::MulAssign =>
                  emit32(
                    emitter,
                    (if is64 { 0x9b007c00 } else { 0x1b007c00 } : Int)
                    .lor(dst)
                    .lor(tmp_old << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                BinaryOp::DivAssign =>
                  emit32(
                    emitter,
                    (if is_unsigned {
                      if is64 { 0x9ac00800 } else { 0x1ac00800 }
                    } else {
                      if is64 { 0x9ac00c00 } else { 0x1ac00c00 }
                    } : Int)
                    .lor(dst)
                    .lor(tmp_old << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                BinaryOp::ModAssign => {
                  emit32(
                    emitter,
                    (if is_unsigned {
                      if is64 { 0x9ac00800 } else { 0x1ac00800 }
                    } else {
                      if is64 { 0x9ac00c00 } else { 0x1ac00c00 }
                    } : Int)
                    .lor(30)
                    .lor(tmp_old << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                  emit32(
                    emitter,
                    (if is64 { 0x9b008000 } else { 0x1b008000 } : Int)
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
                    ((0x1ac02000 : Int).lor(if is64 { 0x80000000 } else { 0 }))
                    .lor(dst)
                    .lor(tmp_old << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                BinaryOp::ShrAssign => {
                  let base : Int = if is_unsigned { 0x1ac02400 } else { 0x1ac02800 }
                  let base64 = if is64 { base.lor(0x80000000) } else { base }
                  emit32(
                    emitter,
                    base64
                    .lor(dst)
                    .lor(tmp_old << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                }
                BinaryOp::BitAndAssign =>
                  emit32(
                    emitter,
                    (if is64 { 0x8a000000 } else { 0x0a000000 } : Int)
                    .lor(dst)
                    .lor(tmp_old << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                BinaryOp::BitOrAssign =>
                  emit32(
                    emitter,
                    (if is64 { 0xaa000000 } else { 0x2a000000 } : Int)
                    .lor(dst)
                    .lor(tmp_old << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                BinaryOp::BitXorAssign =>
                  emit32(
                    emitter,
                    (if is64 { 0xca000000 } else { 0x4a000000 } : Int)
                    .lor(dst)
                    .lor(tmp_old << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                _ => ()
              }
              emit_bitfield_store(emitter, alloc, pool, addr, info, dst, loc, bag)
              give_reg(pool, tmp_old)
              give_reg(pool, addr)
              return
            }
          let (lhs_size, lhs_signed) = match scalar_size_signed_or_error(alloc.sem, left_ty, loc) {
            None => return
            Some(v) => v
          }
          let sz = match arm64_sz_from_size(lhs_size) {
            None => {
              add_error(bag, loc, "codegen: unsupported scalar size")
              return
            }
            Some(v) => v
          }
          let is_unsigned = !lhs_signed
          let is64 = lhs_size == 8
          let addr = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, left, addr, bag)
          arm64_ldrx(
            emitter,
            lhs_signed,
            sz,
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
          emit_mov(emitter, is64, tmp_old, dst)
          let right_ty = type_of_expr(alloc.sem, right)
          gen_expr_int32(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            right,
            dst,
            bag,
            expr_ty=right_ty,
          )
          if is64 {
            emit_int_extend_to_64(emitter, alloc.sem, right_ty, dst, loc, bag)
          }
          match op {
            BinaryOp::AddAssign =>
              emit32(
                emitter,
                (if is64 { 0x8b000000 } else { 0x0b000000 } : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::SubAssign =>
              emit32(
                emitter,
                (if is64 { 0xcb000000 } else { 0x4b000000 } : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::MulAssign =>
              emit32(
                emitter,
                (if is64 { 0x9b007c00 } else { 0x1b007c00 } : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::DivAssign =>
              emit32(
                emitter,
                (if is_unsigned {
                  if is64 { 0x9ac00800 } else { 0x1ac00800 }
                } else {
                  if is64 { 0x9ac00c00 } else { 0x1ac00c00 }
                } : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::ModAssign => {
              emit32(
                emitter,
                (if is_unsigned {
                  if is64 { 0x9ac00800 } else { 0x1ac00800 }
                } else {
                  if is64 { 0x9ac00c00 } else { 0x1ac00c00 }
                } : Int)
                .lor(30)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
              emit32(
                emitter,
                (if is64 { 0x9b008000 } else { 0x1b008000 } : Int)
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
                ((0x1ac02000 : Int).lor(if is64 { 0x80000000 } else { 0 }))
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::ShrAssign => {
              let base : Int = if is_unsigned { 0x1ac02400 } else { 0x1ac02800 }
              let base64 = if is64 { base.lor(0x80000000) } else { base }
              emit32(
                emitter,
                base64
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            }
            BinaryOp::BitAndAssign =>
              emit32(
                emitter,
                (if is64 { 0x8a000000 } else { 0x0a000000 } : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::BitOrAssign =>
              emit32(
                emitter,
                (if is64 { 0xaa000000 } else { 0x2a000000 } : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            BinaryOp::BitXorAssign =>
              emit32(
                emitter,
                (if is64 { 0xca000000 } else { 0x4a000000 } : Int)
                .lor(dst)
                .lor(tmp_old << 5)
                .lor(dst << 16)
                .reinterpret_as_uint(),
              )
            _ => ()
          }
          arm64_strx(
            emitter,
            sz,
            dst.reinterpret_as_uint(),
            addr.reinterpret_as_uint(),
            0,
          )
          give_reg(pool, tmp_old)
          give_reg(pool, addr)
        }
        BinaryOp::LogAnd | BinaryOp::LogOr => {
          let left_ty = type_of_expr(alloc.sem, left)
          let left_fk = match float_kind_of_type(left_ty) {
            None => None
            Some(k) => Some(normalize_float_kind(k))
          }
          if type_is_pointer_like(left_ty) {
            gen_expr_ptr(emitter, alloc, syms, pool, cstrings, left, dst, bag)
            emit_cmp(emitter, true, dst, 31)
          } else {
            match left_fk {
              Some(k) => {
                gen_expr_to_float_kind_bits_with_type(
                  emitter,
                  alloc,
                  syms,
                  pool,
                  cstrings,
                  left,
                  left_ty,
                  k,
                  dst,
                  bag,
                )
                if float_is_double(k) {
                  emit_fmov_x_to_d(emitter, 0, dst)
                  emit_fcmp_zero(emitter, true, 0)
                } else {
                  emit_fmov_w_to_s(emitter, 0, dst)
                  emit_fcmp_zero(emitter, false, 0)
                }
              }
              None => {
                gen_expr_int32(
                  emitter,
                  alloc,
                  syms,
                  pool,
                  cstrings,
                  left,
                  dst,
                  bag,
                  expr_ty=left_ty,
                )
                let left_is64 = match scalar_size_signed_or_error(
                  alloc.sem,
                  left_ty,
                  expr_loc(left),
                ) {
                  None => false
                  Some((size, _)) => size == 8
                }
                emit_cmp(emitter, left_is64, dst, 31)
              }
            }
          }
          let br_short = emit_b_cond_placeholder(
            emitter,
            if op == BinaryOp::LogAnd { ARM64_COND_EQ } else { ARM64_COND_NE },
          )

          let right_ty = type_of_expr(alloc.sem, right)
          let right_fk = match float_kind_of_type(right_ty) {
            None => None
            Some(k) => Some(normalize_float_kind(k))
          }
          if type_is_pointer_like(right_ty) {
            gen_expr_ptr(emitter, alloc, syms, pool, cstrings, right, dst, bag)
            emit_cmp(emitter, true, dst, 31)
          } else {
            match right_fk {
              Some(k) => {
                gen_expr_to_float_kind_bits_with_type(
                  emitter,
                  alloc,
                  syms,
                  pool,
                  cstrings,
                  right,
                  right_ty,
                  k,
                  dst,
                  bag,
                )
                if float_is_double(k) {
                  emit_fmov_x_to_d(emitter, 0, dst)
                  emit_fcmp_zero(emitter, true, 0)
                } else {
                  emit_fmov_w_to_s(emitter, 0, dst)
                  emit_fcmp_zero(emitter, false, 0)
                }
              }
              None => {
                gen_expr_int32(
                  emitter,
                  alloc,
                  syms,
                  pool,
                  cstrings,
                  right,
                  dst,
                  bag,
                  expr_ty=right_ty,
                )
                let right_is64 = match scalar_size_signed_or_error(
                  alloc.sem,
                  right_ty,
                  expr_loc(right),
                ) {
                  None => false
                  Some((size, _)) => size == 8
                }
                emit_cmp(emitter, right_is64, dst, 31)
              }
            }
          }
          if right_fk is Some(_) {
            emit_cset_from_fp_tok(emitter, TOK_NE, dst) catch {
              err => add_error(bag, loc, err.to_string())
            }
          } else {
            emit_cset_from_tok(emitter, TOK_NE, dst, false) catch {
              err => add_error(bag, loc, err.to_string())
            }
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
          let left_fk = match float_kind_of_type(left_ty) {
            None => None
            Some(k) => Some(normalize_float_kind(k))
          }
          let right_fk = match float_kind_of_type(right_ty) {
            None => None
            Some(k) => Some(normalize_float_kind(k))
          }
          let float_kind = match (left_fk, right_fk) {
            (Some(lk), Some(rk)) =>
              if float_is_double(lk) || float_is_double(rk) {
                Some(CFloatKind::Double)
              } else {
                Some(CFloatKind::Float)
              }
            (Some(k), None) | (None, Some(k)) => Some(k)
            _ => None
          }
          if float_kind is Some(k) {
            let rhs_reg = take_reg(pool) catch {
              err => {
                add_error(bag, loc, err.to_string())
                return
              }
            }
            gen_expr_to_float_kind_bits_with_type(
              emitter,
              alloc,
              syms,
              pool,
              cstrings,
              left,
              left_ty,
              k,
              dst,
              bag,
            )
            gen_expr_to_float_kind_bits_with_type(
              emitter,
              alloc,
              syms,
              pool,
              cstrings,
              right,
              right_ty,
              k,
              rhs_reg,
              bag,
            )
            let is_double = float_is_double(k)
            if is_double {
              emit_fmov_x_to_d(emitter, 0, dst)
              emit_fmov_x_to_d(emitter, 1, rhs_reg)
            } else {
              emit_fmov_w_to_s(emitter, 0, dst)
              emit_fmov_w_to_s(emitter, 1, rhs_reg)
            }
            emit_fcmp(emitter, is_double, 0, 1)
            let tok = match op {
              BinaryOp::Eq => TOK_EQ
              BinaryOp::Ne => TOK_NE
              BinaryOp::Lt => TOK_LT
              BinaryOp::Le => TOK_LE
              BinaryOp::Gt => TOK_GT
              BinaryOp::Ge => TOK_GE
              _ => TOK_EQ
            }
            emit_cset_from_fp_tok(emitter, tok, dst) catch {
              err => add_error(bag, loc, err.to_string())
            }
            give_reg(pool, rhs_reg)
            return
          }
          let has_ptr = type_is_pointer_like(left_ty) || type_is_pointer_like(right_ty)
          if has_ptr {
            match op {
              BinaryOp::Eq | BinaryOp::Ne | BinaryOp::Lt | BinaryOp::Le |
              BinaryOp::Gt | BinaryOp::Ge => {
                let tmp = take_reg(pool) catch {
                  err => {
                    add_error(bag, loc, err.to_string())
                    return
                  }
                }
                if type_is_pointer_like(left_ty) {
                  gen_expr_ptr(emitter, alloc, syms, pool, cstrings, left, tmp, bag)
                } else {
                  gen_expr_int32(
                    emitter,
                    alloc,
                    syms,
                    pool,
                    cstrings,
                    left,
                    tmp,
                    bag,
                    expr_ty=left_ty,
                  )
                  emit_int_extend_to_64(emitter, alloc.sem, left_ty, tmp, loc, bag)
                }
                if type_is_pointer_like(right_ty) {
                  gen_expr_ptr(emitter, alloc, syms, pool, cstrings, right, dst, bag)
                } else {
                  gen_expr_int32(
                    emitter,
                    alloc,
                    syms,
                    pool,
                    cstrings,
                    right,
                    dst,
                    bag,
                    expr_ty=right_ty,
                  )
                  emit_int_extend_to_64(emitter, alloc.sem, right_ty, dst, loc, bag)
                }
                emit_cmp(emitter, true, tmp, dst)
                let tok = match op {
                  BinaryOp::Eq => TOK_EQ
                  BinaryOp::Ne => TOK_NE
                  BinaryOp::Lt => TOK_LT
                  BinaryOp::Le => TOK_LE
                  BinaryOp::Gt => TOK_GT
                  BinaryOp::Ge => TOK_GE
                  _ => TOK_EQ
                }
                emit_cset_from_tok(emitter, tok, dst, true) catch {
                  err => add_error(bag, loc, err.to_string())
                }
                give_reg(pool, tmp)
                return
              }
              BinaryOp::Sub =>
                if type_is_pointer_like(left_ty) && type_is_pointer_like(right_ty) {
                  let left_reg = take_reg(pool) catch {
                    err => {
                      add_error(bag, loc, err.to_string())
                      return
                    }
                  }
                  gen_expr_ptr(emitter, alloc, syms, pool, cstrings, left, left_reg, bag)
                  gen_expr_ptr(emitter, alloc, syms, pool, cstrings, right, dst, bag)
                  let elem_ty = match element_type_for_pointer_arith(left_ty) {
                    None => {
                      add_error(bag, loc, "codegen: pointer arithmetic missing element type")
                      give_reg(pool, left_reg)
                      return
                    }
                    Some(t) => t
                  }
                  let (elem_size, _) = match type_size_align_or_error(alloc.sem, elem_ty, loc) {
                    None => {
                      give_reg(pool, left_reg)
                      return
                    }
                    Some(v) => v
                  }
                  emit32(
                    emitter,
                    (0xcb000000 : Int)
                    .lor(dst)
                    .lor(left_reg << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                  if elem_size != 1 {
                    let scale = take_reg(pool) catch {
                      err => {
                        add_error(bag, loc, err.to_string())
                        give_reg(pool, left_reg)
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
                      (0x9ac00c00 : Int)
                      .lor(dst)
                      .lor(dst << 5)
                      .lor(scale << 16)
                      .reinterpret_as_uint(),
                    )
                    give_reg(pool, scale)
                  }
                  emit_mov(emitter, false, dst, dst)
                  give_reg(pool, left_reg)
                  return
                } else {
                  add_error(bag, loc, "codegen: pointer +/- pointer not supported yet")
                  return
                }
              _ => {
                add_error(bag, loc, "codegen: unsupported pointer expression")
                return
              }
            }
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
            expr_ty=left_ty,
          )
          let tmp = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              return
            }
          }
          emit_mov(emitter, true, tmp, left_reg)
          gen_expr_int32(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            right,
            dst,
            bag,
            expr_ty=right_ty,
          )
          match op {
            BinaryOp::Eq | BinaryOp::Ne | BinaryOp::Lt | BinaryOp::Le |
            BinaryOp::Gt | BinaryOp::Ge => {
              let common = common_int_type(alloc.sem, left_ty, right_ty)
              let (cmp_size, cmp_signed) = match scalar_size_signed_or_error(alloc.sem, common, loc) {
                None => {
                  give_reg(pool, tmp)
                  return
                }
                Some(v) => v
              }
              let cmp_is64 = cmp_size == 8
              let cmp_unsigned = !cmp_signed
              emit_int_cast(emitter, alloc.sem, left_ty, common, tmp, loc, bag)
              emit_int_cast(emitter, alloc.sem, right_ty, common, dst, loc, bag)
              emit_cmp(emitter, cmp_is64, tmp, dst)
              let tok = match op {
                BinaryOp::Eq => TOK_EQ
                BinaryOp::Ne => TOK_NE
                BinaryOp::Lt => TOK_LT
                BinaryOp::Le => TOK_LE
                BinaryOp::Gt => TOK_GT
                BinaryOp::Ge => TOK_GE
                _ => TOK_EQ
              }
              emit_cset_from_tok(emitter, tok, dst, cmp_unsigned) catch {
                err => add_error(bag, loc, err.to_string())
              }
            }
            BinaryOp::Shl | BinaryOp::Shr => {
              let result_ty = match expr_ty {
                Some(ty) => ty
                None => type_of_expr(alloc.sem, expr)
              }
              let (res_size, res_signed) = match scalar_size_signed_or_error(alloc.sem, result_ty, loc) {
                None => {
                  give_reg(pool, tmp)
                  return
                }
                Some(v) => v
              }
              let is64 = res_size == 8
              emit_int_cast(emitter, alloc.sem, left_ty, result_ty, tmp, loc, bag)
              emit_int_extend_to_64(emitter, alloc.sem, right_ty, dst, loc, bag)
              match const_i64_from_expr(right) {
                None => {
                  let base_raw : Int =
                    if op == BinaryOp::Shl {
                      0x1ac02000
                    } else if res_signed {
                      0x1ac02800
                    } else {
                      0x1ac02400
                    }
                  let base = if is64 { base_raw.lor(0x80000000) } else { base_raw }
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
                  let shift_tok : Int =
                    if op == BinaryOp::Shl {
                      TOK_SHL
                    } else if res_signed {
                      TOK_SAR
                    } else {
                      TOK_SHR
                    }
                  let _ = arm64_gen_opic(
                    emitter,
                    shift_tok,
                    if is64 { 1 } else { 0 },
                    false,
                    v.reinterpret_as_uint64(),
                    dst,
                    tmp,
                  )
                }
              }
            }
            _ => {
              let result_ty = match expr_ty {
                Some(ty) => ty
                None => type_of_expr(alloc.sem, expr)
              }
              let (res_size, res_signed) = match scalar_size_signed_or_error(alloc.sem, result_ty, loc) {
                None => {
                  give_reg(pool, tmp)
                  return
                }
                Some(v) => v
              }
              let is64 = res_size == 8
              let is_unsigned = !res_signed
              emit_int_cast(emitter, alloc.sem, left_ty, result_ty, tmp, loc, bag)
              emit_int_cast(emitter, alloc.sem, right_ty, result_ty, dst, loc, bag)
              match op {
                BinaryOp::Add =>
                  emit32(
                    emitter,
                    (if is64 { 0x8b000000 } else { 0x0b000000 } : Int)
                    .lor(dst)
                    .lor(tmp << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                BinaryOp::Sub =>
                  emit32(
                    emitter,
                    (if is64 { 0xcb000000 } else { 0x4b000000 } : Int)
                    .lor(dst)
                    .lor(tmp << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                BinaryOp::Mul =>
                  emit32(
                    emitter,
                    (if is64 { 0x9b007c00 } else { 0x1b007c00 } : Int)
                    .lor(dst)
                    .lor(tmp << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                BinaryOp::Div =>
                  emit32(
                    emitter,
                    (if is_unsigned {
                      if is64 { 0x9ac00800 } else { 0x1ac00800 }
                    } else {
                      if is64 { 0x9ac00c00 } else { 0x1ac00c00 }
                    } : Int)
                    .lor(dst)
                    .lor(tmp << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                BinaryOp::Mod => {
                  emit32(
                    emitter,
                    (if is_unsigned {
                      if is64 { 0x9ac00800 } else { 0x1ac00800 }
                    } else {
                      if is64 { 0x9ac00c00 } else { 0x1ac00c00 }
                    } : Int)
                    .lor(30)
                    .lor(tmp << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                  emit32(
                    emitter,
                    (if is64 { 0x9b008000 } else { 0x1b008000 } : Int)
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
                    (if is64 { 0x8a000000 } else { 0x0a000000 } : Int)
                    .lor(dst)
                    .lor(tmp << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                BinaryOp::BitOr =>
                  emit32(
                    emitter,
                    (if is64 { 0xaa000000 } else { 0x2a000000 } : Int)
                    .lor(dst)
                    .lor(tmp << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                BinaryOp::BitXor =>
                  emit32(
                    emitter,
                    (if is64 { 0xca000000 } else { 0x4a000000 } : Int)
                    .lor(dst)
                    .lor(tmp << 5)
                    .lor(dst << 16)
                    .reinterpret_as_uint(),
                  )
                _ => ()
              }
            }
          }
          give_reg(pool, tmp)
        }
      }
    Expr::Call(callee~, args~, loc~, ..) => {
      gen_call_expr(emitter, alloc, syms, pool, cstrings, callee, args, loc, bag)
      if dst != 0 {
        emit_mov(emitter, true, dst, 0)
      }
    }
	    Expr::SizeofExpr(expr=inner, loc~, ..) => {
	      match inner {
	        Expr::Ident(name~, id~, ..) =>
	          if lookup_local(alloc, name, id) is Some(slot) {
	            match strip_top_qualifiers(slot.ty) {
	              CType::Array(size=None, size_expr=Some(_), ..) =>
	                if slot.vla_size_offset is Some(off) {
	                  arm64_ldrx(
	                    emitter,
	                    false,
	                    3,
	                    dst.reinterpret_as_uint(),
	                    (29 : UInt),
	                    off.to_int64().reinterpret_as_uint64(),
	                  )
	                  return
	                } else {
	                  add_error(bag, loc, "codegen: missing VLA byte size slot")
	                }
	              _ => ()
	            }
	          }
	        _ => ()
	      }
	      let ty = type_for_sizeof(alloc.sem, inner)
	      match strip_top_qualifiers(ty) {
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
	          if type_size_align_or_error(alloc.sem, ty, loc) is Some((size, _)) {
	            arm64_movimm(
	              emitter,
	              dst.reinterpret_as_uint(),
	              size.to_uint64(),
	            )
	          }
	      }
	    }
	    Expr::SizeofType(ty~, loc~, ..) =>
	      match strip_top_qualifiers(ty) {
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
	          if type_size_align_or_error(alloc.sem, ty, loc) is Some((size, _)) {
	            arm64_movimm(
	              emitter,
	              dst.reinterpret_as_uint(),
	              size.to_uint64(),
	            )
	          }
	      }
    Expr::Cast(ty=to_ty, expr=inner, loc=cast_loc, ..) => {
      let from_ty = type_of_expr(alloc.sem, inner)
      match (strip_top_qualifiers_keep_attrs(to_ty), strip_top_qualifiers_keep_attrs(from_ty)) {
        (CType::Int(kind=to_kind, unsigned=to_unsigned), CType::Float(kind=from_kind)) => {
          if !float_kind_supported(from_kind) {
            add_error(bag, cast_loc, "codegen: unsupported float type")
            gen_expr_int32(
              emitter,
              alloc,
              syms,
              pool,
              cstrings,
              inner,
              dst,
              bag,
              expr_ty=from_ty,
            )
            return
          }
          gen_expr_to_float_kind_bits_with_type(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            inner,
            from_ty,
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
          emit_int_cast(emitter, alloc.sem, to_ty, to_ty, dst, cast_loc, bag)
        }
        (CType::Int(..), _) => {
          if type_is_pointer_like(from_ty) {
            gen_expr_ptr(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
          } else {
            gen_expr_int32(
              emitter,
              alloc,
              syms,
              pool,
              cstrings,
              inner,
              dst,
              bag,
              expr_ty=from_ty,
            )
          }
          emit_int_cast(emitter, alloc.sem, from_ty, to_ty, dst, cast_loc, bag)
        }
        _ =>
          gen_expr_int32(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            inner,
            dst,
            bag,
            expr_ty=from_ty,
          )
      }
    }
    Expr::Conditional(cond~, then_expr~, else_expr~, loc~, ..) => {
      let result_ty = match expr_ty {
        Some(ty) => ty
        None => type_of_expr(alloc.sem, expr)
      }
      let then_ty = type_of_expr(alloc.sem, then_expr)
      let else_ty = type_of_expr(alloc.sem, else_expr)
      gen_cond_expr_cmp_zero(emitter, alloc, syms, pool, cstrings, cond, bag)
      let br_else = emit_b_cond_placeholder(emitter, ARM64_COND_EQ)
      gen_expr_int32(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        then_expr,
        dst,
        bag,
        expr_ty=then_ty,
      )
      emit_cast_value(emitter, alloc.sem, then_ty, result_ty, dst, loc, bag)
      let br_end = gjmp(emitter, 0)
      let else_pc = emitter_pc(emitter)
      patch_b_cond(emitter, br_else, else_pc, ARM64_COND_EQ) catch {
        err => add_error(bag, loc, err.to_string())
      }
      gen_expr_int32(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        else_expr,
        dst,
        bag,
        expr_ty=else_ty,
      )
      emit_cast_value(emitter, alloc.sem, else_ty, result_ty, dst, loc, bag)
      let end_pc = emitter_pc(emitter)
      gsym_addr(emitter, br_end, end_pc) catch {
        err => add_error(bag, loc, err.to_string())
      }
    }
    Expr::StringLit(value=value, ..) => {
      let sym = cstring_sym_or_add(cstrings, syms, value)
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
    _ =>
      add_error(bag, expr_loc(expr), "codegen: unsupported expression")
  }
}

///|
fn deref_pointee_type(
  sem : SemContext,
  inner : Expr,
  loc : SrcLoc,
  bag : DiagBag,
) -> CType? {
  let inner_ty = type_of_expr(sem, inner)
  match strip_top_qualifiers(inner_ty) {
    CType::Pointer(pointee) => Some(pointee)
    _ => {
      add_error(bag, loc, "codegen: cannot dereference non-pointer")
      None
    }
  }
}

///|
fn gen_expr_ptr(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  expr : Expr,
  dst : Int,
  bag : DiagBag,
) -> Unit {
  match expr {
    Expr::IntLit(value~, loc~, ..) =>
      match parse_int64_literal(value) {
        None => add_error(bag, loc, "codegen: invalid integer literal")
        Some(v) =>
          arm64_movimm(emitter, dst.reinterpret_as_uint(), v.reinterpret_as_uint64())
      }
    Expr::CharLit(value~, ..) =>
      arm64_movimm(emitter, dst.reinterpret_as_uint(), value.to_uint64())
    Expr::StmtExpr(stmts~, loc~, ..) =>
      gen_stmt_expr_with(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        stmts,
        dst,
        true,
        loc,
        bag,
        (expr, dst) =>
          gen_expr_ptr(emitter, alloc, syms, pool, cstrings, expr, dst, bag),
      )
    Expr::StringLit(value=value, ..) => {
      let sym = cstring_sym_or_add(cstrings, syms, value)
      emit_addr_global(emitter, syms, sym, dst)
    }
    Expr::LabelAddr(name~, loc~, ..) =>
      match alloc.labels.addrs.get(name) {
        Some(addr) =>
          emit_adr(emitter, dst, addr - emitter_pc(emitter), loc, bag)
        None => {
          let at = emitter_pc(emitter)
          emit32(
            emitter,
            (0x10000000 : Int).lor(dst).reinterpret_as_uint(),
          )
          record_label_addr_patch(alloc.labels, name, at)
        }
      }
    Expr::Ident(name~, id~, loc~, ..) => {
      if is_func_name_ident(name) {
        if gen_func_name_addr(emitter, syms, cstrings, alloc, dst, loc, bag) {
          return
        }
      }
      match lookup_local(alloc, name, id) {
        Some(slot) =>
          match strip_top_qualifiers(slot.ty) {
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
        None =>
          match lookup_static_local(alloc, id) {
            Some(info) => {
              let sym = sym_for_static_local(syms, info)
              emit_addr_global(emitter, syms, sym, dst)
              match strip_top_qualifiers(info.ty) {
                CType::Array(..) | CType::Function(..) => return
                _ => ()
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
            None => {
              let sym = sym_for_ident(syms, name, id=id)
              emit_addr_global(emitter, syms, sym, dst)
              let has_func = if id > 0 {
                has_function_by_id(alloc.sem, id) || alloc.sem.functions.contains(name)
              } else {
                alloc.sem.functions.contains(name)
              }
              if has_func {
                return
              }
              let global_ty = if id > 0 { get_global_by_id(alloc.sem, id) } else { None }
              let global_ty = match global_ty {
                Some(found) => Some(found)
                None => alloc.sem.globals.get(name)
              }
              if global_ty is Some(gty) {
                match strip_top_qualifiers(gty) {
                  CType::Array(..) => return
                  _ => ()
                }
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
      }
    }
    Expr::Member(base~, name~, id~, is_arrow~, loc~, ..) => {
      let addr = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      let base_ty = type_of_expr(alloc.sem, base)
      let info = member_access_info_from_base_type(
        alloc.sem,
        base_ty,
        name,
        id,
        is_arrow,
        loc,
      )
      match info {
        Some(info) => {
          gen_member_addr_with_info(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            base,
            base_ty,
            is_arrow,
            info,
            addr,
            loc,
            bag,
          )
          match strip_top_qualifiers(info.ty) {
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
        None => {
          gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, expr, addr, bag)
          if type_of_lvalue(alloc.sem, expr) is Some(lty) {
            match strip_top_qualifiers(lty) {
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
        }
      }
      give_reg(pool, addr)
    }
    Expr::Index(base~, index~, loc~, ..) => {
      let addr = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      let elem_ty = match gen_index_addr_with_elem_type(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        base,
        index,
        addr,
        loc,
        bag,
      ) {
        None => {
          give_reg(pool, addr)
          return
        }
        Some(ty) => ty
      }
      match strip_top_qualifiers(elem_ty) {
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
      give_reg(pool, addr)
    }
    Expr::CompoundLiteral(ty~, init~, node_id~, loc~, ..) => {
      let addr = take_reg(pool) catch {
        err => {
          add_error(bag, loc, err.to_string())
          return
        }
      }
      let resolved = match gen_compound_literal_addr_with_type(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        ty,
        init,
        loc,
        node_id,
        addr,
        bag,
      ) {
        None => {
          give_reg(pool, addr)
          return
        }
        Some(rt) => rt
      }
      match strip_top_qualifiers(resolved) {
        CType::Array(..) | CType::Function(..) =>
          if dst != addr {
            emit_mov(emitter, true, dst, addr)
          }
        _ => {
          let (size, signed) = match scalar_size_signed_or_error(
            alloc.sem,
            resolved,
            loc,
          ) {
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
        }
      }
      give_reg(pool, addr)
    }
    Expr::Unary(op=UnaryOp::Addr, expr=inner, ..) =>
      gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
    Expr::Unary(op=UnaryOp::Deref, expr=inner, loc~, ..) => {
      gen_expr_ptr(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
      let ty = match deref_pointee_type(alloc.sem, inner, loc, bag) {
        None => return
        Some(t) => t
      }
      match strip_top_qualifiers(ty) {
        CType::Array(..) | CType::Function(..) => return
        _ => ()
      }
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
    Expr::BuiltinVaArg(list~, ty~, loc~, ..) => {
      if !type_is_pointer_like(ty) {
        add_error(bag, loc, "codegen: expected pointer type for va_arg")
        return
      }
      ignore(
        gen_builtin_va_arg_load(
          emitter,
          alloc,
          syms,
          pool,
          cstrings,
          list,
          ty,
          dst,
          bag,
        ),
      )
    }
    Expr::Unary(op~, expr=inner, loc~, ..) =>
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
          let elem_size = match strip_top_qualifiers(elem_ty) {
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
    Expr::Binary(op~, left~, right~, loc~, ..) =>
      match op {
        BinaryOp::Comma => {
          gen_expr_discard(emitter, alloc, syms, pool, cstrings, left, bag)
          gen_expr_ptr(emitter, alloc, syms, pool, cstrings, right, dst, bag)
        }
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
          let elem_size = match strip_top_qualifiers(elem_ty) {
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

          let base_reg = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              give_reg(pool, addr)
              return
            }
          }
          arm64_ldrx(
            emitter,
            false,
            3,
            base_reg.reinterpret_as_uint(),
            addr.reinterpret_as_uint(),
            0,
          )

          let idx = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              give_reg(pool, base_reg)
              give_reg(pool, addr)
              return
            }
          }
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, right, idx, bag)
          let idx_ty = type_of_expr(alloc.sem, right)
          emit_int_extend_to_64(emitter, alloc.sem, idx_ty, idx, loc, bag)
          if elem_size != 1 {
            let scale = take_reg(pool) catch {
              err => {
                add_error(bag, loc, err.to_string())
                give_reg(pool, idx)
                give_reg(pool, base_reg)
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
            .lor(base_reg)
            .lor(base_reg << 5)
            .lor(idx << 16)
            .reinterpret_as_uint(),
          )
          arm64_strx(
            emitter,
            3,
            base_reg.reinterpret_as_uint(),
            addr.reinterpret_as_uint(),
            0,
          )
          if base_reg != dst {
            emit_mov(emitter, true, dst, base_reg)
          }

          give_reg(pool, idx)
          give_reg(pool, base_reg)
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
          let mut base_reg = dst
          let mut saved_reg : Int? = None
          if expr_may_call(int_expr) && dst < 19 {
            let tmp = take_reg(pool) catch {
              err => {
                add_error(bag, loc, err.to_string())
                return
              }
            }
            emit_mov(emitter, true, tmp, dst)
            base_reg = tmp
            saved_reg = Some(tmp)
          }
          let idx = take_reg(pool) catch {
            err => {
              add_error(bag, loc, err.to_string())
              if saved_reg is Some(r) {
                give_reg(pool, r)
              }
              return
            }
          }
          gen_expr_int32(emitter, alloc, syms, pool, cstrings, int_expr, idx, bag)
          let idx_ty = type_of_expr(alloc.sem, int_expr)
          emit_int_extend_to_64(emitter, alloc.sem, idx_ty, idx, loc, bag)
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
            .lor(base_reg << 5)
            .lor(idx << 16)
            .reinterpret_as_uint(),
          )
          give_reg(pool, idx)
          if saved_reg is Some(r) {
            give_reg(pool, r)
          }
        }
        _ => add_error(bag, loc, "codegen: unsupported pointer expression")
      }
    Expr::Cast(ty=to_ty, expr=inner, loc=cast_loc, ..) => {
      let inner_ty = type_of_expr(alloc.sem, inner)
      if type_is_pointer_like(inner_ty) {
        gen_expr_ptr(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
      } else {
        gen_expr_int32(emitter, alloc, syms, pool, cstrings, inner, dst, bag)
        emit_int_cast(emitter, alloc.sem, inner_ty, to_ty, dst, cast_loc, bag)
      }
    }
    Expr::Call(callee~, args~, loc~, ..) => {
      gen_call_expr(emitter, alloc, syms, pool, cstrings, callee, args, loc, bag)
      if dst != 0 {
        emit_mov(emitter, true, dst, 0)
      }
    }
    Expr::Conditional(cond~, then_expr~, else_expr~, loc~, ..) => {
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
  cstrings : CstringPool,
  expr : Expr,
  dst : Int,
  bag : DiagBag,
) -> Unit {
  let ty = type_of_expr(alloc.sem, expr)
  gen_expr_any_with_type(
    emitter,
    alloc,
    syms,
    pool,
    cstrings,
    expr,
    ty,
    dst,
    bag,
  )
}

///|
fn gen_expr_any_with_type(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  expr : Expr,
  ty : CType,
  dst : Int,
  bag : DiagBag,
) -> Unit {
  match float_kind_of_type(ty) {
    Some(k) =>
      gen_expr_to_float_kind_bits_with_type(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        expr,
        ty,
        k,
        dst,
        bag,
      )
    None =>
      if type_is_pointer_like(ty) {
        gen_expr_ptr(emitter, alloc, syms, pool, cstrings, expr, dst, bag)
      } else {
        gen_expr_int32(emitter, alloc, syms, pool, cstrings, expr, dst, bag, expr_ty=ty)
      }
  }
}

///|
fn gen_expr_discard(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  expr : Expr,
  bag : DiagBag,
) -> Unit {
  match expr {
    Expr::Binary(op=BinaryOp::Assign, ..) => {
      gen_expr_any(emitter, alloc, syms, pool, cstrings, expr, 0, bag)
      return
    }
    _ => ()
  }
  let ty = type_of_expr(alloc.sem, expr)
  match strip_top_qualifiers(ty) {
    CType::Void =>
      match expr {
        Expr::Cast(expr=inner, ..) =>
          gen_expr_discard(emitter, alloc, syms, pool, cstrings, inner, bag)
        Expr::Call(callee~, args~, loc~, ..) =>
          gen_call_expr(emitter, alloc, syms, pool, cstrings, callee, args, loc, bag)
        Expr::Binary(op=BinaryOp::Comma, left~, right~, ..) => {
          gen_expr_discard(emitter, alloc, syms, pool, cstrings, left, bag)
          gen_expr_discard(emitter, alloc, syms, pool, cstrings, right, bag)
        }
        Expr::Conditional(cond~, then_expr~, else_expr~, loc~, ..) => {
          gen_cond_expr_cmp_zero(emitter, alloc, syms, pool, cstrings, cond, bag)
          let br_else = emit_b_cond_placeholder(emitter, ARM64_COND_EQ)
          gen_expr_discard(emitter, alloc, syms, pool, cstrings, then_expr, bag)
          let br_end = gjmp(emitter, 0)
          let else_pc = emitter_pc(emitter)
          patch_b_cond(emitter, br_else, else_pc, ARM64_COND_EQ) catch {
            err => add_error(bag, loc, err.to_string())
          }
          gen_expr_discard(emitter, alloc, syms, pool, cstrings, else_expr, bag)
          let end_pc = emitter_pc(emitter)
          gsym_addr(emitter, br_end, end_pc) catch {
            err => add_error(bag, loc, err.to_string())
          }
        }
        Expr::StmtExpr(stmts~, loc~, ..) =>
          gen_stmt_expr_with(
            emitter,
            alloc,
            syms,
            pool,
            cstrings,
            stmts,
            0,
            true,
            loc,
            bag,
            (expr, _) => gen_expr_discard(
              emitter,
              alloc,
              syms,
              pool,
              cstrings,
              expr,
              bag,
            ),
          )
        _ => gen_expr_any_with_type(emitter, alloc, syms, pool, cstrings, expr, ty, 0, bag)
      }
    _ =>
      if type_is_aggregate(ty) {
        let loc = expr_loc(expr)
        let (size, _) = match type_size_align_or_error(alloc.sem, ty, loc) {
          None => return
          Some(v) => v
        }
        if size <= 0 {
          return
        }
        match alloc.agg_temp_offset {
          None => add_error(bag, loc, "codegen: missing aggregate temp slot")
          Some(tmp_off) => {
            if size > alloc.agg_temp_size {
              add_error(bag, loc, "codegen: aggregate temp too small")
              return
            }
            gen_agg_expr_to_addr(
              emitter,
              alloc,
              syms,
              pool,
              cstrings,
              expr,
              29,
              tmp_off,
              ty,
              loc,
              bag,
            )
          }
        }
      } else {
        gen_expr_any_with_type(emitter, alloc, syms, pool, cstrings, expr, ty, 0, bag)
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
    Stmt::GotoExpr(loc=loc, ..) => loc
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
  addrs : FastMap[String, Int]
  chains : FastMap[String, Int]
  addr_patches : FastMap[String, Array[Int]]
}

///|
fn new_label_ctx() -> LabelCtx {
  { addrs: fast_map_new(), chains: fast_map_new(), addr_patches: fast_map_new() }
}

///|
fn record_label_addr_patch(labels : LabelCtx, name : String, at : Int) -> Unit {
  match labels.addr_patches.get(name) {
    None => {
      let entries : Array[Int] = []
      entries.push(at)
      labels.addr_patches.set(name, entries)
    }
    Some(entries) => entries.push(at)
  }
}

///|
fn patch_label_addr_uses(
  emitter : Arm64Emitter,
  labels : LabelCtx,
  name : String,
  addr : Int,
  loc : SrcLoc,
  bag : DiagBag,
) -> Unit {
  if labels.addr_patches.get(name) is Some(entries) {
    for at in entries {
      patch_adr(emitter, at, addr, loc, bag)
    }
    labels.addr_patches.remove(name)
  }
}

///|
fn gen_stmt_expr_with(
  emitter : Arm64Emitter,
  alloc : LocalAlloc,
  syms : SymTable,
  pool : RegPool,
  cstrings : CstringPool,
  stmts : Array[Stmt],
  dst : Int,
  zero_is64 : Bool,
  loc : SrcLoc,
  bag : DiagBag,
  gen_last : (Expr, Int) -> Unit,
) -> Unit {
  let mut did_scope = false
  let loops : Array[LoopChains] = []
  let switches : Array[SwitchChains] = []
  let breakables : Array[Int] = []
  let labels = alloc.labels
  let mut chain = 0
  let len = stmts.length()
  if len == 0 {
    if dst != 0 {
      emit_mov(emitter, zero_is64, dst, 31)
    }
    if did_scope {
      cg_pop_scope_codegen(emitter, alloc)
    }
    return
  }
  for i = 0; i < len; {
    let stmt = stmts[i]
    if !did_scope && stmt is Stmt::DeclStmt(..) {
      cg_push_scope(alloc)
      did_scope = true
    }
    if i == len - 1 {
      match stmt {
        Stmt::ExprStmt(expr~, ..) => gen_last(expr, dst)
        _ => {
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
            stmt,
            bag,
            chain,
          )
          if dst != 0 {
            emit_mov(emitter, zero_is64, dst, 31)
          }
        }
      }
    } else {
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
        stmt,
        bag,
        chain,
      )
    }
    continue i + 1
  }
  if chain != 0 {
    gsym(emitter, chain) catch {
      err => add_error(bag, loc, err.to_string())
    }
    add_error(bag, loc, "codegen: return in statement expression not supported")
  }
  if did_scope {
    cg_pop_scope_codegen(emitter, alloc)
  }
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
  start : Int64
  end : Int64
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
      Stmt::Case(expr~, end_expr~, body~, ..) => {
        let start = const_int64_from_expr(sem, expr, expr_loc(expr)).unwrap_or(0)
        let end = match end_expr {
          None => start
          Some(e) => const_int64_from_expr(sem, e, expr_loc(e)).unwrap_or(start)
        }
        cases.push({ start, end })
        walk(sem, body, cases, has_default)
      }
      Stmt::Default(body~, ..) => walk(sem, body, cases, true)
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
  cstrings : CstringPool,
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
      let (chain, new_default, new_next) = gen_switch_body(
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
        case_addrs,
        default_addr0,
        next_case0,
      )
      (chain, new_default, new_next)
    }
    Stmt::Default(body=def_body, ..) => {
      default_addr0 = Some(emitter_pc(emitter))
      let (chain, new_default, new_next) = gen_switch_body(
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
        case_addrs,
        default_addr0,
        next_case0,
      )
      (chain, new_default, new_next)
    }
    Stmt::Compound(stmts~, ..) => {
      let mut did_scope = false
      let mut chain = return_chain
      for s in stmts {
        if !did_scope && s is Stmt::DeclStmt(..) {
          cg_push_scope(alloc)
          did_scope = true
        }
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
      if did_scope {
        cg_pop_scope_codegen(emitter, alloc)
      }
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
    Stmt::Label(name~, body~, loc~) => {
      let addr = emitter_pc(emitter)
      if labels.addrs.get(name) is Some(_) {
        add_error(bag, loc, "codegen: duplicate label")
      }
      if labels.chains.get(name) is Some(chain) {
        if chain != 0 {
          gsym_addr(emitter, chain, addr) catch {
            err => add_error(bag, loc, err.to_string())
          }
        }
      }
      labels.addrs.set(name, addr)
      labels.chains.set(name, 0)
      if current_scope_vla_loc(alloc) is Some(off) {
        emit_vla_sp_restore(emitter, off)
      }
      gen_switch_body(
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
        default_addr0,
        next_case0,
      )
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
  cstrings : CstringPool,
  stmt : Stmt,
  bag : DiagBag,
  return_chain : Int,
) -> Int {
  match stmt {
    Stmt::Compound(stmts~, ..) => {
      let mut did_scope = false
      let mut chain = return_chain
      for s in stmts {
        if !did_scope && s is Stmt::DeclStmt(..) {
          cg_push_scope(alloc)
          did_scope = true
        }
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
      if did_scope {
        cg_pop_scope_codegen(emitter, alloc)
      }
      chain
    }
    Stmt::DeclStmt(decls~, ..) => {
      for d in decls {
        let stripped = strip_top_qualifiers(d.ty)
        match stripped {
          CType::Function(..) => continue
          _ => ()
        }
        if d.storage == StorageClass::Extern {
          continue
        }
        if d.storage == StorageClass::Static {
          record_static_local_binding(alloc, d)
          continue
        }
        let mut decl_ty = d.ty
        match stripped {
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
        if alloc_local(alloc, d.name, d.id, decl_ty, d.loc) is Some(slot) {
          let mut slot0 = slot
          let mut slot_stripped = strip_top_qualifiers(slot0.ty)
          match slot_stripped {
            CType::Array(size=None, size_expr=Some(_), ..) => {
              let size_off = alloc_hidden_slot(alloc, 8, 8)
              let updated = {
                offset: slot0.offset,
                ty: slot0.ty,
                vla_size_offset: Some(size_off),
                byref: slot0.byref,
                type_size: slot0.type_size,
                type_align: slot0.type_align,
              }
              if d.id > 0 {
                let scope_idx = alloc.scopes.length() - 1
                alloc.scopes[scope_idx].set(d.id, updated)
              }
              update_local_slot(alloc, d.name, d.id, updated)
              slot0 = updated
              slot_stripped = strip_top_qualifiers(slot0.ty)
              if vla_record_decl(alloc, slot0.offset) is Some(off) {
                emit_vla_sp_save(emitter, off)
              }
            }
            _ => ()
          }
          match slot_stripped {
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
          if d.init is Some(init) {
            let needs_zero = type_is_aggregate(slot0.ty)
            if needs_zero {
              if slot_type_size_align(alloc, slot0, d.loc) is Some((size, _)) {
                if size > 0 {
                  emit_zero_bytes(emitter, 29, slot0.offset, size)
                }
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
      return_chain
    }
    Stmt::TagDef(..) | Stmt::StaticAssert(_) => return_chain
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
      if init is Some(s) {
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
      if step is Some(e) {
        gen_expr_discard(emitter, alloc, syms, pool, cstrings, e, bag)
      }
      gjmp_addr(emitter, cond_pc) catch {
        err => add_error(bag, loc, err.to_string())
      }
      let end_pc = emitter_pc(emitter)
      if br_end is Some(at) {
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
      let cond_ty = type_of_expr(alloc.sem, cond)
      let (cond_is64, cond_unsigned) = match scalar_size_signed_or_error(
        alloc.sem,
        cond_ty,
        loc,
      ) {
        None => (false, false)
        Some((size, signed)) => (size == 8, !signed)
      }
      let range_cond_lt = if cond_unsigned { ARM64_COND_LO } else { ARM64_COND_LT }
      let range_cond_gt = if cond_unsigned { ARM64_COND_HI } else { ARM64_COND_GT }
      let case_addrs : Array[Int] = []
      for _ in cases {
        case_addrs.push(0)
      }
      let mut default_addr : Int? = None

      gen_expr_int32(
        emitter,
        alloc,
        syms,
        pool,
        cstrings,
        cond,
        0,
        bag,
        expr_ty=cond_ty,
      )

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
            info.start.reinterpret_as_uint64(),
          )
          emit_cmp(emitter, cond_is64, 0, tmp)
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
            info.start.reinterpret_as_uint64(),
          )
          emit_cmp(emitter, cond_is64, 0, tmp)
          let skip1 = emit_b_cond_placeholder(emitter, range_cond_lt)
          arm64_movimm(
            emitter,
            tmp.reinterpret_as_uint(),
            info.end.reinterpret_as_uint64(),
          )
          emit_cmp(emitter, cond_is64, 0, tmp)
          let skip2 = emit_b_cond_placeholder(emitter, range_cond_gt)
          give_reg(pool, tmp)

          let jmp = gjmp(emitter, 0)
          range_jmps.push((jmp, i))
          let next_pc = emitter_pc(emitter)
          patch_b_cond(emitter, skip1, next_pc, range_cond_lt) catch {
            err => add_error(bag, loc, err.to_string())
          }
          patch_b_cond(emitter, skip2, next_pc, range_cond_gt) catch {
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
    Stmt::GotoExpr(expr~, ..) => {
      emit_vla_leave(emitter, alloc, 0)
      gen_expr_ptr(emitter, alloc, syms, pool, cstrings, expr, 0, bag)
      emit_br(emitter, 0)
      return_chain
    }
    Stmt::Label(name~, body~, loc~) => {
      let addr = emitter_pc(emitter)
      if labels.addrs.get(name) is Some(_) {
        add_error(bag, loc, "codegen: duplicate label")
      }
      if labels.chains.get(name) is Some(chain) {
        if chain != 0 {
          gsym_addr(emitter, chain, addr) catch {
            err => add_error(bag, loc, err.to_string())
          }
        }
      }
      labels.addrs.set(name, addr)
      labels.chains.set(name, 0)
      patch_label_addr_uses(emitter, labels, name, addr, loc, bag)
      if current_scope_vla_loc(alloc) is Some(off) {
        emit_vla_sp_restore(emitter, off)
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
      gen_expr_discard(emitter, alloc, syms, pool, cstrings, expr, bag)
      return_chain
    }
    Stmt::Asm(stmt) => {
      // Treat inline asm as a barrier when it clobbers memory; otherwise ignore.
      if stmt.is_volatile || stmt.clobbers.contains("memory") {
        emit32(emitter, (0xd5033bbf : Int).reinterpret_as_uint())
      }
      return_chain
    }
    Stmt::Return(value~, loc~) => {
      let rt = strip_top_qualifiers(alloc.ret_ty)
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
              let expr_ty = type_of_expr(alloc.sem, expr)
              gen_expr_to_float_kind_bits_with_type(
                emitter,
                alloc,
                syms,
                pool,
                cstrings,
                expr,
                expr_ty,
                k,
                0,
                bag,
              )
              if k == CFloatKind::Double {
                emit_fmov_x_to_d(emitter, 0, 0)
              } else {
                emit_fmov_w_to_s(emitter, 0, 0)
              }
            }
            None =>
              match rt {
                CType::Struct(..) | CType::Union(..) =>
                  if type_size_align_or_error(alloc.sem, rt, loc) is Some((size, _)) {
                    if size == 0 {
                      ()
                    } else {
                        let ret_loc = cached_ret_loc(alloc, loc, bag)
                        if ret_loc == 1 {
                          match alloc.sret_offset {
                            None => add_error(bag, loc, "codegen: missing sret slot")
                            Some(off) => {
                              let tmp = take_reg(pool) catch {
                                err => {
                                  add_error(bag, loc, err.to_string())
                                  return gjmp(emitter, return_chain)
                                }
                              }
                              arm64_ldrx(
                                emitter,
                                false,
                                3,
                                tmp.reinterpret_as_uint(),
                                (29 : UInt),
                                off.to_int64().reinterpret_as_uint64(),
                              )
                              gen_agg_expr_to_addr(
                                emitter,
                                alloc,
                                syms,
                                pool,
                                cstrings,
                                expr,
                                tmp,
                                0,
                                alloc.ret_ty,
                                loc,
                                bag,
                              )
                              give_reg(pool, tmp)
                            }
                          }
                        } else if ret_loc == 16 {
                          if expr is Expr::Call(callee~, args~, ..) {
                            gen_call_expr(emitter, alloc, syms, pool, cstrings, callee, args, loc, bag)
                          } else {
                            let base_reg : Int = 0
                            if expr_is_lvalue_simple(expr) {
                              gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, expr, base_reg, bag)
                            } else {
                              match alloc.agg_temp_offset {
                                None => {
                                  add_error(bag, loc, "codegen: missing aggregate temp for return")
                                  return gjmp(emitter, return_chain)
                                }
                                Some(off) => {
                                  gen_agg_expr_to_addr(
                                    emitter,
                                    alloc,
                                    syms,
                                    pool,
                                    cstrings,
                                    expr,
                                    29,
                                    off,
                                    alloc.ret_ty,
                                    loc,
                                    bag,
                                  )
                                  emit_addr_local(emitter, base_reg, off, loc, bag)
                                }
                              }
                            }
                            match arm64_hfa(alloc.sem, rt, loc, bag) {
                              None => add_error(bag, loc, "codegen: expected HFA return")
                              Some((count, fsize)) => {
                                let mut j = 0
                                while j < count {
                                  let tmp = take_reg(pool) catch {
                                    err => {
                                      add_error(bag, loc, err.to_string())
                                      return gjmp(emitter, return_chain)
                                    }
                                  }
                                  if fsize == 8 {
                                    arm64_ldrx(
                                      emitter,
                                      false,
                                      3,
                                      tmp.reinterpret_as_uint(),
                                      base_reg.reinterpret_as_uint(),
                                      (j * 8).to_int64().reinterpret_as_uint64(),
                                    )
                                    emit_fmov_x_to_d(emitter, j, tmp)
                                  } else {
                                    arm64_ldrx(
                                      emitter,
                                      false,
                                      2,
                                      tmp.reinterpret_as_uint(),
                                      base_reg.reinterpret_as_uint(),
                                      (j * 4).to_int64().reinterpret_as_uint64(),
                                    )
                                    emit_fmov_w_to_s(emitter, j, tmp)
                                  }
                                  give_reg(pool, tmp)
                                  j = j + 1
                                }
                              }
                            }
                          }
                        } else if expr is Expr::Call(callee~, args~, ..) {
                          gen_call_expr(emitter, alloc, syms, pool, cstrings, callee, args, loc, bag)
                        } else {
                          let base_reg : Int = 0
                          if expr_is_lvalue_simple(expr) {
                            gen_lvalue_addr(emitter, alloc, syms, pool, cstrings, expr, base_reg, bag)
                          } else {
                            match alloc.agg_temp_offset {
                              None => {
                                add_error(bag, loc, "codegen: missing aggregate temp for return")
                                return gjmp(emitter, return_chain)
                              }
                              Some(off) => {
                                gen_agg_expr_to_addr(
                                  emitter,
                                  alloc,
                                  syms,
                                  pool,
                                  cstrings,
                                  expr,
                                  29,
                                  off,
                                  alloc.ret_ty,
                                  loc,
                                  bag,
                                )
                                emit_addr_local(emitter, base_reg, off, loc, bag)
                              }
                            }
                          }
                          arm64_ldrs(emitter, base_reg.reinterpret_as_uint(), size)
                        }
                      }
                  }
                _ => {
                  let expr_ty = type_of_expr(alloc.sem, expr)
                  gen_expr_any_with_type(
                    emitter,
                    alloc,
                    syms,
                    pool,
                    cstrings,
                    expr,
                    expr_ty,
                    0,
                    bag,
                  )
                  emit_cast_value(emitter, alloc.sem, expr_ty, alloc.ret_ty, 0, loc, bag)
                }
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
struct FramePlan {
  frame_size : Int
  used_bytes_after_hidden : Int
  agg_temp_size : Int
  agg_temp_align : Int
  agg_temp_offset : Int?
  compound_literal_slots : FastMap[Int, Int]
  ret_loc : Int
  arg_locs : Array[Int]
  stack_size : Int
  param_tys : Array[CType]
}

///|
fn compute_frame_plan(
  sem : SemContext,
  func : FuncDef,
  static_locals : FastMap[Int, StaticLocalInfo],
  bag : DiagBag,
) -> FramePlan {
  let alloc = new_local_alloc(sem, func.return_type, func.name, static_locals)
  cg_push_scope(alloc)
  let param_tys : Array[CType] = Array::new(capacity=func.params.length())
  for p in func.params {
    param_tys.push(adjust_param_type_for_local(p.ty))
  }
  let variadic_index = if func.varargs { param_tys.length() } else { 0 }
  let layout = arm64_pcs(sem, variadic_index, func.return_type, param_tys, func.loc, bag)
  let ret_loc = layout.ret_loc
  let arg_locs = layout.arg_locs
  let stack_size = layout.stack_size
  alloc.ret_loc = Some(layout.ret_loc)
  reserve_sret_slot(alloc, func.loc, bag)
  let mut i = 0
  while i < func.params.length() {
    let p = func.params[i]
    let param_ty = param_tys[i]
    let loc_i = layout.arg_locs.get(i).unwrap_or(0)
    if (loc_i & 1) != 0 {
      alloc_local_byref(alloc, p.name, p.id, param_ty) |> ignore
    } else {
      alloc_local(alloc, p.name, p.id, param_ty, p.loc) |> ignore
    }
    i = i + 1
  }
  let func_id = func.id
  let compound_keys =
    if func_id > 0 {
      get_opt_by_id(sem.func_compound_literals_by_id, func_id)
    } else {
      sem.func_compound_literals.get(func.name)
    }
  if compound_keys is Some(keys) {
    for key in keys {
      if alloc.compound_literal_slots.get(key) is None {
        if sem.compound_literal_sizes.get(key) is Some((size, align)) {
          if size > 0 {
            let slot_align = if align <= 0 { 1 } else { align }
            let offset = alloc_hidden_slot(alloc, size, slot_align)
            alloc.compound_literal_slots.set(key, offset)
          }
        }
      }
    }
  }
  let agg_temps =
    if func_id > 0 {
      get_opt_by_id(sem.func_agg_temps_by_id, func_id)
    } else {
      sem.func_agg_temps.get(func.name)
    }
  if agg_temps is Some((size, align)) {
    alloc.agg_temp_size = size
    alloc.agg_temp_align = align
  }
  if alloc.agg_temp_size > 0 && alloc.agg_temp_offset is None {
    let align = if alloc.agg_temp_align <= 0 { 1 } else { alloc.agg_temp_align }
    let off = alloc_hidden_slot(alloc, alloc.agg_temp_size, align)
    alloc.agg_temp_offset = Some(off)
  }
  let used_bytes_after_hidden = alloc.used_bytes
  let agg_temp_size = alloc.agg_temp_size
  let agg_temp_align = alloc.agg_temp_align
  let agg_temp_offset = alloc.agg_temp_offset
  let compound_literal_slots = alloc.compound_literal_slots
  let walk_exprs = if func_id > 0 {
    get_opt_by_id(sem.func_has_stmt_expr_by_id, func_id).unwrap_or(false)
  } else {
    sem.func_has_stmt_expr.get(func.name).unwrap_or(false)
  }
  let has_local_decls = if func_id > 0 {
    get_opt_by_id(sem.func_has_local_decl_by_id, func_id).unwrap_or(false)
  } else {
    sem.func_has_local_decl.get(func.name).unwrap_or(false)
  }
  if has_local_decls {
    layout_stmt(alloc, func.body, walk_exprs)
  }
  let frame_size = align_up(alloc.used_bytes, 16)
  cg_pop_scope(alloc)
  {
    frame_size,
    used_bytes_after_hidden,
    agg_temp_size,
    agg_temp_align,
    agg_temp_offset,
    compound_literal_slots,
    ret_loc,
    arg_locs,
    stack_size,
    param_tys,
  }
}

///|
fn callee_saved_regs() -> Array[Int] {
  callee_saved_regs_list
}

///|
fn emit_prologue(emitter : Arm64Emitter, frame_size : Int) -> Unit {
  emit32(emitter, (0xa9bf7bfd : UInt))
  emit32(emitter, (0x910003fd : UInt))
  let regs = callee_saved_regs()
  let callee_save_bytes = regs.length() * 8
  let total_size = frame_size + callee_save_bytes
  if total_size > 0 {
    let off = (0 : UInt64) - total_size.to_uint64()
    arm64_spoff(emitter, (31 : UInt), off)
  }
  // Save callee-saved registers used for temporaries at the bottom of the frame
  // (below locals) so local slots (fp-relative negatives) remain unchanged.
  let base_off = -total_size
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
  let regs = callee_saved_regs()
  let callee_save_bytes = regs.length() * 8
  let total_size = frame_size + callee_save_bytes
  // Restore callee-saved temporaries from the bottom of the frame.
  let base_off = -total_size
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
  let callee_save_bytes = callee_saved_regs().length() * 8
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
  func_offsets : FastMap[String, Int],
  label_addrs_by_func : FastMap[String, FastMap[String, Int]],
  cstrings : CstringPool,
  static_locals : FastMap[Int, StaticLocalInfo],
  func : FuncDef,
  bag : DiagBag,
) -> Unit {
  let link = link_name(func.name)
  sym_for_name(syms, link) |> ignore
  let start = emitter_pc(emitter)
  func_offsets.set(link, start)

  let plan = compute_frame_plan(sem, func, static_locals, bag)
  let frame_size = plan.frame_size
  let alloc =
    new_local_alloc_with_compound_slots(
      sem,
      func.return_type,
      func.name,
      static_locals,
      plan.compound_literal_slots,
    )
  cg_push_scope(alloc)
  let param_tys = plan.param_tys
  alloc.ret_loc = Some(plan.ret_loc)
  reserve_sret_slot(alloc, func.loc, bag)
  emit_prologue(emitter, frame_size)

  let pool = new_reg_pool()
  if alloc.sret_offset is Some(off) {
    arm64_strx(
      emitter,
      3,
      (8 : UInt),
      (29 : UInt),
      off.to_int64().reinterpret_as_uint64(),
    )
  }
  if func.varargs {
    alloc.varargs_stack_size = plan.stack_size
  } else {
    alloc.varargs_stack_size = 0
  }
  let arg_locs = plan.arg_locs

  let mut i = 0
  while i < func.params.length() {
    let p = func.params[i]
    let param_ty = param_tys[i]
    let loc_i = arg_locs.get(i).unwrap_or(0)
    let byref = (loc_i & 1) != 0
    let slot =
      if byref {
        Some(alloc_local_byref(alloc, p.name, p.id, param_ty))
      } else {
        alloc_local(alloc, p.name, p.id, param_ty, p.loc)
      }
    if slot is Some(slot) {
      if byref {
        if loc_i < 16 {
          arm64_strx(
            emitter,
            3,
            (loc_i >> 1).reinterpret_as_uint(),
            (29 : UInt),
            slot.offset.to_int64().reinterpret_as_uint64(),
          )
        } else if loc_i >= 32 {
          let stack_off = (loc_i & (0xfffffffe : Int)) - 32
          let tmp = take_reg(pool) catch {
            err => {
              add_error(bag, p.loc, err.to_string())
              i = i + 1
              continue
            }
          }
          arm64_ldrx(
            emitter,
            false,
            3,
            tmp.reinterpret_as_uint(),
            (29 : UInt),
            (16 + stack_off).to_int64().reinterpret_as_uint64(),
          )
          arm64_strx(
            emitter,
            3,
            tmp.reinterpret_as_uint(),
            (29 : UInt),
            slot.offset.to_int64().reinterpret_as_uint64(),
          )
          give_reg(pool, tmp)
        }
      } else if loc_i < 16 {
        let reg = loc_i >> 1
        match strip_top_qualifiers(slot.ty) {
          CType::Struct(..) | CType::Union(..) =>
            if slot_type_size_align(alloc, slot, p.loc) is Some((size, _)) {
              emit_store_gp_regs_to_addr(
                emitter,
                reg,
                reg + 1,
                size,
                29,
                slot.offset,
                p.loc,
                bag,
              )
            }
          _ =>
            emit_store_local_scalar(
              emitter,
              alloc.sem,
              slot.ty,
              reg,
              slot.offset,
              p.loc,
              bag,
            )
        }
      } else if loc_i < 32 {
        let fp_reg = (loc_i >> 1) - 8
        match arm64_hfa(alloc.sem, slot.ty, p.loc, bag) {
          Some((count, fsize)) => {
            let mut j = 0
            while j < count {
              let tmp = take_reg(pool) catch {
                err => {
                  add_error(bag, p.loc, err.to_string())
                  j = count
                  continue
                }
              }
              if fsize == 8 {
                emit_fmov_d_to_x(emitter, tmp, fp_reg + j)
                arm64_strx(
                  emitter,
                  3,
                  tmp.reinterpret_as_uint(),
                  (29 : UInt),
                  (slot.offset + j * 8).to_int64().reinterpret_as_uint64(),
                )
              } else {
                emit_fmov_s_to_w(emitter, tmp, fp_reg + j)
                arm64_strx(
                  emitter,
                  2,
                  tmp.reinterpret_as_uint(),
                  (29 : UInt),
                  (slot.offset + j * 4).to_int64().reinterpret_as_uint64(),
                )
              }
              give_reg(pool, tmp)
              j = j + 1
            }
          }
          None =>
            if float_kind_of_type(slot.ty) is Some(k) {
              let tmp_reg : Int = 16
              if k == CFloatKind::Double || k == CFloatKind::LongDouble {
                emit_fmov_d_to_x(emitter, tmp_reg, fp_reg)
              } else {
                emit_fmov_s_to_w(emitter, tmp_reg, fp_reg)
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
            }
        }
      } else if loc_i >= 32 {
        if slot_type_size_align(alloc, slot, p.loc) is Some((size, _)) {
          if size > 0 {
            let stack_off = (loc_i & (0xfffffffe : Int)) - 32
            emit_copy_bytes(
              emitter,
              pool,
              29,
              16 + stack_off,
              29,
              slot.offset,
              size,
              p.loc,
              bag,
            )
          }
        }
      }
    }
    i = i + 1
  }
  alloc.agg_temp_size = plan.agg_temp_size
  alloc.agg_temp_align = plan.agg_temp_align
  alloc.agg_temp_offset = plan.agg_temp_offset
  if plan.used_bytes_after_hidden > alloc.used_bytes {
    alloc.used_bytes = plan.used_bytes_after_hidden
  }

  let loops : Array[LoopChains] = []
  let switches : Array[SwitchChains] = []
  let breakables : Array[Int] = []
  let return_chain = gen_stmt(
    emitter,
    alloc,
    syms,
    pool,
    loops,
    switches,
    breakables,
    alloc.labels,
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
  label_addrs_by_func.set(func.name, alloc.labels.addrs)
}

///|
struct StringEntry {
  index : Int
  value : String
}

///|
struct CstringPool {
  order : Array[String]
  syms : FastMap[String, Sym]
}

///|
fn new_cstring_pool(capacity : Int) -> CstringPool {
  {
    order: Array::new(capacity=capacity),
    syms: fast_map_new(capacity=capacity),
  }
}

fn cstring_sym_or_add(
  pool : CstringPool,
  syms : SymTable,
  value : String,
) -> Sym {
  match pool.syms.get(value) {
    Some(sym) => sym
    None => {
      let index = pool.order.length()
      let sym_name = "_L_.str.\{index}"
      let sym = sym_for_name(syms, sym_name)
      pool.syms.set(value, sym)
      pool.order.push(value)
      sym
    }
  }
}

///|
fn string_has_nul(value : String) -> Bool {
  let len = value.length()
  for i = 0; i < len; {
    if value[i] == 0 {
      return true
    }
    continue i + 1
  } else {
    false
  }
}

///|

///|
fn ensure_bytes_len(buf : Array[Int], size : Int) -> Unit {
  if buf.length() < size {
    buf.resize(size, 0)
  }
}

///|
fn store_int_le(buf : Array[Int], offset : Int, size : Int, value : Int) -> Unit {
  ensure_bytes_len(buf, offset + size)
  let mut v = value
  let mut i = 0
  while i < size {
    buf[offset + i] = v & 0xff
    v = v >> 8
    i = i + 1
  }
}

///|
fn store_int64_le(
  buf : Array[Int],
  offset : Int,
  size : Int,
  value : Int64,
) -> Unit {
  ensure_bytes_len(buf, offset + size)
  let mut v = value.reinterpret_as_uint64()
  let mut i = 0
  while i < size {
    buf[offset + i] = (v & (0xff : UInt64)).to_int()
    v = v >> 8
    i = i + 1
  }
}

///|
fn store_uint64_le(buf : Array[Int], offset : Int, size : Int, bits : UInt64) -> Unit {
  ensure_bytes_len(buf, offset + size)
  let mut v = bits
  let mut i = 0
  while i < size {
    buf[offset + i] = (v & (0xff : UInt64)).to_int()
    v = v >> 8
    i = i + 1
  }
}

///|
fn load_uint_le(buf : Array[Int], offset : Int, size : Int) -> UInt64 {
  let mut v : UInt64 = 0
  let mut i = 0
  while i < size {
    if offset + i < buf.length() {
      let b = buf[offset + i].to_uint64() & (0xff : UInt64)
      v = v.lor(b << (i * 8))
    }
    i = i + 1
  }
  v
}

///|
fn store_bitfield_int_le(
  buf : Array[Int],
  offset : Int,
  size : Int,
  bit_off : Int,
  bit_width : Int,
  value : Int,
) -> Unit {
  if bit_width <= 0 {
    return
  }
  ensure_bytes_len(buf, offset + size)
  let unit_bits = size * 8
  let mask : UInt64 = if bit_width >= unit_bits {
    (0 : UInt64).lnot()
  } else {
    ((1 : UInt64) << bit_width) - (1 : UInt64)
  }
  let unit_mask : UInt64 = if unit_bits == 64 {
    (0 : UInt64).lnot()
  } else {
    ((1 : UInt64) << unit_bits) - (1 : UInt64)
  }
  let cur = load_uint_le(buf, offset, size)
  let val = value.to_int64().reinterpret_as_uint64() & mask
  let mask_shift = mask << bit_off
  let inv_mask = unit_mask & mask_shift.lnot()
  let combined = (cur & inv_mask) | ((val << bit_off) & unit_mask)
  store_uint64_le(buf, offset, size, combined)
}

///|
fn store_bitfield_init_le(
  buf : Array[Int],
  base_off : Int,
  info : FieldAccessInfo,
  width : Int,
  value : Int,
) -> Unit {
  let bit_off = match info.bit_offset {
    None => 0
    Some(v) => v
  }
  match info.bit_unit_size {
    Some(unit_size) =>
      store_bitfield_int_le(
        buf,
        base_off + info.offset,
        unit_size,
        bit_off,
        width,
        value,
      )
    None => {
      let byte_off = bit_off / 8
      let inner_bit = bit_off - byte_off * 8
      let bytes_needed = (inner_bit + width + 7) / 8
      store_bitfield_int_le(
        buf,
        base_off + info.offset + byte_off,
        bytes_needed,
        inner_bit,
        width,
        value,
      )
    }
  }
}

///|
struct LabelAddrContext {
  func_sym : Sym
  func_start : Int
  labels : FastMap[String, Int]
}

///|
fn const_pointer_from_lvalue(
  sem : SemContext,
  syms : SymTable,
  cstrings : CstringPool,
  static_locals : FastMap[Int, StaticLocalInfo],
  expr : Expr,
  label_ctx? : LabelAddrContext? = None,
) -> (Sym, Int)? {
  match expr {
    Expr::Ident(name~, id~, ..) =>
      match static_locals.get(id) {
        Some(info) => Some((sym_for_static_local(syms, info), 0))
        None => Some((sym_for_ident(syms, name, id=id), 0))
      }
    Expr::StringLit(value~, ..) =>
      Some((cstring_sym_or_add(cstrings, syms, value), 0))
    Expr::Member(base~, name~, id~, is_arrow~, loc~, ..) => {
      let base_ptr = if is_arrow {
        const_pointer_from_expr(sem, syms, cstrings, static_locals, base, label_ctx=label_ctx)
      } else {
        const_pointer_from_lvalue(sem, syms, cstrings, static_locals, base, label_ctx=label_ctx)
      }
      match base_ptr {
        None => None
        Some((sym, addend)) =>
          match member_access_info(sem, base, name, id, is_arrow, loc) {
            None => None
            Some(info) =>
              match info.bit_width {
                Some(_) => None
                None => Some((sym, addend + info.offset))
              }
          }
      }
    }
    Expr::Index(base~, index~, loc~, ..) => {
      match const_int_from_expr(sem, index, expr_loc(index)) {
        None => None
        Some(idx) =>
          match const_pointer_from_expr(sem, syms, cstrings, static_locals, base, label_ctx=label_ctx) {
            None => None
            Some((sym, addend)) =>
              match element_type_for_pointer_arith(type_of_expr(sem, base)) {
                None => None
                Some(elem_ty) =>
                  match type_size_align_or_error(sem, elem_ty, loc) {
                    None => None
                    Some((elem_size, _)) =>
                      Some((sym, addend + idx * elem_size))
                  }
              }
          }
      }
    }
    Expr::Unary(op=UnaryOp::Deref, expr=inner, ..) =>
      const_pointer_from_expr(sem, syms, cstrings, static_locals, inner, label_ctx=label_ctx)
    Expr::Cast(expr=inner, ..) =>
      const_pointer_from_lvalue(sem, syms, cstrings, static_locals, inner, label_ctx=label_ctx)
    Expr::Unary(op=UnaryOp::Plus, expr=inner, ..) =>
      const_pointer_from_lvalue(sem, syms, cstrings, static_locals, inner, label_ctx=label_ctx)
    _ => None
  }
}

///|
fn const_pointer_from_expr(
  sem : SemContext,
  syms : SymTable,
  cstrings : CstringPool,
  static_locals : FastMap[Int, StaticLocalInfo],
  expr : Expr,
  label_ctx? : LabelAddrContext? = None,
) -> (Sym, Int)? {
  match expr {
    Expr::StringLit(value~, ..) =>
      Some((cstring_sym_or_add(cstrings, syms, value), 0))
    Expr::Ident(name~, id~, ..) =>
      match static_locals.get(id) {
        Some(info) => Some((sym_for_static_local(syms, info), 0))
        None => Some((sym_for_ident(syms, name, id=id), 0))
      }
    Expr::LabelAddr(name~, ..) =>
      match label_ctx {
        None => None
        Some(ctx) =>
          match ctx.labels.get(name) {
            None => None
            Some(addr) => Some((ctx.func_sym, addr - ctx.func_start))
          }
      }
    Expr::Member(..) | Expr::Index(..) =>
      match type_of_lvalue(sem, expr) {
        Some(ty) =>
          match strip_top_qualifiers(ty) {
            CType::Array(..) =>
              const_pointer_from_lvalue(sem, syms, cstrings, static_locals, expr, label_ctx=label_ctx)
            _ => None
          }
        None => None
      }
    Expr::Unary(op=UnaryOp::Addr, expr=inner, ..) =>
      const_pointer_from_lvalue(sem, syms, cstrings, static_locals, inner, label_ctx=label_ctx)
    Expr::Cast(expr=inner, ..) =>
      const_pointer_from_expr(sem, syms, cstrings, static_locals, inner, label_ctx=label_ctx)
    Expr::Unary(op=UnaryOp::Plus, expr=inner, ..) =>
      const_pointer_from_expr(sem, syms, cstrings, static_locals, inner, label_ctx=label_ctx)
    _ => None
  }
}

///|
fn fill_global_initializer_bytes(
  sem : SemContext,
  syms : SymTable,
  cstrings : CstringPool,
  static_locals : FastMap[Int, StaticLocalInfo],
  ty : CType,
  init : Initializer,
  bytes : Array[Int],
  relocs : Array[Reloc],
  base_off : Int,
  bag : DiagBag,
  label_ctx? : LabelAddrContext? = None,
) -> Unit {
  match init {
    Initializer::Expr(expr~, loc~) => {
      match strip_top_qualifiers(ty) {
        CType::Array(elem=elem_ty, ..) =>
          match array_len_from_type_for_init(sem, ty, loc) {
            None => add_error(bag, loc, "codegen: incomplete array type")
            Some(n) =>
              if try_eval_int_const(sem, expr) is Some(0) {
                let (elem_sz, _) = match type_size_align_or_error(sem, elem_ty, loc) {
                  None => return
                  Some(v) => v
                }
                if elem_sz > 0 {
                  ensure_bytes_len(bytes, base_off + n * elem_sz)
                }
              } else {
                match expr {
                  Expr::StringLit(value~, ..) =>
                    if is_char_type(elem_ty) {
                      let (elem_sz, _) = match type_size_align_or_error(sem, elem_ty, loc) {
                        None => return
                        Some(v) => v
                      }
                      if elem_sz != 1 {
                        add_error(bag, loc, "codegen: string initializer for non-byte array")
                        return
                      }
                      let mut idx = 0
                      for b in @encoding/utf8.encode(value) {
                        if idx >= n - 1 {
                          break
                        }
                        store_int_le(bytes, base_off + idx, 1, b.to_int())
                        idx = idx + 1
                      }
                      store_int_le(bytes, base_off + idx, 1, 0)
                    } else {
                      add_error(bag, loc, "codegen: string initializer for non-byte array")
                    }
                  _ =>
                    add_error(bag, loc, "codegen: scalar initializer for array not supported")
                }
              }
          }
        CType::Struct(..) | CType::Union(..) =>
          match expr {
            Expr::CompoundLiteral(ty=lit_ty, init=lit_init, ..) =>
              fill_global_initializer_bytes(
                sem,
                syms,
                cstrings,
                static_locals,
                lit_ty,
                lit_init,
                bytes,
                relocs,
                base_off,
                bag,
                label_ctx=label_ctx,
              )
            _ => add_error(bag, loc, "codegen: aggregate initializer must be a list")
          }
        _ => {
          let (size, _) = match type_size_align_or_error(sem, ty, loc) {
            None => return
            Some(v) => v
          }
          ensure_bytes_len(bytes, base_off + size)
          match float_kind_of_type(ty) {
            Some(k_raw) => {
              let k = normalize_float_kind(k_raw)
              match const_float_bits_from_expr(sem, expr, k, loc) {
                Some(bits) => store_uint64_le(bytes, base_off, size, bits)
                None =>
                  match expr {
                    Expr::FloatLit(..) =>
                      add_error(bag, loc, "codegen: invalid float initializer")
                    _ => add_error(bag, loc, "codegen: non-constant float initializer")
                  }
              }
            }
            None =>
              if type_is_pointer_like(ty) {
                match const_pointer_from_expr(sem, syms, cstrings, static_locals, expr, label_ctx=label_ctx) {
                  Some((sym, addend)) => {
                    let addend64 = addend.to_int64()
                    if size > 4 {
                      store_int64_le(bytes, base_off, size, addend64)
                    } else {
                      store_int_le(bytes, base_off, size, addend)
                    }
                    relocs.push({
                      offset: base_off,
                      kind: R_AARCH64_POINTER,
                      sym,
                      addend: addend64,
                    })
                  }
                  None =>
                    if size > 4 {
                      match const_int64_from_expr(sem, expr, loc) {
                        Some(v) => store_int64_le(bytes, base_off, size, v)
                        None =>
                          add_error(
                            bag,
                            loc,
                            "codegen: non-constant pointer initializer",
                          )
                      }
                    } else {
                      match const_int_from_expr(sem, expr, loc) {
                        Some(v) => store_int_le(bytes, base_off, size, v)
                        None =>
                          add_error(
                            bag,
                            loc,
                            "codegen: non-constant pointer initializer",
                          )
                      }
                    }
                }
              } else {
                if size > 4 {
                  match const_int64_from_expr(sem, expr, loc) {
                    None =>
                      add_error(
                        bag,
                        loc,
                        "codegen: non-constant scalar initializer",
                      )
                    Some(v) => store_int64_le(bytes, base_off, size, v)
                  }
                } else {
                  match const_int_from_expr(sem, expr, loc) {
                    None =>
                      add_error(
                        bag,
                        loc,
                        "codegen: non-constant scalar initializer",
                      )
                    Some(v) => store_int_le(bytes, base_off, size, v)
                  }
                }
              }
          }
        }
      }
    }
    Initializer::List(items~, loc~) => {
      match strip_top_qualifiers(ty) {
        CType::Array(elem=elem_ty, ..) => {
          let n = match array_len_from_type_for_init(sem, ty, loc) {
            None => {
              add_error(bag, loc, "codegen: incomplete array type")
              return
            }
            Some(v) => v
          }
          let (elem_size, _) = match type_size_align_or_error(sem, elem_ty, loc) {
            None => return
            Some(v) => v
          }
          let total_bytes = n * elem_size
          ensure_bytes_len(bytes, base_off + total_bytes)
          let mut next_index = 0
          for item in items {
            let mut idx = next_index
            let mut has_index = false
            let mut range_pos = -1
            let mut range_start : Int? = None
            let mut range_end : Int? = None
            let mut range_loc = item.loc
            if item.designators.length() > 0 {
              match item.designators[0] {
                InitDesignator::Index(expr~, loc=des_loc) =>
                  if const_int_from_expr(sem, expr, des_loc) is Some(v) {
                    idx = v
                    has_index = true
                    if idx < 0 || idx >= n {
                      add_error(bag, des_loc, "codegen: array designator out of bounds")
                    }
                  }
                InitDesignator::IndexRange(start~, end~, loc=des_loc) =>
                  match (const_int_from_expr(sem, start, des_loc), const_int_from_expr(sem, end, des_loc)) {
                    (Some(start_val), Some(end_val)) => {
                      idx = start_val
                      has_index = true
                      range_start = Some(start_val)
                      range_end = Some(end_val)
                      range_loc = des_loc
                      if idx < 0 || idx >= n {
                        add_error(bag, des_loc, "codegen: array designator out of bounds")
                      }
                    }
                    _ =>
                      add_error(
                        bag,
                        des_loc,
                        "codegen: array designator must be constant",
                      )
                  }
                _ => ()
              }
              let mut i = 0
              while i < item.designators.length() {
                match item.designators[i] {
                  InitDesignator::IndexRange(start~, end~, loc=des_loc) => {
                    range_pos = i
                    range_loc = des_loc
                    if range_start is None {
                      range_start =
                        match const_int_from_expr(sem, start, des_loc) {
                          Some(v) => Some(v)
                          None => None
                        }
                      range_end =
                        match const_int_from_expr(sem, end, des_loc) {
                          Some(v) => Some(v)
                          None => None
                        }
                    }
                    break
                  }
                  _ => ()
                }
                i = i + 1
              }
            }
            if range_pos >= 0 {
              if range_pos != item.designators.length() - 1 {
                add_error(bag, range_loc, "codegen: array range designator must be last")
              } else {
                match (range_start, range_end) {
                  (Some(start_idx), Some(end_idx)) => {
                    if end_idx < start_idx {
                      add_error(bag, range_loc, "codegen: array designator range is empty")
                    } else {
                      if range_pos == 0 &&
                        (start_idx < 0 || end_idx < 0 || start_idx >= n || end_idx >= n) {
                        add_error(bag, range_loc, "codegen: array designator out of bounds")
                      }
                      let mut cur = start_idx
                      while cur <= end_idx {
                        if range_pos == 0 && (cur < 0 || cur >= n) {
                          cur = cur + 1
                          continue
                        }
                        let designators = designators_with_range_index(
                          item.designators,
                          cur,
                        )
                        let (target_ty, rel_off) = match resolve_init_designator_offset_type(
                          sem,
                          ty,
                          designators,
                          item.loc,
                          bag,
                        ) {
                          None => (elem_ty, cur * elem_size)
                          Some((t, o)) => (t, o)
                        }
                        fill_global_initializer_bytes(
                          sem,
                          syms,
                          cstrings,
                          static_locals,
                          target_ty,
                          item.value,
                          bytes,
                          relocs,
                          base_off + rel_off,
                          bag,
                          label_ctx=label_ctx,
                        )
                        cur = cur + 1
                      }
                    }
                  }
                  _ =>
                    add_error(
                      bag,
                      range_loc,
                      "codegen: array designator must be constant",
                    )
                }
              }
              if range_pos == 0 {
                match range_end {
                  Some(end_idx) if end_idx >= 0 => next_index = end_idx + 1
                  _ => ()
                }
              } else if has_index {
                if idx >= 0 {
                  next_index = idx + 1
                }
              } else {
                next_index = next_index + 1
              }
              continue
            }
            if !has_index && idx >= n {
              // TCC accepts excess array initializers and truncates them.
              continue
            }
            let (target_ty, rel_off) = if item.designators.length() > 0 {
              match resolve_init_designator_offset_type(
                sem,
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
            fill_global_initializer_bytes(
              sem,
              syms,
              cstrings,
              static_locals,
              target_ty,
              item.value,
              bytes,
              relocs,
              base_off + rel_off,
              bag,
              label_ctx=label_ctx,
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
        CType::Struct(name=tag, id=tag_id, fields=field_list, attrs=_) => {
          let fields = resolve_struct_fields(
            sem,
            tag,
            tag_id,
            field_list,
            is_union=false,
          )
          let list = match fields {
            None => {
              add_error(bag, loc, "codegen: incomplete struct '\{tag}'")
              return
            }
            Some(v) => v
          }
          let (size, _) = match type_size_align_or_error(sem, ty, loc) {
            None => return
            Some(v) => v
          }
          ensure_bytes_len(bytes, base_off + size)
          let mut index = 0
          let mut item_idx = 0
          while item_idx < items.length() {
            let item = items[item_idx]
            if item.designators.length() > 0 {
              if resolve_init_designator_access_info(
                sem,
                ty,
                item.designators,
                item.loc,
                bag,
              ) is Some(info) {
                match info.bit_width {
                  Some(width) => {
                    match item.value {
                      Initializer::Expr(expr~, ..) =>
                        match const_int_from_expr(sem, expr, item.loc) {
                          None =>
                            add_error(
                              bag,
                              item.loc,
                              "codegen: non-constant bitfield initializer",
                            )
                          Some(v) =>
                            store_bitfield_init_le(
                              bytes,
                              base_off,
                              info,
                              width,
                              v,
                            )
                        }
                      _ => add_error(bag, item.loc, "codegen: bitfield initializer must be scalar")
                    }
                  }
                  None =>
                    fill_global_initializer_bytes(
                      sem,
                      syms,
                      cstrings,
                      static_locals,
                      info.ty,
                      item.value,
                      bytes,
                      relocs,
                      base_off + info.offset,
                      bag,
                      label_ctx=label_ctx,
                    )
                }
              }
              match item.designators[0] {
                InitDesignator::Field(name~, id~, ..) =>
                  if find_field_index_cached(sem, ty, name, id, item.loc) is Some(idx) {
                    index = idx + 1
                  }
                _ => ()
              }
              item_idx = item_idx + 1
            } else {
              match next_init_field(list, index) {
                None => {
                  add_error(bag, item.loc, "codegen: too many initializers for aggregate")
                  item_idx = item_idx + 1
                }
                Some((field, next_idx)) => {
                  let field_off =
                    if field.bit_width is Some(_) {
                      0
                    } else {
                      match eval_builtin_offsetof(sem, ty, [field.name], item.loc) {
                        None => 0
                        Some(v) => v
                      }
                    }
                  let mut consumed = 1
                  let mut used_elision = false
                  match (strip_top_qualifiers(field.ty), item.value) {
                    (CType::Array(..), Initializer::Expr(expr~, ..)) =>
                      match expr {
                        Expr::StringLit(..) => ()
                        _ => {
                          let n = array_len_from_type_for_init(sem, field.ty, item.loc)
                          let (elided_items, count) = collect_elided_array_items_codegen(items, item_idx, n)
                          let init = Initializer::List(items=elided_items, loc=item.loc)
                          fill_global_initializer_bytes(
                            sem,
                            syms,
                            cstrings,
                            static_locals,
                            field.ty,
                            init,
                            bytes,
                            relocs,
                            base_off + field_off,
                            bag,
                            label_ctx=label_ctx,
                          )
                          consumed = count
                          used_elision = true
                        }
                      }
                    (CType::Struct(..) | CType::Union(..), Initializer::Expr(..)) =>
                      if has_single_init_field_codegen(sem, field.ty) {
                        let init = Initializer::List(
                          items=[{
                            designators: [],
                            value: item.value,
                            loc: item.loc,
                          }],
                          loc=item.loc,
                        )
                        fill_global_initializer_bytes(
                          sem,
                          syms,
                          cstrings,
                          static_locals,
                          field.ty,
                          init,
                          bytes,
                          relocs,
                          base_off + field_off,
                          bag,
                          label_ctx=label_ctx,
                        )
                        used_elision = true
                      }
                    _ => ()
                  }
                  if !used_elision {
                    if field.bit_width is Some(_) {
                      match record_field_access_info(sem, ty, field.name, field.id, item.loc) {
                        None => add_error(bag, item.loc, "codegen: missing bitfield info")
                        Some(info) =>
                          if info.bit_width is Some(width) {
                            match item.value {
                              Initializer::Expr(expr~, ..) =>
                                match const_int_from_expr(sem, expr, item.loc) {
                                  None =>
                                    add_error(
                                      bag,
                                      item.loc,
                                      "codegen: non-constant bitfield initializer",
                                    )
                                  Some(v) =>
                                    store_bitfield_init_le(
                                      bytes,
                                      base_off,
                                      info,
                                      width,
                                      v,
                                    )
                                }
                              _ =>
                                add_error(bag, item.loc, "codegen: bitfield initializer must be scalar")
                            }
                          }
                      }
                    } else {
                      fill_global_initializer_bytes(
                        sem,
                        syms,
                        cstrings,
                        static_locals,
                        field.ty,
                        item.value,
                        bytes,
                        relocs,
                        base_off + field_off,
                        bag,
                        label_ctx=label_ctx,
                      )
                    }
                  }
                  index = next_idx
                  item_idx = item_idx + consumed
                }
              }
            }
          }
        }
        CType::Union(name=tag, id=tag_id, fields=field_list, attrs=_) => {
          let fields = resolve_struct_fields(
            sem,
            tag,
            tag_id,
            field_list,
            is_union=true,
          )
          let list = match fields {
            None => {
              add_error(bag, loc, "codegen: incomplete union '\{tag}'")
              return
            }
            Some(v) => v
          }
          let (size, _) = match type_size_align_or_error(sem, ty, loc) {
            None => return
            Some(v) => v
          }
          ensure_bytes_len(bytes, base_off + size)
          if items.length() == 0 {
            return
          }
          let first = items[0]
          if first.designators.length() > 0 {
            if resolve_init_designator_access_info(
              sem,
              ty,
              first.designators,
              first.loc,
              bag,
            ) is Some(info) {
              match info.bit_width {
                Some(width) => {
                  match first.value {
                    Initializer::Expr(expr~, ..) =>
                      match const_int_from_expr(sem, expr, first.loc) {
                        None =>
                          add_error(
                            bag,
                            first.loc,
                            "codegen: non-constant bitfield initializer",
                          )
                        Some(v) =>
                          store_bitfield_init_le(
                            bytes,
                            base_off,
                            info,
                            width,
                            v,
                          )
                      }
                    _ => add_error(bag, first.loc, "codegen: bitfield initializer must be scalar")
                  }
                }
                None =>
                  fill_global_initializer_bytes(
                    sem,
                    syms,
                    cstrings,
                    static_locals,
                    info.ty,
                    first.value,
                    bytes,
                    relocs,
                    base_off + info.offset,
                    bag,
                    label_ctx=label_ctx,
                  )
              }
            }
          } else if list.length() > 0 {
            let field = list[0]
            if field.bit_width is Some(_) {
              match record_field_access_info(sem, ty, field.name, field.id, first.loc) {
                None => add_error(bag, first.loc, "codegen: missing bitfield info")
                Some(info) =>
                  if info.bit_width is Some(width) {
                    match first.value {
                      Initializer::Expr(expr~, ..) =>
                        match const_int_from_expr(sem, expr, first.loc) {
                          None =>
                            add_error(
                              bag,
                              first.loc,
                              "codegen: non-constant bitfield initializer",
                            )
                          Some(v) =>
                            store_bitfield_init_le(
                              bytes,
                              base_off,
                              info,
                              width,
                              v,
                            )
                        }
                      _ =>
                        add_error(bag, first.loc, "codegen: bitfield initializer must be scalar")
                    }
                  }
              }
            } else {
              fill_global_initializer_bytes(
                sem,
                syms,
                cstrings,
                static_locals,
                field.ty,
                first.value,
                bytes,
                relocs,
                base_off,
                bag,
                label_ctx=label_ctx,
              )
            }
          }
        }
        _ => add_error(bag, loc, "codegen: initializer list for non-aggregate")
      }
    }
  }
}

///|
fn build_global_initializer_bytes(
  sem : SemContext,
  syms : SymTable,
  cstrings : CstringPool,
  static_locals : FastMap[Int, StaticLocalInfo],
  ty : CType,
  init : Initializer,
  bag : DiagBag,
  label_ctx? : LabelAddrContext? = None,
) -> (Array[Int], Array[Reloc])? {
  let init_loc = match init {
    Initializer::Expr(loc=loc, ..) => loc
    Initializer::List(loc=loc, ..) => loc
  }
  let (size, _) = match type_size_align_or_error(sem, ty, init_loc) {
    None => return None
    Some(v) => v
  }
  let bytes : Array[Int] = []
  ensure_bytes_len(bytes, size)
  let relocs : Array[Reloc] = []
  fill_global_initializer_bytes(
    sem,
    syms,
    cstrings,
    static_locals,
    ty,
    init,
    bytes,
    relocs,
    0,
    bag,
    label_ctx=label_ctx,
  )
  Some((bytes, relocs))
}

///|
fn build_string_section(
  entries : Array[StringEntry],
  name : String,
  align : Int,
) -> (FastMap[String, Int], Section?) {
  if entries.length() == 0 {
    return (fast_map_new(), None)
  }
  let mut size_hint = 0
  for entry in entries {
    size_hint = size_hint + entry.value.length() + 1
    size_hint = (size_hint + 3) & -4
  }
  let offsets : FastMap[String, Int] = fast_map_new(capacity=entries.length())
  let buf = @buffer.new(size_hint=size_hint)
  for entry in entries {
    let off = buf.length()
    offsets.set(entry.value, off)
    buf.write_string_utf8(entry.value[:])
    buf.write_byte(0)
    while (buf.length() & 3) != 0 {
      buf.write_byte(0)
    }
  }
  let size_bytes = buf.length()
  let bytes = buf.view()
  let words : Array[UInt] = Array::new(capacity=(size_bytes + 3) / 4)
  let mut pos = 0
  while pos + 3 < size_bytes {
    let b0 = bytes[pos].to_uint()
    let b1 = bytes[pos + 1].to_uint() << 8
    let b2 = bytes[pos + 2].to_uint() << 16
    let b3 = bytes[pos + 3].to_uint() << 24
    words.push(b0 | b1 | b2 | b3)
    pos = pos + 4
  }
  let sec : Section = { name, data: words, relocs: [], align, size_bytes }
  (offsets, Some(sec))
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
  codegen_arm64_object_bytes_with_sem(unit, sem, bag)
}

///|
fn codegen_arm64_object_bytes_with_sem(
  unit : TranslationUnit,
  sem : SemContext,
  bag : DiagBag,
) -> Bytes? {
  if has_errors(bag) {
    return None
  }
  let decl_count = unit.decls.length()
  let mut func_count = 0
  let mut main_found = false
  let func_defs : Array[FuncDef] = Array::new(capacity=decl_count)
  let var_decls : Array[VarDecl] = Array::new(capacity=decl_count)
  let external_symbols : Array[(String, Bool)] = Array::new(capacity=decl_count)
  for decl in unit.decls {
    match decl {
      Decl::FuncDef(func) => {
        func_count = func_count + 1
        if func.name == "main" {
          main_found = true
        }
        func_defs.push(func)
      }
      Decl::Var(var_decl) =>
        {
          var_decls.push(var_decl)
          let link = link_name(var_decl.name)
          external_symbols.push((link, var_decl.storage == StorageClass::Extern))
        }
      Decl::FuncDecl(func_decl) => {
        let link = link_name(func_decl.name)
        external_symbols.push((link, true))
      }
      _ => ()
    }
  }
  let static_locals_by_func : FastMap[String, FastMap[Int, StaticLocalInfo]] = fast_map_new()
  let static_local_init_maps : FastMap[String, FastMap[Int, StaticLocalInfo]] = fast_map_new()
  let static_local_decls : Array[VarDecl] = Array::new(capacity=decl_count)
  for func in func_defs {
    let func_id = func.id
    let has_static_locals = if func_id > 0 {
      get_opt_by_id(sem.func_has_static_local_by_id, func_id).unwrap_or(false)
    } else {
      sem.func_has_static_local.get(func.name).unwrap_or(false)
    }
    if has_static_locals {
      let func_locals : FastMap[Int, StaticLocalInfo] = fast_map_new()
      collect_static_locals_in_stmt(
        func.name,
        func.body,
        func_locals,
        static_local_decls,
        static_local_init_maps,
      )
      static_locals_by_func.set(func.name, func_locals)
    }
  }
  for decl in static_local_decls {
    var_decls.push(decl)
  }
  let empty_static_locals : FastMap[Int, StaticLocalInfo] = fast_map_new()
  let total_decl_count = decl_count + static_local_decls.length()
  let sym_capacity = if total_decl_count > 0 { total_decl_count * 2 } else { 0 }
  let syms = new_symtab_with_capacity(sym_capacity)
  for pair in external_symbols {
    let (name, is_ext) = pair
    let sym = sym_for_name(syms, name)
    syms.externals.set(sym.id, is_ext)
  }
  let base_capacity = func_count * 256
  let expr_capacity = sem.expr_type_cache.length() * 2
  let code_capacity = if expr_capacity > base_capacity {
    expr_capacity
  } else {
    base_capacity
  }
  let reloc_capacity = func_count * 16
  let emitter = new_arm64_emitter_with_capacity(code_capacity, reloc_capacity)
  let func_offsets : FastMap[String, Int] = fast_map_new(capacity=func_count)
  let label_addrs_by_func : FastMap[String, FastMap[String, Int]] =
    fast_map_new(capacity=func_count)
  let cstring_pool = new_cstring_pool(total_decl_count)

  // Generate `main` first when present for stable layout, but allow objects without `main`.
  if main_found {
    for func in func_defs {
      if func.name == "main" {
        let func_statics = match static_locals_by_func.get(func.name) {
          Some(map) => map
          None => empty_static_locals
        }
        gen_func_def(
          emitter,
          sem,
          syms,
          func_offsets,
          label_addrs_by_func,
          cstring_pool,
          func_statics,
          func,
          bag,
        )
      }
    }
  }
  for func in func_defs {
    if !main_found || func.name != "main" {
      let func_statics = match static_locals_by_func.get(func.name) {
        Some(map) => map
        None => empty_static_locals
      }
      gen_func_def(
        emitter,
        sem,
        syms,
        func_offsets,
        label_addrs_by_func,
        cstring_pool,
        func_statics,
        func,
        bag,
      )
    }
  }
  if has_errors(bag) {
    return None
  }

  let data_words : Array[UInt] = []
  let data_relocs : Array[Reloc] = []
  let mut data_align = 4
  let mut bss_size = 0
  let mut bss_align = 4
  let def_symbols : FastMap[String, ObjSymbol] = fast_map_new(capacity=decl_count * 2)

  for var_decl in var_decls {
    let link = link_name(var_decl.name)
    sym_for_name(syms, link) |> ignore
    let is_extern_decl =
      var_decl.storage == StorageClass::Extern && var_decl.init is None
    if is_extern_decl {
      if !def_symbols.contains(link) {
        let id = syms.name_to_id.get(link).unwrap_or(0)
        def_symbols.set(link, {
          id,
          name: link,
          section: None,
          value: 0,
          is_external: true,
        })
        syms.externals.set(id, true)
      }
    } else {
      let global_ty =
        if var_decl.id > 0 { get_global_by_id(sem, var_decl.id) } else { None }
      let var_ty = match global_ty {
        Some(t) => t
        None =>
          match sem.globals.get(var_decl.name) {
            Some(t) => t
            None => var_decl.ty
          }
      }
      let (size, align) = match type_size_align_or_error(sem, var_ty, var_decl.loc) {
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
          let id = syms.name_to_id.get(link).unwrap_or(0)
          def_symbols.set(link, {
            id: syms.name_to_id.get(link).unwrap_or(0),
            name: link,
            section: Some(".bss"),
            value: aligned,
            is_external: var_decl.storage != StorageClass::Static,
          })
          syms.externals.set(id, false)
        }
        Some(init) => {
          let data_off = align_up(data_words.length() << 2, align)
          let init_locals = match static_local_init_maps.get(var_decl.name) {
            Some(map) => map
            None => empty_static_locals
          }
          let label_ctx =
            match static_local_func_name(var_decl.name) {
              None => None
              Some(func_name) =>
                match label_addrs_by_func.get(func_name) {
                  None => None
                  Some(labels) =>
                    match func_offsets.get(link_name(func_name)) {
                      None => None
                      Some(func_start) => {
                        let func_sym = sym_for_name(syms, link_name(func_name))
                        Some({ func_sym, func_start, labels })
                      }
                    }
                }
            }
          if build_global_initializer_bytes(
            sem,
            syms,
            cstring_pool,
            init_locals,
            var_ty,
            init,
            bag,
            label_ctx=label_ctx,
          ) is Some((bytes, rels)) {
            while (data_words.length() << 2) < data_off {
              data_words.push(0)
            }
            let mut i = 0
            while i < bytes.length() {
              let mut word : UInt = 0
              let mut j = 0
              while j < 4 && i + j < bytes.length() {
                word = word.lor(
                  (bytes[i + j].to_uint() & 0xff) << ((j & 3) << 3),
                )
                j = j + 1
              }
              data_words.push(word)
              i = i + 4
            }
            for rel in rels {
              data_relocs.push({
                offset: data_off + rel.offset,
                kind: rel.kind,
                sym: rel.sym,
                addend: rel.addend,
              })
            }
            let id = syms.name_to_id.get(link).unwrap_or(0)
            def_symbols.set(link, {
              id,
              name: link,
              section: Some(".data"),
              value: data_off,
              is_external: var_decl.storage != StorageClass::Static,
            })
            syms.externals.set(id, false)
            if align > data_align {
              data_align = align
            }
          }
        }
      }
    }
  }

  let cstring_entries : Array[StringEntry] =
    Array::new(capacity=cstring_pool.order.length())
  let rodata_entries : Array[StringEntry] =
    Array::new(capacity=cstring_pool.order.length())
  let mut i = 0
  while i < cstring_pool.order.length() {
    let value = cstring_pool.order[i]
    let entry : StringEntry = { index: i, value }
    if string_has_nul(value) {
      rodata_entries.push(entry)
    } else {
      cstring_entries.push(entry)
    }
    i = i + 1
  }
  let (cstring_offsets, cstring_section) = build_string_section(
    cstring_entries,
    ".cstring",
    1,
  )
  let (rodata_offsets, rodata_section) = build_string_section(
    rodata_entries,
    ".rodata",
    4,
  )

  for entry in cstring_entries {
    let name = "_L_.str.\{entry.index}"
    let off = cstring_offsets.get(entry.value).unwrap_or(0)
    let id = syms.name_to_id.get(name).unwrap_or(0)
    def_symbols.set(name, {
      id,
      name,
      section: Some(".cstring"),
      value: off,
      is_external: false,
    })
    syms.externals.set(id, false)
  }
  for entry in rodata_entries {
    let name = "_L_.str.\{entry.index}"
    let off = rodata_offsets.get(entry.value).unwrap_or(0)
    let id = syms.name_to_id.get(name).unwrap_or(0)
    def_symbols.set(name, {
      id,
      name,
      section: Some(".rodata"),
      value: off,
      is_external: false,
    })
    syms.externals.set(id, false)
  }

  for decl in unit.decls {
    match decl {
      Decl::FuncDef(func) => {
        let link = link_name(func.name)
        sym_for_name(syms, link) |> ignore
        let id = syms.name_to_id.get(link).unwrap_or(0)
        let is_ext = func.storage != StorageClass::Static
        def_symbols.set(link, {
          id,
          name: link,
          section: Some(".text"),
          value: func_offsets.get(link).unwrap_or(0),
          is_external: is_ext,
        })
        syms.externals.set(id, false)
      }
      _ => ()
    }
  }

  let ordered_names : Array[String] = Array::new(capacity=syms.names.length())
  let mut i = 0
  while i < syms.names.length() {
    let name = syms.names[i]
    if def_symbols.get(name) is Some(sym) {
      if sym.section is Some(sec) {
        if sec == ".text" {
          ordered_names.push(name)
        }
      }
    }
    i = i + 1
  }
  i = 0
  while i < syms.names.length() {
    let name = syms.names[i]
    let mut is_text = false
    if def_symbols.get(name) is Some(sym) {
      if sym.section is Some(sec) {
        if sec == ".text" {
          is_text = true
        }
      }
    }
    if !is_text {
      ordered_names.push(name)
    }
    i = i + 1
  }
  let symbols : Array[ObjSymbol] = Array::new(capacity=ordered_names.length())
  i = 0
  while i < ordered_names.length() {
    let name = ordered_names[i]
    let id = syms.name_to_id.get(name).unwrap_or(0)
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

  let text = section_from_emitter_take(".text", emitter)
  let sections : Array[Section] = [text]
  if rodata_section is Some(sec) {
    sections.push(sec)
  }
  if cstring_section is Some(sec) {
    sections.push(sec)
  }
  if data_words.length() > 0 {
    sections.push({
      name: ".data",
      data: data_words,
      relocs: data_relocs,
      align: data_align,
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
