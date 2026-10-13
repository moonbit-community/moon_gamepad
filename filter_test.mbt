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
test "jitter drops small delta" {
  let g = @gamepad.Gil::new_mock(1, update_state=true)
  let id = @gamepad.GamepadId::new(0)

  // seed state
  g.insert_event(
    @gamepad.Event::at(
      id,
      AxisChanged(LeftStickX, 0.5, @gamepad.AXIS_LSTICKX),
      1L,
    ),
  )
  ignore(g.next_event())

  // small delta should drop
  let ev = @gamepad.Event::at(
    id,
    AxisChanged(LeftStickX, 0.505, @gamepad.AXIS_LSTICKX),
    2L,
  )
  let out = @gamepad.Jitter::new().filter(Some(ev), g)
  debug_inspect(out.map(fn(e) { e.is_dropped() }), content="Some(true)")
}

///|
extern "C" fn runtime_now_set_for_test(ms : Int64) -> Unit = "moon_gamepad_now_ms_set_for_test"

///|
extern "C" fn runtime_now_clear_for_test() -> Unit = "moon_gamepad_now_ms_clear_for_test"

///|
test "jitter keeps first axis event without prior axis_data" {
  let g = @gamepad.Gil::new_mock(1, update_state=true)
  let id = @gamepad.GamepadId::new(0)
  let ev = @gamepad.Event::at(
    id,
    AxisChanged(LeftStickX, 0.005, @gamepad.AXIS_LSTICKX),
    1L,
  )
  let out = @gamepad.Jitter::new().filter(Some(ev), g)
  debug_inspect(out.map(filter_event_sig), content="Some((0, 0, 0.005, 65584))")
}

///|
test "filter_ev passes through filter output" {
  let g = @gamepad.Gil::new_mock(1, update_state=false, default_filters=false)
  let id = @gamepad.GamepadId::new(0)
  let ev = @gamepad.Event::at(id, ButtonPressed(South, @gamepad.BTN_SOUTH), 1L)
  let out = @gamepad.filter_ev(
    Some(ev),
    fn(_ev : @gamepad.Event?, _gilrs : @gamepad.Gil) -> @gamepad.Event? { None },
    g,
  )
  debug_inspect(out.map(fn(e) { e.is_dropped() }), content="Some(true)")
}

