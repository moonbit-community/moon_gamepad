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
  InvalidDistanceModel(DistanceModelError)
}

///|
suberror DistanceModelError {
  InvalidReferenceDistance
  InvalidRolloffFactor
  InvalidMaxDistance
  InvalidModelParameter
}

///|
pub struct Ticks {
  ms : Int64
}

///|
pub fn Ticks::from_ms(ms : Int64) -> Ticks {
  { ms, }
}

///|
pub fn Ticks::as_ms(self : Ticks) -> Int64 {
  self.ms
}

///|
pub(all) enum BaseEffectType {
  Weak(Int)
  Strong(Int)
}

///|
pub struct BaseEffect {
  kind : BaseEffectType
  scheduling : Replay
  envelope : Envelope
}

///|
pub fn BaseEffect::default() -> BaseEffect {
  {
    kind: BaseEffectType::Weak(0),
    scheduling: Replay::default(),
    envelope: Envelope::default(),
  }
}

///|
pub enum FfRepeat {
  Infinitely
  For(Int64)
}

///|
let _ff_repeat_keepalive : Array[FfRepeat] = [FfRepeat::For(0L)]

///|
pub enum DistanceModel {
  None
  Linear(
    ref_distance~ : Double,
    rolloff_factor~ : Double,
    max_distance~ : Double
  )
  LinearClamped(
    ref_distance~ : Double,
    rolloff_factor~ : Double,
    max_distance~ : Double
  )
  Inverse(ref_distance~ : Double, rolloff_factor~ : Double)
  InverseClamped(
    ref_distance~ : Double,
    rolloff_factor~ : Double,
    max_distance~ : Double
  )
  Exponential(ref_distance~ : Double, rolloff_factor~ : Double)
  ExponentialClamped(
    ref_distance~ : Double,
    rolloff_factor~ : Double,
    max_distance~ : Double
  )
}

///|
let _distance_model_keepalive : Array[DistanceModel] = [
  DistanceModel::Linear(ref_distance=1.0, rolloff_factor=1.0, max_distance=2.0),
  DistanceModel::LinearClamped(
    ref_distance=1.0,
    rolloff_factor=1.0,
    max_distance=2.0,
  ),
  DistanceModel::Inverse(ref_distance=1.0, rolloff_factor=1.0),
  DistanceModel::InverseClamped(
    ref_distance=1.0,
    rolloff_factor=1.0,
    max_distance=2.0,
  ),
  DistanceModel::Exponential(ref_distance=1.0, rolloff_factor=1.0),
  DistanceModel::ExponentialClamped(
    ref_distance=1.0,
    rolloff_factor=1.0,
    max_distance=2.0,
  ),
]

///|
pub fn DistanceModel::validate(
  self : DistanceModel,
) -> Unit raise DistanceModelError {
  let (ref_distance, rolloff_factor, max_distance) = match self {
    DistanceModel::None => (0.0, 0.0, 0.0)
    DistanceModel::Linear(ref_distance~, rolloff_factor~, max_distance~) => {
      if ref_distance == max_distance {
        raise DistanceModelError::InvalidModelParameter
      }
      (ref_distance, rolloff_factor, max_distance)
    }
    DistanceModel::LinearClamped(ref_distance~, rolloff_factor~, max_distance~) => {
      if ref_distance == max_distance {
        raise DistanceModelError::InvalidModelParameter
      }
      (ref_distance, rolloff_factor, max_distance)
    }
    DistanceModel::Inverse(ref_distance~, rolloff_factor~) => {
      if ref_distance <= 0.0 {
        raise DistanceModelError::InvalidModelParameter
      }
      (ref_distance, rolloff_factor, 0.0)
    }
    DistanceModel::InverseClamped(ref_distance~, rolloff_factor~, max_distance~) => {
      if ref_distance <= 0.0 {
        raise DistanceModelError::InvalidModelParameter
      }
      (ref_distance, rolloff_factor, max_distance)
    }
    DistanceModel::Exponential(ref_distance~, rolloff_factor~) => {
      if ref_distance <= 0.0 {
        raise DistanceModelError::InvalidModelParameter
      }
      (ref_distance, rolloff_factor, 0.0)
    }
    DistanceModel::ExponentialClamped(
      ref_distance~,
      rolloff_factor~,
      max_distance~
    ) => {
      if ref_distance <= 0.0 {
        raise DistanceModelError::InvalidModelParameter
      }
      (ref_distance, rolloff_factor, max_distance)
    }
  }
  if ref_distance < 0.0 {
    raise DistanceModelError::InvalidReferenceDistance
  }
  if rolloff_factor < 0.0 {
    raise DistanceModelError::InvalidRolloffFactor
  }
  if max_distance < 0.0 {
    raise DistanceModelError::InvalidMaxDistance
  }
}

