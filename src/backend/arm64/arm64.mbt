// Copyright (C) 2026 International Digital Economy Academy
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License as published by the Free Software Foundation; version 2.1
// of the License.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public
// License along with this library.  If not, see <https://www.gnu.org/licenses/>.

///|
pub type Sym = @object.Sym

///|
pub type Reloc = @object.Reloc

///|
pub type Section = @object.Section

///|
pub const NB_REGS : Int32 = 28

///|
pub const TREG_R30 : Int32 = 19

///|
pub const TREG_F0 : Int32 = 20

///|
pub const TREG_F7 : Int32 = 27

///|
pub fn treg_r(x : Int32) -> Int32 {
  x
}

///|
pub fn treg_f(x : Int32) -> Int32 {
  TREG_F0 + x
}

///|
pub fn rc_r(x : Int32) -> Int32 {
  1 << (2 + x)
}

///|
pub fn rc_f(x : Int32) -> Int32 {
  1 << (22 + x)
}

///|
let reg_classes : Array[Int32] = [
  RC_INT | rc_r(0),
  RC_INT | rc_r(1),
  RC_INT | rc_r(2),
  RC_INT | rc_r(3),
  RC_INT | rc_r(4),
  RC_INT | rc_r(5),
  RC_INT | rc_r(6),
  RC_INT | rc_r(7),
  RC_INT | rc_r(8),
  RC_INT | rc_r(9),
  RC_INT | rc_r(10),
  RC_INT | rc_r(11),
  RC_INT | rc_r(12),
  RC_INT | rc_r(13),
  RC_INT | rc_r(14),
  RC_INT | rc_r(15),
  RC_INT | rc_r(16),
  RC_INT | rc_r(17),
  RC_INT | rc_r(18),
  RC_R30,
  RC_FLOAT | rc_f(0),
  RC_FLOAT | rc_f(1),
  RC_FLOAT | rc_f(2),
  RC_FLOAT | rc_f(3),
  RC_FLOAT | rc_f(4),
  RC_FLOAT | rc_f(5),
  RC_FLOAT | rc_f(6),
  RC_FLOAT | rc_f(7),
]

///|
pub const R_AARCH64_ADR_GOT_PAGE : Int32 = 311

///|
pub const R_AARCH64_LD64_GOT_LO12_NC : Int32 = 312

///|
pub const R_AARCH64_CALL26 : Int32 = 283

///|
pub const R_AARCH64_ADR_PREL_PG_HI21 : Int32 = 275

///|
pub const R_AARCH64_ADR_PREL_PG_HI21_NC : Int32 = 276

///|
pub const R_AARCH64_ADD_ABS_LO12_NC : Int32 = 277

///|
pub const R_AARCH64_LDST8_ABS_LO12_NC : Int32 = 278

///|
pub const R_AARCH64_JUMP26 : Int32 = 282

///|
/// Absolute 64-bit relocation used for data/pointer references.
pub const R_AARCH64_POINTER : Int32 = 257

///|
pub(all) struct Arm64Emitter {
  mut code : Array[UInt32]
  mut code_len : Int32
  relocs : Array[Reloc]
}

///|
pub fn new_arm64_emitter() -> Arm64Emitter {
  { code: [], code_len: 0, relocs: [], }
}

///|
pub fn new_arm64_emitter_with_capacity(
  code_capacity : Int32,
  reloc_capacity : Int32,
) -> Arm64Emitter {
  if code_capacity <= 0 && reloc_capacity <= 0 {
    return new_arm64_emitter()
  }
  let code_cap = if code_capacity > 0 { code_capacity } else { 0 }
  let reloc_cap = if reloc_capacity > 0 { reloc_capacity } else { 0 }
  let zero : UInt32 = 0
  {
    code: if code_cap > 0 {
      Array::make(code_cap, zero)
    } else {
      []
    },
    code_len: 0,
    relocs: Array::new(capacity=reloc_cap),
  }
}

///|
pub fn section_from_emitter(name : String, emitter : Arm64Emitter) -> Section {
  let code_len = emitter.code_len
  let zero : UInt32 = 0
  let data : Array[UInt32] = Array::make(code_len, zero)
  let mut i = 0
  while i < code_len {
    data[i] = emitter.code[i]
    i = i + 1
  }
  {
    name,
    data,
    relocs: emitter.relocs.copy(),
    align: 4,
    size_bytes: code_len << 2,
  }
}

///|
pub fn section_from_emitter_take(
  name : String,
  emitter : Arm64Emitter,
) -> Section {
  let code_len = emitter.code_len
  {
    name,
    data: emitter.code,
    relocs: emitter.relocs,
    align: 4,
    size_bytes: code_len << 2,
  }
}

///|
pub fn emit32(emitter : Arm64Emitter, insn : UInt32) -> Unit {
  let idx = emitter.code_len
  if idx >= emitter.code.length() {
    let current = emitter.code.length()
    let mut next = if current > 0 { current * 2 } else { 64 }
    if next < idx + 1 {
      next = idx + 1
    }
    let zero : UInt32 = 0
    let expanded : Array[UInt32] = Array::make(next, zero)
    let mut i = 0
    while i < idx {
      expanded[i] = emitter.code[i]
      i = i + 1
    }
    emitter.code = expanded
  }
  emitter.code[idx] = insn
  emitter.code_len = idx + 1
}

///|
pub fn emitter_pc(emitter : Arm64Emitter) -> Int32 {
  emitter.code_len << 2
}

