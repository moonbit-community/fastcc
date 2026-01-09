///|
enum CType {
  Void
  Int
  Pointer(CType)
  Array(elem~ : CType, size~ : Int?)
  Struct(name~ : String, fields~ : Array[Field]?)
  Union(name~ : String, fields~ : Array[Field]?)
  Enum(name~ : String, items~ : Array[EnumItem]?)
  Function(return_type~ : CType, params~ : Array[CType])
} derive(Show, Eq, ToJson)

///|
struct Field {
  name : String
  ty : CType
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
struct EnumItem {
  name : String
  value : Expr?
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
struct Param {
  name : String
  ty : CType
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
struct FuncDef {
  name : String
  return_type : CType
  params : Array[Param]
  body : Stmt
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
struct FuncDecl {
  name : String
  return_type : CType
  params : Array[Param]
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
struct VarDecl {
  name : String
  ty : CType
  init : Expr?
  loc : SrcLoc
} derive(Show, Eq, ToJson)

///|
enum Decl {
  FuncDef(FuncDef)
  FuncDecl(FuncDecl)
  Var(VarDecl)
  Typedef(name~ : String, ty~ : CType, loc~ : SrcLoc)
  TagDef(ty~ : CType, loc~ : SrcLoc)
} derive(Show, Eq, ToJson)

///|
struct TranslationUnit {
  decls : Array[Decl]
} derive(Show, Eq, ToJson)

///|
enum UnaryOp {
  Plus
  Minus
  Not
  BitNot
  Addr
  Deref
  PreInc
  PreDec
  PostInc
  PostDec
} derive(Show, Eq, ToJson)

///|
enum BinaryOp {
  Assign
  Comma
  Add
  Sub
  Mul
  Div
  Mod
  Shl
  Shr
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
  BitAnd
  BitXor
  BitOr
  LogAnd
  LogOr
} derive(Show, Eq, ToJson)

///|
enum Expr {
  IntLit(value~ : String, loc~ : SrcLoc)
  Ident(name~ : String, loc~ : SrcLoc)
  Unary(op~ : UnaryOp, expr~ : Expr, loc~ : SrcLoc)
  Cast(ty~ : CType, expr~ : Expr, loc~ : SrcLoc)
  SizeofExpr(expr~ : Expr, loc~ : SrcLoc)
  SizeofType(ty~ : CType, loc~ : SrcLoc)
  Binary(op~ : BinaryOp, left~ : Expr, right~ : Expr, loc~ : SrcLoc)
  Conditional(cond~ : Expr, then_expr~ : Expr, else_expr~ : Expr, loc~ : SrcLoc)
  Call(callee~ : Expr, args~ : Array[Expr], loc~ : SrcLoc)
  Index(base~ : Expr, index~ : Expr, loc~ : SrcLoc)
  Member(base~ : Expr, name~ : String, is_arrow~ : Bool, loc~ : SrcLoc)
} derive(Show, Eq, ToJson)

///|
enum Stmt {
  Compound(stmts~ : Array[Stmt], loc~ : SrcLoc)
  If(cond~ : Expr, then_branch~ : Stmt, else_branch~ : Stmt?, loc~ : SrcLoc)
  While(cond~ : Expr, body~ : Stmt, loc~ : SrcLoc)
  DoWhile(cond~ : Expr, body~ : Stmt, loc~ : SrcLoc)
  For(init~ : Stmt?, cond~ : Expr?, step~ : Expr?, body~ : Stmt, loc~ : SrcLoc)
  Switch(cond~ : Expr, body~ : Stmt, loc~ : SrcLoc)
  Case(expr~ : Expr, end_expr~ : Expr?, body~ : Stmt, loc~ : SrcLoc)
  Default(body~ : Stmt, loc~ : SrcLoc)
  Label(name~ : String, body~ : Stmt, loc~ : SrcLoc)
  Goto(name~ : String, loc~ : SrcLoc)
  Break(loc~ : SrcLoc)
  Continue(loc~ : SrcLoc)
  Return(value~ : Expr?, loc~ : SrcLoc)
  ExprStmt(expr~ : Expr, loc~ : SrcLoc)
  DeclStmt(decls~ : Array[VarDecl], loc~ : SrcLoc)
  TagDef(ty~ : CType, loc~ : SrcLoc)
  Empty(loc~ : SrcLoc)
} derive(Show, Eq, ToJson)
