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
fn ev_sig(e : Event) -> (Int, Int, Double, Int) {
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
extern "C" fn runtime_now_set_for_test(ms : Int64) -> Unit = "moon_gamepad_now_ms_set_for_test"

///|
extern "C" fn runtime_now_clear_for_test() -> Unit = "moon_gamepad_now_ms_clear_for_test"

///|
test "native remap: digital button emits edge then value" {
  let g = Gilrs::new_mock(1, update_state=true, default_filters=false)
  g.gamepads_data[0].buttons = [BTN_SOUTH]
  g.gamepads_data[0].axes = []
  g.apply_identity_mapping(0)
  g.push_native_event({
    tag: NativeEventTag::ButtonPressed,
    id: 0,
    code: BTN_SOUTH,
    value: 1.0,
    time_ms: 10L,
  })
  let e1 = match g.next_event() {
    None => return
    Some(e) => e
  }
  let e2 = match g.next_event() {
    None => return
    Some(e) => e
  }
  inspect(
    [ev_sig(e1), ev_sig(e2)],
    content="[(1, 0, 1, 589825), (2, 0, 1, 589825)]",
  )
}

///|
test "native remap: button mapped to axis produces axis change" {
  let g = Gilrs::new_mock(1, update_state=true, default_filters=false)
  let m = Mapping::new_default()
  m.insert(BTN_DPAD_UP, AxisOrBtn::Axis(Axis::DPadY))
  g.gamepads_data[0].mapping = m
  g.push_native_event({
    tag: NativeEventTag::ButtonPressed,
    id: 0,
    code: BTN_DPAD_UP,
    value: 1.0,
    time_ms: 1L,
  })
  let e1 = match g.next_event() {
    None => return
    Some(e) => e
  }
  inspect(ev_sig(e1), content="(0, 7, 1, 589840)")
}

///|
test "native remap: axis mapped to button uses thresholds" {
  let g = Gilrs::new_mock(1, update_state=true, default_filters=false)
  g.gamepads_data[0].buttons = []
  g.gamepads_data[0].axes = [AXIS_LT2]
  g.gamepads_data[0].axis_info = [(AXIS_LT2, AxisInfo::new(0, 4, None))]
  g.apply_identity_mapping(0)

  // 0.0 -> ButtonChanged
  g.push_native_event({
    tag: NativeEventTag::AxisChanged,
    id: 0,
    code: AXIS_LT2,
    value: 0.0,
    time_ms: 1L,
  })
  let e1 = match g.next_event() {
    None => return
    Some(e) => e
  }
  inspect(ev_sig(e1), content="(2, 8, 0, 131269)")

  // 0.75 -> edge + value
  g.push_native_event({
    tag: NativeEventTag::AxisChanged,
    id: 0,
    code: AXIS_LT2,
    value: 3.0,
    time_ms: 2L,
  })
  let e2 = match g.next_event() {
    None => return
    Some(e) => e
  }
  let e3 = match g.next_event() {
    None => return
    Some(e) => e
  }
  inspect(
    [ev_sig(e2), ev_sig(e3)],
    content="[(1, 8, 1, 131269), (2, 8, 0.75, 131269)]",
  )

  // 1.0 -> ButtonChanged only
  g.push_native_event({
    tag: NativeEventTag::AxisChanged,
    id: 0,
    code: AXIS_LT2,
    value: 4.0,
    time_ms: 3L,
  })
  let e4 = match g.next_event() {
    None => return
    Some(e) => e
  }
  inspect(ev_sig(e4), content="(2, 8, 1, 131269)")

  // 0.5 -> release edge + value
  g.push_native_event({
    tag: NativeEventTag::AxisChanged,
    id: 0,
    code: AXIS_LT2,
    value: 2.0,
    time_ms: 4L,
  })
  let e5 = match g.next_event() {
    None => return
    Some(e) => e
  }
  let e6 = match g.next_event() {
    None => return
    Some(e) => e
  }
  inspect(
    [ev_sig(e5), ev_sig(e6)],
    content="[(4, 8, 0, 131269), (2, 8, 0.5, 131269)]",
  )
}

///|
test "native remap: axis-to-button threshold edges are inclusive" {
  let g = Gilrs::new_mock(1, update_state=true, default_filters=false)
  g.gamepads_data[0].buttons = []
  g.gamepads_data[0].axes = [AXIS_LT2]
  g.gamepads_data[0].axis_info = [(AXIS_LT2, AxisInfo::new(0, 100, None))]
  g.apply_identity_mapping(0)

  // Exactly at pressed threshold (0.75) should trigger press + changed.
  g.push_native_event({
    tag: NativeEventTag::AxisChanged,
    id: 0,
    code: AXIS_LT2,
    value: 75.0,
    time_ms: 1L,
  })
  let p1 = match g.next_event() {
    None => return
    Some(e) => e
  }
  let p2 = match g.next_event() {
    None => return
    Some(e) => e
  }
  inspect(
    [ev_sig(p1), ev_sig(p2)],
    content="[(1, 8, 1, 131269), (2, 8, 0.75, 131269)]",
  )

  // Exactly at released threshold (0.65) should trigger release + changed.
  g.push_native_event({
    tag: NativeEventTag::AxisChanged,
    id: 0,
    code: AXIS_LT2,
    value: 65.0,
    time_ms: 2L,
  })
  let r1 = match g.next_event() {
    None => return
    Some(e) => e
  }
  let r2 = match g.next_event() {
    None => return
    Some(e) => e
  }
  inspect(
    [ev_sig(r1), ev_sig(r2)],
    content="[(4, 8, 0, 131269), (2, 8, 0.6499999761581421, 131269)]",
  )
}

///|
test "native connected on existing id resets state and rebuilds mapping" {
  let g = Gilrs::new_mock(1, update_state=true, default_filters=false)
  let id = GamepadId::new(0)
  g.gamepads_data[0].buttons = [BTN_SOUTH]
  g.gamepads_data[0].axes = []
  g.apply_identity_mapping(0)

  let custom = Mapping::new()
  custom.insert(BTN_SOUTH, AxisOrBtn::Btn(Button::West))
  g.gamepads_data[0].mapping = custom

  g.update(
    Event::at(id, EventType::ButtonPressed(Button::South, BTN_SOUTH), 1L),
  )
  inspect(g.gamepads_data[0].state.is_pressed(BTN_SOUTH), content="true")

  g.push_native_event({
    tag: NativeEventTag::Connected,
    id: 0,
    code: 0,
    value: 0.0,
    time_ms: 2L,
  })

  let _ = g.next_event()

  inspect(g.gamepads_data[0].state.is_pressed(BTN_SOUTH), content="false")
  let remapped = match g.gamepads_data[0].mapping.map(BTN_SOUTH) {
    Some(AxisOrBtn::Btn(Button::South)) => true
    _ => false
  }
  inspect(remapped, content="true")
}

///|
test "repeat filter ignores disconnected gamepads" {
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)
  g.gamepads_data[0].buttons = [BTN_SOUTH]
  g.gamepads_data[0].axes = []
  g.apply_identity_mapping(0)

  g.update(
    Event::at(id, EventType::ButtonPressed(Button::South, BTN_SOUTH), 0L),
  )
  g.push_native_event({
    tag: NativeEventTag::Disconnected,
    id: 0,
    code: 0,
    value: 0.0,
    time_ms: 1L,
  })
  g.set_time(500L)
  let out = Repeat::new().filter(None, g)
  inspect(out is None, content="true")
}

