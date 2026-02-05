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
// These codes are intentionally "logical" placeholders. They only need to be stable and unique
// within this library for mapping/indexing purposes.
pub const BTN_SOUTH : Code = 0

///|
pub const BTN_EAST : Code = 1

///|
pub const BTN_C : Code = 2

///|
pub const BTN_NORTH : Code = 3

///|
pub const BTN_WEST : Code = 4

///|
pub const BTN_Z : Code = 5

///|
pub const BTN_LT : Code = 6

///|
pub const BTN_RT : Code = 7

///|
pub const BTN_LT2 : Code = 8

///|
pub const BTN_RT2 : Code = 9

///|
pub const BTN_SELECT : Code = 10

///|
pub const BTN_START : Code = 11

///|
pub const BTN_MODE : Code = 12

///|
pub const BTN_LTHUMB : Code = 13

///|
pub const BTN_RTHUMB : Code = 14

///|
pub const BTN_DPAD_UP : Code = 15

///|
pub const BTN_DPAD_DOWN : Code = 16

///|
pub const BTN_DPAD_LEFT : Code = 17

///|
pub const BTN_DPAD_RIGHT : Code = 18

///|
pub const AXIS_LSTICKX : Code = 100

///|
pub const AXIS_LSTICKY : Code = 101

///|
pub const AXIS_LEFTZ : Code = 102

///|
pub const AXIS_RSTICKX : Code = 103

///|
pub const AXIS_RSTICKY : Code = 104

///|
pub const AXIS_RIGHTZ : Code = 105

///|
pub const AXIS_DPADX : Code = 106

///|
pub const AXIS_DPADY : Code = 107

///|
pub const AXIS_RT : Code = 108

///|
pub const AXIS_LT : Code = 109

///|
pub const AXIS_RT2 : Code = 110

///|
pub const AXIS_LT2 : Code = 111

///|
pub fn axis_from_code(code : Code) -> Axis? {
  match code {
    AXIS_LSTICKX => Some(Axis::LeftStickX)
    AXIS_LSTICKY => Some(Axis::LeftStickY)
    AXIS_LEFTZ => Some(Axis::LeftZ)
    AXIS_RSTICKX => Some(Axis::RightStickX)
    AXIS_RSTICKY => Some(Axis::RightStickY)
    AXIS_RIGHTZ => Some(Axis::RightZ)
    AXIS_DPADX => Some(Axis::DPadX)
    AXIS_DPADY => Some(Axis::DPadY)
    _ => None
  }
}

///|
pub fn button_from_code(code : Code) -> Button? {
  match code {
    BTN_SOUTH => Some(Button::South)
    BTN_EAST => Some(Button::East)
    BTN_C => Some(Button::C)
    BTN_NORTH => Some(Button::North)
    BTN_WEST => Some(Button::West)
    BTN_Z => Some(Button::Z)
    BTN_LT => Some(Button::LeftTrigger)
    BTN_RT => Some(Button::RightTrigger)
    BTN_LT2 => Some(Button::LeftTrigger2)
    BTN_RT2 => Some(Button::RightTrigger2)
    BTN_SELECT => Some(Button::Select)
    BTN_START => Some(Button::Start)
    BTN_MODE => Some(Button::Mode)
    BTN_LTHUMB => Some(Button::LeftThumb)
    BTN_RTHUMB => Some(Button::RightThumb)
    BTN_DPAD_UP => Some(Button::DPadUp)
    BTN_DPAD_DOWN => Some(Button::DPadDown)
    BTN_DPAD_LEFT => Some(Button::DPadLeft)
    BTN_DPAD_RIGHT => Some(Button::DPadRight)
    _ => None
  }
}

///|
pub fn axis_or_btn_from_code(code : Code) -> AxisOrBtn? {
  match axis_from_code(code) {
    Some(a) => Some(AxisOrBtn::Axis(a))
    None =>
      match button_from_code(code) {
        Some(b) => Some(AxisOrBtn::Btn(b))
        None => None
      }
  }
}
