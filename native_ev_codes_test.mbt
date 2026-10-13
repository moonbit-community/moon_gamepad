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
test "native_ev_codes: mac HID codes are page<<16|usage" {
  inspect(@gamepad.BTN_SOUTH, content="589825")
  inspect(@gamepad.BTN_EAST, content="589826")
  inspect(@gamepad.AXIS_LSTICKX, content="65584")
  inspect(@gamepad.AXIS_DPADY, content="65594")
  inspect(@gamepad.AXIS_LT2, content="131269")
  inspect(@gamepad.AXIS_RT2, content="131268")
}

///|
test "native_ev_codes: hid_page/hid_usage roundtrip" {
  debug_inspect(
    (
      @gamepad.hid_page(@gamepad.BTN_WEST),
      @gamepad.hid_usage(@gamepad.BTN_WEST),
    ),
    content="(9, 4)",
  )
  debug_inspect(
    (
      @gamepad.hid_page(@gamepad.AXIS_LSTICKY),
      @gamepad.hid_usage(@gamepad.AXIS_LSTICKY),
    ),
    content="(1, 49)",
  )
}

///|
test "native_ev_codes: trigger axes map to buttons" {
  let ok = match @gamepad.axis_or_btn_from_code(@gamepad.AXIS_LT2) {
    Some(Btn(LeftTrigger2)) => true
    _ => false
  }
  inspect(ok, content="true")
}

///|
test "native_ev_codes: unconfirmed macOS axes remain unmapped by default" {
  let rx = @gamepad.hid_code(@gamepad.PAGE_GENERIC_DESKTOP, 0x33)
  let ry = @gamepad.hid_code(@gamepad.PAGE_GENERIC_DESKTOP, 0x34)
  let ok_rx = match @gamepad.axis_or_btn_from_code(rx) {
    None => true
    _ => false
  }
  let ok_ry = match @gamepad.axis_or_btn_from_code(ry) {
    None => true
    _ => false
  }
  debug_inspect((ok_rx, ok_ry), content="(true, true)")
}

///|
test "native_ev_codes: unconfirmed constants use GenericDesktop usage 0" {
  let zero_usage = @gamepad.hid_code(@gamepad.PAGE_GENERIC_DESKTOP, 0)
  inspect(zero_usage, content="65536")
  debug_inspect(
    (
      @gamepad.AXIS_LEFTZ,
      @gamepad.AXIS_RIGHTZ,
      @gamepad.AXIS_LT,
      @gamepad.AXIS_RT,
    ),
    content="(65536, 65536, 65536, 65536)",
  )
}

///|
test "native_ev_codes: usage-0 constants collide to one default mapping" {
  let hit_leftz = match @gamepad.axis_or_btn_from_code(@gamepad.AXIS_LEFTZ) {
    Some(Axis(RightZ)) => true
    _ => false
  }
  let hit_rightz = match @gamepad.axis_or_btn_from_code(@gamepad.AXIS_RIGHTZ) {
    Some(Axis(RightZ)) => true
    _ => false
  }
  let hit_lt = match @gamepad.axis_or_btn_from_code(@gamepad.AXIS_LT) {
    Some(Axis(RightZ)) => true
    _ => false
  }
  let hit_rt = match @gamepad.axis_or_btn_from_code(@gamepad.AXIS_RT) {
    Some(Axis(RightZ)) => true
    _ => false
  }
  debug_inspect(
    (hit_leftz, hit_rightz, hit_lt, hit_rt),
    content="(true, true, true, true)",
  )
}
