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
// Native HID-style codes (macOS parity): Code = (page << 16) | usage.
pub fn hid_code(page : Int, usage : Int) -> Code {
  (page << 16) | usage
}

///|
pub fn hid_page(code : Code) -> Int {
  (code >> 16) & 0xFFFF
}

///|
pub fn hid_usage(code : Code) -> Int {
  code & 0xFFFF
}

///|
pub const PAGE_GENERIC_DESKTOP : Int = 0x01

///|
pub const PAGE_SIMULATION : Int = 0x02

///|
pub const PAGE_BUTTON : Int = 0x09

///|
pub const AXIS_LSTICKX : Code = (PAGE_GENERIC_DESKTOP << 16) | 0x30

///|
pub const AXIS_LSTICKY : Code = (PAGE_GENERIC_DESKTOP << 16) | 0x31

///|
// Unconfirmed in gilrs-core reference on macOS (kept for parity; should not match real devices).
pub const AXIS_LEFTZ : Code = (PAGE_GENERIC_DESKTOP << 16) | 0

///|
pub const AXIS_RSTICKX : Code = (PAGE_GENERIC_DESKTOP << 16) | 0x32

///|
pub const AXIS_RSTICKY : Code = (PAGE_GENERIC_DESKTOP << 16) | 0x35

///|
// Unconfirmed in gilrs-core reference on macOS (kept for parity; should not match real devices).
pub const AXIS_RIGHTZ : Code = (PAGE_GENERIC_DESKTOP << 16) | 0

///|
pub const AXIS_DPADX : Code = (PAGE_GENERIC_DESKTOP << 16) | 0x39

///|
pub const AXIS_DPADY : Code = (PAGE_GENERIC_DESKTOP << 16) | 0x3A

///|
// Unconfirmed in gilrs-core reference on macOS (kept for parity; should not match real devices).
pub const AXIS_RT : Code = (PAGE_GENERIC_DESKTOP << 16) | 0

///|
// Unconfirmed in gilrs-core reference on macOS (kept for parity; should not match real devices).
pub const AXIS_LT : Code = (PAGE_GENERIC_DESKTOP << 16) | 0

///|
pub const AXIS_RT2 : Code = (PAGE_SIMULATION << 16) | 0xC4

///|
pub const AXIS_LT2 : Code = (PAGE_SIMULATION << 16) | 0xC5

///|
pub const BTN_SOUTH : Code = (PAGE_BUTTON << 16) | 1

///|
pub const BTN_EAST : Code = (PAGE_BUTTON << 16) | 2

///|
pub const BTN_WEST : Code = (PAGE_BUTTON << 16) | 4

///|
pub const BTN_NORTH : Code = (PAGE_BUTTON << 16) | 5

///|
pub const BTN_LT : Code = (PAGE_BUTTON << 16) | 7

///|
pub const BTN_RT : Code = (PAGE_BUTTON << 16) | 8

///|
pub const BTN_LT2 : Code = (PAGE_BUTTON << 16) | 9

///|
pub const BTN_RT2 : Code = (PAGE_BUTTON << 16) | 10

///|
pub const BTN_SELECT : Code = (PAGE_BUTTON << 16) | 11

///|
pub const BTN_START : Code = (PAGE_BUTTON << 16) | 12

///|
pub const BTN_MODE : Code = (PAGE_BUTTON << 16) | 13

///|
pub const BTN_LTHUMB : Code = (PAGE_BUTTON << 16) | 14

///|
pub const BTN_RTHUMB : Code = (PAGE_BUTTON << 16) | 15

///|
pub const BTN_DPAD_UP : Code = (PAGE_BUTTON << 16) | 16

///|
pub const BTN_DPAD_DOWN : Code = (PAGE_BUTTON << 16) | 17

///|
pub const BTN_DPAD_LEFT : Code = (PAGE_BUTTON << 16) | 18

///|
pub const BTN_DPAD_RIGHT : Code = (PAGE_BUTTON << 16) | 19

///|
pub const BTN_C : Code = (PAGE_BUTTON << 16) | 20

///|
pub const BTN_Z : Code = (PAGE_BUTTON << 16) | 21

///|
// Legacy “logical” codes for non-macOS backends (best-effort compatibility).
pub const LEGACY_BTN_SOUTH : Code = 0

///|
pub const LEGACY_BTN_EAST : Code = 1

///|
pub const LEGACY_BTN_C : Code = 2

///|
pub const LEGACY_BTN_NORTH : Code = 3

///|
pub const LEGACY_BTN_WEST : Code = 4

///|
pub const LEGACY_BTN_Z : Code = 5

///|
pub const LEGACY_BTN_LT : Code = 6

///|
pub const LEGACY_BTN_RT : Code = 7

///|
pub const LEGACY_BTN_LT2 : Code = 8

///|
pub const LEGACY_BTN_RT2 : Code = 9

///|
pub const LEGACY_BTN_SELECT : Code = 10

///|
pub const LEGACY_BTN_START : Code = 11

///|
pub const LEGACY_BTN_MODE : Code = 12

///|
pub const LEGACY_BTN_LTHUMB : Code = 13

