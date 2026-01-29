///|
pub type Diag = @diag_core.Diag

///|
pub type DiagBag = @diag_core.DiagBag

///|
pub fn new_diag_bag() -> DiagBag {
  @diag_core.new_diag_bag()
}

///|
pub fn add_error(bag : DiagBag, loc : @source.SrcLoc, message : String) -> Unit {
  @diag_core.add_error(bag, loc, message)
}

///|
pub fn has_errors(bag : DiagBag) -> Bool {
  @diag_core.has_errors(bag)
}

///|
pub fn format_diag(d : Diag) -> String {
  @diag_core.format_diag(d)
}
