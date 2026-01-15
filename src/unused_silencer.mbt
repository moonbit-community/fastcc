///| Gather unused helpers to suppress warnings while keeping parity with refs/tinycc
fn touch_unused_symbols() -> Unit {
  // arm64 helpers/constants
  let _treg_f7 = TREG_F7
  let treg_r_ref = treg_r
  let treg_f_ref = treg_f
  let greloc_ref = greloc
  let gind_ref = gind
  let gjmp_append_ref = gjmp_append
  let gen_fill_nops_ref = gen_fill_nops
  let arm64_vset_VT_CMP_ref = arm64_vset_VT_CMP
  let gjmp_cond_ref = gjmp_cond
  let arm64_ldrs_ref = arm64_ldrs
  let arm64_strv_ref = arm64_strv

  // codegen helpers
  let emit_fcmp_ref = emit_fcmp
  let emit_cset_from_fp_tok_ref = emit_cset_from_fp_tok
  let emit_load_local_int32_ref = emit_load_local_int32
  let emit_store_local_int32_ref = emit_store_local_int32

  // codegen state constants/functions
  let tok_land_ref = TOK_LAND
  let tok_lor_ref = TOK_LOR
  let rc_iret_ref = RC_IRET
  let rc_fret_ref = RC_FRET
  let vdup_ref = vdup

  // diag helper
  let format_diag_ref = format_diag

  // Mach-O layout struct and helper
  let layout = {
    name: "",
    section_indices: [],
    fileoff: 0,
    filesize: 0,
    maxprot: 0,
    initprot: 0,
  }
  let _layout_ref = layout
  let layout_name = layout.name
  let layout_sections_len = layout.section_indices.length()
  let layout_fileoff = layout.fileoff
  let layout_filesize = layout.filesize
  let layout_maxprot = layout.maxprot
  let layout_initprot = layout.initprot
  let write_macho_object_ref = write_macho_object

  // object helpers
  let new_section_ref = new_section
  let reloc_addend_ref = reloc_addend

  // sem helper
  let type_contains_vla_ref = type_contains_vla

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
    tok_land_ref,
    tok_lor_ref,
    rc_iret_ref,
    rc_fret_ref,
    vdup_ref,
    format_diag_ref,
    _layout_ref,
    layout_name,
    layout_sections_len,
    layout_fileoff,
    layout_filesize,
    layout_maxprot,
    layout_initprot,
    write_macho_object_ref,
    new_section_ref,
    reloc_addend_ref,
    type_contains_vla_ref,
  )
}
