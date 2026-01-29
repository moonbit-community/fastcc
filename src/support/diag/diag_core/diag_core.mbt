///|
pub(all) struct Diag {
  loc : @source.SrcLoc
  message : String
}

///|
pub(all) struct DiagBag {
  diags : Array[Diag]
}

///|
pub fn new_diag_bag() -> DiagBag {
  { diags: [] }
}

///|
pub fn add_error(bag : DiagBag, loc : @source.SrcLoc, message : String) -> Unit {
  bag.diags.push({ loc, message })
}

///|
pub fn has_errors(bag : DiagBag) -> Bool {
  bag.diags.length() > 0
}

///|
pub fn format_diag(d : Diag) -> String {
  d.message
}
