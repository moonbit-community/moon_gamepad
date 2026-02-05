// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
fn core_event_sig(e : Event) -> (Int, Int, Double, Int) {
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
test "gilrs next_event default filters skip dropped" {
  let g = Gilrs::new_mock(1, update_state=true, default_filters=true)
  let id = GamepadId::new(0)
  g.insert_event(
    Event::at(
      id,
      EventType::AxisChanged(Axis::LeftStickX, 0.5, AXIS_LSTICKX),
      1L,
    ),
  )
  g.insert_event(
    Event::at(
      id,
      EventType::AxisChanged(Axis::LeftStickX, 0.505, AXIS_LSTICKX),
      2L,
    ),
  )
  g.insert_event(
    Event::at(
      id,
      EventType::AxisChanged(Axis::LeftStickX, 0.7, AXIS_LSTICKX),
      3L,
    ),
  )
  let ev1 = g.next_event()
  inspect(ev1.map(core_event_sig), content="Some((0, 0, 0.5, 100))")
  let ev2 = g.next_event()
  // The small-delta event is dropped by Jitter and skipped.
  inspect(ev2.map(core_event_sig), content="Some((0, 0, 0.7, 100))")
  inspect(g.state(id).map(fn(s) { s.value(AXIS_LSTICKX) }), content="Some(0.7)")
  inspect(g.next_event() is None, content="true")
}

///|
test "builder build_mock wires flags" {
  let b = GilrsBuilder::new()
    .with_default_filters(true)
    .set_update_state(false)
    .with_mock_gamepad_count(1)
  let g = b.build()
  inspect(g.default_filters_enabled(), content="true")
  inspect(g.update_state_enabled(), content="false")
}

///|
test "gamepad handle delegates mapping/state" {
  let g = GilrsBuilder::new()
    .with_default_filters(false)
    .set_update_state(false)
    .with_mock_gamepad_count(1)
    .build()
  let id = GamepadId::new(0)
  let m = Mapping::new()
  m.insert(BTN_SOUTH, AxisOrBtn::Btn(Button::South))
  g.set_mapping(id, m)
  let gp = g.gamepad(id).unwrap()
  let ok = match gp.axis_or_btn_name(BTN_SOUTH) {
    Some(AxisOrBtn::Btn(Button::South)) => true
    _ => false
  }
  inspect(ok, content="true")
  g.update(
    Event::at(id, EventType::ButtonPressed(Button::South, BTN_SOUTH), 0L),
  )
  inspect(g.gamepad(id).unwrap().is_pressed(BTN_SOUTH), content="true")
}
