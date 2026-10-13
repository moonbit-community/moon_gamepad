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
fn build_ok_ff(builder : @gamepad.GilBuilder) -> @gamepad.Gil {
  let res : Result[@gamepad.Gil, @gamepad.GilError] = try
    builder.build() |> Ok
  catch {
    e => Err(e)
  }
  match res {
    Ok(g) => g
    Err(_) =>
      @gamepad.Gil::new_mock(0, update_state=false, default_filters=false)
  }
}

///|
test "finish without gamepads returns NoGamepads" {
  let g = build_ok_ff(@gamepad.GilBuilder::new().with_mock_gamepad_count(1))
  let res : Result[@gamepad.Effect, @gamepad.FfError] = try
    @gamepad.EffectBuilder::new().finish(g) |> Ok
  catch {
    e => Err(e)
  }
  inspect(res is Err(_), content="true")
}

///|
test "mock gamepad is not ff supported" {
  let g = build_ok_ff(@gamepad.GilBuilder::new().with_mock_gamepad_count(1))
  let res : Result[@gamepad.Effect, @gamepad.FfError] = try
    @gamepad.EffectBuilder::new()
    .add_gamepad_id(@gamepad.GamepadId::new(0))
    .rumble(1.0, 0.0)
    .finish(g)
    |> Ok
  catch {
    e => Err(e)
  }
  inspect(res is Err(_), content="true")
}
