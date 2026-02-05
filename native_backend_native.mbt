///|
type BackendOwner

///|
extern "C" fn backend_new() -> BackendOwner = "moon_gamepad_backend_new"

///|
#borrow(owner)
extern "C" fn backend_poll(owner : BackendOwner) -> Unit = "moon_gamepad_backend_poll"

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
pub fn NativeBackend::gamepad_count(self : NativeBackend) -> Int {
  backend_gamepad_count(self.owner)
}

///|
pub fn NativeBackend::next_event(self : NativeBackend) -> NativeEvent? {
  let b = backend_next_event_bin(self.owner)
  decode_native_event(b)
}
