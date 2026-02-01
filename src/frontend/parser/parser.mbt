///|
pub fn parse_translation_unit(
  pp : @preproc.Preprocessor,
) -> @ast.TranslationUnit {
  @parser_core.parse_translation_unit(pp)
}
