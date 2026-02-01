///|
pub fn empty_qual() -> TypeQual {
  { is_const: false, is_volatile: false, is_restrict: false, is_atomic: false }
}

///|
pub fn merge_qual(a : TypeQual, b : TypeQual) -> TypeQual {
  {
    is_const: a.is_const || b.is_const,
    is_volatile: a.is_volatile || b.is_volatile,
    is_restrict: a.is_restrict || b.is_restrict,
    is_atomic: a.is_atomic || b.is_atomic,
  }
}

///|
fn qual_is_empty(qual : TypeQual) -> Bool {
  !qual.is_const && !qual.is_volatile && !qual.is_restrict && !qual.is_atomic
}

///|
pub fn with_const(qual : TypeQual) -> TypeQual {
  {
    is_const: true,
    is_volatile: qual.is_volatile,
    is_restrict: qual.is_restrict,
    is_atomic: qual.is_atomic,
  }
}

///|
pub fn with_volatile(qual : TypeQual) -> TypeQual {
  {
    is_const: qual.is_const,
    is_volatile: true,
    is_restrict: qual.is_restrict,
    is_atomic: qual.is_atomic,
  }
}

///|
pub fn with_restrict(qual : TypeQual) -> TypeQual {
  {
    is_const: qual.is_const,
    is_volatile: qual.is_volatile,
    is_restrict: true,
    is_atomic: qual.is_atomic,
  }
}

///|
pub fn with_atomic(qual : TypeQual) -> TypeQual {
  {
    is_const: qual.is_const,
    is_volatile: qual.is_volatile,
    is_restrict: qual.is_restrict,
    is_atomic: true,
  }
}

///|
pub fn apply_qualifiers(ty : CType, qual : TypeQual) -> CType {
  if qual_is_empty(qual) {
    return ty
  }
  match ty {
    Qualified(qual=existing, base~) =>
      Qualified(qual=merge_qual(existing, qual), base~)
    _ => Qualified(qual~, base=ty)
  }
}
