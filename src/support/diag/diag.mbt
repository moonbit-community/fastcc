///|
struct Diag {
  loc : SrcLoc
  message : String
}

///|
struct DiagBag {
  diags : Array[Diag]
}

///|
fn new_diag_bag() -> DiagBag {
  { diags: [] }
}

///|
fn add_error(bag : DiagBag, loc : SrcLoc, message : String) -> Unit {
  bag.diags.push({ loc, message })
}

///|
fn has_errors(bag : DiagBag) -> Bool {
  bag.diags.length() > 0
}

///|
fn format_diag(d : Diag) -> String {
  d.message
}
