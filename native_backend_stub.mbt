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
pub fn NativeBackend::next_event(self : NativeBackend) -> NativeEvent? {
  let _ = self
  None
}

///|
pub fn NativeBackend::gamepad_count(self : NativeBackend) -> Int {
  let _ = self
  0
}