///|
pub fn greloca(
  emitter : Arm64Emitter,
  sym : Sym,
  offset : Int32,
  kind : Int32,
  addend : Int64,
) -> Unit {
  emitter.relocs.push({ offset, kind, sym, addend, })
}

///|
pub fn greloc(
  emitter : Arm64Emitter,
  sym : Sym,
  offset : Int32,
  kind : Int32,
) -> Unit {
  greloca(emitter, sym, offset, kind, 0)
}

///|
pub fn intr(r : Int32) -> Int32 {
  if r < TREG_R30 {
    r
  } else {
    30
  }
}

///|
pub fn fltr(r : Int32) -> Int32 {
  r - TREG_F0
}

///|
pub fn is_freg(r : Int32) -> Bool {
  r >= TREG_F0
}

///|
pub fn u64_mask(bits : Int32) -> UInt64 {
  if bits <= 0 {
    return 0
  }
  let one : UInt64 = 1
  (one << bits) - 1
}

///|
pub fn arm64_encode_bimm64(value : UInt64) -> Int32 {
  let mut x = value
  let neg = (x & 1) != 0
  if neg {
    x = x.lnot()
  }
  if x == 0 {
    return -1
  }
  let mut rep = 64
  if x >> 2 == (x & u64_mask(64 - 2)) {
    rep = 2
    x = x & u64_mask(2)
  } else if x >> 4 == (x & u64_mask(64 - 4)) {
    rep = 4
    x = x & u64_mask(4)
  } else if x >> 8 == (x & u64_mask(64 - 8)) {
    rep = 8
    x = x & u64_mask(8)
  } else if x >> 16 == (x & u64_mask(64 - 16)) {
    rep = 16
    x = x & u64_mask(16)
  } else if x >> 32 == (x & u64_mask(64 - 32)) {
    rep = 32
    x = x & u64_mask(32)
  }
  let mut pos = 0
  if (x & u64_mask(32)) == 0 {
    x = x >> 32
    pos = pos + 32
  }
  if (x & u64_mask(16)) == 0 {
    x = x >> 16
    pos = pos + 16
  }
  if (x & u64_mask(8)) == 0 {
    x = x >> 8
    pos = pos + 8
  }
  if (x & u64_mask(4)) == 0 {
    x = x >> 4
    pos = pos + 4
  }
  if (x & u64_mask(2)) == 0 {
    x = x >> 2
    pos = pos + 2
  }
  if (x & u64_mask(1)) == 0 {
    x = x >> 1
    pos = pos + 1
  }
  let mut len = 0
  if (x.lnot() & u64_mask(32)) == 0 {
    x = x >> 32
    len = len + 32
  }
  if (x.lnot() & u64_mask(16)) == 0 {
    x = x >> 16
    len = len + 16
  }
  if (x.lnot() & u64_mask(8)) == 0 {
    x = x >> 8
    len = len + 8
  }
  if (x.lnot() & u64_mask(4)) == 0 {
    x = x >> 4
    len = len + 4
  }
  if (x.lnot() & u64_mask(2)) == 0 {
    x = x >> 2
    len = len + 2
  }
  if (x.lnot() & u64_mask(1)) == 0 {
    x = x >> 1
    len = len + 1
  }
  if x != 0 {
    return -1
  }
  let mut pos1 = pos
  let mut len1 = len
  if neg {
    pos1 = (pos1 + len1) & (rep - 1)
    len1 = rep - len1
  }
  (0x1000 & (rep << 6)) |
  ((((rep - 1) ^ 31) << 1) & 63) |
  (((rep - pos1) & (rep - 1)) << 6) |
  (len1 - 1)
}

///|
pub fn arm64_movi(reg : UInt32, value : UInt64) -> UInt32 {
  let m : UInt64 = 0xffff
  if (value & m.lnot()) == 0 {
    return (0x52800000 : UInt64).lor(reg.to_uint64()).lor(value << 5).to_uint()
  }
  if (value & (m << 16).lnot()) == 0 {
    return (0x52a00000 : UInt64).lor(reg.to_uint64()).lor(value >> 11).to_uint()
  }
  if (value & (m << 32).lnot()) == 0 {
    return (0xd2c00000 : UInt64).lor(reg.to_uint64()).lor(value >> 27).to_uint()
  }
  if (value & (m << 48).lnot()) == 0 {
    return (0xd2e00000 : UInt64).lor(reg.to_uint64()).lor(value >> 43).to_uint()
  }
  if (value & m.lnot()) == m << 16 {
    return (0x12800000 : UInt64)
      .lor(reg.to_uint64())
      .lor((value.lnot() << 5) & 0x1fffe0)
      .to_uint()
  }
  if (value & (m << 16).lnot()) == m {
    return (0x12a00000 : UInt64)
      .lor(reg.to_uint64())
      .lor((value.lnot() >> 11) & 0x1fffe0)
      .to_uint()
  }
  if value.lor(m).lnot() == 0 {
    return (0x92800000 : UInt64)
      .lor(reg.to_uint64())
      .lor((value.lnot() << 5) & 0x1fffe0)
      .to_uint()
  }
  if value.lor(m << 16).lnot() == 0 {
    return (0x92a00000 : UInt64)
      .lor(reg.to_uint64())
      .lor((value.lnot() >> 11) & 0x1fffe0)
      .to_uint()
  }
  if value.lor(m << 32).lnot() == 0 {
    return (0x92c00000 : UInt64)
      .lor(reg.to_uint64())
      .lor((value.lnot() >> 27) & 0x1fffe0)
      .to_uint()
  }
  if value.lor(m << 48).lnot() == 0 {
    return (0x92e00000 : UInt64)
      .lor(reg.to_uint64())
      .lor((value.lnot() >> 43) & 0x1fffe0)
      .to_uint()
  }
  if value >> 32 == 0 {
    let e = arm64_encode_bimm64(value | (value << 32))
    if e >= 0 {
      return (0x320003e0 : UInt64)
        .lor(reg.to_uint64())
        .lor(e.to_uint64() << 10)
        .to_uint()
    }
  }
  let e64 = arm64_encode_bimm64(value)
  if e64 >= 0 {
    return (0xb20003e0 : UInt64)
      .lor(reg.to_uint64())
      .lor(e64.to_uint64() << 10)
      .to_uint()
  }
  0
}

