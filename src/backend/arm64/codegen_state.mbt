///|
const VT_BTYPE : Int32 = 0x000f

///|
const VT_VOID : Int32 = 0

///|
const VT_BYTE : Int32 = 1

///|
const VT_SHORT : Int32 = 2

///|
const VT_INT : Int32 = 3

///|
const VT_LLONG : Int32 = 4

///|
const VT_PTR : Int32 = 5

///|
const VT_FUNC : Int32 = 6

///|
const VT_STRUCT : Int32 = 7

///|
const VT_FLOAT : Int32 = 8

///|
const VT_DOUBLE : Int32 = 9

///|
const VT_LDOUBLE : Int32 = 10

///|
const VT_BOOL : Int32 = 11

///|
const VT_UNSIGNED : Int32 = 0x0010

///|
const VT_CONST : Int32 = 0x0030

///|
const VT_LLOCAL : Int32 = 0x0031

///|
const VT_LOCAL : Int32 = 0x0032

///|
const VT_CMP : Int32 = 0x0033

///|
const VT_JMP : Int32 = 0x0034

///|
const VT_JMPI : Int32 = 0x0035

///|
const VT_VALMASK : Int32 = 0x003f

///|
const VT_LVAL : Int32 = 0x0100

///|
const VT_SYM : Int32 = 0x0200

///|
pub const TOK_LAND : Int32 = 0x90

///|
pub const TOK_LOR : Int32 = 0x91

///|
pub const TOK_ULT : Int32 = 0x92

///|
pub const TOK_UGE : Int32 = 0x93

///|
pub const TOK_EQ : Int32 = 0x94

///|
pub const TOK_NE : Int32 = 0x95

///|
pub const TOK_ULE : Int32 = 0x96

///|
pub const TOK_UGT : Int32 = 0x97

///|
pub const TOK_LT : Int32 = 0x9c

///|
pub const TOK_GE : Int32 = 0x9d

///|
pub const TOK_LE : Int32 = 0x9e

///|
pub const TOK_GT : Int32 = 0x9f

///|
pub const TOK_UDIV : Int32 = 0x83

///|
pub const TOK_UMOD : Int32 = 0x84

///|
pub const TOK_PDIV : Int32 = 0x85

///|
pub const TOK_SHL : Int32 = 0x3c

///|
pub const TOK_SAR : Int32 = 0x3e

///|
pub const TOK_SHR : Int32 = 0x8b

///|
pub const TOK_ADD : Int32 = 0x2b

///|
pub const TOK_SUB : Int32 = 0x2d

///|
pub const TOK_MUL : Int32 = 0x2a

///|
pub const TOK_DIV : Int32 = 0x2f

///|
pub const TOK_MOD : Int32 = 0x25

///|
pub const TOK_XOR : Int32 = 0x5e

///|
pub const TOK_AND : Int32 = 0x26

///|
pub const TOK_OR : Int32 = 0x7c

///|
const RC_INT : Int32 = 1 << 0

///|
const RC_FLOAT : Int32 = 1 << 1

///|
const RC_R30 : Int32 = 1 << 21

///|
pub const RC_IRET : Int32 = 1 << 2

///|
pub const RC_FRET : Int32 = 1 << 22

///|
priv struct SValue {
  type_t : Int32
  mut r : Int32
  r2 : Int32
  mut jtrue : Int32
  mut jfalse : Int32
  c_i : Int64
  sym : Sym?
  mut cmp_op : Int32
  mut cmp_r : Int32
}

///|
let vstack : Array[SValue] = []

///|
fn vtop_index() -> Int32 {
  vstack.length() - 1
}

///|
fn vpushi(value : Int32) -> Unit {
  vstack.push({
    type_t: VT_INT,
    r: VT_CONST,
    r2: VT_CONST,
    jtrue: 0,
    jfalse: 0,
    c_i: value.to_int64(),
    sym: None,
    cmp_op: 0,
    cmp_r: 0,
  })
}

///|
fn vpop() -> Unit {
  if vstack.length() > 0 {
    vstack.pop() |> ignore
  }
}

