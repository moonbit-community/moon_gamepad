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
  if ms <= 0L {
    { ms: 0L }
  } else {
    let tick = 50L
    let q = (ms + tick - 1L) / tick
    { ms: q * tick }
  }
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
pub fn Replay::dur(self : Replay) -> Int {
  self.play_for + self.with_delay
}

///|
fn Replay::wrap(self : Replay, ticks : Int) -> Int? {
  if ticks < self.after {
    None
  } else {
    let d = self.dur()
    if d <= 0 {
      None
    } else {
      Some((ticks - self.after) % d)
    }
  }
}

///|
fn clamp_u16(x : Double) -> Int {
  if x <= 0.0 || x != x {
    0
  } else if x >= 65535.0 {
    65535
  } else {
    x.to_int()
  }
}

///|
fn BaseEffectType::scaled(
  self : BaseEffectType,
  rhs : Double,
) -> BaseEffectType {
  let mg = match self {
    BaseEffectType::Weak(m) => m
    BaseEffectType::Strong(m) => m
  }
  let mg2 = clamp_u16(mg.to_double() * rhs)
  match self {
    BaseEffectType::Weak(_) => BaseEffectType::Weak(mg2)
    BaseEffectType::Strong(_) => BaseEffectType::Strong(mg2)
  }
}

///|
fn BaseEffect::magnitude_at(self : BaseEffect, ticks : Int) -> BaseEffectType {
  match self.scheduling.wrap(ticks) {
    None => self.kind.scaled(0.0)
    Some(wrapped) => {
      let gate = self.scheduling.at(wrapped)
      if gate == 0.0 {
        self.kind.scaled(0.0)
      } else {
        let att = gate * self.envelope.at(wrapped, self.scheduling.play_for)
        self.kind.scaled(att)
      }
    }
  }
}

///|
fn clamp_distance(x : Double, lo : Double, hi : Double) -> Double {
  let y = if x < lo { lo } else { x }
  if y > hi {
    hi
  } else {
    y
  }
}

///|
fn DistanceModel::attenuation(
  self : DistanceModel,
  distance : Double,
) -> Double {
  let mut distance = distance
  match self {
    DistanceModel::Linear(ref_distance~, rolloff_factor~, max_distance~) => {
      distance = if distance > max_distance { max_distance } else { distance }
      1.0 -
      rolloff_factor * (distance - ref_distance) / (max_distance - ref_distance)
    }
    DistanceModel::LinearClamped(ref_distance~, rolloff_factor~, max_distance~) => {
      distance = clamp_distance(distance, ref_distance, max_distance)
      1.0 -
      rolloff_factor * (distance - ref_distance) / (max_distance - ref_distance)
    }
    DistanceModel::Inverse(ref_distance~, rolloff_factor~) =>
      ref_distance / (ref_distance + rolloff_factor * (distance - ref_distance))
    DistanceModel::InverseClamped(ref_distance~, rolloff_factor~, max_distance~) => {
      distance = clamp_distance(distance, ref_distance, max_distance)
      ref_distance / (ref_distance + rolloff_factor * (distance - ref_distance))
    }
    DistanceModel::Exponential(ref_distance~, rolloff_factor~) =>
      @math.pow(distance / ref_distance, -rolloff_factor)
    DistanceModel::ExponentialClamped(
      ref_distance~,
      rolloff_factor~,
      max_distance~
    ) => {
      distance = clamp_distance(distance, ref_distance, max_distance)
      @math.pow(distance / ref_distance, -rolloff_factor)
    }
    DistanceModel::None => 1.0
  }
}

///|
pub struct Effect {
  gilrs : Gilrs
  effect_token : Int
  mut gamepads : Array[GamepadId]
  strong : Double
  weak : Double
  duration_ms : Int64
  base_effects : Array[BaseEffect]
  mut repeat_mode : FfRepeat
  mut distance_model : DistanceModel
  mut position : (Double, Double, Double)
  mut gain : Double
  mut playing_since_ms : Int64?
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
  let effect : Effect = {
    gilrs,
    effect_token: gilrs.new_effect_token(),
    gamepads: self.gamepads,
    strong: self.strong,
    weak: self.weak,
    duration_ms: self.duration_ms,
    base_effects: self.base_effects,
    repeat_mode: self.repeat_mode,
    distance_model: self.distance_model,
    position: self.position,
    gain: self.gain,
    playing_since_ms: None,
  }
  gilrs.ff_upsert_effect_from_handle(effect)
  effect
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
  self.gilrs.ff_set_effect_gamepads(self.effect_token, out)
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
  self.gilrs.ff_set_effect_gamepads(self.effect_token, self.gamepads)
}

///|
pub fn Effect::set_gain(self : Effect, gain : Double) -> Unit {
  self.gain = if gain < 0.0 { 0.0 } else { gain }
  self.gilrs.ff_set_effect_gain(self.effect_token, self.gain)
}

///|
pub fn Effect::set_repeat(self : Effect, repeat_mode : FfRepeat) -> Unit {
  self.repeat_mode = repeat_mode
  self.gilrs.ff_set_effect_repeat(self.effect_token, repeat_mode)
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
  self.gilrs.ff_set_effect_distance_model(self.effect_token, model)
}

///|
pub fn Effect::set_position(
  self : Effect,
  position : (Double, Double, Double),
) -> Unit {
  self.position = position
  self.gilrs.ff_set_effect_position(self.effect_token, position)
}

///|
pub fn Effect::play(self : Effect) -> Unit raise FfError {
  if self.gilrs.backend is None {
    raise FfError::NotSupported
  }
  self.gilrs.ff_upsert_effect_from_handle(self)
  let now = runtime_now_ms()
  let tick = self.gilrs.ff_now_tick(now)
  self.playing_since_ms = Some(now)
  self.gilrs.ff_play_effect(self.effect_token, tick)
  self.gilrs.ff_tick_update(now, true)
}

///|
pub fn Effect::stop(self : Effect) -> Unit raise FfError {
  if self.gilrs.backend is None {
    raise FfError::NotSupported
  }
  self.gilrs.ff_upsert_effect_from_handle(self)
  self.playing_since_ms = None
  self.gilrs.ff_stop_effect(self.effect_token)
  let now = runtime_now_ms()
  self.gilrs.ff_tick_update(now, true)
}