///|
fn filter_event_sig(e : @gamepad.Event) -> (Int32, Int32, Double, Int32) {
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
test "deadzone clamps axis and preserves range" {
  let g = @gamepad.Gil::new_mock(1, update_state=true)
  let id = @gamepad.GamepadId::new(0)
  g.set_deadzone(id, @gamepad.AXIS_LSTICKX, 0.2)
  let ev = @gamepad.Event::at(
    id,
    AxisChanged(LeftStickX, 0.1, @gamepad.AXIS_LSTICKX),
    1L,
  )
  let out = @gamepad.deadzone(Some(ev), g)
  debug_inspect(out.map(filter_event_sig), content="Some((99, 0, 0, 0))")
}

///|
test "deadzone enqueues paired-axis zero when primary event drops" {
  let g = @gamepad.Gil::new_mock(1, update_state=false, default_filters=false)
  let id = @gamepad.GamepadId::new(0)
  g.set_deadzone(id, @gamepad.AXIS_LSTICKX, 0.2)
  g.set_deadzone(id, @gamepad.AXIS_LSTICKY, 0.2)
  let m = @gamepad.Mapping::new()
  m.insert(@gamepad.AXIS_LSTICKX, Axis(LeftStickX))
  m.insert(@gamepad.AXIS_LSTICKY, Axis(LeftStickY))
  g.set_mapping(id, m)

  // Seed non-zero X through deadzone so paired-axis clear path can trigger later.
  let seed = @gamepad.Event::at(
    id,
    AxisChanged(LeftStickX, 0.3, @gamepad.AXIS_LSTICKX),
    1L,
  )
  let seed_out = @gamepad.deadzone(Some(seed), g).unwrap()
  g.update(seed_out)

  // Y event lands both axes in deadzone; Y gets dropped, X clear is queued.
  let ev = @gamepad.Event::at(
    id,
    AxisChanged(LeftStickY, 0.0, @gamepad.AXIS_LSTICKY),
    2L,
  )
  let out = @gamepad.deadzone(Some(ev), g).unwrap()
  inspect(out.is_dropped(), content="true")
  let queued = g.next_event()
  debug_inspect(queued.map(filter_event_sig), content="Some((0, 0, 0, 65584))")
  inspect(g.gamepads_data[0].have_sent_nonzero_for_axis[2], content="false")
}

///|
test "deadzone button branch drops or emits changed value" {
  let g = @gamepad.Gil::new_mock(1, update_state=false, default_filters=false)
  let id = @gamepad.GamepadId::new(0)
  g.set_deadzone(id, @gamepad.BTN_SOUTH, 0.2)

  // 0.1 falls into deadzone => dropped.
  let ev1 = @gamepad.Event::at(
    id,
    ButtonChanged(South, 0.1, @gamepad.BTN_SOUTH),
    1L,
  )
  let out1 = @gamepad.deadzone(Some(ev1), g)
  debug_inspect(out1.map(fn(e) { e.is_dropped() }), content="Some(true)")

  // 0.5 survives deadzone => changed with remapped value.
  let ev2 = @gamepad.Event::at(
    id,
    ButtonChanged(South, 0.5, @gamepad.BTN_SOUTH),
    2L,
  )
  let out2 = @gamepad.deadzone(Some(ev2), g)
  let ok = match out2 {
    None => false
    Some(e) =>
      match e.event() {
        ButtonChanged(South, v, BTN_SOUTH) => Double::abs(v - 0.375) < 0.000001
        _ => false
      }
  }
  inspect(ok, content="true")
}

///|
test "axis_dpad_to_button maps dpad axis to button events" {
  let g = @gamepad.Gil::new_mock(1, update_state=true)
  let id = @gamepad.GamepadId::new(0)

  // mapping with hats mapped to allow mapping
  let m = @gamepad.Mapping::new()
  m.set_hats_mapped(0b1111)
  g.set_mapping(id, m)
  let ev = @gamepad.Event::at(
    id,
    AxisChanged(DPadX, 1.0, @gamepad.AXIS_DPADX),
    1L,
  )
  let out = @gamepad.axis_dpad_to_button(Some(ev), g)
  debug_inspect(out.map(filter_event_sig), content="Some((1, 18, 1, 589843))")
  // extra queued event should exist
  let extra = g.next_event()
  debug_inspect(extra.map(filter_event_sig), content="Some((2, 18, 1, 589843))")
}

///|
test "axis_dpad_to_button uses legacy codes when input axis code is legacy" {
  let g = @gamepad.Gil::new_mock(1, update_state=true)
  let id = @gamepad.GamepadId::new(0)

  // mapping with hats mapped to allow mapping
  let m = @gamepad.Mapping::new()
  m.set_hats_mapped(0b1111)
  g.set_mapping(id, m)
  let ev = @gamepad.Event::at(
    id,
    AxisChanged(DPadX, 1.0, @gamepad.LEGACY_AXIS_DPADX),
    1L,
  )
  let out = @gamepad.axis_dpad_to_button(Some(ev), g)
  debug_inspect(out.map(filter_event_sig), content="Some((1, 18, 1, 18))")
  let extra = g.next_event()
  debug_inspect(extra.map(filter_event_sig), content="Some((2, 18, 1, 18))")
}

///|
test "axis_dpad_to_button handles immediate left-to-right transition" {
  let g = @gamepad.Gil::new_mock(1, update_state=false, default_filters=false)
  let id = @gamepad.GamepadId::new(0)
  let m = @gamepad.Mapping::new()
  m.set_hats_mapped(0b1111)
  g.set_mapping(id, m)
  let left_ev = @gamepad.Event::at(
    id,
    AxisChanged(DPadX, -1.0, @gamepad.AXIS_DPADX),
    1L,
  )
  let left_out = @gamepad.axis_dpad_to_button(Some(left_ev), g).unwrap()
  debug_inspect(filter_event_sig(left_out), content="(1, 17, 1, 589842)")
  g.update(left_out)
  let left_extra = g.next_event().unwrap()
  debug_inspect(filter_event_sig(left_extra), content="(2, 17, 1, 589842)")
  g.update(left_extra)
  let right_ev = @gamepad.Event::at(
    id,
    AxisChanged(DPadX, 1.0, @gamepad.AXIS_DPADX),
    2L,
  )
  let right_out = @gamepad.axis_dpad_to_button(Some(right_ev), g).unwrap()
  debug_inspect(filter_event_sig(right_out), content="(4, 17, 0, 589842)")
  let q1 = g.next_event().unwrap()
  let q2 = g.next_event().unwrap()
  let q3 = g.next_event().unwrap()
  debug_inspect(
    [filter_event_sig(q1), filter_event_sig(q2), filter_event_sig(q3)],
    content="[(2, 18, 1, 589843), (1, 18, 1, 589843), (2, 17, 0, 589842)]",
  )
}

///|
test "axis_dpad_to_button handles immediate up-to-down transition" {
  let g = @gamepad.Gil::new_mock(1, update_state=false, default_filters=false)
  let id = @gamepad.GamepadId::new(0)
  let m = @gamepad.Mapping::new()
  m.set_hats_mapped(0b1111)
  g.set_mapping(id, m)
  let up_ev = @gamepad.Event::at(
    id,
    AxisChanged(DPadY, 1.0, @gamepad.AXIS_DPADY),
    1L,
  )
  let up_out = @gamepad.axis_dpad_to_button(Some(up_ev), g).unwrap()
  debug_inspect(filter_event_sig(up_out), content="(1, 15, 1, 589840)")
  g.update(up_out)
  let up_extra = g.next_event().unwrap()
  debug_inspect(filter_event_sig(up_extra), content="(2, 15, 1, 589840)")
  g.update(up_extra)
  let down_ev = @gamepad.Event::at(
    id,
    AxisChanged(DPadY, -1.0, @gamepad.AXIS_DPADY),
    2L,
  )
  let down_out = @gamepad.axis_dpad_to_button(Some(down_ev), g).unwrap()
  debug_inspect(filter_event_sig(down_out), content="(4, 15, 0, 589840)")
  let q1 = g.next_event().unwrap()
  let q2 = g.next_event().unwrap()
  let q3 = g.next_event().unwrap()
  debug_inspect(
    [filter_event_sig(q1), filter_event_sig(q2), filter_event_sig(q3)],
    content="[(2, 16, 1, 589841), (1, 16, 1, 589841), (2, 15, 0, 589840)]",
  )
}

///|
test "axis_dpad_to_button keeps axis event when hats mapping is partial" {
  let g = @gamepad.Gil::new_mock(1, update_state=false, default_filters=false)
  let id = @gamepad.GamepadId::new(0)
  let m = @gamepad.Mapping::new()
  m.set_hats_mapped(0b0001)
  g.set_mapping(id, m)
  let ev = @gamepad.Event::at(
    id,
    AxisChanged(DPadX, 1.0, @gamepad.AXIS_DPADX),
    1L,
  )
  let out = @gamepad.axis_dpad_to_button(Some(ev), g)
  debug_inspect(out.map(filter_event_sig), content="Some((0, 6, 1, 65593))")
  inspect(g.next_event() is None, content="true")
}

///|
test "axis_dpad_to_button keeps axis event when dpad button exists" {
  let g = @gamepad.Gil::new_mock(1, update_state=false, default_filters=false)
  let id = @gamepad.GamepadId::new(0)
  let m = @gamepad.Mapping::new()
  m.insert(@gamepad.BTN_DPAD_RIGHT, Btn(DPadRight))
  g.set_mapping(id, m)
  let ev = @gamepad.Event::at(
    id,
    AxisChanged(DPadX, 1.0, @gamepad.AXIS_DPADX),
    1L,
  )
  let out = @gamepad.axis_dpad_to_button(Some(ev), g)
  debug_inspect(out.map(filter_event_sig), content="Some((0, 6, 1, 65593))")
  inspect(g.next_event() is None, content="true")
}

///|
test "axis_dpad_to_button maps when hats_mapped is zero and no dpad bindings" {
  let g = @gamepad.Gil::new_mock(1, update_state=false, default_filters=false)
  let id = @gamepad.GamepadId::new(0)
  let m = @gamepad.Mapping::new()
  m.set_hats_mapped(0)
  g.set_mapping(id, m)
  let ev = @gamepad.Event::at(
    id,
    AxisChanged(DPadX, 1.0, @gamepad.AXIS_DPADX),
    1L,
  )
  let out = @gamepad.axis_dpad_to_button(Some(ev), g)
  debug_inspect(out.map(filter_event_sig), content="Some((1, 18, 1, 589843))")
  debug_inspect(
    g.next_event().map(filter_event_sig),
    content="Some((2, 18, 1, 589843))",
  )
}

///|
test "axis_dpad_to_button passthrough when mapping is missing" {
  let g = @gamepad.Gil::new_mock(1, update_state=false, default_filters=false)
  let id = @gamepad.GamepadId::new(9)
  let ev = @gamepad.Event::at(
    id,
    AxisChanged(DPadX, 1.0, @gamepad.AXIS_DPADX),
    1L,
  )
  let out = @gamepad.axis_dpad_to_button(Some(ev), g)
  debug_inspect(out.map(filter_event_sig), content="Some((0, 6, 1, 65593))")
  inspect(g.next_event() is None, content="true")
}

///|
test "axis_dpad_to_button releases X direction on center value" {
  let g = @gamepad.Gil::new_mock(1, update_state=false, default_filters=false)
  let id = @gamepad.GamepadId::new(0)
  let m = @gamepad.Mapping::new()
  m.set_hats_mapped(0b1111)
  g.set_mapping(id, m)
  let press_ev = @gamepad.Event::at(
    id,
    AxisChanged(DPadX, 1.0, @gamepad.AXIS_DPADX),
    1L,
  )
  let press_out = @gamepad.axis_dpad_to_button(Some(press_ev), g).unwrap()
  g.update(press_out)
  g.update(g.next_event().unwrap())
  let center_ev = @gamepad.Event::at(
    id,
    AxisChanged(DPadX, 0.0, @gamepad.AXIS_DPADX),
    2L,
  )
  let center_out = @gamepad.axis_dpad_to_button(Some(center_ev), g).unwrap()
  debug_inspect(filter_event_sig(center_out), content="(4, 18, 0, 589843)")
  let extra = g.next_event().unwrap()
  debug_inspect(filter_event_sig(extra), content="(2, 18, 0, 589843)")
}

///|
test "axis_dpad_to_button releases Y direction on center value" {
  let g = @gamepad.Gil::new_mock(1, update_state=false, default_filters=false)
  let id = @gamepad.GamepadId::new(0)
  let m = @gamepad.Mapping::new()
  m.set_hats_mapped(0b1111)
  g.set_mapping(id, m)
  let press_ev = @gamepad.Event::at(
    id,
    AxisChanged(DPadY, 1.0, @gamepad.AXIS_DPADY),
    1L,
  )
  let press_out = @gamepad.axis_dpad_to_button(Some(press_ev), g).unwrap()
  g.update(press_out)
  g.update(g.next_event().unwrap())
  let center_ev = @gamepad.Event::at(
    id,
    AxisChanged(DPadY, 0.0, @gamepad.AXIS_DPADY),
    2L,
  )
  let center_out = @gamepad.axis_dpad_to_button(Some(center_ev), g).unwrap()
  debug_inspect(filter_event_sig(center_out), content="(4, 15, 0, 589840)")
  let extra = g.next_event().unwrap()
  debug_inspect(filter_event_sig(extra), content="(2, 15, 0, 589840)")
}

///|
test "repeat generates repeated events on None" {
  let g = @gamepad.Gil::new_mock(1, update_state=false)
  let id = @gamepad.GamepadId::new(0)
  // mapping so Repeat can name the button
  let m = @gamepad.Mapping::new()
  m.insert(@gamepad.BTN_SOUTH, Btn(South))
  g.set_mapping(id, m)

  // pressed at t=0
  g.update(@gamepad.Event::at(id, ButtonPressed(South, @gamepad.BTN_SOUTH), 0L))
  runtime_now_set_for_test(500L)
  let rep = @gamepad.Repeat::new()
  let out1 = rep.filter(None, g)
  debug_inspect(out1.map(filter_event_sig), content="Some((3, 0, 0, 589825))")
  // update state with repeat, then next repeat at +30ms
  g.update(out1.unwrap())
  runtime_now_set_for_test(530L)
  let out2 = rep.filter(None, g)
  debug_inspect(out2.map(filter_event_sig), content="Some((3, 0, 0, 589825))")
  runtime_now_clear_for_test()
}
