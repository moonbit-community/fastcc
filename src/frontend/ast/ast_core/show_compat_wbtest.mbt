///|
test "legacy AST Show compatibility" {
  assert_eq(
    Show::to_string(TypeQual::{
      is_const: true,
      is_volatile: true,
      is_restrict: true,
      is_atomic: true,
    }),
    "{is_const: true, is_volatile: true, is_restrict: true, is_atomic: true}",
  )
  assert_eq(Show::to_string(AlignSpec::Default), "Default")
  assert_eq(
    Show::to_string(
      AlignSpec::Expr(
        expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
      ),
    ),
    "Expr(expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}))",
  )
  assert_eq(Show::to_string(Visibility::Default), "Default")
  assert_eq(Show::to_string(Visibility::Hidden), "Hidden")
  assert_eq(Show::to_string(Visibility::Internal), "Internal")
  assert_eq(Show::to_string(Visibility::Protected), "Protected")
  assert_eq(Show::to_string(CallConv::Default), "Default")
  assert_eq(Show::to_string(CallConv::Cdecl), "Cdecl")
  assert_eq(Show::to_string(CallConv::Stdcall), "Stdcall")
  assert_eq(Show::to_string(CallConv::Fastcall), "Fastcall")
  assert_eq(Show::to_string(CallConv::Thiscall), "Thiscall")
  assert_eq(Show::to_string(CallConv::Regparm(count=7)), "Regparm(count=7)")
  assert_eq(
    Show::to_string(Attributes::{
      aligned: None,
      packed: true,
      ms_struct: true,
      transparent_union: true,
      weak: true,
      visibility: None,
      section: None,
      alias_name: None,
      asm_label: None,
      cleanup: None,
      noreturn: true,
      constructor_attr: true,
      destructor: true,
      always_inline: true,
      call_conv: None,
      dll_import: true,
      dll_export: true,
      nodecorate: true,
      nodebug: true,
    }),
    "{aligned: None, packed: true, ms_struct: true, transparent_union: true, weak: true, visibility: None, section: None, alias_name: None, asm_label: None, cleanup: None, noreturn: true, constructor_attr: true, destructor: true, always_inline: true, call_conv: None, dll_import: true, dll_export: true, nodecorate: true, nodebug: true}",
  )
  assert_eq(Show::to_string(CIntKind::Char), "Char")
  assert_eq(Show::to_string(CIntKind::Short), "Short")
  assert_eq(Show::to_string(CIntKind::Int), "Int")
  assert_eq(Show::to_string(CIntKind::Long), "Long")
  assert_eq(Show::to_string(CIntKind::LongLong), "LongLong")
  assert_eq(Show::to_string(CFloatKind::Float), "Float")
  assert_eq(Show::to_string(CFloatKind::Double), "Double")
  assert_eq(Show::to_string(CFloatKind::LongDouble), "LongDouble")
  assert_eq(Show::to_string(StorageClass::Default), "Default")
  assert_eq(Show::to_string(StorageClass::Extern), "Extern")
  assert_eq(Show::to_string(StorageClass::Static), "Static")
  assert_eq(Show::to_string(StorageClass::Auto), "Auto")
  assert_eq(Show::to_string(StorageClass::Register), "Register")
  assert_eq(Show::to_string(CType::Void), "Void")
  assert_eq(Show::to_string(CType::Bool), "Bool")
  assert_eq(
    Show::to_string(CType::Int(kind=CIntKind::Char, unsigned=true)),
    "Int(kind=Char, unsigned=true)",
  )
  assert_eq(
    Show::to_string(CType::Float(kind=CFloatKind::Float)),
    "Float(kind=Float)",
  )
  assert_eq(Show::to_string(CType::Pointer(CType::Void)), "Pointer(Void)")
  assert_eq(
    Show::to_string(CType::Array(elem=CType::Void, size=None, size_expr=None)),
    "Array(elem=Void, size=None, size_expr=None)",
  )
  assert_eq(
    Show::to_string(
      CType::Struct(name="raw\"text", id=7, fields=None, attrs=Attributes::{
        aligned: None,
        packed: true,
        ms_struct: true,
        transparent_union: true,
        weak: true,
        visibility: None,
        section: None,
        alias_name: None,
        asm_label: None,
        cleanup: None,
        noreturn: true,
        constructor_attr: true,
        destructor: true,
        always_inline: true,
        call_conv: None,
        dll_import: true,
        dll_export: true,
        nodecorate: true,
        nodebug: true,
      }),
    ),
    "Struct(name=raw\"text, id=7, fields=None, attrs={aligned: None, packed: true, ms_struct: true, transparent_union: true, weak: true, visibility: None, section: None, alias_name: None, asm_label: None, cleanup: None, noreturn: true, constructor_attr: true, destructor: true, always_inline: true, call_conv: None, dll_import: true, dll_export: true, nodecorate: true, nodebug: true})",
  )
  assert_eq(
    Show::to_string(
      CType::Union(name="raw\"text", id=7, fields=None, attrs=Attributes::{
        aligned: None,
        packed: true,
        ms_struct: true,
        transparent_union: true,
        weak: true,
        visibility: None,
        section: None,
        alias_name: None,
        asm_label: None,
        cleanup: None,
        noreturn: true,
        constructor_attr: true,
        destructor: true,
        always_inline: true,
        call_conv: None,
        dll_import: true,
        dll_export: true,
        nodecorate: true,
        nodebug: true,
      }),
    ),
    "Union(name=raw\"text, id=7, fields=None, attrs={aligned: None, packed: true, ms_struct: true, transparent_union: true, weak: true, visibility: None, section: None, alias_name: None, asm_label: None, cleanup: None, noreturn: true, constructor_attr: true, destructor: true, always_inline: true, call_conv: None, dll_import: true, dll_export: true, nodecorate: true, nodebug: true})",
  )
  assert_eq(
    Show::to_string(CType::Enum(name="raw\"text", id=7, items=None)),
    "Enum(name=raw\"text, id=7, items=None)",
  )
  assert_eq(
    Show::to_string(
      CType::TypeofExpr(
        expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
      ),
    ),
    "TypeofExpr(expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}))",
  )
  assert_eq(
    Show::to_string(
      CType::Function(
        return_type=CType::Void,
        params=[],
        varargs=true,
        is_old_style=true,
        call_conv=CallConv::Default,
      ),
    ),
    "Function(return_type=Void, params=[], varargs=true, is_old_style=true, call_conv=Default)",
  )
  assert_eq(
    Show::to_string(
      CType::Attributed(
        attrs=Attributes::{
          aligned: None,
          packed: true,
          ms_struct: true,
          transparent_union: true,
          weak: true,
          visibility: None,
          section: None,
          alias_name: None,
          asm_label: None,
          cleanup: None,
          noreturn: true,
          constructor_attr: true,
          destructor: true,
          always_inline: true,
          call_conv: None,
          dll_import: true,
          dll_export: true,
          nodecorate: true,
          nodebug: true,
        },
        base=CType::Void,
      ),
    ),
    "Attributed(attrs={aligned: None, packed: true, ms_struct: true, transparent_union: true, weak: true, visibility: None, section: None, alias_name: None, asm_label: None, cleanup: None, noreturn: true, constructor_attr: true, destructor: true, always_inline: true, call_conv: None, dll_import: true, dll_export: true, nodecorate: true, nodebug: true}, base=Void)",
  )
  assert_eq(
    Show::to_string(
      CType::Qualified(
        qual=TypeQual::{
          is_const: true,
          is_volatile: true,
          is_restrict: true,
          is_atomic: true,
        },
        base=CType::Void,
      ),
    ),
    "Qualified(qual={is_const: true, is_volatile: true, is_restrict: true, is_atomic: true}, base=Void)",
  )
  assert_eq(
    Show::to_string(Field::{
      name: "raw\"text",
      id: 7,
      ty: CType::Void,
      bit_width: None,
      attrs: Attributes::{
        aligned: None,
        packed: true,
        ms_struct: true,
        transparent_union: true,
        weak: true,
        visibility: None,
        section: None,
        alias_name: None,
        asm_label: None,
        cleanup: None,
        noreturn: true,
        constructor_attr: true,
        destructor: true,
        always_inline: true,
        call_conv: None,
        dll_import: true,
        dll_export: true,
        nodecorate: true,
        nodebug: true,
      },
      loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
    }),
    "{name: raw\"text, id: 7, ty: Void, bit_width: None, attrs: {aligned: None, packed: true, ms_struct: true, transparent_union: true, weak: true, visibility: None, section: None, alias_name: None, asm_label: None, cleanup: None, noreturn: true, constructor_attr: true, destructor: true, always_inline: true, call_conv: None, dll_import: true, dll_export: true, nodecorate: true, nodebug: true}, loc: {file_id: 1, line: 2, col: 3, offset: 4}}",
  )
  assert_eq(
    Show::to_string(StaticAssert::{
      expr: Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
      message: None,
      loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
    }),
    "{expr: IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), message: None, loc: {file_id: 1, line: 2, col: 3, offset: 4}}",
  )
  assert_eq(
    Show::to_string(
      RecordItem::Field(Field::{
        name: "raw\"text",
        id: 7,
        ty: CType::Void,
        bit_width: None,
        attrs: Attributes::{
          aligned: None,
          packed: true,
          ms_struct: true,
          transparent_union: true,
          weak: true,
          visibility: None,
          section: None,
          alias_name: None,
          asm_label: None,
          cleanup: None,
          noreturn: true,
          constructor_attr: true,
          destructor: true,
          always_inline: true,
          call_conv: None,
          dll_import: true,
          dll_export: true,
          nodecorate: true,
          nodebug: true,
        },
        loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      }),
    ),
    "Field({name: raw\"text, id: 7, ty: Void, bit_width: None, attrs: {aligned: None, packed: true, ms_struct: true, transparent_union: true, weak: true, visibility: None, section: None, alias_name: None, asm_label: None, cleanup: None, noreturn: true, constructor_attr: true, destructor: true, always_inline: true, call_conv: None, dll_import: true, dll_export: true, nodecorate: true, nodebug: true}, loc: {file_id: 1, line: 2, col: 3, offset: 4}})",
  )
  assert_eq(
    Show::to_string(
      RecordItem::StaticAssert(StaticAssert::{
        expr: Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        message: None,
        loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      }),
    ),
    "StaticAssert({expr: IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), message: None, loc: {file_id: 1, line: 2, col: 3, offset: 4}})",
  )
  assert_eq(
    Show::to_string(EnumItem::{
      name: "raw\"text",
      id: 7,
      value: None,
      loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
    }),
    "{name: raw\"text, id: 7, value: None, loc: {file_id: 1, line: 2, col: 3, offset: 4}}",
  )
  assert_eq(
    Show::to_string(Param::{
      name: "raw\"text",
      id: 7,
      ty: CType::Void,
      loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
    }),
    "{name: raw\"text, id: 7, ty: Void, loc: {file_id: 1, line: 2, col: 3, offset: 4}}",
  )
  assert_eq(
    Show::to_string(FuncDef::{
      name: "raw\"text",
      id: 7,
      return_type: CType::Void,
      params: [],
      varargs: true,
      is_old_style: true,
      storage: StorageClass::Default,
      is_inline: true,
      attrs: Attributes::{
        aligned: None,
        packed: true,
        ms_struct: true,
        transparent_union: true,
        weak: true,
        visibility: None,
        section: None,
        alias_name: None,
        asm_label: None,
        cleanup: None,
        noreturn: true,
        constructor_attr: true,
        destructor: true,
        always_inline: true,
        call_conv: None,
        dll_import: true,
        dll_export: true,
        nodecorate: true,
        nodebug: true,
      },
      body: Stmt::Compound(stmts=[], loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
      loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
    }),
    "{name: raw\"text, id: 7, return_type: Void, params: [], varargs: true, is_old_style: true, storage: Default, is_inline: true, attrs: {aligned: None, packed: true, ms_struct: true, transparent_union: true, weak: true, visibility: None, section: None, alias_name: None, asm_label: None, cleanup: None, noreturn: true, constructor_attr: true, destructor: true, always_inline: true, call_conv: None, dll_import: true, dll_export: true, nodecorate: true, nodebug: true}, body: Compound(stmts=[], loc={file_id: 1, line: 2, col: 3, offset: 4}), loc: {file_id: 1, line: 2, col: 3, offset: 4}}",
  )
  assert_eq(
    Show::to_string(FuncDecl::{
      name: "raw\"text",
      id: 7,
      return_type: CType::Void,
      params: [],
      varargs: true,
      is_old_style: true,
      storage: StorageClass::Default,
      is_inline: true,
      attrs: Attributes::{
        aligned: None,
        packed: true,
        ms_struct: true,
        transparent_union: true,
        weak: true,
        visibility: None,
        section: None,
        alias_name: None,
        asm_label: None,
        cleanup: None,
        noreturn: true,
        constructor_attr: true,
        destructor: true,
        always_inline: true,
        call_conv: None,
        dll_import: true,
        dll_export: true,
        nodecorate: true,
        nodebug: true,
      },
      loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
    }),
    "{name: raw\"text, id: 7, return_type: Void, params: [], varargs: true, is_old_style: true, storage: Default, is_inline: true, attrs: {aligned: None, packed: true, ms_struct: true, transparent_union: true, weak: true, visibility: None, section: None, alias_name: None, asm_label: None, cleanup: None, noreturn: true, constructor_attr: true, destructor: true, always_inline: true, call_conv: None, dll_import: true, dll_export: true, nodecorate: true, nodebug: true}, loc: {file_id: 1, line: 2, col: 3, offset: 4}}",
  )
  assert_eq(
    Show::to_string(VarDecl::{
      name: "raw\"text",
      id: 7,
      ty: CType::Void,
      init: None,
      storage: StorageClass::Default,
      attrs: Attributes::{
        aligned: None,
        packed: true,
        ms_struct: true,
        transparent_union: true,
        weak: true,
        visibility: None,
        section: None,
        alias_name: None,
        asm_label: None,
        cleanup: None,
        noreturn: true,
        constructor_attr: true,
        destructor: true,
        always_inline: true,
        call_conv: None,
        dll_import: true,
        dll_export: true,
        nodecorate: true,
        nodebug: true,
      },
      loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
    }),
    "{name: raw\"text, id: 7, ty: Void, init: None, storage: Default, attrs: {aligned: None, packed: true, ms_struct: true, transparent_union: true, weak: true, visibility: None, section: None, alias_name: None, asm_label: None, cleanup: None, noreturn: true, constructor_attr: true, destructor: true, always_inline: true, call_conv: None, dll_import: true, dll_export: true, nodecorate: true, nodebug: true}, loc: {file_id: 1, line: 2, col: 3, offset: 4}}",
  )
  assert_eq(
    Show::to_string(
      Decl::FuncDef(FuncDef::{
        name: "raw\"text",
        id: 7,
        return_type: CType::Void,
        params: [],
        varargs: true,
        is_old_style: true,
        storage: StorageClass::Default,
        is_inline: true,
        attrs: Attributes::{
          aligned: None,
          packed: true,
          ms_struct: true,
          transparent_union: true,
          weak: true,
          visibility: None,
          section: None,
          alias_name: None,
          asm_label: None,
          cleanup: None,
          noreturn: true,
          constructor_attr: true,
          destructor: true,
          always_inline: true,
          call_conv: None,
          dll_import: true,
          dll_export: true,
          nodecorate: true,
          nodebug: true,
        },
        body: Stmt::Compound(stmts=[], loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      }),
    ),
    "FuncDef({name: raw\"text, id: 7, return_type: Void, params: [], varargs: true, is_old_style: true, storage: Default, is_inline: true, attrs: {aligned: None, packed: true, ms_struct: true, transparent_union: true, weak: true, visibility: None, section: None, alias_name: None, asm_label: None, cleanup: None, noreturn: true, constructor_attr: true, destructor: true, always_inline: true, call_conv: None, dll_import: true, dll_export: true, nodecorate: true, nodebug: true}, body: Compound(stmts=[], loc={file_id: 1, line: 2, col: 3, offset: 4}), loc: {file_id: 1, line: 2, col: 3, offset: 4}})",
  )
  assert_eq(
    Show::to_string(
      Decl::FuncDecl(FuncDecl::{
        name: "raw\"text",
        id: 7,
        return_type: CType::Void,
        params: [],
        varargs: true,
        is_old_style: true,
        storage: StorageClass::Default,
        is_inline: true,
        attrs: Attributes::{
          aligned: None,
          packed: true,
          ms_struct: true,
          transparent_union: true,
          weak: true,
          visibility: None,
          section: None,
          alias_name: None,
          asm_label: None,
          cleanup: None,
          noreturn: true,
          constructor_attr: true,
          destructor: true,
          always_inline: true,
          call_conv: None,
          dll_import: true,
          dll_export: true,
          nodecorate: true,
          nodebug: true,
        },
        loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      }),
    ),
    "FuncDecl({name: raw\"text, id: 7, return_type: Void, params: [], varargs: true, is_old_style: true, storage: Default, is_inline: true, attrs: {aligned: None, packed: true, ms_struct: true, transparent_union: true, weak: true, visibility: None, section: None, alias_name: None, asm_label: None, cleanup: None, noreturn: true, constructor_attr: true, destructor: true, always_inline: true, call_conv: None, dll_import: true, dll_export: true, nodecorate: true, nodebug: true}, loc: {file_id: 1, line: 2, col: 3, offset: 4}})",
  )
  assert_eq(
    Show::to_string(
      Decl::Var(VarDecl::{
        name: "raw\"text",
        id: 7,
        ty: CType::Void,
        init: None,
        storage: StorageClass::Default,
        attrs: Attributes::{
          aligned: None,
          packed: true,
          ms_struct: true,
          transparent_union: true,
          weak: true,
          visibility: None,
          section: None,
          alias_name: None,
          asm_label: None,
          cleanup: None,
          noreturn: true,
          constructor_attr: true,
          destructor: true,
          always_inline: true,
          call_conv: None,
          dll_import: true,
          dll_export: true,
          nodecorate: true,
          nodebug: true,
        },
        loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      }),
    ),
    "Var({name: raw\"text, id: 7, ty: Void, init: None, storage: Default, attrs: {aligned: None, packed: true, ms_struct: true, transparent_union: true, weak: true, visibility: None, section: None, alias_name: None, asm_label: None, cleanup: None, noreturn: true, constructor_attr: true, destructor: true, always_inline: true, call_conv: None, dll_import: true, dll_export: true, nodecorate: true, nodebug: true}, loc: {file_id: 1, line: 2, col: 3, offset: 4}})",
  )
  assert_eq(
    Show::to_string(
      Decl::Typedef(
        name="raw\"text",
        ty=CType::Void,
        attrs=Attributes::{
          aligned: None,
          packed: true,
          ms_struct: true,
          transparent_union: true,
          weak: true,
          visibility: None,
          section: None,
          alias_name: None,
          asm_label: None,
          cleanup: None,
          noreturn: true,
          constructor_attr: true,
          destructor: true,
          always_inline: true,
          call_conv: None,
          dll_import: true,
          dll_export: true,
          nodecorate: true,
          nodebug: true,
        },
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "Typedef(name=raw\"text, ty=Void, attrs={aligned: None, packed: true, ms_struct: true, transparent_union: true, weak: true, visibility: None, section: None, alias_name: None, asm_label: None, cleanup: None, noreturn: true, constructor_attr: true, destructor: true, always_inline: true, call_conv: None, dll_import: true, dll_export: true, nodecorate: true, nodebug: true}, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Decl::TagDef(ty=CType::Void, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "TagDef(ty=Void, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Decl::StaticAssert(StaticAssert::{
        expr: Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        message: None,
        loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      }),
    ),
    "StaticAssert({expr: IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), message: None, loc: {file_id: 1, line: 2, col: 3, offset: 4}})",
  )
  assert_eq(
    Show::to_string(
      Decl::Asm(AsmStmt::{
        template: "raw\"text",
        outputs: [],
        inputs: [],
        clobbers: [],
        labels: [],
        is_volatile: true,
        is_goto: true,
        loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      }),
    ),
    "Asm({template: raw\"text, outputs: [], inputs: [], clobbers: [], labels: [], is_volatile: true, is_goto: true, loc: {file_id: 1, line: 2, col: 3, offset: 4}})",
  )
  assert_eq(
    Show::to_string(TranslationUnit::{ decls: [], expr_id_max: 7, }),
    "{decls: [], expr_id_max: 7}",
  )
  assert_eq(Show::to_string(UnaryOp::Plus), "Plus")
  assert_eq(Show::to_string(UnaryOp::Minus), "Minus")
  assert_eq(Show::to_string(UnaryOp::Not), "Not")
  assert_eq(Show::to_string(UnaryOp::BitNot), "BitNot")
  assert_eq(Show::to_string(UnaryOp::Addr), "Addr")
  assert_eq(Show::to_string(UnaryOp::Deref), "Deref")
  assert_eq(Show::to_string(UnaryOp::PreInc), "PreInc")
  assert_eq(Show::to_string(UnaryOp::PreDec), "PreDec")
  assert_eq(Show::to_string(UnaryOp::PostInc), "PostInc")
  assert_eq(Show::to_string(UnaryOp::PostDec), "PostDec")
  assert_eq(Show::to_string(BinaryOp::Assign), "Assign")
  assert_eq(Show::to_string(BinaryOp::AddAssign), "AddAssign")
  assert_eq(Show::to_string(BinaryOp::SubAssign), "SubAssign")
  assert_eq(Show::to_string(BinaryOp::MulAssign), "MulAssign")
  assert_eq(Show::to_string(BinaryOp::DivAssign), "DivAssign")
  assert_eq(Show::to_string(BinaryOp::ModAssign), "ModAssign")
  assert_eq(Show::to_string(BinaryOp::ShlAssign), "ShlAssign")
  assert_eq(Show::to_string(BinaryOp::ShrAssign), "ShrAssign")
  assert_eq(Show::to_string(BinaryOp::BitAndAssign), "BitAndAssign")
  assert_eq(Show::to_string(BinaryOp::BitXorAssign), "BitXorAssign")
  assert_eq(Show::to_string(BinaryOp::BitOrAssign), "BitOrAssign")
  assert_eq(Show::to_string(BinaryOp::Comma), "Comma")
  assert_eq(Show::to_string(BinaryOp::Add), "Add")
  assert_eq(Show::to_string(BinaryOp::Sub), "Sub")
  assert_eq(Show::to_string(BinaryOp::Mul), "Mul")
  assert_eq(Show::to_string(BinaryOp::Div), "Div")
  assert_eq(Show::to_string(BinaryOp::Mod), "Mod")
  assert_eq(Show::to_string(BinaryOp::Shl), "Shl")
  assert_eq(Show::to_string(BinaryOp::Shr), "Shr")
  assert_eq(Show::to_string(BinaryOp::Eq), "Eq")
  assert_eq(Show::to_string(BinaryOp::Ne), "Ne")
  assert_eq(Show::to_string(BinaryOp::Lt), "Lt")
  assert_eq(Show::to_string(BinaryOp::Le), "Le")
  assert_eq(Show::to_string(BinaryOp::Gt), "Gt")
  assert_eq(Show::to_string(BinaryOp::Ge), "Ge")
  assert_eq(Show::to_string(BinaryOp::BitAnd), "BitAnd")
  assert_eq(Show::to_string(BinaryOp::BitXor), "BitXor")
  assert_eq(Show::to_string(BinaryOp::BitOr), "BitOr")
  assert_eq(Show::to_string(BinaryOp::LogAnd), "LogAnd")
  assert_eq(Show::to_string(BinaryOp::LogOr), "LogOr")
  assert_eq(
    Show::to_string(
      Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::FloatLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "FloatLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::CharLit(value=7, node_id=7, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "CharLit(value=7, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::StringLit(value="raw\"text", length=7, node_id=7, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "StringLit(value=raw\"text, length=7, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::Ident(name="raw\"text", id=7, node_id=7, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "Ident(name=raw\"text, id=7, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::LabelAddr(name="raw\"text", id=7, node_id=7, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "LabelAddr(name=raw\"text, id=7, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::BuiltinTypesCompatibleP(a=CType::Void, b=CType::Void, node_id=7, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "BuiltinTypesCompatibleP(a=Void, b=Void, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::BuiltinOffsetof(ty=CType::Void, path=[], node_id=7, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "BuiltinOffsetof(ty=Void, path=[], node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::BuiltinVaArg(
        list=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        ty=CType::Void,
        node_id=7,
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "BuiltinVaArg(list=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), ty=Void, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::Unary(
        op=UnaryOp::Plus,
        expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        node_id=7,
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "Unary(op=Plus, expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::Cast(
        ty=CType::Void,
        expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        node_id=7,
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "Cast(ty=Void, expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::CompoundLiteral(
        ty=CType::Void,
        init=Initializer::Expr(
          expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
            file_id: 1,
            line: 2,
            col: 3,
            offset: 4,
          }),
          loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
        ),
        node_id=7,
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "CompoundLiteral(ty=Void, init=Expr(expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), loc={file_id: 1, line: 2, col: 3, offset: 4}), node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::StmtExpr(stmts=[], node_id=7, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "StmtExpr(stmts=[], node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::SizeofExpr(
        expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        node_id=7,
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "SizeofExpr(expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::SizeofType(ty=CType::Void, node_id=7, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "SizeofType(ty=Void, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::AlignofExpr(
        expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        node_id=7,
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "AlignofExpr(expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::AlignofType(ty=CType::Void, node_id=7, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "AlignofType(ty=Void, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::Binary(
        op=BinaryOp::Assign,
        left=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        right=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        node_id=7,
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "Binary(op=Assign, left=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), right=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::Conditional(
        cond=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        then_expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        else_expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        node_id=7,
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "Conditional(cond=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), then_expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), else_expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::Call(
        callee=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        args=[],
        node_id=7,
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "Call(callee=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), args=[], node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::Index(
        base=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        index=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        node_id=7,
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "Index(base=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), index=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Expr::Member(
        base=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        name="raw\"text",
        id=7,
        is_arrow=true,
        node_id=7,
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "Member(base=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), name=raw\"text, id=7, is_arrow=true, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      InitDesignator::Index(
        expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "Index(expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      InitDesignator::IndexRange(
        start=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        end=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "IndexRange(start=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), end=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      InitDesignator::Field(name="raw\"text", id=7, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "Field(name=raw\"text, id=7, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(InitItem::{
      designators: [],
      value: Initializer::Expr(
        expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
      loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
    }),
    "{designators: [], value: Expr(expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), loc={file_id: 1, line: 2, col: 3, offset: 4}), loc: {file_id: 1, line: 2, col: 3, offset: 4}}",
  )
  assert_eq(
    Show::to_string(
      Initializer::Expr(
        expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "Expr(expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Initializer::List(items=[], loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "List(items=[], loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(AsmOperand::{
      name: None,
      constraint: "raw\"text",
      expr: Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
      loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
    }),
    "{name: None, constraint: raw\"text, expr: IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), loc: {file_id: 1, line: 2, col: 3, offset: 4}}",
  )
  assert_eq(
    Show::to_string(AsmStmt::{
      template: "raw\"text",
      outputs: [],
      inputs: [],
      clobbers: [],
      labels: [],
      is_volatile: true,
      is_goto: true,
      loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
    }),
    "{template: raw\"text, outputs: [], inputs: [], clobbers: [], labels: [], is_volatile: true, is_goto: true, loc: {file_id: 1, line: 2, col: 3, offset: 4}}",
  )
  assert_eq(
    Show::to_string(
      Stmt::Compound(stmts=[], loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "Compound(stmts=[], loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::If(
        cond=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        then_branch=Stmt::Compound(stmts=[], loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        else_branch=None,
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "If(cond=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), then_branch=Compound(stmts=[], loc={file_id: 1, line: 2, col: 3, offset: 4}), else_branch=None, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::While(
        cond=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        body=Stmt::Compound(stmts=[], loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "While(cond=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), body=Compound(stmts=[], loc={file_id: 1, line: 2, col: 3, offset: 4}), loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::DoWhile(
        cond=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        body=Stmt::Compound(stmts=[], loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "DoWhile(cond=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), body=Compound(stmts=[], loc={file_id: 1, line: 2, col: 3, offset: 4}), loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::For(
        init=None,
        cond=None,
        step=None,
        body=Stmt::Compound(stmts=[], loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "For(init=None, cond=None, step=None, body=Compound(stmts=[], loc={file_id: 1, line: 2, col: 3, offset: 4}), loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::Switch(
        cond=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        body=Stmt::Compound(stmts=[], loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "Switch(cond=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), body=Compound(stmts=[], loc={file_id: 1, line: 2, col: 3, offset: 4}), loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::Case(
        expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        end_expr=None,
        body=Stmt::Compound(stmts=[], loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "Case(expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), end_expr=None, body=Compound(stmts=[], loc={file_id: 1, line: 2, col: 3, offset: 4}), loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::Default(
        body=Stmt::Compound(stmts=[], loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "Default(body=Compound(stmts=[], loc={file_id: 1, line: 2, col: 3, offset: 4}), loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::Label(
        name="raw\"text",
        body=Stmt::Compound(stmts=[], loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "Label(name=raw\"text, body=Compound(stmts=[], loc={file_id: 1, line: 2, col: 3, offset: 4}), loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::Goto(name="raw\"text", loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "Goto(name=raw\"text, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::GotoExpr(
        expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "GotoExpr(expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::Break(loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "Break(loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::Continue(loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "Continue(loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::Return(value=None, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "Return(value=None, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::Asm(AsmStmt::{
        template: "raw\"text",
        outputs: [],
        inputs: [],
        clobbers: [],
        labels: [],
        is_volatile: true,
        is_goto: true,
        loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      }),
    ),
    "Asm({template: raw\"text, outputs: [], inputs: [], clobbers: [], labels: [], is_volatile: true, is_goto: true, loc: {file_id: 1, line: 2, col: 3, offset: 4}})",
  )
  assert_eq(
    Show::to_string(
      Stmt::ExprStmt(
        expr=Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        loc=@source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      ),
    ),
    "ExprStmt(expr=IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::DeclStmt(decls=[], loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "DeclStmt(decls=[], loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::TagDef(ty=CType::Void, loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "TagDef(ty=Void, loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
  assert_eq(
    Show::to_string(
      Stmt::StaticAssert(StaticAssert::{
        expr: Expr::IntLit(value="raw\"text", node_id=7, loc=@source.SrcLoc::{
          file_id: 1,
          line: 2,
          col: 3,
          offset: 4,
        }),
        message: None,
        loc: @source.SrcLoc::{ file_id: 1, line: 2, col: 3, offset: 4, },
      }),
    ),
    "StaticAssert({expr: IntLit(value=raw\"text, node_id=7, loc={file_id: 1, line: 2, col: 3, offset: 4}), message: None, loc: {file_id: 1, line: 2, col: 3, offset: 4}})",
  )
  assert_eq(
    Show::to_string(
      Stmt::Empty(loc=@source.SrcLoc::{
        file_id: 1,
        line: 2,
        col: 3,
        offset: 4,
      }),
    ),
    "Empty(loc={file_id: 1, line: 2, col: 3, offset: 4})",
  )
}
