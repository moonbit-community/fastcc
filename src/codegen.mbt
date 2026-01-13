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
fn simple_return_call(func : FuncDef) -> String? {
  match func.body {
    Stmt::Compound(stmts~, ..) =>
      if stmts.length() == 1 {
        match stmts[0] {
          Stmt::Return(value=Some(expr), ..) =>
            match expr {
              Expr::Call(callee=Expr::Ident(name~, ..), args~, ..) =>
                if args.length() == 0 {
                  Some(name)
                } else {
                  None
                }
              _ => None
            }
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
fn simple_return_ident(func : FuncDef) -> String? {
  match func.body {
    Stmt::Compound(stmts~, ..) =>
      if stmts.length() == 1 {
        match stmts[0] {
          Stmt::Return(value=Some(expr), ..) =>
            match expr {
              Expr::Ident(name~, ..) => Some(name)
              _ => None
            }
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
fn gen_arm64_call(emitter : Arm64Emitter, sym : Sym) -> Unit {
  let ind = emitter_pc(emitter)
  greloca(emitter, sym, ind, R_AARCH64_CALL26, 0)
  emit32(emitter, (0x94000000 : UInt))
}

///|
fn gen_arm64_load_global_int(emitter : Arm64Emitter, sym : Sym) -> Unit {
  let adrp_off = emitter_pc(emitter)
  greloca(emitter, sym, adrp_off, R_AARCH64_ADR_PREL_PG_HI21, 0)
  emit32(emitter, (0x90000000 : UInt))
  let add_off = emitter_pc(emitter)
  greloca(emitter, sym, add_off, R_AARCH64_LDST8_ABS_LO12_NC, 0)
  emit32(emitter, (0x91000000 : UInt))
  emit32(emitter, (0xb9400000 : UInt))
}

///|
fn const_u32_from_initializer(init : Initializer) -> UInt? {
  match init {
    Initializer::Expr(expr~, ..) =>
      match const_i64_from_expr(expr) {
        None => None
        Some(value) => Some((value.to_uint64() & 0xffff_ffff).to_uint())
      }
    _ => None
  }
}

///|
fn codegen_arm64_object_bytes(unit : TranslationUnit, bag : DiagBag) -> Bytes? {
  let mut main_def : FuncDef? = None
  let func_defs : Map[String, FuncDef] = {}
  let globals : Map[String, VarDecl] = {}
  for decl in unit.decls {
    match decl {
      Decl::FuncDef(func) =>
        if func.name == "main" {
          main_def = Some(func)
        } else {
          func_defs.set(func.name, func)
        }
      Decl::Var(var_decl) => globals.set(var_decl.name, var_decl)
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
      match
        (
          simple_return_const(func),
          simple_return_call(func),
          simple_return_ident(func),
        ) {
        (Some(value), _, _) => {
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
        (None, Some(name), _) => {
          let emitter = new_arm64_emitter()
          gen_arm64_prologue(emitter)
          gen_arm64_call(emitter, { id: 2 })
          gen_arm64_epilogue(emitter)
          let mut callee_offset : Int? = None
          match func_defs.get(name) {
            None => ()
            Some(def) =>
              match simple_return_const(def) {
                None => ()
                Some(value) => {
                  callee_offset = Some(emitter_pc(emitter))
                  gen_arm64_prologue(emitter)
                  arm64_movimm(emitter, 0, value.to_uint64())
                  gen_arm64_epilogue(emitter)
                }
              }
          }
          let text = section_from_emitter(".text", emitter)
          let symbols = [
            {
              id: 1,
              name: "_main",
              section: Some(".text"),
              value: 0,
              is_external: true,
            },
            {
              id: 2,
              name: "_\{name}",
              section: match callee_offset {
                None => None
                Some(_) => Some(".text")
              },
              value: match callee_offset {
                None => 0
                Some(v) => v
              },
              is_external: true,
            },
          ]
          Some(encode_macho_object([text], symbols))
        }
        (None, None, Some(name)) =>
          match globals.get(name) {
            None => {
              add_error(
                bag,
                func.loc,
                "codegen: only supports 'int main(){return <const>;}', 'int main(){return f();}', or 'int main(){return <global>;}' for now",
              )
              None
            }
            Some(var_decl) =>
              if var_decl.storage == StorageClass::Extern {
                add_error(
                  bag,
                  func.loc,
                  "codegen: only supports non-extern global for now",
                )
                None
              } else {
                let emitter = new_arm64_emitter()
                gen_arm64_prologue(emitter)
                gen_arm64_load_global_int(emitter, { id: 2 })
                gen_arm64_epilogue(emitter)
                let text = section_from_emitter(".text", emitter)
                match var_decl.init {
                  None => {
                    let bss : Section = {
                      name: ".bss",
                      data: [],
                      relocs: [],
                      align: 4,
                      size_bytes: 4,
                    }
                    let symbols = [
                      {
                        id: 1,
                        name: "_main",
                        section: Some(".text"),
                        value: 0,
                        is_external: true,
                      },
                      {
                        id: 2,
                        name: "_\{name}",
                        section: Some(".bss"),
                        value: 0,
                        is_external: true,
                      },
                    ]
                    Some(encode_macho_object([text, bss], symbols))
                  }
                  Some(init) =>
                    match const_u32_from_initializer(init) {
                      None => {
                        add_error(
                          bag,
                          func.loc,
                          "codegen: only supports constant int initializer for global for now",
                        )
                        None
                      }
                      Some(word) => {
                        let data : Section = {
                          name: ".data",
                          data: [word],
                          relocs: [],
                          align: 4,
                          size_bytes: 4,
                        }
                        let symbols = [
                          {
                            id: 1,
                            name: "_main",
                            section: Some(".text"),
                            value: 0,
                            is_external: true,
                          },
                          {
                            id: 2,
                            name: "_\{name}",
                            section: Some(".data"),
                            value: 0,
                            is_external: true,
                          },
                        ]
                        Some(encode_macho_object([text, data], symbols))
                      }
                    }
                }
              }
          }
        _ => {
          add_error(
            bag,
            func.loc,
            "codegen: only supports 'int main(){return <const>;}', 'int main(){return f();}', or 'int main(){return <global>;}' for now",
          )
          None
        }
      }
  }
}
