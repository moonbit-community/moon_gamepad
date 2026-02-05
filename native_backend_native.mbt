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