///|
pub fn arm64_movimm(
  emitter : Arm64Emitter,
  reg : UInt32,
  value : UInt64,
) -> Unit {
  let insn = arm64_movi(reg, value)
  if insn != 0 {
    emit32(emitter, insn)
    return
  }
  let mut z = 0
  let mut m = 0
  let mut mov1 : UInt64 = 0xd2800000
  let mut x1 = value
  let mask16 : UInt64 = 0xffff
  let mut i = 0
  while i < 64 {
    if ((value >> i) & mask16) == 0 {
      z = z + 1
    }
    if ((value.lnot() >> i) & mask16) == 0 {
      m = m + 1
    }
    i = i + 16
  }
  if m > z {
    x1 = value.lnot()
    mov1 = 0x92800000
  }
  i = 0
  while i < 64 {
    let chunk = (x1 >> i) & mask16
    if chunk != 0 {
      let insn1 = mov1
        .lor(reg.to_uint64())
        .lor(chunk << 5)
        .lor(i.to_uint64() << 17)
        .to_uint()
      emit32(emitter, insn1)
      i = i + 16
      break
    }
    i = i + 16
  }
  while i < 64 {
    if ((x1 >> i) & mask16) != 0 {
      let chunk = (value >> i) & mask16
      let insn1 = (0xf2800000 : UInt64)
        .lor(reg.to_uint64())
        .lor(chunk << 5)
        .lor(i.to_uint64() << 17)
        .to_uint()
      emit32(emitter, insn1)
    }
    i = i + 16
  }
}

///|
pub fn gsym_addr(emitter : Arm64Emitter, t_ : Int32, a_ : Int32) -> Unit raise {
  let mut t = t_
  let a = a_
  while t != 0 {
    let idx = t >> 2
    let next = emitter.code[idx].reinterpret_as_int()
    let diff = a - t
    if diff + 0x8000000 >= 0x10000000 {
      fail("branch out of range")
    }
    let insn : UInt32 = if diff == 4 {
      0xd503201f
    } else {
      let imm = (diff >> 2) & 0x3ffffff
      (0x14000000 : Int32).lor(imm).reinterpret_as_uint()
    }
    emitter.code[idx] = insn
    t = next
  }
}

///|
pub fn gsym(emitter : Arm64Emitter, t : Int32) -> Unit raise {
  if t != 0 {
    gsym_addr(emitter, t, emitter_pc(emitter))
  }
}

///|
pub fn gind(emitter : Arm64Emitter) -> Int32 {
  emitter_pc(emitter)
}

///|
pub fn gjmp(emitter : Arm64Emitter, t : Int32) -> Int32 {
  let r = emitter_pc(emitter)
  emit32(emitter, t.reinterpret_as_uint())
  r
}

///|
pub fn gjmp_addr(emitter : Arm64Emitter, a : Int32) -> Unit raise {
  let ind = emitter_pc(emitter)
  if a - ind + 0x8000000 >= 0x10000000 {
    fail("branch out of range")
  }
  let imm = ((a - ind) >> 2) & 0x3ffffff
  let insn = (0x14000000 : Int32).lor(imm).reinterpret_as_uint()
  emit32(emitter, insn)
}

///|
pub fn gjmp_append(emitter : Arm64Emitter, n : Int32, t : Int32) -> Int32 {
  let mut t1 = t
  let mut n1 = n
  if n1 != 0 {
    while true {
      let idx = n1 >> 2
      let next = emitter.code[idx].reinterpret_as_int()
      if next == 0 {
        emitter.code[idx] = t1.reinterpret_as_uint()
        break
      }
      n1 = next
    }
    t1 = n
  }
  t1
}

///|
pub fn gen_fill_nops(emitter : Arm64Emitter, bytes : Int32) -> Unit raise {
  let mut remaining = bytes
  if (remaining & 3) != 0 {
    fail("alignment of code section not multiple of 4")
  }
  while remaining > 0 {
    emit32(emitter, 0xd503201f)
    remaining = remaining - 4
  }
}

///|
pub fn arm64_vset_VT_CMP(op : Int32) -> Unit {
  if op >= TOK_ULT && op <= TOK_GT {
    let idx = vtop_index()
    vstack[idx].cmp_r = vstack[idx].r
    vset_VT_CMP(0x80)
  }
}