///|
pub struct Envelope {
  attack_length : Int
  attack_level : Double
  fade_length : Int
  fade_level : Double
}

///|
pub fn Envelope::default() -> Envelope {
  { attack_length: 0, attack_level: 1.0, fade_length: 0, fade_level: 1.0 }
}

///|
pub fn Envelope::at(self : Envelope, ticks : Int, dur : Int) -> Double {
  if ticks < self.attack_length {
    self.attack_level +
    ticks.to_double() *
    (1.0 - self.attack_level) /
    self.attack_length.to_double()
  } else if ticks + self.fade_length > dur {
    1.0 +
    (ticks + self.fade_length - dur).to_double() *
    (self.fade_level - 1.0) /
    self.fade_length.to_double()
  } else {
    1.0
  }
}

///|
pub struct Replay {
  after : Int
  play_for : Int
  with_delay : Int
}

///|
pub fn Replay::default() -> Replay {
  { after: 0, play_for: 1, with_delay: 0 }
}

///|
pub fn Replay::at(self : Replay, ticks : Int) -> Double {
  if ticks >= self.play_for {
    0.0
  } else {
    1.0
  }
}

///|
pub struct Effect {
  gilrs : Gilrs
  mut gamepads : Array[GamepadId]
  strong : Double
  weak : Double
  duration_ms : Int64
  base_effects : Array[BaseEffect]
  mut repeat_mode : FfRepeat
  mut distance_model : DistanceModel
  mut position : (Double, Double, Double)
  mut gain : Double
}

///|
pub struct EffectBuilder {
  gamepads : Array[GamepadId]
  base_effects : Array[BaseEffect]
  mut repeat_mode : FfRepeat
  mut distance_model : DistanceModel
  mut position : (Double, Double, Double)
  mut gain : Double
  mut strong : Double
  mut weak : Double
  mut duration_ms : Int64
}

///|
pub fn EffectBuilder::new() -> EffectBuilder {
  {
    gamepads: [],
    base_effects: [],
    repeat_mode: FfRepeat::Infinitely,
    distance_model: DistanceModel::None,
    position: (0.0, 0.0, 0.0),
    gain: 1.0,
    strong: 0.0,
    weak: 0.0,
    duration_ms: 1000L,
  }
}

///|
fn contains_gamepad_id(ids : Array[GamepadId], id : GamepadId) -> Bool {
  for x in ids {
    if x.value() == id.value() {
      return true
    }
  }
  false
}

///|
pub fn EffectBuilder::gamepads(
  self : EffectBuilder,
  ids : Array[GamepadId],
) -> EffectBuilder {
  for id in ids {
    if !contains_gamepad_id(self.gamepads, id) {
      self.gamepads.push(id)
    }
  }
  self
}

///|
pub fn EffectBuilder::add_gamepad(
  self : EffectBuilder,
  gamepad : Gamepad,
) -> EffectBuilder {
  let id = gamepad.id()
  if !contains_gamepad_id(self.gamepads, id) {
    self.gamepads.push(id)
  }
  self
}

