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
  inspect(BTN_SOUTH, content="589825")
  inspect(BTN_EAST, content="589826")
  inspect(AXIS_LSTICKX, content="65584")
  inspect(AXIS_DPADY, content="65594")
  inspect(AXIS_LT2, content="131269")
  inspect(AXIS_RT2, content="131268")
}

///|
test "native_ev_codes: hid_page/hid_usage roundtrip" {
  inspect((hid_page(BTN_WEST), hid_usage(BTN_WEST)), content="(9, 4)")
  inspect((hid_page(AXIS_LSTICKY), hid_usage(AXIS_LSTICKY)), content="(1, 49)")
}

///|
test "native_ev_codes: trigger axes map to buttons" {
  let ok = match axis_or_btn_from_code(AXIS_LT2) {
    Some(AxisOrBtn::Btn(Button::LeftTrigger2)) => true
    _ => false
  }
  inspect(ok, content="true")
}

///|
test "native_ev_codes: unconfirmed macOS axes remain unmapped by default" {
  let rx = hid_code(PAGE_GENERIC_DESKTOP, 0x33)
  let ry = hid_code(PAGE_GENERIC_DESKTOP, 0x34)
  let ok_rx = match axis_or_btn_from_code(rx) {
    None => true
    _ => false
  }
  let ok_ry = match axis_or_btn_from_code(ry) {
    None => true
    _ => false
  }
  inspect((ok_rx, ok_ry), content="(true, true)")
}

///|
test "native_ev_codes: unconfirmed constants use GenericDesktop usage 0" {
  let zero_usage = hid_code(PAGE_GENERIC_DESKTOP, 0)
  inspect(zero_usage, content="65536")
  inspect(
    (AXIS_LEFTZ, AXIS_RIGHTZ, AXIS_LT, AXIS_RT),
    content="(65536, 65536, 65536, 65536)",
  )
}

///|
test "native_ev_codes: unconfirmed constants stay unmapped by default" {
  let ok_leftz = match axis_or_btn_from_code(AXIS_LEFTZ) {
    None => true
    _ => false
  }
  let ok_rightz = match axis_or_btn_from_code(AXIS_RIGHTZ) {
    None => true
    _ => false
  }
  let ok_lt = match axis_or_btn_from_code(AXIS_LT) {
    None => true
    _ => false
  }
  let ok_rt = match axis_or_btn_from_code(AXIS_RT) {
    None => true
    _ => false
  }
  inspect(
    (ok_leftz, ok_rightz, ok_lt, ok_rt),
    content="(true, true, true, true)",
  )
}
