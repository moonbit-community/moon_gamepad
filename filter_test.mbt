///|
test "jitter drops small delta" {
  let g = Gilrs::new_mock(1, update_state=true)
  let id = GamepadId::new(0)

  // seed state
  g.insert_event(
    Event::at(
      id,
      EventType::AxisChanged(Axis::LeftStickX, 0.5, AXIS_LSTICKX),
      1L,
    ),
  )
  ignore(g.next_event())

  // small delta should drop
  let ev = Event::at(
    id,
    EventType::AxisChanged(Axis::LeftStickX, 0.505, AXIS_LSTICKX),
    2L,
  )
  let out = Jitter::new().filter(Some(ev), g)
  inspect(out.map(fn(e) { e.is_dropped() }), content="Some(true)")
}

///|
fn filter_event_sig(e : Event) -> (Int, Int, Double, Int) {
  match e.event() {
    EventType::AxisChanged(axis, val, code) => (0, axis.to_index(), val, code)
    EventType::ButtonPressed(btn, code) => (1, btn.to_index(), 1.0, code)
    EventType::ButtonChanged(btn, val, code) => (2, btn.to_index(), val, code)
    EventType::ButtonRepeated(btn, code) => (3, btn.to_index(), 0.0, code)
    EventType::ButtonReleased(btn, code) => (4, btn.to_index(), 0.0, code)
    _ => (99, 0, 0.0, 0)
  }
}

///|
test "deadzone clamps axis and preserves range" {
  let g = Gilrs::new_mock(1, update_state=true)
  let id = GamepadId::new(0)
  g.set_deadzone(id, AXIS_LSTICKX, 0.2)
  let ev = Event::at(
    id,
    EventType::AxisChanged(Axis::LeftStickX, 0.1, AXIS_LSTICKX),
    1L,
  )
  let out = deadzone(Some(ev), g)
  inspect(out.map(filter_event_sig), content="Some((99, 0, 0, 0))")
}

///|
test "axis_dpad_to_button maps dpad axis to button events" {
  let g = Gilrs::new_mock(1, update_state=true)
  let id = GamepadId::new(0)

  // mapping with hats mapped to allow mapping
  let m = Mapping::new()
  m.set_hats_mapped(0b1111)
  g.set_mapping(id, m)
  let ev = Event::at(
    id,
    EventType::AxisChanged(Axis::DPadX, 1.0, AXIS_DPADX),
    1L,
  )
  let out = axis_dpad_to_button(Some(ev), g)
  inspect(out.map(filter_event_sig), content="Some((1, 18, 1, 18))")
  // extra queued event should exist
  let extra = g.next_event()
  inspect(extra.map(filter_event_sig), content="Some((2, 18, 1, 18))")
}

///|
test "repeat generates repeated events on None" {
  let g = Gilrs::new_mock(1, update_state=false)
  let id = GamepadId::new(0)
  // mapping so Repeat can name the button
  let m = Mapping::new()
  m.insert(BTN_SOUTH, AxisOrBtn::Btn(Button::South))
  g.set_mapping(id, m)

  // pressed at t=0
  g.update(
    Event::at(id, EventType::ButtonPressed(Button::South, BTN_SOUTH), 0L),
  )
  g.set_time(500L)
  let rep = Repeat::new()
  let out1 = rep.filter(None, g)
  inspect(out1.map(filter_event_sig), content="Some((3, 0, 0, 0))")
  // update state with repeat, then next repeat at +30ms
  g.update(out1.unwrap())
  g.set_time(530L)
  let out2 = rep.filter(None, g)
  inspect(out2.map(filter_event_sig), content="Some((3, 0, 0, 0))")
}
