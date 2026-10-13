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
  let id = @gamepad.GamepadId::new(0)
  let ev = @gamepad.Event::new(id, Connected)
  inspect(ev.is_dropped(), content="false")
  inspect(ev.drop().is_dropped(), content="true")
}

///|
test "button categories" {
  inspect(@gamepad.Button::South.is_action(), content="true")
  inspect(@gamepad.Button::LeftTrigger2.is_trigger(), content="true")
  inspect(@gamepad.Button::Start.is_menu(), content="true")
  inspect(@gamepad.Button::LeftThumb.is_stick(), content="true")
  inspect(@gamepad.Button::DPadLeft.is_dpad(), content="true")
  inspect(@gamepad.Button::Unknown.is_action(), content="false")
}

///|
test "axis second axis" {
  fn axis_name(ax : @gamepad.Axis) -> String {
    match ax {
      LeftStickX => "LeftStickX"
      LeftStickY => "LeftStickY"
      LeftZ => "LeftZ"
      RightStickX => "RightStickX"
      RightStickY => "RightStickY"
      RightZ => "RightZ"
      DPadX => "DPadX"
      DPadY => "DPadY"
      Unknown => "Unknown"
    }
  }

  fn axis_opt_name(ax : @gamepad.Axis?) -> String {
    match ax {
      None => "None"
      Some(ax) => "Some(" + axis_name(ax) + ")"
    }
  }

  inspect(
    axis_opt_name(@gamepad.Axis::LeftStickX.second_axis()),
    content="Some(LeftStickY)",
  )
  inspect(
    axis_opt_name(@gamepad.Axis::LeftStickY.second_axis()),
    content="Some(LeftStickX)",
  )
  inspect(
    axis_opt_name(@gamepad.Axis::DPadX.second_axis()),
    content="Some(DPadY)",
  )
  inspect(axis_opt_name(@gamepad.Axis::Unknown.second_axis()), content="None")
}

///|
test "ev helper branches parity" {
  inspect(@gamepad.Axis::LeftStickX.is_stick(), content="true")
  inspect(@gamepad.Axis::LeftZ.is_stick(), content="false")
  debug_inspect(
    @gamepad.Axis::RightStickX.second_axis().map(fn(ax) { ax.to_index() }),
    content="Some(4)",
  )
  debug_inspect(
    @gamepad.Axis::RightStickY.second_axis().map(fn(ax) { ax.to_index() }),
    content="Some(3)",
  )
  debug_inspect(
    @gamepad.Axis::DPadY.second_axis().map(fn(ax) { ax.to_index() }),
    content="Some(6)",
  )
  inspect(@gamepad.Button::South.is_trigger(), content="false")
  inspect(@gamepad.Button::South.is_menu(), content="false")
  inspect(@gamepad.Button::South.is_stick(), content="false")
  inspect(@gamepad.Button::South.is_dpad(), content="false")
  inspect(@gamepad.Button::C.to_index(), content="2")
  inspect(@gamepad.Button::Z.to_index(), content="5")
  inspect(@gamepad.AxisOrBtn::Axis(Unknown).is_button(), content="false")
}
