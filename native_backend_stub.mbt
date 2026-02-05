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
pub struct NativeBackend {
  mut _dummy : Int
}

///|
pub fn NativeBackend::new() -> NativeBackend {
  { _dummy: 0 }
}

///|
pub fn NativeBackend::poll(self : NativeBackend) -> Unit {
  let _ = self
  ()
}

///|
pub fn NativeBackend::poll_timeout(
  self : NativeBackend,
  timeout_ms : Int,
) -> Unit {
  let _ = self
  let _ = timeout_ms
  ()
}

///|
pub fn NativeBackend::next_event(self : NativeBackend) -> NativeEvent? {
  let _ = self
  None
}

///|
pub fn NativeBackend::gamepad_count(self : NativeBackend) -> Int {
  let _ = self
  0
}

///|
pub fn NativeBackend::name(self : NativeBackend, id : Int) -> String {
  let _ = self
  let _ = id
  ""
}

///|
pub fn NativeBackend::uuid_simple(self : NativeBackend, id : Int) -> String {
  let _ = self
  let _ = id
  ""
}

///|
pub fn NativeBackend::vendor_id(self : NativeBackend, id : Int) -> Int? {
  let _ = self
  let _ = id
  None
}

///|
pub fn NativeBackend::product_id(self : NativeBackend, id : Int) -> Int? {
  let _ = self
  let _ = id
  None
}

///|
pub fn NativeBackend::is_ff_supported(self : NativeBackend, id : Int) -> Bool {
  let _ = self
  let _ = id
  false
}

///|
pub fn NativeBackend::set_rumble(
  self : NativeBackend,
  id : Int,
  strong : Double,
  weak : Double,
  duration_ms : Int,
) -> Bool {
  let _ = self
  let _ = id
  let _ = strong
  let _ = weak
  let _ = duration_ms
  false
}
