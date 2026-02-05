///|
test "force feedback stubs are not supported yet" {
  let g = GilrsBuilder::new().with_mock_gamepad_count(1).build()
  let res : Result[Effect, FfError] = try? EffectBuilder::new().finish(g)
  inspect(res is Err(_), content="true")
}
