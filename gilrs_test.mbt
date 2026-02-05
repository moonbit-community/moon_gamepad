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
test "gilrs fifo + auto update_state" {
  let gilrs = Gilrs::new_mock(1, update_state=true)
  let id = GamepadId::new(0)
  gilrs.insert_event(
    Event::at(id, EventType::ButtonPressed(Button::South, BTN_SOUTH), 10L),
  )
  gilrs.insert_event(
    Event::at(id, EventType::ButtonReleased(Button::South, BTN_SOUTH), 11L),
  )
  let ev1 = gilrs.next_event()
  inspect(ev1 is Some(_), content="true")
  inspect(
    gilrs.state(id).map(fn(s) { s.is_pressed(BTN_SOUTH) }),
    content="Some(true)",
  )
  let c1 = match gilrs.state(id) {
    None => None
    Some(s) => s.button_data(BTN_SOUTH).map(fn(d) { d.counter() })
  }
  inspect(c1, content="Some(0)")
  gilrs.inc()
  let ev2 = gilrs.next_event()
  inspect(ev2 is Some(_), content="true")
  inspect(
    gilrs.state(id).map(fn(s) { s.is_pressed(BTN_SOUTH) }),
    content="Some(false)",
  )
  let c2 = match gilrs.state(id) {
    None => None
    Some(s) => s.button_data(BTN_SOUTH).map(fn(d) { d.counter() })
  }
  inspect(c2, content="Some(1)")
}

///|
test "gilrs no auto update when disabled" {
  let gilrs = Gilrs::new_mock(1, update_state=false)
  let id = GamepadId::new(0)
  gilrs.insert_event(
    Event::at(id, EventType::ButtonPressed(Button::South, BTN_SOUTH), 10L),
  )
  let _ = gilrs.next_event()
  inspect(
    gilrs.state(id).map(fn(s) { s.is_pressed(BTN_SOUTH) }),
    content="Some(false)",
  )
  gilrs.update(
    Event::at(id, EventType::ButtonPressed(Button::South, BTN_SOUTH), 10L),
  )
  inspect(
    gilrs.state(id).map(fn(s) { s.is_pressed(BTN_SOUTH) }),
    content="Some(true)",
  )
}

///|
fn gilrs_event_sig(e : Event) -> (Int, Int, Double, Int) {
  match e.event() {
    EventType::AxisChanged(axis, val, code) => (0, axis.to_index(), val, code)
    EventType::ButtonPressed(btn, code) => (1, btn.to_index(), 1.0, code)
    EventType::ButtonChanged(btn, val, code) => (2, btn.to_index(), val, code)
    EventType::ButtonReleased(btn, code) => (4, btn.to_index(), 0.0, code)
    _ => (99, 0, 0.0, 0)
  }
}

///|
test "gilrs next_event applies default filters by default" {
  let g = Gilrs::new_mock(1, update_state=true)
  let id = GamepadId::new(0)

  // seed state so jitter can compare
  g.insert_event(
    Event::at(
      id,
      EventType::AxisChanged(Axis::LeftStickX, 0.5, AXIS_LSTICKX),
      1L,
    ),
  )
  let _ = g.next_event()

  // small delta should be dropped; next_event skips dropped events
  g.insert_event(
    Event::at(
      id,
      EventType::AxisChanged(Axis::LeftStickX, 0.505, AXIS_LSTICKX),
      2L,
    ),
  )
  inspect(g.next_event() is None, content="true")
}

///|
test "gilrs builder can disable default filters" {
  let g = GilrsBuilder::new()
    .with_mock_gamepad_count(1)
    .set_update_state(true)
    .with_default_filters(false)
    .build()
  let id = GamepadId::new(0)
  g.insert_event(
    Event::at(
      id,
      EventType::AxisChanged(Axis::LeftStickX, 0.5, AXIS_LSTICKX),
      1L,
    ),
  )
  let _ = g.next_event()
  g.insert_event(
    Event::at(
      id,
      EventType::AxisChanged(Axis::LeftStickX, 0.505, AXIS_LSTICKX),
      2L,
    ),
  )
  inspect(
    g.next_event().map(gilrs_event_sig),
    content="Some((0, 0, 0.505, 100))",
  )
}

///|
test "gilrs next_event runs axis_dpad_to_button in default pipeline" {
  let g = Gilrs::new_mock(1, update_state=true)
  let id = GamepadId::new(0)
  let m = Mapping::new()
  m.set_hats_mapped(0b1111)
  g.set_mapping(id, m)
  g.insert_event(
    Event::at(id, EventType::AxisChanged(Axis::DPadX, 1.0, AXIS_DPADX), 1L),
  )
  inspect(g.next_event().map(gilrs_event_sig), content="Some((1, 18, 1, 18))")
  inspect(g.next_event().map(gilrs_event_sig), content="Some((2, 18, 1, 18))")
}

///|
test "gilrs next_event_blocking timeout 0 behaves like next_event (mock)" {
  let g = Gilrs::new_mock(1)
  inspect(g.next_event_blocking(Some(0L)) is None, content="true")
  let id = GamepadId::new(0)
  g.insert_event(Event::at(id, EventType::Connected, 1L))
  let got = g
    .next_event_blocking(Some(0L))
    .map(fn(ev) {
      match ev.event() {
        EventType::Connected => 1
        _ => 0
      }
    })
  inspect(got, content="Some(1)")
}

///|
test "gamepad power_info default is Unknown (mock)" {
  let g = Gilrs::new_mock(1)
  let id = GamepadId::new(0)
  let p = g
    .gamepad(id)
    .map(fn(gp) {
      match gp.power_info() {
        PowerInfo::Unknown => 0
        _ => 1
      }
    })
  inspect(p, content="Some(0)")
}
