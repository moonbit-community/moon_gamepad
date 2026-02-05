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
test "event drop" {
  let id = GamepadId::new(0)
  let ev = Event::new(id, EventType::Connected)
  inspect(ev.is_dropped(), content="false")
  inspect(ev.drop().is_dropped(), content="true")
}

///|
test "button categories" {
  inspect(Button::South.is_action(), content="true")
  inspect(Button::LeftTrigger2.is_trigger(), content="true")
  inspect(Button::Start.is_menu(), content="true")
  inspect(Button::LeftThumb.is_stick(), content="true")
  inspect(Button::DPadLeft.is_dpad(), content="true")
  inspect(Button::Unknown.is_action(), content="false")
}

///|
test "axis second axis" {
  fn axis_name(ax : Axis) -> String {
    match ax {
      Axis::LeftStickX => "LeftStickX"
      Axis::LeftStickY => "LeftStickY"
      Axis::LeftZ => "LeftZ"
      Axis::RightStickX => "RightStickX"
      Axis::RightStickY => "RightStickY"
      Axis::RightZ => "RightZ"
      Axis::DPadX => "DPadX"
      Axis::DPadY => "DPadY"
      Axis::Unknown => "Unknown"
    }
  }

  fn axis_opt_name(ax : Axis?) -> String {
    match ax {
      None => "None"
      Some(ax) => "Some(" + axis_name(ax) + ")"
    }
  }

  inspect(
    axis_opt_name(Axis::LeftStickX.second_axis()),
    content="Some(LeftStickY)",
  )
  inspect(
    axis_opt_name(Axis::LeftStickY.second_axis()),
    content="Some(LeftStickX)",
  )
  inspect(axis_opt_name(Axis::DPadX.second_axis()), content="Some(DPadY)")
  inspect(axis_opt_name(Axis::Unknown.second_axis()), content="None")
}
