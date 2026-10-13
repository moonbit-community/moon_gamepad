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
test "axis_value documented case" {
  let info = @gamepad.AxisInfo::new(0, 255, None)
  inspect(@gamepad.axis_value(info, 127, LeftStickY), content="0")
}

///|
test "axis_value overflow behavior" {
  let minv = @moonbitlang/core/int.MIN_VALUE
  let maxv = @moonbitlang/core/int.MAX_VALUE
  let info = @gamepad.AxisInfo::new(minv, maxv, None)
  let axis = @gamepad.Axis::LeftStickY
  inspect(@gamepad.axis_value(info, -1, axis), content="0")
  inspect(@gamepad.axis_value(info, 0, axis), content="0")
  inspect(@gamepad.axis_value(info, 1, axis), content="0")
  inspect(@gamepad.axis_value(info, minv, axis), content="1")
  inspect(@gamepad.axis_value(info, maxv, axis), content="-1")
}

///|
test "btn_value overflow behavior" {
  let minv = @moonbitlang/core/int.MIN_VALUE
  let maxv = @moonbitlang/core/int.MAX_VALUE
  let info = @gamepad.AxisInfo::new(minv, maxv, None)
  inspect(@gamepad.btn_value(info, -1), content="0.5")
  inspect(@gamepad.btn_value(info, 0), content="0.5")
  inspect(@gamepad.btn_value(info, 1), content="0.5")
  inspect(@gamepad.btn_value(info, minv), content="0")
  inspect(@gamepad.btn_value(info, maxv), content="1")
}