///|
pub fn arm64_load_cmp(
  emitter : Arm64Emitter,
  r : Int32,
  sv_index : Int32,
) -> Unit raise {
  vstack[sv_index].r = vstack[sv_index].cmp_r
  if (vstack[sv_index].c_i & 1L) != 0 {
    vpushi(1)
    arm64_gen_opil(emitter, TOK_XOR, 0)
  }
  if r != vstack[sv_index].r {
    load(emitter, r, sv_index)
    vstack[sv_index].r = r
  }
}

///|
pub fn gjmp_cond(emitter : Arm64Emitter, op : Int32, t : Int32) -> Int32 raise {
  let idx = vtop_index()
  let bt = vstack[idx].type_t & VT_BTYPE
  let inv = op & 1
  vstack[idx].r = vstack[idx].cmp_r
  if bt == VT_LDOUBLE {
    let f = fltr(gv(emitter, RC_FLOAT))
    let a0 = get_reg(RC_INT)
    vpushi(0)
    vstack[vtop_index()].r = a0
    let b0 = get_reg(RC_INT)
    let a = intr(a0)
    let b = intr(b0)
    emit32(
      emitter,
      (0x4e083c00 : Int32).lor(a).lor(f << 5).reinterpret_as_uint(),
    )
    emit32(
      emitter,
      (0x4e183c00 : Int32).lor(b).lor(f << 5).reinterpret_as_uint(),
    )
    emit32(
      emitter,
      (0xaa000400 : Int32).lor(a).lor(a << 5).lor(b << 16).reinterpret_as_uint(),
    )
    let inv_bit = if inv != 0 { 1 } else { 0 }
    emit32(
      emitter,
      (0xb4000040 : Int32).lor(a).lor(inv_bit << 24).reinterpret_as_uint(),
    )
    vpop()
  } else if bt == VT_FLOAT || bt == VT_DOUBLE {
    let a = fltr(gv(emitter, RC_FLOAT))
    let is_double = if bt != VT_FLOAT { 1 } else { 0 }
    emit32(
      emitter,
      (0x1e202008 : Int32)
      .lor(a << 5)
      .lor(is_double << 22)
      .reinterpret_as_uint(),
    )
    let inv_bit = if inv != 0 { 1 } else { 0 }
    emit32(emitter, (0x54000040 : Int32).lor(inv_bit).reinterpret_as_uint())
  } else {
    let ll = bt == VT_PTR || bt == VT_LLONG
    let a = intr(gv(emitter, RC_INT))
    let inv_bit = if inv != 0 { 1 } else { 0 }
    let ll_bit = if ll { 1 } else { 0 }
    emit32(
      emitter,
      (0x34000040 : Int32)
      .lor(a)
      .lor(inv_bit << 24)
      .lor(ll_bit << 31)
      .reinterpret_as_uint(),
    )
  }
  gjmp(emitter, t)
}

///|
pub fn arm64_iconst(sv_index : Int32) -> UInt64? {
  let sv = vstack[sv_index]
  let mask = VT_VALMASK | VT_LVAL | VT_SYM
  if (sv.r & mask) != VT_CONST {
    return None
  }
  let t = sv.type_t
  let bt = t & VT_BTYPE
  if bt == VT_LLONG || bt == VT_PTR {
    return Some(sv.c_i.reinterpret_as_uint64())
  }
  let low = sv.c_i.reinterpret_as_uint64() & (0xffffffff : UInt64)
  if (t & VT_UNSIGNED) != 0 {
    return Some(low)
  }
  let sign_mask : UInt32 = 0x80000000
  let low_u32 = low.to_uint()
  if (low_u32 & sign_mask) != 0 {
    let upper : UInt64 = (0xffffffff : UInt64) << 32
    return Some(low | upper)
  }
  Some(low)
}

///|
pub fn arm64_type_size(t : Int32) -> Int32 {
  match t & VT_BTYPE {
    VT_BYTE => 0
    VT_SHORT => 1
    VT_INT => 2
    VT_LLONG => 3
    VT_PTR => 3
    VT_FUNC => 3
    VT_STRUCT => 3
    VT_FLOAT => 2
    VT_DOUBLE => 3
    VT_LDOUBLE => 4
    VT_BOOL => 0
    VT_VOID => 0
    _ => 0
  }
}

