///|
fn align_up(value : Int, align : Int) -> Int {
  if align <= 0 {
    value
  } else {
    let mask = align - 1
    (value + mask) & mask.lnot()
  }
}