///|
fn vpop_value() -> SValue raise {
  match vstack.pop() {
    Some(value) => value
    None => fail("vstack underflow")
  }
}

///|
pub fn vdup() -> Unit {
  let idx = vtop_index()
  if idx >= 0 {
    let val = vstack[idx]
    let _ = (val.jtrue, val.jfalse, val.cmp_op)
    vstack.push(val)
  }
}

///|
fn vswap() -> Unit {
  let len = vstack.length()
  if len < 2 {
    return
  }
  let idx = len - 1
  let tmp = vstack[idx]
  vstack[idx] = vstack[idx - 1]
  vstack[idx - 1] = tmp
}

///|
fn vset_VT_CMP(op : Int32) -> Unit {
  let idx = vtop_index()
  if idx >= 0 {
    vstack[idx].r = VT_CMP
    vstack[idx].cmp_op = op
    vstack[idx].jfalse = 0
    vstack[idx].jtrue = 0
  }
}

///|
fn gv(emitter : Arm64Emitter, rc : Int32) -> Int32 raise {
  let idx = vtop_index()
  if idx < 0 {
    fail("gv empty")
  }
  let sv = vstack[idx]
  let r = sv.r & VT_VALMASK
  let r_ok = (sv.r & VT_LVAL) == 0 && r < VT_CONST && (reg_classes[r] & rc) != 0
  if !r_ok {
    let r1 = get_reg(rc)
    load(emitter, r1, idx)
    vstack[idx].r = r1
    return r1
  }
  r
}

///|
fn get_reg(rc : Int32) -> Int32 raise {
  let mut r = 0
  while r < NB_REGS {
    if (reg_classes[r] & rc) != 0 {
      let mut used = false
      for sv in vstack {
        let vr = sv.r & VT_VALMASK
        if vr == r || sv.r2 == r {
          used = true
          break
        }
      }
      if !used {
        return r
      }
    }
    r = r + 1
  }
  fail("no free register")
}

///|
fn gv2(emitter : Arm64Emitter, rc1 : Int32, rc2 : Int32) -> Unit raise {
  let idx = vtop_index()
  if idx < 1 {
    fail("gv2 stack underflow")
  }
  if vstack[idx].r != VT_CMP && rc1 <= rc2 {
    vswap()
    gv(emitter, rc1) |> ignore
    vswap()
    gv(emitter, rc2) |> ignore
    if (vstack[idx - 1].r & VT_VALMASK) >= VT_CONST {
      vswap()
      gv(emitter, rc1) |> ignore
      vswap()
    }
  } else {
    gv(emitter, rc2) |> ignore
    vswap()
    gv(emitter, rc1) |> ignore
    vswap()
    if (vstack[idx].r & VT_VALMASK) >= VT_CONST {
      gv(emitter, rc2) |> ignore
    }
  }
}

