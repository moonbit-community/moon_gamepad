///|
pub(all) enum NativeEventTag {
  Connected
  Disconnected
  ButtonPressed
  ButtonReleased
  AxisChanged
  ButtonChanged
}

///|
pub struct NativeEvent {
  tag : NativeEventTag
  id : Int
  code : Code
  value : Double
  time_ms : Int64
}

///|
fn read_u32_le(b : Bytes, off : Int) -> Int {
  let b0 = b[off + 0].to_int()
  let b1 = b[off + 1].to_int()
  let b2 = b[off + 2].to_int()
  let b3 = b[off + 3].to_int()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
fn read_u64_le(b : Bytes, off : Int) -> UInt64 {
  let mut out : UInt64 = 0UL
  for i in 0..<8 {
    let v = b[off + i].to_uint64()
    out = out | (v << (i * 8))
  }
  out
}

///|
pub fn decode_native_event(b : Bytes) -> NativeEvent? {
  if b.length() == 0 {
    return None
  }
  if b.length() < 32 {
    return None
  }
  let tag_i = read_u32_le(b, 0)
  let id = read_u32_le(b, 4)
  let code = read_u32_le(b, 8)
  let value_bits = read_u64_le(b, 16)
  let time_bits = read_u64_le(b, 24)
  let value = UInt64::reinterpret_as_double(value_bits)
  let time_ms = UInt64::reinterpret_as_int64(time_bits)
  let tag = match tag_i {
    0 => NativeEventTag::Connected
    1 => NativeEventTag::Disconnected
    2 => NativeEventTag::ButtonPressed
    3 => NativeEventTag::ButtonReleased
    4 => NativeEventTag::AxisChanged
    5 => NativeEventTag::ButtonChanged
    _ => return None
  }
  Some({ tag, id, code, value, time_ms })
}