///|
test "repeat filter scans connected ids only" {
  let g = Gilrs::new_mock(2, update_state=false, default_filters=false)
  let id0 = GamepadId::new(0)
  let id1 = GamepadId::new(1)
  g.gamepads_data[0].buttons = [BTN_SOUTH]
  g.gamepads_data[0].axes = []
  g.gamepads_data[1].buttons = [BTN_EAST]
  g.gamepads_data[1].axes = []
  g.apply_identity_mapping(0)
  g.apply_identity_mapping(1)

  g.update(
    Event::at(id0, EventType::ButtonPressed(Button::South, BTN_SOUTH), 0L),
  )
  g.update(Event::at(id1, EventType::ButtonPressed(Button::East, BTN_EAST), 0L))
  g.push_native_event({
    tag: NativeEventTag::Disconnected,
    id: 0,
    code: 0,
    value: 0.0,
    time_ms: 1L,
  })
  g.set_time(500L)

  let out = Repeat::new().filter(None, g)
  inspect(
    out.map(fn(e) { (e.id().value(), ev_sig(e)) }),
    content="Some((1, (3, 1, 0, 589826)))",
  )
}

///|
test "repeat uses runtime clock fallback when logical clock is unset" {
  runtime_now_set_for_test(650L)
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)
  g.gamepads_data[0].buttons = [BTN_SOUTH]
  g.gamepads_data[0].axes = []
  g.apply_identity_mapping(0)
  g.update(
    Event::at(id, EventType::ButtonPressed(Button::South, BTN_SOUTH), 100L),
  )
  g.set_time(0L)
  let out = Repeat::new().filter(None, g)
  runtime_now_clear_for_test()
  inspect(out.map(ev_sig), content="Some((3, 0, 0, 589825))")
}

