///|
const VT_BTYPE : Int = 0x000f

///|
const VT_VOID : Int = 0

///|
const VT_BYTE : Int = 1

///|
const VT_SHORT : Int = 2

///|
const VT_INT : Int = 3

///|
const VT_LLONG : Int = 4

///|
const VT_PTR : Int = 5

///|
const VT_FUNC : Int = 6

///|
const VT_STRUCT : Int = 7

///|
const VT_FLOAT : Int = 8

///|
const VT_DOUBLE : Int = 9

///|
const VT_LDOUBLE : Int = 10

///|
const VT_BOOL : Int = 11

///|
const VT_UNSIGNED : Int = 0x0010

///|
const VT_CONST : Int = 0x0030

///|
const VT_LLOCAL : Int = 0x0031

///|
const VT_LOCAL : Int = 0x0032

///|
const VT_CMP : Int = 0x0033

///|
const VT_JMP : Int = 0x0034

///|
const VT_JMPI : Int = 0x0035

///|
const VT_VALMASK : Int = 0x003f

///|
const VT_LVAL : Int = 0x0100

///|
const VT_SYM : Int = 0x0200

///|
const TOK_LAND : Int = 0x90

///|
const TOK_LOR : Int = 0x91

///|
const TOK_ULT : Int = 0x92

///|
const TOK_UGE : Int = 0x93

///|
const TOK_EQ : Int = 0x94

///|
const TOK_NE : Int = 0x95

///|
const TOK_ULE : Int = 0x96

///|
const TOK_UGT : Int = 0x97

///|
const TOK_LT : Int = 0x9c

///|
const TOK_GE : Int = 0x9d

///|
const TOK_LE : Int = 0x9e

///|
const TOK_GT : Int = 0x9f

///|
const RC_INT : Int = 1 << 0

///|
const RC_FLOAT : Int = 1 << 1

///|
struct SValue {
  type_t : Int
  mut r : Int
  mut r2 : Int
  mut jtrue : Int
  mut jfalse : Int
  c_i : Int64
  mut cmp_op : Int
  mut cmp_r : Int
}

///|
let vstack : Array[SValue] = []

///|
fn vtop_index() -> Int {
  vstack.length() - 1
}

///|
fn vpushi(value : Int) -> Unit {
  vstack.push({
    type_t: VT_INT,
    r: VT_CONST,
    r2: VT_CONST,
    jtrue: 0,
    jfalse: 0,
    c_i: value.to_int64(),
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
fn vset_VT_CMP(op : Int) -> Unit {
  let idx = vtop_index()
  if idx >= 0 {
    vstack[idx].r = VT_CMP
    vstack[idx].cmp_op = op
    vstack[idx].jfalse = 0
    vstack[idx].jtrue = 0
  }
}

///|
fn gv(rc : Int) -> Int raise {
  fail("gv unimplemented")
}

///|
fn get_reg(rc : Int) -> Int raise {
  fail("get_reg unimplemented")
}

///|
fn arm64_gen_opil(emitter : Arm64Emitter, op : Char, l : Int) -> Unit raise {
  fail("arm64_gen_opil unimplemented")
}

///|
fn load(emitter : Arm64Emitter, r : Int, sv_index : Int) -> Unit raise {
  fail("load unimplemented")
}
