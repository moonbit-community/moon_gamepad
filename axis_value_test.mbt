///|
test "axis_value documented case" {
  let info = AxisInfo::new(0, 255, None)
  inspect(axis_value(info, 127, Axis::LeftStickY), content="0")
}

///|
test "axis_value overflow behavior" {
  let minv = @moonbitlang/core/int.min_value
  let maxv = @moonbitlang/core/int.max_value
  let info = AxisInfo::new(minv, maxv, None)
  let axis = Axis::LeftStickY
  inspect(axis_value(info, -1, axis), content="2.3283064365386963e-10")
  inspect(axis_value(info, 0, axis), content="-2.3283064365386963e-10")
  inspect(axis_value(info, 1, axis), content="-6.984919309616089e-10")
  inspect(axis_value(info, minv, axis), content="1")
  inspect(axis_value(info, maxv, axis), content="-1")
}

///|
test "btn_value overflow behavior" {
  let minv = @moonbitlang/core/int.min_value
  let maxv = @moonbitlang/core/int.max_value
  let info = AxisInfo::new(minv, maxv, None)
  inspect(btn_value(info, -1), content="0.4999999998835847")
  inspect(btn_value(info, 0), content="0.5000000001164153")
  inspect(btn_value(info, 1), content="0.500000000349246")
  inspect(btn_value(info, minv), content="0")
  inspect(btn_value(info, maxv), content="1")
}
