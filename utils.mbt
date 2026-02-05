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
pub fn ceil_div(a : UInt, b : UInt) -> UInt {
  if a == 0U {
    0U
  } else {
    1U + (a - 1U) / b
  }
}

///|
pub fn clamp(x : Double, min : Double, max : Double) -> Double {
  if x < min {
    min
  } else if x > max {
    max
  } else {
    x
  }
}
