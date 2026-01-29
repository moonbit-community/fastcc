///|
type BuiltinIds = @parser_core.BuiltinIds

///|
type DeclSpecs = @parser_core.DeclSpecs

///|
type DeclWrapper = @parser_core.DeclWrapper

///|
type Declarator = @parser_core.Declarator

///|
type ParenDeclParts = @parser_core.ParenDeclParts

///|
type Parser = @parser_core.Parser

///|
pub fn parse_translation_unit(pp : @preproc.Preprocessor) -> @ast.TranslationUnit {
  @parser_core.parse_translation_unit(pp)
}
