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
test "Uuid::nil is 32 zeros" {
  inspect(Uuid::nil().simple(), content="00000000000000000000000000000000")
}

///|
test "Uuid::parse accepts hyphens and normalizes to lowercase" {
  let u = Uuid::parse("A0B1C2D3-E4F5-6789-ABCD-EF0123456789")
  inspect(u.simple(), content="a0b1c2d3e4f56789abcdef0123456789")
}

///|
test "Uuid::parse treats xinput as nil" {
  let u = Uuid::parse("xinput")
  inspect(u.simple(), content="00000000000000000000000000000000")
}

///|
test "Uuid::parse rejects invalid character" {
  let mut ok = true
  try {
    let _ = Uuid::parse("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")

  } catch {
    _ => ok = false
  }
  inspect(ok, content="false")
}

///|
test "Uuid::parse rejects invalid length" {
  let mut ok = true
  try {
    let _ = Uuid::parse("a0b1")

  } catch {
    _ => ok = false
  }
  inspect(ok, content="false")
}
