///|
test "clamp" {
  inspect(clamp(-1.0, 0.0, 1.0), content="0")
  inspect(clamp(0.5, 0.0, 1.0), content="0.5")
  inspect(clamp(2.0, 0.0, 1.0), content="1")
}
