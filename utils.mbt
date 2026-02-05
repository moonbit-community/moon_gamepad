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
