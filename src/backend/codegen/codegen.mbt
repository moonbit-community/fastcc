///|
pub fn codegen_arm64_object_bytes(unit : @ast.TranslationUnit, bag : @diag.DiagBag) -> Bytes? {
  codegen_arm64_object_bytes_from_ast(unit, bag)
}
