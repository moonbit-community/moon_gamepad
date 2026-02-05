///|
test "state update + readback" {
  let s = GamepadState::new()
  s.set_btn_pressed(BTN_SOUTH, true, 1L, 100L)
  inspect(s.is_pressed(BTN_SOUTH), content="true")
  inspect(s.value(BTN_SOUTH), content="1")
  s.set_btn_pressed(BTN_SOUTH, false, 2L, 110L)
  inspect(s.is_pressed(BTN_SOUTH), content="false")
  inspect(s.value(BTN_SOUTH), content="1")
  s.set_btn_value(BTN_SOUTH, 0.25, 3L, 120L)
  inspect(s.value(BTN_SOUTH), content="0.25")
  s.set_btn_repeating(BTN_SOUTH, 4L, 130L)
  inspect(
    s.button_data(BTN_SOUTH).map(fn(d) { d.is_repeating() }),
    content="Some(true)",
  )
  s.set_axis_value(AXIS_LSTICKX, -0.5, 5L, 200L)
  inspect(s.value(AXIS_LSTICKX), content="-0.5")
  inspect(
    s.axis_data(AXIS_LSTICKX).map(fn(d) { d.counter() }),
    content="Some(5)",
  )
}