///|
test "repeat prefers explicit logical clock over runtime clock" {
  runtime_now_set_for_test(2000L)
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)
  g.gamepads_data[0].buttons = [BTN_SOUTH]
  g.gamepads_data[0].axes = []
  g.apply_identity_mapping(0)
  g.update(
    Event::at(id, EventType::ButtonPressed(Button::South, BTN_SOUTH), 100L),
  )
  g.set_time(500L)
  let out = Repeat::new().filter(None, g)
  runtime_now_clear_for_test()
  inspect(out is None, content="true")
}

///|
test "set_mapping_data updates mapping and returns SDL line" {
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)
  g.gamepads_data[0].buttons = [BTN_SOUTH]
  g.gamepads_data[0].axes = [AXIS_LSTICKX]
  g.gamepads_data[0].name = "Mock Pad"

  let data = MappingData::new()
  ignore(data.insert_btn(BTN_SOUTH, Button::South))
  let s = g.set_mapping_data(id, data, name=Some("Custom Pad"))

  let mapped_ok = match g.mapping(id).unwrap().map(BTN_SOUTH) {
    Some(AxisOrBtn::Btn(Button::South)) => true
    _ => false
  }
  inspect(mapped_ok, content="true")
  inspect(s.contains(",Custom Pad,"), content="true")
}

///|
test "set_mapping_data returns NotConnected for disconnected gamepad" {
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)
  g.push_native_event({
    tag: NativeEventTag::Disconnected,
    id: 0,
    code: 0,
    value: 0.0,
    time_ms: 1L,
  })

  let data = MappingData::new()
  ignore(data.insert_btn(BTN_SOUTH, Button::South))
  let res : Result[String, MappingError] = try? g.set_mapping_data(id, data)
  let ok = match res {
    Err(MappingError::NotConnected) => true
    _ => false
  }
  inspect(ok, content="true")
}

///|
test "set_mapping_data_strict rejects SDL-incompatible entries" {
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)
  g.gamepads_data[0].buttons = [BTN_C]
  g.gamepads_data[0].axes = []

  let data = MappingData::new()
  ignore(data.insert_btn(BTN_C, Button::C))
  let res : Result[String, MappingError] = try? g.set_mapping_data_strict(
    id, data,
  )
  let ok = match res {
    Err(MappingError::NotSdl2Compatible) => true
    _ => false
  }
  inspect(ok, content="true")
}

///|
test "connected_gamepad returns None after disconnect while gamepad still exists" {
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)
  inspect(g.connected_gamepad(id) is Some(_), content="true")
  g.push_native_event({
    tag: NativeEventTag::Disconnected,
    id: 0,
    code: 0,
    value: 0.0,
    time_ms: 1L,
  })
  inspect(g.connected_gamepad(id) is None, content="true")
  inspect(g.gamepad(id) is Some(_), content="true")
}

///|
test "gamepad map_name follows mapping default/name semantics" {
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)

  // Unnamed default mapping => None
  g.gamepads_data[0].buttons = [BTN_SOUTH]
  g.gamepads_data[0].axes = []
  g.apply_identity_mapping(0)
  let n0 = g.gamepad(id).unwrap().map_name()
  inspect(n0, content="None")

  // Non-default mapping with custom name => Some(name)
  g.gamepads_data[0].name = "Mock Pad"
  let data = MappingData::new()
  ignore(data.insert_btn(BTN_SOUTH, Button::South))
  ignore(g.set_mapping_data(id, data, name=Some("Named Mapping")))
  let n1 = g.gamepad(id).unwrap().map_name()
  inspect(n1, content="Some(\"Named Mapping\")")
}