///|
pub fn arm64_gen_opic(
  emitter : Arm64Emitter,
  op : Int32,
  l : Int32,
  rev : Bool,
  val : UInt64,
  x : Int32,
  a : Int32,
) -> Bool {
  let mut op1 = op
  let mut val1 = val
  if op1 == TOK_SUB && !rev {
    val1 = (0 : UInt64) - val1
    op1 = TOK_ADD
  }
  if l == 0 {
    val1 = val1 & (0xffffffff : UInt64)
  }
  match op1 {
    TOK_ADD => {
      let s : UInt64 = if l != 0 { val1 >> 63 } else { val1 >> 31 }
      let s_bit : Int32 = if (s & 1) != 0 { 1 } else { 0 }
      if s_bit != 0 {
        val1 = (0 : UInt64) - val1
      }
      if l == 0 {
        val1 = val1 & (0xffffffff : UInt64)
      }
      if (val1 & (0xfff : UInt64).lnot()) == 0 {
        emit32(
          emitter,
          (0x11000000 : Int32)
          .lor(l << 31)
          .lor(s_bit << 30)
          .lor(x)
          .lor(a << 5)
          .lor(val1.to_int() << 10)
          .reinterpret_as_uint(),
        )
      } else if (val1 & (0xfff000 : UInt64).lnot()) == 0 {
        emit32(
          emitter,
          (0x11400000 : Int32)
          .lor(l << 31)
          .lor(s_bit << 30)
          .lor(x)
          .lor(a << 5)
          .lor((val1 >> 12).to_int() << 10)
          .reinterpret_as_uint(),
        )
      } else {
        arm64_movimm(emitter, (30 : UInt32), val1)
        emit32(
          emitter,
          (0x0b1e0000 : Int32)
          .lor(l << 31)
          .lor(s_bit << 30)
          .lor(x)
          .lor(a << 5)
          .reinterpret_as_uint(),
        )
      }
      true
    }
    TOK_SUB => {
      let minus_one : UInt64 = if l != 0 {
        (0 : UInt64).lnot()
      } else {
        (0xffffffff : UInt64)
      }
      if val1 == 0 {
        emit32(
          emitter,
          (0x4b0003e0 : Int32)
          .lor(l << 31)
          .lor(x)
          .lor(a << 16)
          .reinterpret_as_uint(),
        )
      } else if val1 == minus_one {
        emit32(
          emitter,
          (0x2a2003e0 : Int32)
          .lor(l << 31)
          .lor(x)
          .lor(a << 16)
          .reinterpret_as_uint(),
        )
      } else {
        arm64_movimm(emitter, (30 : UInt32), val1)
        emit32(
          emitter,
          (0x4b0003c0 : Int32)
          .lor(l << 31)
          .lor(x)
          .lor(a << 16)
          .reinterpret_as_uint(),
        )
      }
      true
    }
    TOK_XOR => {
      if val1 == (0 : UInt64).lnot() ||
        (l == 0 && val1 == (0xffffffff : UInt64)) {
        emit32(
          emitter,
          (0x2a2003e0 : Int32)
          .lor(l << 31)
          .lor(x)
          .lor(a << 16)
          .reinterpret_as_uint(),
        )
        return true
      }
      let e = arm64_encode_bimm64(
        if l != 0 {
          val1
        } else {
          val1 | (val1 << 32)
        },
      )
      if e < 0 {
        return false
      }
      emit32(
        emitter,
        (0x52000000 : Int32)
        .lor(l << 31)
        .lor(x)
        .lor(a << 5)
        .lor(e << 10)
        .reinterpret_as_uint(),
      )
      true
    }
    TOK_AND => {
      let e = arm64_encode_bimm64(
        if l != 0 {
          val1
        } else {
          val1 | (val1 << 32)
        },
      )
      if e < 0 {
        return false
      }
      emit32(
        emitter,
        (0x12000000 : Int32)
        .lor(l << 31)
        .lor(x)
        .lor(a << 5)
        .lor(e << 10)
        .reinterpret_as_uint(),
      )
      true
    }
    TOK_OR => {
      let e = arm64_encode_bimm64(
        if l != 0 {
          val1
        } else {
          val1 | (val1 << 32)
        },
      )
      if e < 0 {
        return false
      }
      emit32(
        emitter,
        (0x32000000 : Int32)
        .lor(l << 31)
        .lor(x)
        .lor(a << 5)
        .lor(e << 10)
        .reinterpret_as_uint(),
      )
      true
    }
    TOK_SAR | TOK_SHL | TOK_SHR => {
      let n : Int32 = 32 << l
      if rev {
        return false
      }
      let val2 : Int32 = (val1 & (n - 1).to_uint64()).to_int()
      if val2 == 0 {
        // Shift-by-zero is a no-op; preserve the destination register.
        let base : Int32 = if l != 0 { 0xaa0003e0 } else { 0x2a0003e0 }
        emit32(emitter, base.lor(x).lor(a << 16).reinterpret_as_uint())
        return true
      }
      if op1 == TOK_SHL {
        emit32(
          emitter,
          (0x53000000 : Int32)
          .lor(l << 31)
          .lor(l << 22)
          .lor(x)
          .lor(a << 5)
          .lor((n - val2) << 16)
          .lor((n - 1 - val2) << 10)
          .reinterpret_as_uint(),
        )
      } else {
        emit32(
          emitter,
          (0x13000000 : Int32)
          .lor((if op1 == TOK_SHR { 1 } else { 0 }) << 30)
          .lor(l << 31)
          .lor(l << 22)
          .lor(x)
          .lor(a << 5)
          .lor(val2 << 16)
          .lor((n - 1) << 10)
          .reinterpret_as_uint(),
        )
      }
      true
    }
    _ => false
  }
}

///|
pub fn arm64_spoff(emitter : Arm64Emitter, reg : UInt32, off : UInt64) -> Unit {
  let sub = off >> 63
  let mut off1 = off
  if sub != 0 {
    off1 = (0 : UInt64) - off
  }
  if off1 < (4096 : UInt64) {
    let insn = (0x910003e0 : UInt64)
      .lor(sub << 30)
      .lor(reg.to_uint64())
      .lor(off1 << 10)
      .to_uint()
    emit32(emitter, insn)
  } else {
    arm64_movimm(emitter, (30 : UInt32), off1)
    let insn = (0x8b3e63e0 : UInt64)
      .lor(sub << 30)
      .lor(reg.to_uint64())
      .to_uint()
    emit32(emitter, insn)
  }
}

