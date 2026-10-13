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
fn core_event_sig(e : @gamepad.Event) -> (Int32, Int32, Double, Int32) {
  match e.event() {
    AxisChanged(axis, val, code) => (0, axis.to_index(), val, code)
    ButtonPressed(btn, code) => (1, btn.to_index(), 1.0, code)
    ButtonChanged(btn, val, code) => (2, btn.to_index(), val, code)
    ButtonRepeated(btn, code) => (3, btn.to_index(), 0.0, code)
    ButtonReleased(btn, code) => (4, btn.to_index(), 0.0, code)
    _ => (99, 0, 0.0, 0)
  }
}

///|
fn build_ok_core(builder : @gamepad.GilBuilder) -> @gamepad.Gil {
  let res : Result[@gamepad.Gil, @gamepad.GilError] = try
    builder.build() |> Ok
  catch {
    e => Err(e)
  }
  match res {
    Ok(g) => g
    Err(_) =>
      @gamepad.Gil::new_mock(0, update_state=false, default_filters=false)
  }
}

///|
test "gil next_event default filters skip dropped" {
  let g = @gamepad.Gil::new_mock(1, update_state=true, default_filters=true)
  let id = @gamepad.GamepadId::new(0)
  g.insert_event(
    @gamepad.Event::at(
      id,
      AxisChanged(LeftStickX, 0.5, @gamepad.AXIS_LSTICKX),
      1L,
    ),
  )
  g.insert_event(
    @gamepad.Event::at(
      id,
      AxisChanged(LeftStickX, 0.505, @gamepad.AXIS_LSTICKX),
      2L,
    ),
  )
  g.insert_event(
    @gamepad.Event::at(
      id,
      AxisChanged(LeftStickX, 0.7, @gamepad.AXIS_LSTICKX),
      3L,
    ),
  )
  let ev1 = g.next_event()
  debug_inspect(ev1.map(core_event_sig), content="Some((0, 0, 0.5, 65584))")
  let ev2 = g.next_event()
  // The small-delta event is dropped by Jitter and skipped.
  debug_inspect(ev2.map(core_event_sig), content="Some((0, 0, 0.7, 65584))")
  debug_inspect(
    g.state(id).map(fn(s) { s.value(@gamepad.AXIS_LSTICKX) }),
    content="Some(0.7)",
  )
  inspect(g.next_event() is None, content="true")
}

///|
test "builder build_mock wires flags" {
  let b = @gamepad.GilBuilder::new()
    .with_default_filters(true)
    .set_update_state(false)
    .with_mock_gamepad_count(1)
  let g = build_ok_core(b)
  inspect(g.default_filters_enabled(), content="true")
  inspect(g.update_state_enabled(), content="false")
}

///|
test "builder rejects invalid axis_to_btn thresholds" {
  let bad : Result[@gamepad.Gil, @gamepad.GilError] = try
    @gamepad.GilBuilder::new().set_axis_to_btn(0.4, 0.5).build() |> Ok
  catch {
    e => Err(e)
  }
  let is_invalid = match bad {
    Ok(_) => false
    Err(e) => e.is_invalid_axis_to_btn()
  }
  inspect(is_invalid, content="true")
}

///|
test "gamepad handle delegates mapping/state" {
  let g = build_ok_core(
    @gamepad.GilBuilder::new()
    .with_default_filters(false)
    .set_update_state(false)
    .with_mock_gamepad_count(1),
  )
  let id = @gamepad.GamepadId::new(0)
  let m = @gamepad.Mapping::new()
  m.insert(@gamepad.BTN_SOUTH, Btn(South))
  m.insert(@gamepad.AXIS_LSTICKX, Axis(LeftStickX))
  g.set_mapping(id, m)
  let gp = g.gamepad(id).unwrap()
  let ok = match gp.axis_or_btn_name(@gamepad.BTN_SOUTH) {
    Some(Btn(South)) => true
    _ => false
  }
  inspect(ok, content="true")
  g.update(@gamepad.Event::at(id, ButtonPressed(South, @gamepad.BTN_SOUTH), 0L))
  g.update(
    @gamepad.Event::at(
      id,
      AxisChanged(LeftStickX, 0.25, @gamepad.AXIS_LSTICKX),
      1L,
    ),
  )
  let gp2 = g.gamepad(id).unwrap()
  inspect(gp2.is_pressed(South), content="true")
  inspect(gp2.value(LeftStickX), content="0.25")
  debug_inspect(
    gp2.button_data(South).map(fn(d) { d.is_pressed() }),
    content="Some(true)",
  )
  debug_inspect(
    gp2.axis_data(LeftStickX).map(fn(d) { d.value() }),
    content="Some(0.25)",
  )
}

///|
test "gamepad name/map_name/os_name semantics" {
  let g = @gamepad.Gil::new_mock(1, update_state=false, default_filters=false)
  let id = @gamepad.GamepadId::new(0)
  let gp0 = g.gamepad(id).unwrap()
  let os_name = gp0.os_name()
  debug_inspect(gp0.map_name(), content="Some(\"\")")
  inspect(gp0.name() == os_name, content="true")

  let data = @gamepad.MappingData::new()
  ignore(g.set_mapping_data(id, data, name=Some("Mapped Pad")))
  let gp1 = g.gamepad(id).unwrap()
  debug_inspect(gp1.map_name(), content="Some(\"Mapped Pad\")")
  inspect(gp1.name(), content="Mapped Pad")
  inspect(gp1.os_name() == os_name, content="true")
}

///|
test "gamepad semantic accessors follow gil mapping rules" {
  let g = @gamepad.Gil::new_mock(1, update_state=false, default_filters=false)
  let id = @gamepad.GamepadId::new(0)
  g.update(@gamepad.Event::at(id, ButtonPressed(South, @gamepad.BTN_SOUTH), 0L))
  g.update(
    @gamepad.Event::at(
      id,
      AxisChanged(LeftStickX, 0.42, @gamepad.AXIS_LSTICKX),
      1L,
    ),
  )
  let gp = g.gamepad(id).unwrap()
  inspect(gp.is_pressed(South), content="true")
  inspect(gp.value(LeftStickX), content="0")
  inspect(gp.button_data(South) is None, content="true")
  inspect(gp.axis_data(LeftStickX) is None, content="true")
}