///|
test "builder add_mappings loads mapping DB entries" {
  let g = GilrsBuilder::new()
    .with_mock_gamepad_count(1)
    .add_mappings("00000000000000000000000000000000,Pad One,a:b0,")
    .add_mappings("030000005e0400008e02000000000000,Pad Two,a:b0,")
    .build()
  inspect(g.mappings.get(Uuid::nil()) is Some(_), content="true")
  inspect(
    g.mappings.get(Uuid::parse("030000005e0400008e02000000000000")),
    content="Some(\"030000005e0400008e02000000000000,Pad Two,a:b0,\")",
  )
}

///|
test "builder add_mappings participates in connected remap" {
  let g = GilrsBuilder::new()
    .with_mock_gamepad_count(1)
    .add_mappings("00000000000000000000000000000000,Pad From DB,b:b0,")
    .build()
  let id = GamepadId::new(0)
  g.gamepads_data[0].buttons = [BTN_SOUTH]
  g.gamepads_data[0].axes = []

  g.push_native_event({
    tag: NativeEventTag::Connected,
    id: 0,
    code: 0,
    value: 0.0,
    time_ms: 1L,
  })
  ignore(g.next_event())
  let mapped = match g.mapping(id).unwrap().map(BTN_SOUTH) {
    Some(AxisOrBtn::Btn(Button::East)) => true
    _ => false
  }
  inspect(mapped, content="true")
}

///|
test "mapping_source reports Driver for default mapping" {
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)
  g.gamepads_data[0].buttons = [BTN_SOUTH]
  g.gamepads_data[0].axes = []
  g.apply_identity_mapping(0)
  let source = g.gamepad(id).unwrap().mapping_source()
  let ok = match source {
    MappingSource::Driver => true
    _ => false
  }
  inspect(ok, content="true")
}

///|
test "mapping_source reports SdlMappings for parsed SDL mapping" {
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)
  g.gamepads_data[0].buttons = [BTN_SOUTH]
  g.gamepads_data[0].axes = []
  g.gamepads_data[0].name = "Mock Pad"
  let data = MappingData::new()
  ignore(data.insert_btn(BTN_SOUTH, Button::South))
  ignore(g.set_mapping_data(id, data, name=Some("Mapped Pad")))
  let source = g.gamepad(id).unwrap().mapping_source()
  let ok = match source {
    MappingSource::SdlMappings => true
    _ => false
  }
  inspect(ok, content="true")
}

///|
test "mapping_source reports Unmapped for invalid gamepad handle" {
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let ghost : Gamepad = { gilrs: g, id: GamepadId::new(99) }
  let source = ghost.mapping_source()
  let ok = match source {
    MappingSource::Unmapped => true
    _ => false
  }
  inspect(ok, content="true")
}

///|
test "builder set_axis_to_btn wires thresholds into gilrs" {
  let g = GilrsBuilder::new()
    .with_mock_gamepad_count(1)
    .with_default_filters(false)
    .set_axis_to_btn(0.5, 0.4)
    .build()
  inspect(g.axis_to_btn_pressed, content="0.5")
  inspect(g.axis_to_btn_released, content="0.4")
}

///|
test "builder set_axis_to_btn affects axis-to-button press edge" {
  let g = GilrsBuilder::new()
    .with_mock_gamepad_count(1)
    .with_default_filters(false)
    .set_axis_to_btn(0.5, 0.4)
    .build()
  g.gamepads_data[0].buttons = []
  g.gamepads_data[0].axes = [AXIS_LT2]
  g.gamepads_data[0].axis_info = [(AXIS_LT2, AxisInfo::new(0, 100, None))]
  g.apply_identity_mapping(0)

  g.push_native_event({
    tag: NativeEventTag::AxisChanged,
    id: 0,
    code: AXIS_LT2,
    value: 50.0,
    time_ms: 1L,
  })
  let e1 = match g.next_event() {
    None => return
    Some(e) => e
  }
  let e2 = match g.next_event() {
    None => return
    Some(e) => e
  }
  inspect(
    [ev_sig(e1), ev_sig(e2)],
    content="[(1, 8, 1, 131269), (2, 8, 0.5, 131269)]",
  )
}
