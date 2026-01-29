///|
test "arm64 emit32 advances code_len" {
  let emitter = @arm64.new_arm64_emitter()
  @arm64.emit32(emitter, (0x14000000 : UInt))
  assert_eq(emitter.code_len, 1)
  assert_eq(emitter.code[0], (0x14000000 : UInt))
}