///|
pub fn arm64_check_offset(invert : Bool, sz_ : Int32, off : UInt64) -> UInt64 {
  let sz = sz_
  let mask32 : UInt32 = (0xfff : UInt32) << sz
  let mask32_u64 = mask32.to_uint64()
  let mask32_not_u64 = mask32.lnot().to_uint64()
  let neg_off = (0 : UInt64) - off
  if (off & mask32_not_u64) == 0 ||
    off < (256 : UInt64) ||
    neg_off <= (256 : UInt64) {
    return if invert { off } else { 0 }
  } else if (off & mask32_u64) != 0 {
    return if invert { off & mask32_u64 } else { off & mask32_not_u64 }
  } else {
    let mask9 : UInt32 = 0x1ff
    let mask9_u64 = mask9.to_uint64()
    let mask9_not_u64 = mask9.lnot().to_uint64()
    if (off & mask9_u64) != 0 {
      return if invert { off & mask9_u64 } else { off & mask9_not_u64 }
    }
  }
  if invert {
    0
  } else {
    off
  }
}

///|
pub fn arm64_sym(
  emitter : Arm64Emitter,
  r : UInt32,
  sym : Sym,
  addend : UInt64,
) -> Unit {
  let ind0 = emitter_pc(emitter)
  greloca(emitter, sym, ind0, R_AARCH64_ADR_GOT_PAGE, 0)
  emit32(emitter, (0x90000000 : UInt64).lor(r.to_uint64()).to_uint())
  let ind1 = emitter_pc(emitter)
  greloca(emitter, sym, ind1, R_AARCH64_LD64_GOT_LO12_NC, 0)
  emit32(
    emitter,
    (0xf9400000 : UInt64).lor(r.to_uint64()).lor(r.to_uint64() << 5).to_uint(),
  )
  if addend != 0 {
    if (addend & (0xfff : UInt64)) != 0 {
      emit32(
        emitter,
        (0x91000000 : UInt64)
        .lor(r.to_uint64())
        .lor(r.to_uint64() << 5)
        .lor((addend & (0xfff : UInt64)) << 10)
        .to_uint(),
      )
    }
    if addend > (0xfff : UInt64) {
      if (addend & (0xfff000 : UInt64)) != 0 {
        emit32(
          emitter,
          (0x91400000 : UInt64)
          .lor(r.to_uint64())
          .lor(r.to_uint64() << 5)
          .lor(((addend >> 12) & (0xfff : UInt64)) << 10)
          .to_uint(),
        )
      }
      if addend > (0xffffff : UInt64) {
        let t : UInt32 = if r != (0 : UInt32) { 0 } else { 1 }
        emit32(emitter, (0xf81f0fe0 : UInt64).lor(t.to_uint64()).to_uint())
        arm64_movimm(emitter, t, addend & (0xffffff : UInt64).lnot())
        emit32(
          emitter,
          (0x8b000000 : UInt64)
          .lor(t.to_uint64() << 16)
          .lor(r.to_uint64() << 5)
          .lor(r.to_uint64())
          .to_uint(),
        )
        emit32(emitter, (0xf84107e0 : UInt64).lor(t.to_uint64()).to_uint())
      }
    }
  }
}

///|
pub fn arm64_ldrx(
  emitter : Arm64Emitter,
  sg : Bool,
  sz_ : Int32,
  dst : UInt32,
  bas : UInt32,
  off : UInt64,
) -> Unit {
  let sz = sz_
  if sg && sz == 2 {
    let mask32 : UInt32 = (0xfff : UInt32) << sz
    let mask32_not_u64 = mask32.lnot().to_uint64()
    if (off & mask32_not_u64) == 0 {
      let insn = (0xb9800000 : UInt64)
        .lor(dst.to_uint64())
        .lor(bas.to_uint64() << 5)
        .lor(off << (10 - sz))
        .to_uint()
      emit32(emitter, insn)
    } else if off < (256 : UInt64) || (0 : UInt64) - off <= (256 : UInt64) {
      let insn = (0xb8800000 : UInt64)
        .lor(dst.to_uint64())
        .lor(bas.to_uint64() << 5)
        .lor((off & (0x1ff : UInt64)) << 12)
        .to_uint()
      emit32(emitter, insn)
    } else {
      arm64_movimm(emitter, (30 : UInt32), off)
      let insn = (0xb8a06800 : UInt64)
        .lor(dst.to_uint64())
        .lor(bas.to_uint64() << 5)
        .lor((30 : UInt64) << 16)
        .to_uint()
      emit32(emitter, insn)
    }
    return
  }
  let sg1 = if sz >= 2 { false } else { sg }
  let sg_bit : UInt64 = if sg1 { 1 } else { 0 }
  let mask32 : UInt32 = (0xfff : UInt32) << sz
  let mask32_not_u64 = mask32.lnot().to_uint64()
  if (off & mask32_not_u64) == 0 {
    let insn = (0x39400000 : UInt64)
      .lor(dst.to_uint64())
      .lor(bas.to_uint64() << 5)
      .lor(off << (10 - sz))
      .lor(sg_bit << 23)
      .lor(sz.to_uint64() << 30)
      .to_uint()
    emit32(emitter, insn)
  } else if off < (256 : UInt64) || (0 : UInt64) - off <= (256 : UInt64) {
    let insn = (0x38400000 : UInt64)
      .lor(dst.to_uint64())
      .lor(bas.to_uint64() << 5)
      .lor((off & (0x1ff : UInt64)) << 12)
      .lor(sg_bit << 23)
      .lor(sz.to_uint64() << 30)
      .to_uint()
    emit32(emitter, insn)
  } else {
    arm64_movimm(emitter, (30 : UInt32), off)
    let sg_enc : UInt64 = if sg1 { 2 } else { 1 }
    let insn = (0x38206800 : UInt64)
      .lor(dst.to_uint64())
      .lor(bas.to_uint64() << 5)
      .lor((30 : UInt64) << 16)
      .lor(sg_enc << 22)
      .lor(sz.to_uint64() << 30)
      .to_uint()
    emit32(emitter, insn)
  }
}

