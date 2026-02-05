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
    EventType::ButtonReleased(btn, code) => (4, btn.to_index(), 0.0, code)
    _ => (99, 0, 0.0, 0)
  }
}

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
