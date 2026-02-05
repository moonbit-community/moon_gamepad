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
suberror FfError {
  NotSupported
  NoGamepads
  Disconnected(GamepadId)
  FfNotSupported(GamepadId)
}

///|
pub struct Effect {
  gilrs : Gilrs
  gamepads : Array[GamepadId]
  strong : Double
  weak : Double
  duration_ms : Int64
}

///|
pub struct EffectBuilder {
  mut gamepads : Array[GamepadId]
  mut strong : Double
  mut weak : Double
  mut duration_ms : Int64
}

///|
pub fn EffectBuilder::new() -> EffectBuilder {
  { gamepads: [], strong: 0.0, weak: 0.0, duration_ms: 1000L }
}

///|
pub fn EffectBuilder::gamepads(
  self : EffectBuilder,
  ids : Array[GamepadId],
) -> EffectBuilder {
  self.gamepads = ids
  self
}

///|
pub fn EffectBuilder::add_gamepad(
  self : EffectBuilder,
  gamepad : Gamepad,
) -> EffectBuilder {
  self.gamepads.push(gamepad.id())
  self
}

///|
pub fn EffectBuilder::add_gamepad_id(
  self : EffectBuilder,
  id : GamepadId,
) -> EffectBuilder {
  self.gamepads.push(id)
  self
}

///|
pub fn EffectBuilder::rumble(
  self : EffectBuilder,
  strong : Double,
  weak : Double,
) -> EffectBuilder {
  self.strong = strong
  self.weak = weak
  self
}

///|
pub fn EffectBuilder::duration(
  self : EffectBuilder,
  duration_ms : Int64,
) -> EffectBuilder {
  self.duration_ms = duration_ms
  self
}

///|
fn to_duration_int(ms : Int64) -> Int {
  if ms <= 0L {
    0
  } else if ms >= 0x7FFF_FFFFL {
    0x7FFF_FFFF
  } else {
    ms.to_int()
  }
}

///|
pub fn EffectBuilder::finish(
  self : EffectBuilder,
  gilrs : Gilrs,
) -> Effect raise FfError {
  if self.gamepads.length() == 0 {
    raise FfError::NoGamepads
  }
  // Validate: connected + ff supported.
  for id in self.gamepads {
    match gilrs.gamepad(id) {
      None => raise FfError::Disconnected(id)
      Some(gp) =>
        if !gp.is_connected() {
          raise FfError::Disconnected(id)
        } else if !gp.is_ff_supported() {
          raise FfError::FfNotSupported(id)
        }
    }
  }
  // Must have a native backend to talk to.
  match gilrs.backend {
    None => raise FfError::NotSupported
    Some(_) => ()
  }
  {
    gilrs,
    gamepads: self.gamepads,
    strong: self.strong,
    weak: self.weak,
    duration_ms: self.duration_ms,
  }
}

///|
pub fn Effect::play(self : Effect) -> Unit raise FfError {
  match self.gilrs.backend {
    None => raise FfError::NotSupported
    Some(b) => {
      let dur = to_duration_int(self.duration_ms)
      for id in self.gamepads {
        let ok = b.set_rumble(id.value(), self.strong, self.weak, dur)
        if !ok {
          raise FfError::NotSupported
        }
      }
    }
  }
}

///|
pub fn Effect::stop(self : Effect) -> Unit raise FfError {
  match self.gilrs.backend {
    None => raise FfError::NotSupported
    Some(b) =>
      for id in self.gamepads {
        let ok = b.set_rumble(id.value(), 0.0, 0.0, 0)
        if !ok {
          raise FfError::NotSupported
        }
      }
  }
}
