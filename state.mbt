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
pub struct ButtonData {
  last_event_ts : Int64
  counter : Int64
  value : Double
  is_pressed : Bool
  is_repeating : Bool
}

///|
fn ButtonData::new(
  value : Double,
  pressed : Bool,
  repeating : Bool,
  counter : Int64,
  time : Int64,
) -> ButtonData {
  {
    last_event_ts: time,
    counter,
    value,
    is_pressed: pressed,
    is_repeating: repeating,
  }
}

///|
pub fn ButtonData::is_pressed(self : ButtonData) -> Bool {
  self.is_pressed
}

///|
pub fn ButtonData::value(self : ButtonData) -> Double {
  self.value
}

///|
pub fn ButtonData::is_repeating(self : ButtonData) -> Bool {
  self.is_repeating
}

///|
pub fn ButtonData::counter(self : ButtonData) -> Int64 {
  self.counter
}

///|
pub fn ButtonData::timestamp(self : ButtonData) -> Int64 {
  self.last_event_ts
}

///|
pub struct AxisData {
  last_event_ts : Int64
  last_event_c : Int64
  value : Double
}

///|
fn AxisData::new(value : Double, counter : Int64, time : Int64) -> AxisData {
  { last_event_ts: time, last_event_c: counter, value }
}

///|
pub fn AxisData::value(self : AxisData) -> Double {
  self.value
}

///|
pub fn AxisData::counter(self : AxisData) -> Int64 {
  self.last_event_c
}

///|
pub fn AxisData::timestamp(self : AxisData) -> Int64 {
  self.last_event_ts
}

///|
pub struct GamepadState {
  buttons : Array[(Code, ButtonData)]
  axes : Array[(Code, AxisData)]
}

///|
pub fn GamepadState::new() -> GamepadState {
  { buttons: [], axes: [] }
}

///|
pub fn GamepadState::buttons_entries(
  self : GamepadState,
) -> Array[(Code, ButtonData)] {
  self.buttons.copy()
}

///|
pub fn GamepadState::axes_entries(
  self : GamepadState,
) -> Array[(Code, AxisData)] {
  self.axes.copy()
}

///|
fn find_idx_button(buttons : Array[(Code, ButtonData)], code : Code) -> Int? {
  for i in 0..<buttons.length() {
    let (c, _) = buttons[i]
    if c == code {
      return Some(i)
    }
  }
  None
}

///|
fn find_idx_axis(axes : Array[(Code, AxisData)], code : Code) -> Int? {
  for i in 0..<axes.length() {
    let (c, _) = axes[i]
    if c == code {
      return Some(i)
    }
  }
  None
}

///|
pub fn GamepadState::is_pressed(self : GamepadState, btn : Code) -> Bool {
  match find_idx_button(self.buttons, btn) {
    None => false
    Some(i) => {
      let (_, data) = self.buttons[i]
      data.is_pressed()
    }
  }
}

///|
pub fn GamepadState::value(self : GamepadState, el : Code) -> Double {
  match find_idx_axis(self.axes, el) {
    Some(i) => {
      let (_, data) = self.axes[i]
      data.value()
    }
    None =>
      match find_idx_button(self.buttons, el) {
        Some(i) => {
          let (_, data) = self.buttons[i]
          data.value()
        }
        None => 0.0
      }
  }
}

///|
pub fn GamepadState::button_data(
  self : GamepadState,
  btn : Code,
) -> ButtonData? {
  match find_idx_button(self.buttons, btn) {
    None => None
    Some(i) => {
      let (_, data) = self.buttons[i]
      Some(data)
    }
  }
}

///|
pub fn GamepadState::axis_data(self : GamepadState, axis : Code) -> AxisData? {
  match find_idx_axis(self.axes, axis) {
    None => None
    Some(i) => {
      let (_, data) = self.axes[i]
      Some(data)
    }
  }
}

///|
fn GamepadState::set_btn_pressed(
  self : GamepadState,
  btn : Code,
  pressed : Bool,
  counter : Int64,
  timestamp : Int64,
) -> Unit {
  let idx = find_idx_button(self.buttons, btn)
  let data = match idx {
    None =>
      ButtonData::new(
        if pressed {
          1.0
        } else {
          0.0
        },
        pressed,
        false,
        counter,
        timestamp,
      )
    Some(i) => {
      let (_, old) = self.buttons[i]
      ButtonData::new(old.value(), pressed, false, counter, timestamp)
    }
  }
  match idx {
    None => self.buttons.push((btn, data))
    Some(i) => self.buttons[i] = (btn, data)
  }
}

///|
fn GamepadState::set_btn_repeating(
  self : GamepadState,
  btn : Code,
  counter : Int64,
  timestamp : Int64,
) -> Unit {
  let idx = find_idx_button(self.buttons, btn)
  let data = match idx {
    None => ButtonData::new(1.0, true, true, counter, timestamp)
    Some(i) => {
      let (_, old) = self.buttons[i]
      ButtonData::new(old.value(), old.is_pressed(), true, counter, timestamp)
    }
  }
  match idx {
    None => self.buttons.push((btn, data))
    Some(i) => self.buttons[i] = (btn, data)
  }
}

///|
fn GamepadState::set_btn_value(
  self : GamepadState,
  btn : Code,
  value : Double,
  counter : Int64,
  timestamp : Int64,
) -> Unit {
  let idx = find_idx_button(self.buttons, btn)
  let data = match idx {
    None => ButtonData::new(value, false, false, counter, timestamp)
    Some(i) => {
      let (_, old) = self.buttons[i]
      ButtonData::new(
        value,
        old.is_pressed(),
        old.is_repeating(),
        counter,
        timestamp,
      )
    }
  }
  match idx {
    None => self.buttons.push((btn, data))
    Some(i) => self.buttons[i] = (btn, data)
  }
}

///|
fn GamepadState::update_axis(
  self : GamepadState,
  axis : Code,
  data : AxisData,
) -> Unit {
  match find_idx_axis(self.axes, axis) {
    None => self.axes.push((axis, data))
    Some(i) => self.axes[i] = (axis, data)
  }
}

///|
fn GamepadState::set_axis_value(
  self : GamepadState,
  axis : Code,
  value : Double,
  counter : Int64,
  timestamp : Int64,
) -> Unit {
  self.update_axis(axis, AxisData::new(value, counter, timestamp))
}
