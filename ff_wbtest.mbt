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
test "effect play/stop without backend errors" {
  let g = Gilrs::new_mock(1)
  let e : Effect = {
    gilrs: g,
    gamepads: [GamepadId::new(0)],
    strong: 1.0,
    weak: 1.0,
    duration_ms: 100L,
  }
  let r1 : Result[Unit, FfError] = try? e.play()
  inspect(r1 is Err(_), content="true")
  let r2 : Result[Unit, FfError] = try? e.stop()
  inspect(r2 is Err(_), content="true")
}