///|
pub const LEGACY_BTN_RTHUMB : Code = 14

///|
pub const LEGACY_BTN_DPAD_UP : Code = 15

///|
pub const LEGACY_BTN_DPAD_DOWN : Code = 16

///|
pub const LEGACY_BTN_DPAD_LEFT : Code = 17

///|
pub const LEGACY_BTN_DPAD_RIGHT : Code = 18

///|
pub const LEGACY_AXIS_LSTICKX : Code = 100

///|
pub const LEGACY_AXIS_LSTICKY : Code = 101

///|
pub const LEGACY_AXIS_LEFTZ : Code = 102

///|
pub const LEGACY_AXIS_RSTICKX : Code = 103

///|
pub const LEGACY_AXIS_RSTICKY : Code = 104

///|
pub const LEGACY_AXIS_RIGHTZ : Code = 105

///|
pub const LEGACY_AXIS_DPADX : Code = 106

///|
pub const LEGACY_AXIS_DPADY : Code = 107

///|
pub const LEGACY_AXIS_RT : Code = 108

///|
pub const LEGACY_AXIS_LT : Code = 109

///|
pub const LEGACY_AXIS_RT2 : Code = 110

///|
pub const LEGACY_AXIS_LT2 : Code = 111

///|
pub fn axis_from_code(code : Code) -> Axis? {
  match code {
    AXIS_LSTICKX | LEGACY_AXIS_LSTICKX => Some(Axis::LeftStickX)
    AXIS_LSTICKY | LEGACY_AXIS_LSTICKY => Some(Axis::LeftStickY)
    LEGACY_AXIS_LEFTZ => Some(Axis::LeftZ)
    AXIS_RSTICKX | LEGACY_AXIS_RSTICKX => Some(Axis::RightStickX)
    AXIS_RSTICKY | LEGACY_AXIS_RSTICKY => Some(Axis::RightStickY)
    LEGACY_AXIS_RIGHTZ => Some(Axis::RightZ)
    AXIS_DPADX | LEGACY_AXIS_DPADX => Some(Axis::DPadX)
    AXIS_DPADY | LEGACY_AXIS_DPADY => Some(Axis::DPadY)
    _ => None
  }
}

///|
pub fn button_from_code(code : Code) -> Button? {
  match code {
    BTN_SOUTH | LEGACY_BTN_SOUTH => Some(Button::South)
    BTN_EAST | LEGACY_BTN_EAST => Some(Button::East)
    BTN_C | LEGACY_BTN_C => Some(Button::C)
    BTN_NORTH | LEGACY_BTN_NORTH => Some(Button::North)
    BTN_WEST | LEGACY_BTN_WEST => Some(Button::West)
    BTN_Z | LEGACY_BTN_Z => Some(Button::Z)
    BTN_LT | LEGACY_BTN_LT => Some(Button::LeftTrigger)
    BTN_RT | LEGACY_BTN_RT => Some(Button::RightTrigger)
    BTN_LT2 | LEGACY_BTN_LT2 => Some(Button::LeftTrigger2)
    BTN_RT2 | LEGACY_BTN_RT2 => Some(Button::RightTrigger2)
    BTN_SELECT | LEGACY_BTN_SELECT => Some(Button::Select)
    BTN_START | LEGACY_BTN_START => Some(Button::Start)
    BTN_MODE | LEGACY_BTN_MODE => Some(Button::Mode)
    BTN_LTHUMB | LEGACY_BTN_LTHUMB => Some(Button::LeftThumb)
    BTN_RTHUMB | LEGACY_BTN_RTHUMB => Some(Button::RightThumb)
    BTN_DPAD_UP | LEGACY_BTN_DPAD_UP => Some(Button::DPadUp)
    BTN_DPAD_DOWN | LEGACY_BTN_DPAD_DOWN => Some(Button::DPadDown)
    BTN_DPAD_LEFT | LEGACY_BTN_DPAD_LEFT => Some(Button::DPadLeft)
    BTN_DPAD_RIGHT | LEGACY_BTN_DPAD_RIGHT => Some(Button::DPadRight)
    _ => None
  }
}

///|
pub fn axis_or_btn_from_code(code : Code) -> AxisOrBtn? {
  match code {
    // Analog triggers are axes on some backends, but map to Button semantics in gilrs.
    AXIS_LT2 | LEGACY_AXIS_LT2 =>
      return Some(AxisOrBtn::Btn(Button::LeftTrigger2))
    AXIS_RT2 | LEGACY_AXIS_RT2 =>
      return Some(AxisOrBtn::Btn(Button::RightTrigger2))
    LEGACY_AXIS_LT => return Some(AxisOrBtn::Btn(Button::LeftTrigger))
    LEGACY_AXIS_RT => return Some(AxisOrBtn::Btn(Button::RightTrigger))
    _ => ()
  }
  match axis_from_code(code) {
    Some(a) => Some(AxisOrBtn::Axis(a))
    None =>
      match button_from_code(code) {
        Some(b) => Some(AxisOrBtn::Btn(b))
        None => None
      }
  }
}
