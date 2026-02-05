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
