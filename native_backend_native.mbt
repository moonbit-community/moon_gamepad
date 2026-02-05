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
type BackendOwner

///|
extern "C" fn backend_new() -> BackendOwner = "moon_gamepad_backend_new"

///|
#borrow(owner)
extern "C" fn backend_poll(owner : BackendOwner) -> Unit = "moon_gamepad_backend_poll"

///|
#borrow(owner)
extern "C" fn backend_poll_timeout(
  owner : BackendOwner,
  timeout_ms : Int,
) -> Unit = "moon_gamepad_backend_poll_timeout"

///|
#borrow(owner)
extern "C" fn backend_gamepad_count(owner : BackendOwner) -> Int = "moon_gamepad_backend_gamepad_count"

///|
#borrow(owner)
extern "C" fn backend_next_event_bin(owner : BackendOwner) -> Bytes = "moon_gamepad_backend_next_event_bin"

///|
#borrow(owner)
extern "C" fn backend_name(owner : BackendOwner, id : Int) -> String = "moon_gamepad_backend_name"

///|
#borrow(owner)
extern "C" fn backend_uuid_simple(owner : BackendOwner, id : Int) -> String = "moon_gamepad_backend_uuid_simple"

///|
#borrow(owner)
extern "C" fn backend_vendor_id(owner : BackendOwner, id : Int) -> Int = "moon_gamepad_backend_vendor_id"

///|
#borrow(owner)
extern "C" fn backend_product_id(owner : BackendOwner, id : Int) -> Int = "moon_gamepad_backend_product_id"

///|
#borrow(owner)
extern "C" fn backend_is_ff_supported(owner : BackendOwner, id : Int) -> Int = "moon_gamepad_backend_is_ff_supported"

///|
#borrow(owner)
extern "C" fn backend_set_rumble(
  owner : BackendOwner,
  id : Int,
  strong : Double,
  weak : Double,
  duration_ms : Int,
) -> Int = "moon_gamepad_backend_set_rumble"

///|
pub struct NativeBackend {
  owner : BackendOwner
}

///|
pub fn NativeBackend::new() -> NativeBackend {
  { owner: backend_new() }
}

///|
pub fn NativeBackend::poll(self : NativeBackend) -> Unit {
  backend_poll(self.owner)
}

///|
pub fn NativeBackend::poll_timeout(
  self : NativeBackend,
  timeout_ms : Int,
) -> Unit {
  backend_poll_timeout(self.owner, timeout_ms)
}

///|
pub fn NativeBackend::gamepad_count(self : NativeBackend) -> Int {
  backend_gamepad_count(self.owner)
}

///|
pub fn NativeBackend::next_event(self : NativeBackend) -> NativeEvent? {
  let b = backend_next_event_bin(self.owner)
  decode_native_event(b)
}

///|
pub fn NativeBackend::name(self : NativeBackend, id : Int) -> String {
  backend_name(self.owner, id)
}

///|
pub fn NativeBackend::uuid_simple(self : NativeBackend, id : Int) -> String {
  backend_uuid_simple(self.owner, id)
}

///|
pub fn NativeBackend::vendor_id(self : NativeBackend, id : Int) -> Int? {
  let v = backend_vendor_id(self.owner, id)
  if v < 0 {
    None
  } else {
    Some(v)
  }
}

///|
pub fn NativeBackend::product_id(self : NativeBackend, id : Int) -> Int? {
  let v = backend_product_id(self.owner, id)
  if v < 0 {
    None
  } else {
    Some(v)
  }
}

///|
pub fn NativeBackend::is_ff_supported(self : NativeBackend, id : Int) -> Bool {
  backend_is_ff_supported(self.owner, id) != 0
}

///|
pub fn NativeBackend::set_rumble(
  self : NativeBackend,
  id : Int,
  strong : Double,
  weak : Double,
  duration_ms : Int,
) -> Bool {
  backend_set_rumble(self.owner, id, strong, weak, duration_ms) != 0
}