///|
fn arm64_gen_opil(emitter : Arm64Emitter, op : Int32, l : Int32) -> Unit raise {
  let mut rev = true
  if vtop_index() >= 0 {
    if arm64_iconst(vtop_index()) is Some(_) {
      vswap()
      rev = false
    }
  }
  let idx = vtop_index()
  if idx >= 1 {
    let left_idx = idx - 1
    if arm64_iconst(left_idx) is Some(val) {
      gv(emitter, RC_INT) |> ignore
      let a = intr(vstack[idx].r)
      let saved = vpop_value()
      let x = get_reg(RC_INT)
      vstack.push(saved)
      if arm64_gen_opic(emitter, op, l, rev, val, intr(x), a) {
        vstack[idx].r = x
        vswap()
        vpop()
        return
      }
    }
  }
  if !rev {
    vswap()
  }
  gv2(emitter, RC_INT, RC_INT)
  let idx2 = vtop_index()
  let a = intr(vstack[idx2 - 1].r)
  let b = intr(vstack[idx2].r)
  vpop_value() |> ignore
  let left = vpop_value()
  let x = get_reg(RC_INT)
  left.r = x
  vstack.push(left)
  let x1 = intr(x)
  match op {
    TOK_MOD => {
      emit32(
        emitter,
        (0x1ac00c00 : Int32)
        .lor(l << 31)
        .lor(30)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
      emit32(
        emitter,
        (0x1b008000 : Int32)
        .lor(l << 31)
        .lor(x1)
        .lor(30 << 5)
        .lor(b << 16)
        .lor(a << 10)
        .reinterpret_as_uint(),
      )
    }
    TOK_AND =>
      emit32(
        emitter,
        (0x0a000000 : Int32)
        .lor(l << 31)
        .lor(x1)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
    TOK_MUL =>
      emit32(
        emitter,
        (0x1b007c00 : Int32)
        .lor(l << 31)
        .lor(x1)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
    TOK_ADD =>
      emit32(
        emitter,
        (0x0b000000 : Int32)
        .lor(l << 31)
        .lor(x1)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
    TOK_SUB =>
      emit32(
        emitter,
        (0x4b000000 : Int32)
        .lor(l << 31)
        .lor(x1)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
    TOK_DIV =>
      emit32(
        emitter,
        (0x1ac00c00 : Int32)
        .lor(l << 31)
        .lor(x1)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
    TOK_PDIV =>
      emit32(
        emitter,
        (0x1ac00c00 : Int32)
        .lor(l << 31)
        .lor(x1)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
    TOK_XOR =>
      emit32(
        emitter,
        (0x4a000000 : Int32)
        .lor(l << 31)
        .lor(x1)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
    TOK_OR =>
      emit32(
        emitter,
        (0x2a000000 : Int32)
        .lor(l << 31)
        .lor(x1)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
    TOK_EQ => {
      emit32(
        emitter,
        (0x6b00001f : Int32)
        .lor(l << 31)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
      emit32(emitter, (0x1a9f17e0 : Int32).lor(x1).reinterpret_as_uint())
    }
    TOK_GE => {
      emit32(
        emitter,
        (0x6b00001f : Int32)
        .lor(l << 31)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
      emit32(emitter, (0x1a9fb7e0 : Int32).lor(x1).reinterpret_as_uint())
    }
    TOK_GT => {
      emit32(
        emitter,
        (0x6b00001f : Int32)
        .lor(l << 31)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
      emit32(emitter, (0x1a9fd7e0 : Int32).lor(x1).reinterpret_as_uint())
    }
    TOK_LE => {
      emit32(
        emitter,
        (0x6b00001f : Int32)
        .lor(l << 31)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
      emit32(emitter, (0x1a9fc7e0 : Int32).lor(x1).reinterpret_as_uint())
    }
    TOK_LT => {
      emit32(
        emitter,
        (0x6b00001f : Int32)
        .lor(l << 31)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
      emit32(emitter, (0x1a9fa7e0 : Int32).lor(x1).reinterpret_as_uint())
    }
    TOK_NE => {
      emit32(
        emitter,
        (0x6b00001f : Int32)
        .lor(l << 31)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
      emit32(emitter, (0x1a9f07e0 : Int32).lor(x1).reinterpret_as_uint())
    }
    TOK_SAR =>
      emit32(
        emitter,
        (0x1ac02800 : Int32)
        .lor(l << 31)
        .lor(x1)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
    TOK_SHL =>
      emit32(
        emitter,
        (0x1ac02000 : Int32)
        .lor(l << 31)
        .lor(x1)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
    TOK_SHR =>
      emit32(
        emitter,
        (0x1ac02400 : Int32)
        .lor(l << 31)
        .lor(x1)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
    TOK_UDIV =>
      emit32(
        emitter,
        (0x1ac00800 : Int32)
        .lor(l << 31)
        .lor(x1)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
    TOK_UGE => {
      emit32(
        emitter,
        (0x6b00001f : Int32)
        .lor(l << 31)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
      emit32(emitter, (0x1a9f37e0 : Int32).lor(x1).reinterpret_as_uint())
    }
    TOK_UGT => {
      emit32(
        emitter,
        (0x6b00001f : Int32)
        .lor(l << 31)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
      emit32(emitter, (0x1a9f97e0 : Int32).lor(x1).reinterpret_as_uint())
    }
    TOK_ULT => {
      emit32(
        emitter,
        (0x6b00001f : Int32)
        .lor(l << 31)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
      emit32(emitter, (0x1a9f27e0 : Int32).lor(x1).reinterpret_as_uint())
    }
    TOK_ULE => {
      emit32(
        emitter,
        (0x6b00001f : Int32)
        .lor(l << 31)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
      emit32(emitter, (0x1a9f87e0 : Int32).lor(x1).reinterpret_as_uint())
    }
    TOK_UMOD => {
      emit32(
        emitter,
        (0x1ac00800 : Int32)
        .lor(l << 31)
        .lor(30)
        .lor(a << 5)
        .lor(b << 16)
        .reinterpret_as_uint(),
      )
      emit32(
        emitter,
        (0x1b008000 : Int32)
        .lor(l << 31)
        .lor(x1)
        .lor(30 << 5)
        .lor(b << 16)
        .lor(a << 10)
        .reinterpret_as_uint(),
      )
    }
    _ => fail("unsupported op")
  }
}

///|
fn load(emitter : Arm64Emitter, r : Int32, sv_index : Int32) -> Unit raise {
  let sv = vstack[sv_index]
  let svtt = sv.type_t
  let svr = sv.r
  let svrv = svr & VT_VALMASK
  let mut svcul = sv.c_i.reinterpret_as_uint64() & (0xffffffff : UInt64)
  if ((svcul >> 31) & (1 : UInt64)) != 0 {
    svcul = svcul - ((1 : UInt64) << 32)
  }
  if svr == (VT_LOCAL | VT_LVAL) {
    if is_freg(r) {
      arm64_ldrv(
        emitter,
        arm64_type_size(svtt),
        fltr(r).reinterpret_as_uint(),
        (29 : UInt32),
        svcul,
      )
    } else {
      arm64_ldrx(
        emitter,
        (svtt & VT_UNSIGNED) == 0,
        arm64_type_size(svtt),
        intr(r).reinterpret_as_uint(),
        (29 : UInt32),
        svcul,
      )
    }
    return
  }
  if svr == (VT_CONST | VT_LVAL) {
    let mut i = sv.c_i.reinterpret_as_uint64()
    if sv.sym is Some(sym) {
      let off = arm64_check_offset(false, arm64_type_size(svtt), i)
      arm64_sym(emitter, (30 : UInt32), sym, off)
    } else {
      arm64_movimm(emitter, (30 : UInt32), i)
      i = 0
    }
    if is_freg(r) {
      arm64_ldrv(
        emitter,
        arm64_type_size(svtt),
        fltr(r).reinterpret_as_uint(),
        (30 : UInt32),
        arm64_check_offset(true, arm64_type_size(svtt), i),
      )
    } else {
      arm64_ldrx(
        emitter,
        (svtt & VT_UNSIGNED) == 0,
        arm64_type_size(svtt),
        intr(r).reinterpret_as_uint(),
        (30 : UInt32),
        arm64_check_offset(true, arm64_type_size(svtt), i),
      )
    }
    return
  }
  if (svr & VT_VALMASK.lnot()) == VT_LVAL && svrv < VT_CONST {
    if (svtt & VT_BTYPE) != VT_VOID {
      if is_freg(r) {
        arm64_ldrv(
          emitter,
          arm64_type_size(svtt),
          fltr(r).reinterpret_as_uint(),
          intr(svrv).reinterpret_as_uint(),
          0,
        )
      } else {
        arm64_ldrx(
          emitter,
          (svtt & VT_UNSIGNED) == 0,
          arm64_type_size(svtt),
          intr(r).reinterpret_as_uint(),
          intr(svrv).reinterpret_as_uint(),
          0,
        )
      }
    }
    return
  }
  if svr == (VT_CONST | VT_LVAL | VT_SYM) {
    let off = arm64_check_offset(false, arm64_type_size(svtt), svcul)
    match sv.sym {
      Some(sym) => arm64_sym(emitter, (30 : UInt32), sym, off)
      None => fail("missing symbol for VT_SYM")
    }
    if is_freg(r) {
      arm64_ldrv(
        emitter,
        arm64_type_size(svtt),
        fltr(r).reinterpret_as_uint(),
        (30 : UInt32),
        arm64_check_offset(true, arm64_type_size(svtt), svcul),
      )
    } else {
      arm64_ldrx(
        emitter,
        (svtt & VT_UNSIGNED) == 0,
        arm64_type_size(svtt),
        intr(r).reinterpret_as_uint(),
        (30 : UInt32),
        arm64_check_offset(true, arm64_type_size(svtt), svcul),
      )
    }
    return
  }
  if svr == (VT_CONST | VT_SYM) {
    match sv.sym {
      Some(sym) => arm64_sym(emitter, intr(r).reinterpret_as_uint(), sym, svcul)
      None => fail("missing symbol for VT_SYM")
    }
    return
  }
  if svr == VT_CONST {
    if (svtt & VT_BTYPE) != VT_VOID {
      let value : UInt64 = if arm64_type_size(svtt) == 3 {
        sv.c_i.reinterpret_as_uint64()
      } else {
        svcul
      }
      arm64_movimm(emitter, intr(r).reinterpret_as_uint(), value)
    }
    return
  }
  if svr < VT_CONST {
    if is_freg(r) && is_freg(svr) {
      if svtt == VT_LDOUBLE {
        emit32(
          emitter,
          (0x4ea01c00 : Int32)
          .lor(fltr(r) | (fltr(svr) << 5))
          .reinterpret_as_uint(),
        )
      } else {
        emit32(
          emitter,
          (0x1e604000 : Int32)
          .lor(fltr(r) | (fltr(svr) << 5))
          .reinterpret_as_uint(),
        )
      }
    } else if !is_freg(r) && !is_freg(svr) {
      emit32(
        emitter,
        (0xaa0003e0 : Int32)
        .lor(intr(r))
        .lor(intr(svr) << 16)
        .reinterpret_as_uint(),
      )
    } else {
      fail("mismatched register class")
    }
    return
  }
  if svr == VT_LOCAL {
    let neg = (0 : UInt64) - svcul
    if neg < (0x1000 : UInt64) {
      emit32(
        emitter,
        (0xd10003a0 : Int32)
        .lor(intr(r))
        .lor(neg.reinterpret_as_int64().to_int() << 10)
        .reinterpret_as_uint(),
      )
    } else {
      arm64_movimm(emitter, (30 : UInt32), neg)
      emit32(
        emitter,
        (0xcb0003a0 : Int32).lor(intr(r)).lor(30 << 16).reinterpret_as_uint(),
      )
    }
    return
  }
  if svr == VT_JMP || svr == VT_JMPI {
    let t = if svr == VT_JMPI { 1 } else { 0 }
    arm64_movimm(emitter, intr(r).reinterpret_as_uint(), t.to_uint64())
    emit32(emitter, (0x14000002 : UInt32))
    gsym(emitter, svcul.reinterpret_as_int64().to_int())
    arm64_movimm(emitter, intr(r).reinterpret_as_uint(), (1 - t).to_uint64())
    return
  }
  if svr == (VT_LLOCAL | VT_LVAL) {
    arm64_ldrx(emitter, false, 3, (30 : UInt32), (29 : UInt32), svcul)
    if is_freg(r) {
      arm64_ldrv(
        emitter,
        arm64_type_size(svtt),
        fltr(r).reinterpret_as_uint(),
        (30 : UInt32),
        0,
      )
    } else {
      arm64_ldrx(
        emitter,
        (svtt & VT_UNSIGNED) == 0,
        arm64_type_size(svtt),
        intr(r).reinterpret_as_uint(),
        (30 : UInt32),
        0,
      )
    }
    return
  }
  if svr == VT_CMP {
    arm64_load_cmp(emitter, r, sv_index)
    return
  }
  fail("unsupported load")
}