///|
pub fn arm64_ldrv(
  emitter : Arm64Emitter,
  sz_ : Int32,
  dst : UInt32,
  bas : UInt32,
  off : UInt64,
) -> Unit {
  let sz = sz_
  let mask32 : UInt32 = (0xfff : UInt32) << sz
  let mask32_not_u64 = mask32.lnot().to_uint64()
  if (off & mask32_not_u64) == 0 {
    let insn = (0x3d400000 : UInt64)
      .lor(dst.to_uint64())
      .lor(bas.to_uint64() << 5)
      .lor(off << (10 - sz))
      .lor((sz & 4).to_uint64() << 21)
      .lor((sz & 3).to_uint64() << 30)
      .to_uint()
    emit32(emitter, insn)
  } else if off < (256 : UInt64) || (0 : UInt64) - off <= (256 : UInt64) {
    let insn = (0x3c400000 : UInt64)
      .lor(dst.to_uint64())
      .lor(bas.to_uint64() << 5)
      .lor((off & (0x1ff : UInt64)) << 12)
      .lor((sz & 4).to_uint64() << 21)
      .lor((sz & 3).to_uint64() << 30)
      .to_uint()
    emit32(emitter, insn)
  } else {
    arm64_movimm(emitter, (30 : UInt32), off)
    let insn = (0x3c606800 : UInt64)
      .lor(dst.to_uint64())
      .lor(bas.to_uint64() << 5)
      .lor((30 : UInt64) << 16)
      .lor(sz.to_uint64() << 30)
      .lor((sz & 4).to_uint64() << 21)
      .to_uint()
    emit32(emitter, insn)
  }
}

///|
pub fn arm64_ldrs(emitter : Arm64Emitter, reg : UInt32, size : Int32) -> Unit {
  match size {
    0 => ()
    1 => arm64_ldrx(emitter, false, 0, reg, reg, 0)
    2 => arm64_ldrx(emitter, false, 1, reg, reg, 0)
    3 => {
      arm64_ldrx(emitter, false, 2, reg, reg, 0)
      arm64_gen_opic(
        emitter,
        TOK_AND,
        0,
        false,
        (0x00ffffff : UInt64),
        reg.reinterpret_as_int(),
        reg.reinterpret_as_int(),
      )
      |> ignore
    }
    4 => arm64_ldrx(emitter, false, 2, reg, reg, 0)
    5 => {
      arm64_ldrx(emitter, false, 3, reg, reg, 0)
      let mask : UInt64 = ((1 : UInt64) << (5 * 8)) - 1
      arm64_gen_opic(
        emitter,
        TOK_AND,
        1,
        false,
        mask,
        reg.reinterpret_as_int(),
        reg.reinterpret_as_int(),
      )
      |> ignore
    }
    6 => {
      arm64_ldrx(emitter, false, 3, reg, reg, 0)
      let mask : UInt64 = ((1 : UInt64) << (6 * 8)) - 1
      arm64_gen_opic(
        emitter,
        TOK_AND,
        1,
        false,
        mask,
        reg.reinterpret_as_int(),
        reg.reinterpret_as_int(),
      )
      |> ignore
    }
    7 => {
      arm64_ldrx(emitter, false, 3, reg, reg, 0)
      let mask : UInt64 = ((1 : UInt64) << (7 * 8)) - 1
      arm64_gen_opic(
        emitter,
        TOK_AND,
        1,
        false,
        mask,
        reg.reinterpret_as_int(),
        reg.reinterpret_as_int(),
      )
      |> ignore
    }
    8 => arm64_ldrx(emitter, false, 3, reg, reg, 0)
    9 => {
      arm64_ldrx(emitter, false, 3, reg + 1, reg, 8)
      let mask : UInt64 = ((1 : UInt64) << (1 * 8)) - 1
      arm64_gen_opic(
        emitter,
        TOK_AND,
        1,
        false,
        mask,
        (reg + 1).reinterpret_as_int(),
        (reg + 1).reinterpret_as_int(),
      )
      |> ignore
      arm64_ldrx(emitter, false, 3, reg, reg, 0)
    }
    10 => {
      arm64_ldrx(emitter, false, 3, reg + 1, reg, 8)
      let mask : UInt64 = ((1 : UInt64) << (2 * 8)) - 1
      arm64_gen_opic(
        emitter,
        TOK_AND,
        1,
        false,
        mask,
        (reg + 1).reinterpret_as_int(),
        (reg + 1).reinterpret_as_int(),
      )
      |> ignore
      arm64_ldrx(emitter, false, 3, reg, reg, 0)
    }
    11 => {
      arm64_ldrx(emitter, false, 3, reg + 1, reg, 8)
      let mask : UInt64 = ((1 : UInt64) << (3 * 8)) - 1
      arm64_gen_opic(
        emitter,
        TOK_AND,
        1,
        false,
        mask,
        (reg + 1).reinterpret_as_int(),
        (reg + 1).reinterpret_as_int(),
      )
      |> ignore
      arm64_ldrx(emitter, false, 3, reg, reg, 0)
    }
    12 => {
      arm64_ldrx(emitter, false, 3, reg + 1, reg, 8)
      let mask : UInt64 = ((1 : UInt64) << (4 * 8)) - 1
      arm64_gen_opic(
        emitter,
        TOK_AND,
        1,
        false,
        mask,
        (reg + 1).reinterpret_as_int(),
        (reg + 1).reinterpret_as_int(),
      )
      |> ignore
      arm64_ldrx(emitter, false, 3, reg, reg, 0)
    }
    13 => {
      arm64_ldrx(emitter, false, 3, reg + 1, reg, 8)
      let mask : UInt64 = ((1 : UInt64) << (5 * 8)) - 1
      arm64_gen_opic(
        emitter,
        TOK_AND,
        1,
        false,
        mask,
        (reg + 1).reinterpret_as_int(),
        (reg + 1).reinterpret_as_int(),
      )
      |> ignore
      arm64_ldrx(emitter, false, 3, reg, reg, 0)
    }
    14 => {
      arm64_ldrx(emitter, false, 3, reg + 1, reg, 8)
      let mask : UInt64 = ((1 : UInt64) << (6 * 8)) - 1
      arm64_gen_opic(
        emitter,
        TOK_AND,
        1,
        false,
        mask,
        (reg + 1).reinterpret_as_int(),
        (reg + 1).reinterpret_as_int(),
      )
      |> ignore
      arm64_ldrx(emitter, false, 3, reg, reg, 0)
    }
    15 => {
      arm64_ldrx(emitter, false, 3, reg + 1, reg, 8)
      let mask : UInt64 = ((1 : UInt64) << (7 * 8)) - 1
      arm64_gen_opic(
        emitter,
        TOK_AND,
        1,
        false,
        mask,
        (reg + 1).reinterpret_as_int(),
        (reg + 1).reinterpret_as_int(),
      )
      |> ignore
      arm64_ldrx(emitter, false, 3, reg, reg, 0)
    }
    16 => {
      let insn = (0xa9400000 : UInt64)
        .lor(reg.to_uint64())
        .lor((reg + 1).to_uint64() << 10)
        .lor(reg.to_uint64() << 5)
        .to_uint()
      emit32(emitter, insn)
    }
    _ => ()
  }
}

