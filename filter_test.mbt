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
test "deadzone enqueues paired-axis zero when primary event drops" {
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)
  g.set_deadzone(id, AXIS_LSTICKX, 0.2)
  g.set_deadzone(id, AXIS_LSTICKY, 0.2)
  let m = Mapping::new()
  m.insert(AXIS_LSTICKX, AxisOrBtn::Axis(Axis::LeftStickX))
  m.insert(AXIS_LSTICKY, AxisOrBtn::Axis(Axis::LeftStickY))
  g.set_mapping(id, m)

  // Seed non-zero X through deadzone so paired-axis clear path can trigger later.
  let seed = Event::at(
    id,
    EventType::AxisChanged(Axis::LeftStickX, 0.3, AXIS_LSTICKX),
    1L,
  )
  let seed_out = deadzone(Some(seed), g).unwrap()
  g.update(seed_out)

  // Y event lands both axes in deadzone; Y gets dropped, X clear is queued.
  let ev = Event::at(
    id,
    EventType::AxisChanged(Axis::LeftStickY, 0.0, AXIS_LSTICKY),
    2L,
  )
  let out = deadzone(Some(ev), g).unwrap()
  inspect(out.is_dropped(), content="true")
  let queued = g.next_event()
  inspect(queued.map(filter_event_sig), content="Some((0, 0, 0, 65584))")
  inspect(g.gamepads_data[0].have_sent_nonzero_for_axis[2], content="false")
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
  inspect(out.map(filter_event_sig), content="Some((1, 18, 1, 589843))")
  // extra queued event should exist
  let extra = g.next_event()
  inspect(extra.map(filter_event_sig), content="Some((2, 18, 1, 589843))")
}

///|
test "axis_dpad_to_button handles immediate left-to-right transition" {
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)
  let m = Mapping::new()
  m.set_hats_mapped(0b1111)
  g.set_mapping(id, m)
  let left_ev = Event::at(
    id,
    EventType::AxisChanged(Axis::DPadX, -1.0, AXIS_DPADX),
    1L,
  )
  let left_out = axis_dpad_to_button(Some(left_ev), g).unwrap()
  inspect(filter_event_sig(left_out), content="(1, 17, 1, 589842)")
  g.update(left_out)
  let left_extra = g.next_event().unwrap()
  inspect(filter_event_sig(left_extra), content="(2, 17, 1, 589842)")
  g.update(left_extra)
  let right_ev = Event::at(
    id,
    EventType::AxisChanged(Axis::DPadX, 1.0, AXIS_DPADX),
    2L,
  )
  let right_out = axis_dpad_to_button(Some(right_ev), g).unwrap()
  inspect(filter_event_sig(right_out), content="(4, 17, 0, 589842)")
  let q1 = g.next_event().unwrap()
  let q2 = g.next_event().unwrap()
  let q3 = g.next_event().unwrap()
  inspect(
    [filter_event_sig(q1), filter_event_sig(q2), filter_event_sig(q3)],
    content="[(2, 18, 1, 589843), (1, 18, 1, 589843), (2, 17, 0, 589842)]",
  )
}

///|
test "axis_dpad_to_button handles immediate up-to-down transition" {
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)
  let m = Mapping::new()
  m.set_hats_mapped(0b1111)
  g.set_mapping(id, m)
  let up_ev = Event::at(
    id,
    EventType::AxisChanged(Axis::DPadY, 1.0, AXIS_DPADY),
    1L,
  )
  let up_out = axis_dpad_to_button(Some(up_ev), g).unwrap()
  inspect(filter_event_sig(up_out), content="(1, 15, 1, 589840)")
  g.update(up_out)
  let up_extra = g.next_event().unwrap()
  inspect(filter_event_sig(up_extra), content="(2, 15, 1, 589840)")
  g.update(up_extra)
  let down_ev = Event::at(
    id,
    EventType::AxisChanged(Axis::DPadY, -1.0, AXIS_DPADY),
    2L,
  )
  let down_out = axis_dpad_to_button(Some(down_ev), g).unwrap()
  inspect(filter_event_sig(down_out), content="(4, 15, 0, 589840)")
  let q1 = g.next_event().unwrap()
  let q2 = g.next_event().unwrap()
  let q3 = g.next_event().unwrap()
  inspect(
    [filter_event_sig(q1), filter_event_sig(q2), filter_event_sig(q3)],
    content="[(2, 16, 1, 589841), (1, 16, 1, 589841), (2, 15, 0, 589840)]",
  )
}

///|
test "axis_dpad_to_button keeps axis event when hats mapping is partial" {
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)
  let m = Mapping::new()
  m.set_hats_mapped(0b0001)
  g.set_mapping(id, m)
  let ev = Event::at(
    id,
    EventType::AxisChanged(Axis::DPadX, 1.0, AXIS_DPADX),
    1L,
  )
  let out = axis_dpad_to_button(Some(ev), g)
  inspect(out.map(filter_event_sig), content="Some((0, 6, 1, 65593))")
  inspect(g.next_event() is None, content="true")
}

///|
test "axis_dpad_to_button keeps axis event when dpad button exists" {
  let g = Gilrs::new_mock(1, update_state=false, default_filters=false)
  let id = GamepadId::new(0)
  let m = Mapping::new()
  m.insert(BTN_DPAD_RIGHT, AxisOrBtn::Btn(Button::DPadRight))
  g.set_mapping(id, m)
  let ev = Event::at(
    id,
    EventType::AxisChanged(Axis::DPadX, 1.0, AXIS_DPADX),
    1L,
  )
  let out = axis_dpad_to_button(Some(ev), g)
  inspect(out.map(filter_event_sig), content="Some((0, 6, 1, 65593))")
  inspect(g.next_event() is None, content="true")
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
  inspect(out1.map(filter_event_sig), content="Some((3, 0, 0, 589825))")
  // update state with repeat, then next repeat at +30ms
  g.update(out1.unwrap())
  g.set_time(530L)
  let out2 = rep.filter(None, g)
  inspect(out2.map(filter_event_sig), content="Some((3, 0, 0, 589825))")
}
