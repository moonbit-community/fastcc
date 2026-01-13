///|
fn parse_int64_literal(text : String) -> Int64? {
  let value = try @strconv.parse_int(text, base=0) catch {
    _ => None
  } noraise {
    v => Some(v.to_int64())
  }
  value
}

///|
fn const_i64_from_expr(expr : Expr) -> Int64? {
  match expr {
    Expr::IntLit(value~, ..) => parse_int64_literal(value)
    Expr::Unary(op=UnaryOp::Plus, expr=inner, ..) => const_i64_from_expr(inner)
    Expr::Unary(op=UnaryOp::Minus, expr=inner, ..) =>
      match const_i64_from_expr(inner) {
        None => None
        Some(v) => Some(-v)
      }
    _ => None
  }
}

///|
fn simple_return_const(func : FuncDef) -> Int64? {
  match func.body {
    Stmt::Compound(stmts~, ..) =>
      if stmts.length() == 1 {
        match stmts[0] {
          Stmt::Return(value=Some(expr), ..) => const_i64_from_expr(expr)
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
fn gen_arm64_prologue(emitter : Arm64Emitter) -> Unit {
  emit32(emitter, (0xa9bf7bfd : UInt))
  emit32(emitter, (0x910003fd : UInt))
}

///|
fn gen_arm64_epilogue(emitter : Arm64Emitter) -> Unit {
  emit32(emitter, (0xa8c17bfd : UInt))
  emit32(emitter, (0xd65f03c0 : UInt))
}

///|
fn codegen_arm64_object_bytes(unit : TranslationUnit, bag : DiagBag) -> Bytes? {
  let mut main_def : FuncDef? = None
  for decl in unit.decls {
    match decl {
      Decl::FuncDef(func) => if func.name == "main" { main_def = Some(func) }
      _ => ()
    }
  }
  match main_def {
    None => {
      add_error(
        bag,
        dummy_loc(0),
        "codegen: missing function definition 'main'",
      )
      None
    }
    Some(func) =>
      match simple_return_const(func) {
        None => {
          add_error(
            bag,
            func.loc,
            "codegen: only supports 'int main(){return <const>;}' for now",
          )
          None
        }
        Some(value) => {
          let emitter = new_arm64_emitter()
          gen_arm64_prologue(emitter)
          arm64_movimm(emitter, 0, value.to_uint64())
          gen_arm64_epilogue(emitter)
          let text = section_from_emitter(".text", emitter)
          let symbols = [
            {
              id: 1,
              name: "_main",
              section: Some(".text"),
              value: 0,
              is_external: true,
            },
          ]
          Some(encode_macho_object([text], symbols))
        }
      }
  }
}
