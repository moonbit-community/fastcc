///| Gather unused helpers to suppress warnings while keeping parity with refs/tinycc
pub fn touch_unused_symbols() -> Unit {
  // arm64 helpers/constants
  let _treg_f7 = @arm64.TREG_F7
  let treg_r_ref = @arm64.treg_r
  let treg_f_ref = @arm64.treg_f
  let greloc_ref = @arm64.greloc
  let gind_ref = @arm64.gind
  let gjmp_append_ref = @arm64.gjmp_append
  let gen_fill_nops_ref = @arm64.gen_fill_nops
  let arm64_vset_VT_CMP_ref = @arm64.arm64_vset_VT_CMP
  let gjmp_cond_ref = @arm64.gjmp_cond
  let arm64_ldrs_ref = @arm64.arm64_ldrs
  let arm64_strv_ref = @arm64.arm64_strv

  // codegen helpers
  let emit_fcmp_ref = emit_fcmp
  let emit_cset_from_fp_tok_ref = emit_cset_from_fp_tok
  let emit_load_local_int32_ref = emit_load_local_int32
  let emit_store_local_int32_ref = emit_store_local_int32
  let codegen_arm64_object_bytes_ref = codegen_arm64_object_bytes

  // codegen state constants/functions
  let tok_land_ref = @arm64.TOK_LAND
  let tok_lor_ref = @arm64.TOK_LOR
  let rc_iret_ref = @arm64.RC_IRET
  let rc_fret_ref = @arm64.RC_FRET
  let vdup_ref = @arm64.vdup

  // diag helper
  let format_diag_ref = @diag.format_diag
  let write_macho_object_ref = @macho.write_macho_object

  // object helpers
  let new_section_ref = @object.new_section
  let section_from_emitter_ref = @arm64.section_from_emitter
  let reloc_addend_ref = @object.reloc_addend

  // sem helper
  let type_contains_vla_ref = @sem.type_contains_vla
  let strip_qualifiers_ref = @sem.strip_qualifiers
  let strip_qual_attrs_ref = @sem.strip_qual_attrs

  // Touch refs to avoid unused warnings
  let _ = (
    _treg_f7,
    treg_r_ref,
    treg_f_ref,
    greloc_ref,
    gind_ref,
    gjmp_append_ref,
    gen_fill_nops_ref,
    arm64_vset_VT_CMP_ref,
    gjmp_cond_ref,
    arm64_ldrs_ref,
    arm64_strv_ref,
    emit_fcmp_ref,
    emit_cset_from_fp_tok_ref,
    emit_load_local_int32_ref,
    emit_store_local_int32_ref,
    codegen_arm64_object_bytes_ref,
    tok_land_ref,
    tok_lor_ref,
    rc_iret_ref,
    rc_fret_ref,
    vdup_ref,
    format_diag_ref,
    write_macho_object_ref,
    new_section_ref,
    section_from_emitter_ref,
    reloc_addend_ref,
    type_contains_vla_ref,
    strip_qualifiers_ref,
    strip_qual_attrs_ref,
  )
}
