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
test "gil fifo + auto update_state" {
  let gil = Gil::new_mock(1, update_state=true)
  let id = GamepadId::new(0)
  gil.insert_event(
    Event::at(id, EventType::ButtonPressed(Button::South, BTN_SOUTH), 10L),
  )
  gil.insert_event(
    Event::at(id, EventType::ButtonReleased(Button::South, BTN_SOUTH), 11L),
  )
  let ev1 = gil.next_event()
  inspect(ev1 is Some(_), content="true")
  inspect(
    gil.state(id).map(fn(s) { s.is_pressed(BTN_SOUTH) }),
    content="Some(true)",
  )
  let c1 = match gil.state(id) {
    None => None
    Some(s) => s.button_data(BTN_SOUTH).map(fn(d) { d.counter() })
  }
  inspect(c1, content="Some(0)")
  gil.inc()
  let ev2 = gil.next_event()
  inspect(ev2 is Some(_), content="true")
  inspect(
    gil.state(id).map(fn(s) { s.is_pressed(BTN_SOUTH) }),
    content="Some(false)",
  )
  let c2 = match gil.state(id) {
    None => None
    Some(s) => s.button_data(BTN_SOUTH).map(fn(d) { d.counter() })
  }
  inspect(c2, content="Some(1)")
}

///|
test "gil no auto update when disabled" {
  let gil = Gil::new_mock(1, update_state=false)
  let id = GamepadId::new(0)
  gil.insert_event(
    Event::at(id, EventType::ButtonPressed(Button::South, BTN_SOUTH), 10L),
  )
  let _ = gil.next_event()
  inspect(
    gil.state(id).map(fn(s) { s.is_pressed(BTN_SOUTH) }),
    content="Some(false)",
  )
  gil.update(
    Event::at(id, EventType::ButtonPressed(Button::South, BTN_SOUTH), 10L),
  )
  inspect(
    gil.state(id).map(fn(s) { s.is_pressed(BTN_SOUTH) }),
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
fn build_ok_gilrs(builder : GilBuilder) -> Gil {
  let res : Result[Gil, GilError] = try? builder.build()
  match res {
    Ok(g) => g
    Err(_) => Gil::new_mock(0, update_state=false, default_filters=false)
  }
}

///|
test "gil next_event applies default filters by default" {
  let g = Gil::new_mock(1, update_state=true)
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
test "gil builder can disable default filters" {
  let g = build_ok_gilrs(
    GilBuilder::new()
    .with_mock_gamepad_count(1)
    .set_update_state(true)
    .with_default_filters(false),
  )
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
    content="Some((0, 0, 0.505, 65584))",
  )
}

///|
test "gil returns dropped when default filters are disabled" {
  let g = Gil::new_mock(1, update_state=true, default_filters=false)
  let id = GamepadId::new(0)
  g.insert_event(Event::at(id, EventType::Dropped, 1L))
  let got = g
    .next_event()
    .map(fn(ev) {
      match ev.event() {
        EventType::Dropped => 1
        _ => 0
      }
    })
  inspect(got, content="Some(1)")
}

///|
test "gil update ignores connection events but next_event syncs connection" {
  let g = Gil::new_mock(1, update_state=true, default_filters=false)
  let id = GamepadId::new(0)
  g.update(Event::at(id, EventType::Disconnected, 1L))
  inspect(g.gamepad(id).map(fn(gp) { gp.is_connected() }), content="Some(true)")
  g.insert_event(Event::at(id, EventType::Disconnected, 2L))
  ignore(g.next_event())
  inspect(
    g.gamepad(id).map(fn(gp) { gp.is_connected() }),
    content="Some(false)",
  )
}

///|
test "gil next_event runs axis_dpad_to_button in default pipeline" {
  let g = Gil::new_mock(1, update_state=true)
  let id = GamepadId::new(0)
  let m = Mapping::new()
  m.set_hats_mapped(0b1111)
  g.set_mapping(id, m)
  g.insert_event(
    Event::at(id, EventType::AxisChanged(Axis::DPadX, 1.0, AXIS_DPADX), 1L),
  )
  inspect(
    g.next_event().map(gilrs_event_sig),
    content="Some((1, 18, 1, 589843))",
  )
  inspect(
    g.next_event().map(gilrs_event_sig),
    content="Some((2, 18, 1, 589843))",
  )
}

///|
test "gil next_event_blocking timeout 0 behaves like next_event (mock)" {
  let g = Gil::new_mock(1)
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
  let g = Gil::new_mock(1)
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

///|
test "gamepad is_ff_supported default is false (mock)" {
  let g = Gil::new_mock(1)
  let id = GamepadId::new(0)
  let supported = g.gamepad(id).map(fn(gp) { gp.is_ff_supported() })
  inspect(supported, content="Some(false)")
}

///|
test "gil keeps historical disconnected ids after reconnect-style sequence" {
  let g = Gil::new_mock(2)
  let id0 = GamepadId::new(0)
  let id1 = GamepadId::new(1)
  g.insert_event(Event::at(id0, EventType::Connected, 1L))
  g.insert_event(Event::at(id0, EventType::Disconnected, 2L))
  g.insert_event(Event::at(id1, EventType::Connected, 3L))
  let t1 = g
    .next_event()
    .map(fn(ev) {
      match ev.event() {
        EventType::Connected => 1
        EventType::Disconnected => 2
        _ => 0
      }
    })
  let t2 = g
    .next_event()
    .map(fn(ev) {
      match ev.event() {
        EventType::Connected => 1
        EventType::Disconnected => 2
        _ => 0
      }
    })
  let t3 = g
    .next_event()
    .map(fn(ev) {
      match ev.event() {
        EventType::Connected => 1
        EventType::Disconnected => 2
        _ => 0
      }
    })
  inspect((t1, t2, t3), content="(Some(1), Some(2), Some(1))")
  inspect(
    g.gamepad(id0).map(fn(gp) { gp.is_connected() }),
    content="Some(false)",
  )
  inspect(
    g.gamepad(id1).map(fn(gp) { gp.is_connected() }),
    content="Some(true)",
  )
  inspect(
    g
    .gamepads()
    .map(fn(pair) {
      let (id, _) = pair
      id.value()
    }),
    content="[1]",
  )
}