///|
pub fn EffectBuilder::add_gamepad_id(
  self : EffectBuilder,
  id : GamepadId,
) -> EffectBuilder {
  if !contains_gamepad_id(self.gamepads, id) {
    self.gamepads.push(id)
  }
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
pub fn EffectBuilder::add_effect(
  self : EffectBuilder,
  effect : BaseEffect,
) -> EffectBuilder {
  self.base_effects.push(effect)
  self
}

///|
pub fn EffectBuilder::repeat(
  self : EffectBuilder,
  repeat_mode : FfRepeat,
) -> EffectBuilder {
  self.repeat_mode = repeat_mode
  self
}

///|
pub fn EffectBuilder::distance_model(
  self : EffectBuilder,
  model : DistanceModel,
) -> EffectBuilder {
  self.distance_model = model
  self
}

///|
pub fn EffectBuilder::position(
  self : EffectBuilder,
  position : (Double, Double, Double),
) -> EffectBuilder {
  self.position = position
  self
}

///|
pub fn EffectBuilder::gain(
  self : EffectBuilder,
  gain : Double,
) -> EffectBuilder {
  self.gain = if gain < 0.0 { 0.0 } else { gain }
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
  self.distance_model.validate() catch {
    err => raise FfError::InvalidDistanceModel(err)
  }
  {
    gilrs,
    gamepads: self.gamepads,
    strong: self.strong,
    weak: self.weak,
    duration_ms: self.duration_ms,
    base_effects: self.base_effects,
    repeat_mode: self.repeat_mode,
    distance_model: self.distance_model,
    position: self.position,
    gain: self.gain,
  }
}

///|
pub fn Effect::set_gamepads(
  self : Effect,
  ids : Array[GamepadId],
  gilrs : Gilrs,
) -> Unit raise FfError {
  let out : Array[GamepadId] = []
  for id in ids {
    match gilrs.connected_gamepad(id) {
      None => raise FfError::Disconnected(id)
      Some(gp) =>
        if !gp.is_ff_supported() {
          raise FfError::FfNotSupported(id)
        } else if !contains_gamepad_id(out, id) {
          out.push(id)
        }
    }
  }
  self.gamepads = out
}

///|
pub fn Effect::add_gamepad(
  self : Effect,
  gamepad : Gamepad,
) -> Unit raise FfError {
  let id = gamepad.id()
  if !gamepad.is_connected() {
    raise FfError::Disconnected(id)
  }
  if !gamepad.is_ff_supported() {
    raise FfError::FfNotSupported(id)
  }
  if !contains_gamepad_id(self.gamepads, id) {
    self.gamepads.push(id)
  }
}

///|
pub fn Effect::set_gain(self : Effect, gain : Double) -> Unit {
  self.gain = if gain < 0.0 { 0.0 } else { gain }
}

///|
pub fn Effect::set_repeat(self : Effect, repeat_mode : FfRepeat) -> Unit {
  self.repeat_mode = repeat_mode
}

///|
pub fn Effect::set_distance_model(
  self : Effect,
  model : DistanceModel,
) -> Unit raise FfError {
  model.validate() catch {
    err => raise FfError::InvalidDistanceModel(err)
  }
  self.distance_model = model
}

///|
pub fn Effect::set_position(
  self : Effect,
  position : (Double, Double, Double),
) -> Unit {
  self.position = position
}

///|
fn magnitude_to_amp(magnitude : Int) -> Double {
  clamp(magnitude.to_double() / 65535.0, 0.0, 1.0)
}

///|
fn base_effect_motor_amplitudes(effect : BaseEffect) -> (Double, Double) {
  match effect.kind {
    BaseEffectType::Weak(magnitude) => (0.0, magnitude_to_amp(magnitude))
    BaseEffectType::Strong(magnitude) => (magnitude_to_amp(magnitude), 0.0)
  }
}

///|
pub fn Effect::play(self : Effect) -> Unit raise FfError {
  match self.gilrs.backend {
    None => raise FfError::NotSupported
    Some(b) => {
      let dur = to_duration_int(self.duration_ms)
      let mut base_strong = 0.0
      let mut base_weak = 0.0
      for effect in self.base_effects {
        let (s, w) = base_effect_motor_amplitudes(effect)
        base_strong = base_strong + s
        base_weak = base_weak + w
      }
      ignore(self.repeat_mode)
      ignore(self.distance_model)
      ignore(self.position)
      let strong = clamp((self.strong + base_strong) * self.gain, 0.0, 1.0)
      let weak = clamp((self.weak + base_weak) * self.gain, 0.0, 1.0)
      for id in self.gamepads {
        let ok = b.set_rumble(id.value(), strong, weak, dur)
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
