///|
enum CType {
  Void
  Int
  Pointer(CType)
  Function(return_type~ : CType, params~ : Array[CType])
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
} derive(Show, Eq, ToJson)

///|
enum BinaryOp {
  Assign
  Add
  Sub
  Mul
  Div
  Mod
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
} derive(Show, Eq, ToJson)

///|
enum Expr {
  IntLit(value~ : String, loc~ : SrcLoc)
  Ident(name~ : String, loc~ : SrcLoc)
  Unary(op~ : UnaryOp, expr~ : Expr, loc~ : SrcLoc)
  Binary(op~ : BinaryOp, left~ : Expr, right~ : Expr, loc~ : SrcLoc)
  Call(callee~ : Expr, args~ : Array[Expr], loc~ : SrcLoc)
} derive(Show, Eq, ToJson)

///|
enum Stmt {
  Compound(stmts~ : Array[Stmt], loc~ : SrcLoc)
  Return(value~ : Expr?, loc~ : SrcLoc)
  ExprStmt(expr~ : Expr, loc~ : SrcLoc)
  DeclStmt(decl~ : VarDecl, loc~ : SrcLoc)
  Empty(loc~ : SrcLoc)
} derive(Show, Eq, ToJson)
