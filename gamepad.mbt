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
pub struct AxisInfo {
  min : Int
  max : Int
  deadzone : Int?
}

///|
pub fn AxisInfo::new(min : Int, max : Int, deadzone : Int?) -> AxisInfo {
  { min, max, deadzone }
}

///|
const IS_Y_AXIS_REVERSED : Bool = true

///|
const INT_MAX_I64 : Int64 = 2147483647L

///|
pub fn axis_value(info : AxisInfo, val : Int, axis : Axis) -> Double {
  let range_i64 = info.max.to_int64() - info.min.to_int64()
  let minf = Float::from_int(info.min)
  let onef = Float::from_int(1)
  let twof = Float::from_int(2)
  let mut range = Float::from_int(info.max) - minf
  let mut v = Float::from_int(val) - minf

  // Mirror gilrs' overflow behavior: only do the odd-range centering adjustment
  // when max - min fits into 32-bit Int.
  if range_i64 <= INT_MAX_I64 && range_i64 >= 0L {
    if range_i64 % 2L == 1L {
      range = range + onef
      v = v + onef
    }
  }
  v = v / range * twof - onef
  let mut out = v.to_double()
  let is_y_axis = match axis {
    Axis::LeftStickY | Axis::RightStickY | Axis::DPadY => true
    _ => false
  }
  if IS_Y_AXIS_REVERSED && is_y_axis && out != 0.0 {
    out = -out
  }
  clamp(out, -1.0, 1.0)
}

///|
pub fn btn_value(info : AxisInfo, val : Int) -> Double {
  let minf = Float::from_int(info.min)
  let range = Float::from_int(info.max) - minf
  let mut v = Float::from_int(val) - minf
  v = v / range
  clamp(v.to_double(), 0.0, 1.0)
}
