///|
pub type CondState = @preproc_core.CondState
///|

///|
pub type ExpandingGuard = @preproc_core.ExpandingGuard
///|

///|
pub type HiddenNode = @preproc_core.HiddenNode
///|

///|
pub type HiddenPool = @preproc_core.HiddenPool
///|

///|
pub type IfParser = @preproc_core.IfParser
///|

///|
pub type IncludeSpec = @preproc_core.IncludeSpec
///|

///|
pub type Macro = @preproc_core.Macro
///|

///|
pub type PpValue = @preproc_core.PpValue
///|

///|
pub type PreprocBuiltinIds = @preproc_core.PreprocBuiltinIds
///|

///|
pub type Preprocessor = @preproc_core.Preprocessor
///|

///|

///|
pub fn new_hidden_pool() -> HiddenPool {
  @preproc_core.new_hidden_pool()
}
///|
pub fn clear_hidden_pool(pool : HiddenPool) -> Unit {
  @preproc_core.clear_hidden_pool(pool)
}
///|
pub fn make_builtin_token(kind : @tokens.TokenKind, id? : Int = 0, lexeme_id? : Int = 0) -> @tokens.Token {
  @preproc_core.make_builtin_token(kind, id=id, lexeme_id=lexeme_id)
}
///|
pub fn make_builtin_word_token(pp : Preprocessor, word : String) -> @tokens.Token {
  @preproc_core.make_builtin_word_token(pp, word)
}
///|
pub fn pp_token_lexeme(pp : Preprocessor, tok : @tokens.Token) -> String {
  @preproc_core.pp_token_lexeme(pp, tok)
}
///|
pub fn pp_token_lexeme_len(pp : Preprocessor, tok : @tokens.Token) -> Int {
  @preproc_core.pp_token_lexeme_len(pp, tok)
}
///|
pub fn define_macro(pp : Preprocessor, name : String, replacement : Array[@tokens.Token]) -> Unit {
  @preproc_core.define_macro(pp, name, replacement)
}
///|
pub fn define_words_macro(pp : Preprocessor, name : String, words : Array[String]) ->
  Unit {
  @preproc_core.define_words_macro(pp, name, words)
}
///|
pub fn define_int_macro(pp : Preprocessor, name : String, value : Int) -> Unit {
  @preproc_core.define_int_macro(pp, name, value)
}
///|
pub fn define_func_macro_zero(pp : Preprocessor, name : String) -> Unit {
  @preproc_core.define_func_macro_zero(pp, name)
}
///|
pub fn define_func_macro_empty(pp : Preprocessor, name : String) -> Unit {
  @preproc_core.define_func_macro_empty(pp, name)
}
///|
pub fn init_builtin_macros(pp : Preprocessor) -> Unit {
  @preproc_core.init_builtin_macros(pp)
}
///|
pub fn new_preprocessor(map : @source.SourceMap, file : @source.SourceFile, diags : @diag.DiagBag) ->
  Preprocessor {
  @preproc_core.new_preprocessor(map, file, diags)
}
///|
pub fn finalize_preprocessor(pp : Preprocessor) -> Unit {
  @preproc_core.finalize_preprocessor(pp)
}
///|
pub fn current_active(pp : Preprocessor) -> Bool {
  @preproc_core.current_active(pp)
}
///|
pub fn add_pp_error(pp : Preprocessor, loc : @source.SrcLoc, message : String) -> Unit {
  @preproc_core.add_pp_error(pp, loc, message)
}
///|
pub fn is_macro_name_token(tok : @tokens.Token) -> Bool {
  @preproc_core.is_macro_name_token(tok)
}
///|
pub fn macro_id_from_name(pp : Preprocessor, name : String) -> Int {
  @preproc_core.macro_id_from_name(pp, name)
}
///|
pub fn macro_id_from_token(_pp : Preprocessor, tok : @tokens.Token) -> Int {
  @preproc_core.macro_id_from_token(_pp, tok)
}
///|
pub fn ensure_macro_capacity(pp : Preprocessor, id : Int) -> Unit {
  @preproc_core.ensure_macro_capacity(pp, id)
}
///|
pub fn get_macro(pp : Preprocessor, id : Int) -> Macro? {
  @preproc_core.get_macro(pp, id)
}
///|
pub fn has_macro(pp : Preprocessor, id : Int) -> Bool {
  @preproc_core.has_macro(pp, id)
}
///|
pub fn set_macro(pp : Preprocessor, id : Int, macro_def : Macro) -> Unit {
  @preproc_core.set_macro(pp, id, macro_def)
}
///|
pub fn remove_macro(pp : Preprocessor, id : Int) -> Unit {
  @preproc_core.remove_macro(pp, id)
}
///|
pub fn next_input_token(pp : Preprocessor) -> @tokens.Token {
  @preproc_core.next_input_token(pp)
}
///|
pub fn read_directive_tokens(pp : Preprocessor) -> Array[@tokens.Token] {
  @preproc_core.read_directive_tokens(pp)
}
///|
pub fn read_directive_head_token(pp : Preprocessor) -> @tokens.Token? {
  @preproc_core.read_directive_head_token(pp)
}
///|
pub fn skip_directive_line(pp : Preprocessor) -> Unit {
  @preproc_core.skip_directive_line(pp)
}
///|
pub fn skip_inactive(pp : Preprocessor) -> Unit {
  @preproc_core.skip_inactive(pp)
}
///|
pub fn read_directive_text(pp : Preprocessor) -> String {
  @preproc_core.read_directive_text(pp)
}
///|
pub fn slice_tokens(tokens : Array[@tokens.Token], start : Int) -> Array[@tokens.Token] {
  @preproc_core.slice_tokens(tokens, start)
}
///|
pub fn prefix_tokens(tokens : Array[@tokens.Token], end : Int) -> Array[@tokens.Token] {
  @preproc_core.prefix_tokens(tokens, end)
}
///|
pub fn dir_name(path : String) -> String {
  @preproc_core.dir_name(path)
}
///|
pub fn join_path(base : String, name : String) -> String {
  @preproc_core.join_path(base, name)
}
///|
pub fn add_include_path(pp : Preprocessor, path : String) -> Unit {
  @preproc_core.add_include_path(pp, path)
}
///|
pub fn strip_quotes(lexeme : String) -> String {
  @preproc_core.strip_quotes(lexeme)
}
///|
pub fn parse_include_path(pp : Preprocessor, args : Array[@tokens.Token], loc : @source.SrcLoc) -> IncludeSpec? {
  @preproc_core.parse_include_path(pp, args, loc)
}
///|
pub fn parse_has_include_path(pp : Preprocessor, args : Array[@tokens.Token]) -> IncludeSpec? {
  @preproc_core.parse_has_include_path(pp, args)
}
///|
pub fn eval_has_include(pp : Preprocessor, args : Array[@tokens.Token], include_next~ : Bool) -> Int {
  @preproc_core.eval_has_include(pp, args, include_next=include_next)
}
///|
pub fn resolve_include_path(pp : Preprocessor, path : String, is_angle : Bool, include_next~ : Bool) -> String? {
  @preproc_core.resolve_include_path(pp, path, is_angle, include_next=include_next)
}
///|
pub fn include_file(pp : Preprocessor, spec : IncludeSpec, loc : @source.SrcLoc, include_next~ : Bool) -> Unit {
  @preproc_core.include_file(pp, spec, loc, include_next=include_next)
}
///|
pub fn parse_define_macro(pp : Preprocessor, name_tok : @tokens.Token, args : Array[@tokens.Token], loc : @source.SrcLoc) -> Macro? {
  @preproc_core.parse_define_macro(pp, name_tok, args, loc)
}
///|
pub fn parse_macro_params(pp : Preprocessor, args : Array[@tokens.Token], loc : @source.SrcLoc) -> (Array[Int], Bool, Array[@tokens.Token])? {
  @preproc_core.parse_macro_params(pp, args, loc)
}
///|
pub fn next_raw_token(pp : Preprocessor) -> @tokens.Token {
  @preproc_core.next_raw_token(pp)
}
///|
pub fn push_back(pp : Preprocessor, tok : @tokens.Token) -> Unit {
  @preproc_core.push_back(pp, tok)
}
///|
pub fn read_macro_args(pp : Preprocessor, loc : @source.SrcLoc) -> Array[Array[@tokens.Token]]? {
  @preproc_core.read_macro_args(pp, loc)
}
///|
pub fn normalize_macro_args(macro_def : Macro, args : Array[Array[@tokens.Token]], loc : @source.SrcLoc) -> Array[Array[@tokens.Token]]? {
  @preproc_core.normalize_macro_args(macro_def, args, loc)
}
///|
pub fn is_adjacent(pp : Preprocessor, left : @tokens.Token, right : @tokens.Token) -> Bool {
  @preproc_core.is_adjacent(pp, left, right)
}
///|
pub fn is_expanding(pp : Preprocessor, id : Int) -> Bool {
  @preproc_core.is_expanding(pp, id)
}
///|
pub fn push_expanding(pp : Preprocessor, id : Int) -> Unit {
  @preproc_core.push_expanding(pp, id)
}
///|
pub fn pop_expanding(pp : Preprocessor) -> Unit {
  @preproc_core.pop_expanding(pp)
}
///|
pub fn stringize_tokens(pp : Preprocessor, tokens : Array[@tokens.Token]) -> String {
  @preproc_core.stringize_tokens(pp, tokens)
}
///|
pub fn make_string_literal(pp : Preprocessor, text : String, loc : @source.SrcLoc) -> @tokens.Token {
  @preproc_core.make_string_literal(pp, text, loc)
}
///|
pub fn escape_string(text : String) -> String {
  @preproc_core.escape_string(text)
}
///|
pub fn logical_line(pp : Preprocessor, loc : @source.SrcLoc) -> Int {
  @preproc_core.logical_line(pp, loc)
}
///|
pub fn make_int_literal_token(pp : Preprocessor, value : Int, loc : @source.SrcLoc) -> @tokens.Token {
  @preproc_core.make_int_literal_token(pp, value, loc)
}
///|
pub fn builtin_macro_tokens(pp : Preprocessor, tok : @tokens.Token) -> Array[@tokens.Token]? {
  @preproc_core.builtin_macro_tokens(pp, tok)
}
///|
pub fn is_builtin_macro_id(pp : Preprocessor, id : Int) -> Bool {
  @preproc_core.is_builtin_macro_id(pp, id)
}
///|
pub fn tokens_need_expansion(pp : Preprocessor, tokens : Array[@tokens.Token]) -> Bool {
  @preproc_core.tokens_need_expansion(pp, tokens)
}
///|
pub fn token_needs_expansion(pp : Preprocessor, tok : @tokens.Token) -> Bool {
  @preproc_core.token_needs_expansion(pp, tok)
}
///|
pub fn macro_replacement_needs_expand(pp : Preprocessor, macro_id : Int, macro_def : Macro) -> Bool {
  @preproc_core.macro_replacement_needs_expand(pp, macro_id, macro_def)
}
///|
pub fn tokens_have_id(tokens : Array[@tokens.Token]) -> Bool {
  @preproc_core.tokens_have_id(tokens)
}
///|
pub fn init_datetime_literals() -> (String, String) {
  @preproc_core.init_datetime_literals()
}
///|
pub fn format_date(dt : @time.ZonedDateTime) -> String {
  @preproc_core.format_date(dt)
}
///|
pub fn format_time(dt : @time.ZonedDateTime) -> String {
  @preproc_core.format_time(dt)
}
///|
pub fn month_name(month : Int) -> String {
  @preproc_core.month_name(month)
}
///|
pub fn pad2(value : Int) -> String {
  @preproc_core.pad2(value)
}
///|
pub fn pad2_space(value : Int) -> String {
  @preproc_core.pad2_space(value)
}
///|
pub fn lookup_param_index(params : Array[Int], id : Int) -> Int? {
  @preproc_core.lookup_param_index(params, id)
}
///|
pub fn lex_paste_tokens(pp : Preprocessor, text : String, left : String, right : String, loc : @source.SrcLoc, hidden : Int) -> Array[@tokens.Token] {
  @preproc_core.lex_paste_tokens(pp, text, left, right, loc, hidden)
}
///|
pub fn substitute_macro(pp : Preprocessor, macro_def : Macro, raw_args : Array[Array[@tokens.Token]], loc : @source.SrcLoc) -> (Array[@tokens.Token], Bool) {
  @preproc_core.substitute_macro(pp, macro_def, raw_args, loc)
}
///|
pub fn read_macro_args_from_tokens(pp : Preprocessor, tokens : Array[@tokens.Token], start : Int, loc : @source.SrcLoc) -> (Array[Array[@tokens.Token]], Int)? {
  @preproc_core.read_macro_args_from_tokens(pp, tokens, start, loc)
}
///|
pub fn ensure_expanded_arg(pp : Preprocessor, raw_args : Array[Array[@tokens.Token]], expanded_cache : Array[Array[@tokens.Token]?], idx : Int) -> Array[@tokens.Token] {
  @preproc_core.ensure_expanded_arg(pp, raw_args, expanded_cache, idx)
}
///|
pub fn expand_tokens(pp : Preprocessor, tokens : Array[@tokens.Token]) -> Array[@tokens.Token] {
  @preproc_core.expand_tokens(pp, tokens)
}
///|
pub fn push_cond(pp : Preprocessor, cond : Bool) -> Unit {
  @preproc_core.push_cond(pp, cond)
}
///|
pub fn update_elif(pp : Preprocessor, cond : Bool, loc : @source.SrcLoc) -> Unit {
  @preproc_core.update_elif(pp, cond, loc)
}
///|
pub fn update_else(pp : Preprocessor, loc : @source.SrcLoc) -> Unit {
  @preproc_core.update_else(pp, loc)
}
///|
pub fn pop_cond(pp : Preprocessor, loc : @source.SrcLoc) -> Unit {
  @preproc_core.pop_cond(pp, loc)
}
///|
pub fn normalize_macro_tokens(tokens : Array[@tokens.Token]) -> Array[@tokens.Token] {
  @preproc_core.normalize_macro_tokens(tokens)
}
///|
pub fn expand_if_tokens(pp : Preprocessor, tokens : Array[@tokens.Token]) -> Array[@tokens.Token] {
  @preproc_core.expand_if_tokens(pp, tokens)
}
///|
pub fn push_tokens(pp : Preprocessor, tokens : Array[@tokens.Token]) -> Unit {
  @preproc_core.push_tokens(pp, tokens)
}
///|
pub fn release_expanding_guards(pp : Preprocessor) -> Unit {
  @preproc_core.release_expanding_guards(pp)
}
///|
pub fn hidden_is_empty(hidden : Int) -> Bool {
  @preproc_core.hidden_is_empty(hidden)
}
///|
pub fn hidden_contains(pool : HiddenPool, hidden : Int, id : Int) -> Bool {
  @preproc_core.hidden_contains(pool, hidden, id)
}
///|
pub fn ensure_hidden_singleton_slot(pool : HiddenPool, id : Int) -> Unit {
  @preproc_core.ensure_hidden_singleton_slot(pool, id)
}
///|
pub fn hidden_add(pool : HiddenPool, hidden : Int, id : Int) -> Int {
  @preproc_core.hidden_add(pool, hidden, id)
}
///|
pub fn merge_hidden(pool : HiddenPool, a : Int, b : Int) -> Int {
  @preproc_core.merge_hidden(pool, a, b)
}
///|
pub fn add_hidden(pp : Preprocessor, tok : @tokens.Token, id : Int) -> @tokens.Token {
  @preproc_core.add_hidden(pp, tok, id)
}
///|
pub fn add_hidden_tokens(pp : Preprocessor, tokens : Array[@tokens.Token], id : Int) -> Array[@tokens.Token] {
  @preproc_core.add_hidden_tokens(pp, tokens, id)
}
///|
pub fn handle_line_directive(pp : Preprocessor, tokens : Array[@tokens.Token], loc : @source.SrcLoc) -> Unit {
  @preproc_core.handle_line_directive(pp, tokens, loc)
}
///|
pub fn eval_if_expr(pp : Preprocessor, tokens : Array[@tokens.Token], loc : @source.SrcLoc) -> Bool {
  @preproc_core.eval_if_expr(pp, tokens, loc)
}
///|
pub fn pp_bool_value(cond : Bool) -> PpValue {
  @preproc_core.pp_bool_value(cond)
}
///|
pub fn pp_is_zero(v : PpValue) -> Bool {
  @preproc_core.pp_is_zero(v)
}
///|
pub fn pp_unsigned_result(a : PpValue, b : PpValue) -> Bool {
  @preproc_core.pp_unsigned_result(a, b)
}
///|
pub fn pp_shift_count(v : PpValue) -> Int {
  @preproc_core.pp_shift_count(v)
}
///|
pub fn peek_if(p : IfParser) -> @tokens.Token? {
  @preproc_core.peek_if(p)
}
///|
pub fn advance_if(p : IfParser) -> @tokens.Token? {
  @preproc_core.advance_if(p)
}
///|
pub fn match_kind(p : IfParser, kind : @tokens.TokenKind) -> Bool {
  @preproc_core.match_kind(p, kind)
}
///|
pub fn parse_line_int_literal(pp : Preprocessor, lexeme : String, loc : @source.SrcLoc) -> Int {
  @preproc_core.parse_line_int_literal(pp, lexeme, loc)
}
///|
pub fn parse_pp_int_literal(pp : Preprocessor, lexeme : String, loc : @source.SrcLoc) -> PpValue {
  @preproc_core.parse_pp_int_literal(pp, lexeme, loc)
}
///|
pub fn parse_pp_char_literal(pp : Preprocessor, tok : @tokens.Token) -> PpValue {
  @preproc_core.parse_pp_char_literal(pp, tok)
}
///|
pub fn decode_pp_escape_value(pp : Preprocessor, text : String, start : Int, loc : @source.SrcLoc) -> (Int, Int) {
  @preproc_core.decode_pp_escape_value(pp, text, start, loc)
}
///|
pub fn parse_pp_hex_escape(pp : Preprocessor, text : String, start : Int, loc : @source.SrcLoc) -> (Int, Int) {
  @preproc_core.parse_pp_hex_escape(pp, text, start, loc)
}
///|
pub fn parse_pp_octal_escape(text : String, start : Int) -> (Int, Int) {
  @preproc_core.parse_pp_octal_escape(text, start)
}
///|
pub fn pp_is_oct_digit(code : UInt16) -> Bool {
  @preproc_core.pp_is_oct_digit(code)
}
///|
pub fn pp_hex_digit_value(code : UInt16) -> Int? {
  @preproc_core.pp_hex_digit_value(code)
}
///|
pub fn macro_int_value(pp : Preprocessor, tok : @tokens.Token, loc : @source.SrcLoc) -> PpValue? {
  @preproc_core.macro_int_value(pp, tok, loc)
}
///|
pub fn parse_primary(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  @preproc_core.parse_primary(p, loc)
}
///|
pub fn peek_is_rparen(p : IfParser) -> Bool {
  @preproc_core.peek_is_rparen(p)
}
///|
pub fn parse_defined(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  @preproc_core.parse_defined(p, loc)
}
///|
pub fn skip_paren_expr(p : IfParser, loc : @source.SrcLoc) -> Unit {
  @preproc_core.skip_paren_expr(p, loc)
}
///|
pub fn parse_unary(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  @preproc_core.parse_unary(p, loc)
}
///|
pub fn parse_mul(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  @preproc_core.parse_mul(p, loc)
}
///|
pub fn parse_add(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  @preproc_core.parse_add(p, loc)
}
///|
pub fn parse_shift(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  @preproc_core.parse_shift(p, loc)
}
///|
pub fn parse_rel(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  @preproc_core.parse_rel(p, loc)
}
///|
pub fn parse_eq(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  @preproc_core.parse_eq(p, loc)
}
///|
pub fn parse_bit_and(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  @preproc_core.parse_bit_and(p, loc)
}
///|
pub fn parse_bit_xor(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  @preproc_core.parse_bit_xor(p, loc)
}
///|
pub fn parse_bit_or(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  @preproc_core.parse_bit_or(p, loc)
}
///|
pub fn parse_logical_and(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  @preproc_core.parse_logical_and(p, loc)
}
///|
pub fn parse_logical_or(p : IfParser, loc : @source.SrcLoc) -> PpValue {
  @preproc_core.parse_logical_or(p, loc)
}
///|
pub fn handle_directive(pp : Preprocessor, _hash_tok : @tokens.Token) -> Unit {
  @preproc_core.handle_directive(pp, _hash_tok)
}
///|
pub fn next_pp_token(pp : Preprocessor) -> @tokens.Token {
  @preproc_core.next_pp_token(pp)
}
///|
pub fn dump_tokens(pp : Preprocessor, max_count : Int) -> Array[@tokens.Token] {
  @preproc_core.dump_tokens(pp, max_count)
}