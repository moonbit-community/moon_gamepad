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
  let val_i64 = val.to_int64() - info.min.to_int64()
  let mut range = range_i64.to_double()
  let mut v = val_i64.to_double()

  // Mirror gilrs' overflow behavior: only do the odd-range centering adjustment
  // when max - min fits into 32-bit Int.
  if range_i64 <= INT_MAX_I64 && range_i64 >= 0L {
    if range_i64 % 2L == 1L {
      range = range + 1.0
      v = v + 1.0
    }
  }
  v = v / range * 2.0 - 1.0
  let is_y_axis = match axis {
    Axis::LeftStickY | Axis::RightStickY | Axis::DPadY => true
    _ => false
  }
  if IS_Y_AXIS_REVERSED && is_y_axis && v != 0.0 {
    v = -v
  }
  clamp(v, -1.0, 1.0)
}

///|
pub fn btn_value(info : AxisInfo, val : Int) -> Double {
  let range = (info.max.to_int64() - info.min.to_int64()).to_double()
  let mut v = (val.to_int64() - info.min.to_int64()).to_double()
  v = v / range
  clamp(v, 0.0, 1.0)
}