///|
pub fn arm64_strx(
  emitter : Arm64Emitter,
  sz_ : Int32,
  dst : UInt32,
  bas : UInt32,
  off : UInt64,
) -> Unit {
  let sz = sz_
  let mask32 : UInt32 = (0xfff : UInt32) << sz
  let mask32_not_u64 = mask32.lnot().to_uint64()
  if (off & mask32_not_u64) == 0 {
    let insn = (0x39000000 : UInt64)
      .lor(dst.to_uint64())
      .lor(bas.to_uint64() << 5)
      .lor(off << (10 - sz))
      .lor(sz.to_uint64() << 30)
      .to_uint()
    emit32(emitter, insn)
  } else if off < (256 : UInt64) || (0 : UInt64) - off <= (256 : UInt64) {
    let insn = (0x38000000 : UInt64)
      .lor(dst.to_uint64())
      .lor(bas.to_uint64() << 5)
      .lor((off & (0x1ff : UInt64)) << 12)
      .lor(sz.to_uint64() << 30)
      .to_uint()
    emit32(emitter, insn)
  } else {
    arm64_movimm(emitter, (30 : UInt32), off)
    let insn = (0x38206800 : UInt64)
      .lor(dst.to_uint64())
      .lor(bas.to_uint64() << 5)
      .lor((30 : UInt64) << 16)
      .lor(sz.to_uint64() << 30)
      .to_uint()
    emit32(emitter, insn)
  }
}

///|
pub fn arm64_strv(
  emitter : Arm64Emitter,
  sz_ : Int32,
  dst : UInt32,
  bas : UInt32,
  off : UInt64,
) -> Unit {
  let sz = sz_
  let mask32 : UInt32 = (0xfff : UInt32) << sz
  let mask32_not_u64 = mask32.lnot().to_uint64()
  if (off & mask32_not_u64) == 0 {
    let insn = (0x3d000000 : UInt64)
      .lor(dst.to_uint64())
      .lor(bas.to_uint64() << 5)
      .lor(off << (10 - sz))
      .lor((sz & 4).to_uint64() << 21)
      .lor((sz & 3).to_uint64() << 30)
      .to_uint()
    emit32(emitter, insn)
  } else if off < (256 : UInt64) || (0 : UInt64) - off <= (256 : UInt64) {
    let insn = (0x3c000000 : UInt64)
      .lor(dst.to_uint64())
      .lor(bas.to_uint64() << 5)
      .lor((off & (0x1ff : UInt64)) << 12)
      .lor((sz & 4).to_uint64() << 21)
      .lor((sz & 3).to_uint64() << 30)
      .to_uint()
    emit32(emitter, insn)
  } else {
    arm64_movimm(emitter, (30 : UInt32), off)
    let insn = (0x3c206800 : UInt64)
      .lor(dst.to_uint64())
      .lor(bas.to_uint64() << 5)
      .lor((30 : UInt64) << 16)
      .lor(sz.to_uint64() << 30)
      .lor((sz & 4).to_uint64() << 21)
      .to_uint()
    emit32(emitter, insn)
  }
}
