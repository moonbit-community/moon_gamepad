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
suberror GilError {
  NotImplemented
  InvalidAxisToBtn
}

///|
let _gilrs_error_keepalive : Array[GilError] = [GilError::NotImplemented]

///|
pub fn GilError::is_invalid_axis_to_btn(self : GilError) -> Bool {
  match self {
    GilError::InvalidAxisToBtn => true
    _ => false
  }
}

///|
pub struct GamepadData {
  state : GamepadState
  mut connected : Bool
  mut mapping : Mapping
  mut name : String
  mut uuid : Uuid
  mut vendor_id : Int?
  mut product_id : Int?
  mut ff_supported : Bool
  mut listener_position : (Double, Double, Double)
  mut power_info : PowerInfo
  mut axes : Array[Code]
  mut buttons : Array[Code]
  mut axis_info : Array[(Code, AxisInfo)]
  deadzones : Array[(Code, Double)]
  have_sent_nonzero_for_axis : Array[Bool]
}

///|
fn GamepadData::new() -> GamepadData {
  {
    state: GamepadState::new(),
    connected: true,
    mapping: Mapping::new(),
    name: "",
    uuid: Uuid::nil(),
    vendor_id: None,
    product_id: None,
    ff_supported: false,
    listener_position: (0.0, 0.0, 0.0),
    power_info: PowerInfo::Unknown,
    axes: [],
    buttons: [],
    axis_info: [],
    deadzones: [],
    have_sent_nonzero_for_axis: Array::make(6, false),
  }
}

///|
const FF_TICK_DURATION_MS : Int64 = 50L

///|
priv struct FfMagnitude {
  strong : Int
  weak : Int
}

///|
priv enum FfEffectState {
  Playing(Int)
  Stopped
}

///|
struct FfEffectSource {
  token : Int
  base_effects : Array[BaseEffect]
  mut devices : Array[Int]
  mut repeat_mode : FfRepeat
  mut distance_model : DistanceModel
  mut position : (Double, Double, Double)
  mut gain : Double
  mut state : FfEffectState
  strong : Int
  weak : Int
}

///|
pub struct Gil {
  mut counter : Int64
  update_state : Bool
  mut default_filters : Bool
  mut axis_to_btn_pressed : Double
  mut axis_to_btn_released : Double
  events : Array[Event]
  mut events_head : Int
  gamepads_data : Array[GamepadData]
  mappings : MappingDb
  mut now_ms : Int64
  mut next_effect_token : Int
  ff_tick_base_ms : Int64
  mut ff_tick : Int
  mut ff_dirty : Bool
  ff_effects : Array[FfEffectSource]
  mut ff_events : Array[Event]
  mut ff_events_head : Int
  backend : NativeBackend?
}

///|
pub fn Gil::new_mock(
  gamepad_count : Int,
  update_state? : Bool = true,
  default_filters? : Bool = true,
) -> Gil {
  let data : Array[GamepadData] = []
  for _ in 0..<gamepad_count {
    data.push(GamepadData::new())
  }
  {
    counter: 0L,
    update_state,
    default_filters,
    axis_to_btn_pressed: 0.75,
    axis_to_btn_released: 0.65,
    events: [],
    events_head: 0,
    gamepads_data: data,
    mappings: MappingDb::new(),
    now_ms: 0L,
    next_effect_token: 1,
    ff_tick_base_ms: runtime_now_ms(),
    ff_tick: 0,
    ff_dirty: false,
    ff_effects: [],
    ff_events: [],
    ff_events_head: 0,
    backend: None,
  }
}

///|
pub fn Gil::new_native(
  update_state? : Bool = true,
  default_filters? : Bool = true,
) -> Gil {
  {
    counter: 0L,
    update_state,
    default_filters,
    axis_to_btn_pressed: 0.75,
    axis_to_btn_released: 0.65,
    events: [],
    events_head: 0,
    gamepads_data: [],
    mappings: MappingDb::new(),
    now_ms: 0L,
    next_effect_token: 1,
    ff_tick_base_ms: runtime_now_ms(),
    ff_tick: 0,
    ff_dirty: false,
    ff_effects: [],
    ff_events: [],
    ff_events_head: 0,
    backend: Some(NativeBackend::new()),
  }
}

///|
pub fn Gil::load_mappings(self : Gil, s : String) -> Unit {
  self.mappings.insert(s)
}

///|
pub fn Gil::set_axis_to_btn(
  self : Gil,
  pressed : Double,
  released : Double,
) -> Unit raise GilError {
  if pressed <= released ||
    pressed < 0.0 ||
    pressed > 1.0 ||
    released < 0.0 ||
    released > 1.0 {
    raise GilError::InvalidAxisToBtn
  }
  self.axis_to_btn_pressed = pressed
  self.axis_to_btn_released = released
}

///|
pub fn Gil::with_default_filters(self : Gil, enabled : Bool) -> Gil {
  self.default_filters = enabled
  self
}

///|
pub fn Gil::default_filters_enabled(self : Gil) -> Bool {
  self.default_filters
}

///|
pub fn Gil::update_state_enabled(self : Gil) -> Bool {
  self.update_state
}

///|
pub fn Gil::set_time(self : Gil, now_ms : Int64) -> Unit {
  self.now_ms = now_ms
}

///|
pub fn Gil::time(self : Gil) -> Int64 {
  self.now_ms
}

///|
fn contains_id(ids : Array[Int], id : Int) -> Bool {
  for x in ids {
    if x == id {
      return true
    }
  }
  false
}

///|
fn Gil::new_effect_token(self : Gil) -> Int {
  let token = self.next_effect_token
  if token >= 0x7FFF_FFFF {
    self.next_effect_token = 1
  } else {
    self.next_effect_token = token + 1
  }
  token
}

///|
fn u16_saturating_add(lhs : Int, rhs : Int) -> Int {
  let sum = lhs + rhs
  if sum >= 65535 {
    65535
  } else if sum <= 0 {
    0
  } else {
    sum
  }
}

///|
fn u16_scale(magnitude : Int, factor : Double) -> Int {
  if factor <= 0.0 || Double::is_nan(factor) {
    return 0
  }
  let x = magnitude.to_double() * factor
  if x <= 0.0 || Double::is_nan(x) {
    0
  } else if x >= 65535.0 {
    65535
  } else {
    x.to_int()
  }
}

///|
fn u16_from_amp(amp : Double) -> Int {
  if amp <= 0.0 || Double::is_nan(amp) {
    0
  } else if amp >= 1.0 {
    65535
  } else {
    (amp * 65535.0).to_int()
  }
}

///|
fn amp_from_u16(magnitude : Int) -> Double {
  clamp(magnitude.to_double() / 65535.0, 0.0, 1.0)
}

///|
fn Gil::ff_find_effect_idx(self : Gil, token : Int) -> Int? {
  for i in 0..<self.ff_effects.length() {
    if self.ff_effects[i].token == token {
      return Some(i)
    }
  }
  None
}

///|
fn ff_devices_contains(devices : Array[Int], id : Int) -> Bool {
  for x in devices {
    if x == id {
      return true
    }
  }
  false
}

///|
fn ff_repeat_max_ticks(repeat : FfRepeat) -> Int? {
  match repeat {
    FfRepeat::Infinitely => None
    FfRepeat::For(ms) => {
      let q = Ticks::from_ms(ms)
      let ticks = (q.as_ms() / FF_TICK_DURATION_MS).to_int()
      Some(ticks)
    }
  }
}

///|
fn Gil::ff_take_next_event(self : Gil) -> Event? {
  if self.ff_events_head >= self.ff_events.length() {
    self.ff_events = []
    self.ff_events_head = 0
    return None
  }
  let ev = self.ff_events[self.ff_events_head]
  self.ff_events_head = self.ff_events_head + 1
  Some(ev)
}

///|
fn Gil::ff_push_event(self : Gil, ev : Event) -> Unit {
  self.ff_events.push(ev)
}

///|
fn Gil::ff_now_tick(self : Gil, now_ms : Int64) -> Int {
  let elapsed = now_ms - self.ff_tick_base_ms
  if elapsed <= 0L {
    0
  } else {
    (elapsed / FF_TICK_DURATION_MS).to_int()
  }
}

///|
fn Gil::ff_has_active_effect(self : Gil) -> Bool {
  for eff in self.ff_effects {
    match eff.state {
      FfEffectState::Playing(_) => return true
      FfEffectState::Stopped => ()
    }
  }
  false
}

///|
fn Gil::ff_next_tick_wait_ms(self : Gil, now_ms : Int64) -> Int {
  let tick = self.ff_now_tick(now_ms)
  let next_tick_at = self.ff_tick_base_ms +
    (tick.to_int64() + 1L) * FF_TICK_DURATION_MS
  let wait = next_tick_at - now_ms
  if wait <= 0L {
    0
  } else if wait >= 0x7FFF_FFFFL {
    0x7FFF_FFFF
  } else {
    wait.to_int()
  }
}

///|
fn Gil::ff_upsert_effect_from_handle(self : Gil, effect : Effect) -> Unit {
  let token = effect.effect_token
  let devices : Array[Int] = []
  for gid in effect.gamepads {
    let id = gid.value()
    if id >= 0 && !contains_id(devices, id) {
      devices.push(id)
    }
  }
  let base_effects = effect.base_effects.copy()
  let strong_u16 = u16_from_amp(effect.strong)
  let weak_u16 = u16_from_amp(effect.weak)
  let mut state = FfEffectState::Stopped
  match effect.playing_since_ms {
    None => ()
    Some(_) => state = FfEffectState::Playing(self.ff_tick)
  }
  match self.ff_find_effect_idx(token) {
    None =>
      self.ff_effects.push({
        token,
        base_effects,
        devices,
        repeat_mode: effect.repeat_mode,
        distance_model: effect.distance_model,
        position: effect.position,
        gain: effect.gain,
        state,
        strong: strong_u16,
        weak: weak_u16,
      })
    Some(idx) =>
      self.ff_effects[idx] = {
        token,
        base_effects,
        devices,
        repeat_mode: effect.repeat_mode,
        distance_model: effect.distance_model,
        position: effect.position,
        gain: effect.gain,
        state,
        strong: strong_u16,
        weak: weak_u16,
      }
  }
}

///|
fn Gil::ff_set_effect_gamepads(
  self : Gil,
  token : Int,
  gamepads : Array[GamepadId],
) -> Unit {
  match self.ff_find_effect_idx(token) {
    None => ()
    Some(idx) => {
      let devices : Array[Int] = []
      for gid in gamepads {
        let id = gid.value()
        if id >= 0 && !contains_id(devices, id) {
          devices.push(id)
        }
      }
      self.ff_effects[idx].devices = devices
    }
  }
  self.ff_dirty = true
}

///|
fn Gil::ff_set_effect_repeat(
  self : Gil,
  token : Int,
  repeat : FfRepeat,
) -> Unit {
  match self.ff_find_effect_idx(token) {
    None => ()
    Some(idx) => self.ff_effects[idx].repeat_mode = repeat
  }
  self.ff_dirty = true
}

///|
fn Gil::ff_set_effect_distance_model(
  self : Gil,
  token : Int,
  model : DistanceModel,
) -> Unit {
  match self.ff_find_effect_idx(token) {
    None => ()
    Some(idx) => self.ff_effects[idx].distance_model = model
  }
  self.ff_dirty = true
}

///|
fn Gil::ff_set_effect_position(
  self : Gil,
  token : Int,
  position : (Double, Double, Double),
) -> Unit {
  match self.ff_find_effect_idx(token) {
    None => ()
    Some(idx) => self.ff_effects[idx].position = position
  }
  self.ff_dirty = true
}

///|
fn Gil::ff_set_effect_gain(self : Gil, token : Int, gain : Double) -> Unit {
  match self.ff_find_effect_idx(token) {
    None => ()
    Some(idx) => self.ff_effects[idx].gain = gain
  }
  self.ff_dirty = true
}

///|
fn Gil::ff_play_effect(self : Gil, token : Int, tick : Int) -> Unit {
  match self.ff_find_effect_idx(token) {
    None => ()
    Some(idx) => self.ff_effects[idx].state = FfEffectState::Playing(tick)
  }
  self.ff_dirty = true
}

///|
fn Gil::ff_stop_effect(self : Gil, token : Int) -> Unit {
  match self.ff_find_effect_idx(token) {
    None => ()
    Some(idx) => self.ff_effects[idx].state = FfEffectState::Stopped
  }
  self.ff_dirty = true
}

///|
fn distance(
  a : (Double, Double, Double),
  b : (Double, Double, Double),
) -> Double {
  let (ax, ay, az) = a
  let (bx, by, bz) = b
  let dx = bx - ax
  let dy = by - ay
  let dz = bz - az
  Double::sqrt(dx * dx + dy * dy + dz * dz)
}

///|
fn Gil::ff_combine_base_effects(
  self : Gil,
  idx : Int,
  tick : Int,
  actor_pos : (Double, Double, Double),
  now_ms : Int64,
) -> FfMagnitude {
  let mut rel_ticks = 0
  match self.ff_effects[idx].state {
    FfEffectState::Stopped => return { strong: 0, weak: 0 }
    FfEffectState::Playing(since_tick) => {
      rel_ticks = tick - since_tick
      if rel_ticks < 0 {
        rel_ticks = 0
      }
    }
  }

  match ff_repeat_max_ticks(self.ff_effects[idx].repeat_mode) {
    None => ()
    Some(max_dur) =>
      if rel_ticks > max_dur {
        self.ff_effects[idx].state = FfEffectState::Stopped
        for id in self.ff_effects[idx].devices {
          self.ff_push_event(
            Event::at(
              GamepadId::new(id),
              EventType::ForceFeedbackEffectCompleted,
              now_ms,
            ),
          )
        }
        return { strong: 0, weak: 0 }
      }
  }

  let dist = distance(self.ff_effects[idx].position, actor_pos)
  let attenuation = self.ff_effects[idx].distance_model.attenuation(dist) *
    self.ff_effects[idx].gain
  if attenuation < 0.05 {
    return { strong: 0, weak: 0 }
  }

  let mut strong = self.ff_effects[idx].strong
  let mut weak = self.ff_effects[idx].weak
  for effect in self.ff_effects[idx].base_effects {
    match effect.magnitude_at(rel_ticks) {
      BaseEffectType::Strong(magnitude) =>
        strong = u16_saturating_add(strong, magnitude)
      BaseEffectType::Weak(magnitude) =>
        weak = u16_saturating_add(weak, magnitude)
    }
  }
  { strong: u16_scale(strong, attenuation), weak: u16_scale(weak, attenuation) }
}

///|
fn Gil::ff_tick_update(self : Gil, now_ms : Int64, force : Bool) -> Unit {
  match self.backend {
    None => ()
    Some(b) => {
      let tick = self.ff_now_tick(now_ms)
      let should_tick = force || self.ff_dirty || tick != self.ff_tick
      if !should_tick {
        return
      }
      self.ff_tick = tick
      self.ff_dirty = false

      for dev_id in 0..<self.gamepads_data.length() {
        let data = self.gamepads_data[dev_id]
        if !data.connected || !data.ff_supported {
          continue
        }
        let mut strong = 0
        let mut weak = 0
        for eff_idx in 0..<self.ff_effects.length() {
          if ff_devices_contains(self.ff_effects[eff_idx].devices, dev_id) {
            let mag = self.ff_combine_base_effects(
              eff_idx,
              tick,
              data.listener_position,
              now_ms,
            )
            strong = u16_saturating_add(strong, mag.strong)
            weak = u16_saturating_add(weak, mag.weak)
          }
        }
        let _ = b.set_rumble(
          dev_id,
          amp_from_u16(strong),
          amp_from_u16(weak),
          100,
        )
      }
    }
  }
}

///|
pub fn Gil::insert_event(self : Gil, ev : Event) -> Unit {
  self.events.push(ev)
}

///|
fn Gil::apply_connection_event(self : Gil, ev : Event) -> Unit {
  let id = ev.id().value()
  match ev.event() {
    EventType::Connected => self.set_connected(id, true)
    EventType::Disconnected => self.set_connected(id, false)
    _ => ()
  }
}

///|
fn Gil::ensure_gamepad_data(self : Gil, id : Int) -> Unit {
  if id < 0 {
    return
  }
  while self.gamepads_data.length() <= id {
    self.gamepads_data.push(GamepadData::new())
  }
}

///|
fn Gil::set_connected(self : Gil, id : Int, connected : Bool) -> Unit {
  self.ensure_gamepad_data(id)
  if id < 0 || id >= self.gamepads_data.length() {
    return
  }
  self.gamepads_data[id].connected = connected
}

///|
fn Gil::apply_identity_mapping(self : Gil, id : Int) -> Unit {
  self.ensure_gamepad_data(id)
  if id < 0 || id >= self.gamepads_data.length() {
    return
  }
  let data = self.gamepads_data[id]
  let m = Mapping::new_default()
  for code in data.buttons {
    match axis_or_btn_from_code(code) {
      None => ()
      Some(el) => m.insert(code, el)
    }
  }
  for code in data.axes {
    match axis_or_btn_from_code(code) {
      None => ()
      Some(el) => m.insert(code, el)
    }
  }
  data.mapping = m
}

///|
fn find_axis_info(infos : Array[(Code, AxisInfo)], code : Code) -> AxisInfo? {
  for pair in infos {
    let (c, info) = pair
    if c == code {
      return Some(info)
    }
  }
  None
}

///|
fn Gil::refresh_gamepad_data_on_connected(
  self : Gil,
  id : Int,
  existed_before : Bool,
) -> Unit {
  if id < 0 || id >= self.gamepads_data.length() {
    return
  }
  let data = GamepadData::new()
  data.connected = true

  if existed_before {
    let prev = self.gamepads_data[id]
    data.name = prev.name
    data.uuid = prev.uuid
    data.vendor_id = prev.vendor_id
    data.product_id = prev.product_id
    data.ff_supported = prev.ff_supported
    data.power_info = prev.power_info
    data.axes = prev.axes
    data.buttons = prev.buttons
    data.axis_info = prev.axis_info
  }

  match self.backend {
    None => ()
    Some(b) => {
      data.name = b.name(id)
      let uuid_s = b.uuid_simple(id)
      let uuid = Uuid::parse(uuid_s) catch { _ => Uuid::nil() }
      data.uuid = uuid
      data.vendor_id = b.vendor_id(id)
      data.product_id = b.product_id(id)
      data.ff_supported = b.is_ff_supported(id)
      data.power_info = b.power_info(id)
      data.axes = b.axes(id)
      data.buttons = b.buttons(id)
      let infos : Array[(Code, AxisInfo)] = []
      for c in data.axes {
        match b.axis_info(id, c) {
          None => ()
          Some(info) => infos.push((c, info))
        }
      }
      data.axis_info = infos
    }
  }

  self.gamepads_data[id] = data
  self.apply_identity_mapping(id)
  let uuid = self.gamepads_data[id].uuid
  match self.mappings.get(uuid) {
    None => ()
    Some(line) => {
      let parsed : Result[Mapping, Error] = try? Mapping::parse_sdl_mapping(
        line,
        self.gamepads_data[id].buttons,
        self.gamepads_data[id].axes,
      )
      match parsed {
        Ok(m) => self.gamepads_data[id].mapping = m
        Err(_) => ()
      }
    }
  }
}

///|
fn Gil::finish_gamepads_creation(self : Gil) -> Unit {
  match self.backend {
    None => ()
    Some(b) => {
      let hint = b.last_gamepad_hint()
      for id in 0..<hint {
        let existed_before = id >= 0 && id < self.gamepads_data.length()
        self.ensure_gamepad_data(id)
        self.refresh_gamepad_data_on_connected(id, existed_before)
        self.set_connected(id, b.is_connected(id))
      }
    }
  }
}

///|
fn Gil::push_native_event(self : Gil, ne : NativeEvent) -> Unit {
  let id = ne.id
  let existed_before = id >= 0 && id < self.gamepads_data.length()
  self.ensure_gamepad_data(id)
  let gid = GamepadId::new(id)
  match ne.tag {
    NativeEventTag::Connected => {
      self.refresh_gamepad_data_on_connected(id, existed_before)
      self.insert_event(Event::at(gid, EventType::Connected, ne.time_ms))
    }
    NativeEventTag::Disconnected => {
      match self.backend {
        None => ()
        Some(b) => {
          let _ = b.set_rumble(id, 0.0, 0.0, 0)
        }
      }
      self.set_connected(id, false)
      self.insert_event(Event::at(gid, EventType::Disconnected, ne.time_ms))
    }
    NativeEventTag::ButtonPressed => {
      let code = ne.code
      match self.axis_or_btn_name(gid, code) {
        Some(AxisOrBtn::Btn(btn)) => {
          self.insert_event(
            Event::at(gid, EventType::ButtonPressed(btn, code), ne.time_ms),
          )
          self.insert_event(
            Event::at(gid, EventType::ButtonChanged(btn, 1.0, code), ne.time_ms),
          )
        }
        Some(AxisOrBtn::Axis(axis)) =>
          self.insert_event(
            Event::at(gid, EventType::AxisChanged(axis, 1.0, code), ne.time_ms),
          )
        None => {
          self.insert_event(
            Event::at(
              gid,
              EventType::ButtonPressed(Button::Unknown, code),
              ne.time_ms,
            ),
          )
          self.insert_event(
            Event::at(
              gid,
              EventType::ButtonChanged(Button::Unknown, 1.0, code),
              ne.time_ms,
            ),
          )
        }
      }
    }
    NativeEventTag::ButtonReleased => {
      let code = ne.code
      match self.axis_or_btn_name(gid, code) {
        Some(AxisOrBtn::Btn(btn)) => {
          self.insert_event(
            Event::at(gid, EventType::ButtonReleased(btn, code), ne.time_ms),
          )
          self.insert_event(
            Event::at(gid, EventType::ButtonChanged(btn, 0.0, code), ne.time_ms),
          )
        }
        Some(AxisOrBtn::Axis(axis)) =>
          self.insert_event(
            Event::at(gid, EventType::AxisChanged(axis, 0.0, code), ne.time_ms),
          )
        None => {
          self.insert_event(
            Event::at(
              gid,
              EventType::ButtonReleased(Button::Unknown, code),
              ne.time_ms,
            ),
          )
          self.insert_event(
            Event::at(
              gid,
              EventType::ButtonChanged(Button::Unknown, 0.0, code),
              ne.time_ms,
            ),
          )
        }
      }
    }
    NativeEventTag::AxisChanged => {
      if id < 0 || id >= self.gamepads_data.length() {
        return
      }
      let code = ne.code
      let info = match find_axis_info(self.gamepads_data[id].axis_info, code) {
        None => AxisInfo::new(0, 1, None)
        Some(i) => i
      }
      let raw_val = ne.value.to_int()
      match self.axis_or_btn_name(gid, code) {
        Some(AxisOrBtn::Btn(btn)) => {
          let val = btn_value(info, raw_val)
          if val >= self.axis_to_btn_pressed &&
            !self.gamepads_data[id].state.is_pressed(code) {
            self.insert_event(
              Event::at(gid, EventType::ButtonPressed(btn, code), ne.time_ms),
            )
            self.insert_event(
              Event::at(
                gid,
                EventType::ButtonChanged(btn, val, code),
                ne.time_ms,
              ),
            )
          } else if val <= self.axis_to_btn_released &&
            self.gamepads_data[id].state.is_pressed(code) {
            self.insert_event(
              Event::at(gid, EventType::ButtonReleased(btn, code), ne.time_ms),
            )
            self.insert_event(
              Event::at(
                gid,
                EventType::ButtonChanged(btn, val, code),
                ne.time_ms,
              ),
            )
          } else {
            self.insert_event(
              Event::at(
                gid,
                EventType::ButtonChanged(btn, val, code),
                ne.time_ms,
              ),
            )
          }
        }
        Some(AxisOrBtn::Axis(axis)) => {
          let val = axis_value(info, raw_val, axis)
          self.insert_event(
            Event::at(gid, EventType::AxisChanged(axis, val, code), ne.time_ms),
          )
        }
        None => {
          let val = axis_value(info, raw_val, Axis::Unknown)
          self.insert_event(
            Event::at(
              gid,
              EventType::AxisChanged(Axis::Unknown, val, code),
              ne.time_ms,
            ),
          )
        }
      }
    }
    NativeEventTag::ButtonChanged => {
      // Legacy tag: treat backend value as already normalized.
      let code = ne.code
      match self.axis_or_btn_name(gid, code) {
        Some(AxisOrBtn::Btn(btn)) =>
          self.insert_event(
            Event::at(
              gid,
              EventType::ButtonChanged(btn, ne.value, code),
              ne.time_ms,
            ),
          )
        Some(AxisOrBtn::Axis(axis)) =>
          self.insert_event(
            Event::at(
              gid,
              EventType::AxisChanged(axis, ne.value, code),
              ne.time_ms,
            ),
          )
        None => ()
      }
    }
  }
}

///|
pub fn Gil::poll(self : Gil) -> Unit {
  match self.backend {
    None => ()
    Some(b) => {
      b.poll()
      match b.next_event() {
        None => ()
        Some(ne) => self.push_native_event(ne)
      }
    }
  }
}

///|
fn clamp_blocking_timeout(timeout_ms : Int64?) -> Int {
  match timeout_ms {
    None => -1
    Some(ms) =>
      if ms <= 0L {
        0
      } else if ms >= 0x7FFF_FFFFL {
        0x7FFF_FFFF
      } else {
        ms.to_int()
      }
  }
}

///|
fn min_timeout(lhs : Int, rhs : Int) -> Int {
  if lhs < 0 {
    rhs
  } else if rhs < 0 {
    lhs
  } else if lhs < rhs {
    lhs
  } else {
    rhs
  }
}

///|
pub fn Gil::next_event(self : Gil) -> Event? {
  let jitter_filter = Jitter::new()
  while true {
    let now = runtime_now_ms()
    self.ff_tick_update(now, false)
    match self.ff_take_next_event() {
      None => ()
      Some(ev) => {
        if self.update_state {
          self.update(ev)
        }
        return Some(ev)
      }
    }
    if self.events_head >= self.events.length() {
      self.poll()
    }
    let raw : Event? = if self.events_head >= self.events.length() {
      None
    } else {
      let ev = self.events[self.events_head]
      self.events_head = self.events_head + 1
      Some(ev)
    }
    match raw {
      None => ()
      Some(ev) => self.apply_connection_event(ev)
    }
    let mut ev : Event? = raw
    if self.default_filters {
      ev = filter_ev(ev, axis_dpad_to_button, self)
      ev = filter_ev(ev, fn(ev, g) { jitter_filter.filter(ev, g) }, self)
      ev = filter_ev(ev, deadzone, self)
    }
    match ev {
      Some(e) =>
        if self.default_filters && e.is_dropped() {
          continue
        } else {
          if self.update_state {
            self.update(e)
          }
          return Some(e)
        }
      None => return None
    }
  } nobreak {
    None
  }
}

///|
pub fn Gil::next_event_blocking(self : Gil, timeout_ms : Int64?) -> Event? {
  let jitter_filter = Jitter::new()
  while true {
    let now = runtime_now_ms()
    self.ff_tick_update(now, false)
    match self.ff_take_next_event() {
      None => ()
      Some(ev) => {
        if self.update_state {
          self.update(ev)
        }
        return Some(ev)
      }
    }
    if self.events_head >= self.events.length() {
      match self.backend {
        None => ()
        Some(b) => {
          let base_timeout = clamp_blocking_timeout(timeout_ms)
          let t = if self.ff_has_active_effect() {
            min_timeout(base_timeout, self.ff_next_tick_wait_ms(now))
          } else {
            base_timeout
          }
          b.poll_timeout(t)
          match b.next_event() {
            None => ()
            Some(ne) => self.push_native_event(ne)
          }
        }
      }
    }
    let raw : Event? = if self.events_head >= self.events.length() {
      None
    } else {
      let ev = self.events[self.events_head]
      self.events_head = self.events_head + 1
      Some(ev)
    }
    match raw {
      None => ()
      Some(ev) => self.apply_connection_event(ev)
    }
    let mut ev : Event? = raw
    if self.default_filters {
      ev = filter_ev(ev, axis_dpad_to_button, self)
      ev = filter_ev(ev, fn(ev, g) { jitter_filter.filter(ev, g) }, self)
      ev = filter_ev(ev, deadzone, self)
    }
    match ev {
      Some(e) =>
        if self.default_filters && e.is_dropped() {
          continue
        } else {
          if self.update_state {
            self.update(e)
          }
          return Some(e)
        }
      None => return None
    }
  } nobreak {
    None
  }
}

///|
pub fn Gil::update(self : Gil, event : Event) -> Unit {
  let id = event.id().value()
  if id < 0 || id >= self.gamepads_data.length() {
    return
  }
  let counter = self.counter
  let time = event.time()
  let data = self.gamepads_data[id]
  match event.event() {
    EventType::ButtonPressed(_, code) =>
      data.state.set_btn_pressed(code, true, counter, time)
    EventType::ButtonReleased(_, code) =>
      data.state.set_btn_pressed(code, false, counter, time)
    EventType::ButtonRepeated(_, code) =>
      data.state.set_btn_repeating(code, counter, time)
    EventType::ButtonChanged(_, value, code) =>
      data.state.set_btn_value(code, value, counter, time)
    EventType::AxisChanged(_, value, code) =>
      data.state.set_axis_value(code, value, counter, time)
    EventType::Connected
    | EventType::Disconnected
    | EventType::Dropped
    | EventType::ForceFeedbackEffectCompleted => ()
  }
}

///|
pub fn Gil::inc(self : Gil) -> Unit {
  if self.counter == 0x3FFF_FFFF_FFFF_FFFFL {
    self.counter = 0L
  } else {
    self.counter = self.counter + 1L
  }
}

///|
pub fn Gil::counter(self : Gil) -> Int64 {
  self.counter
}

///|
pub fn Gil::reset_counter(self : Gil) -> Unit {
  self.counter = 0L
}

///|
pub fn Gil::state(self : Gil, id : GamepadId) -> GamepadState? {
  let i = id.value()
  if i < 0 || i >= self.gamepads_data.length() {
    None
  } else {
    Some(self.gamepads_data[i].state)
  }
}

///|
pub fn Gil::is_connected(self : Gil, id : GamepadId) -> Bool {
  let i = id.value()
  if i < 0 || i >= self.gamepads_data.length() {
    false
  } else {
    self.gamepads_data[i].connected
  }
}

///|
pub fn Gil::set_mapping_data(
  self : Gil,
  id : GamepadId,
  mapping_data : MappingData,
  name? : String? = None,
) -> String raise MappingError {
  let i = id.value()
  if i < 0 || i >= self.gamepads_data.length() {
    raise MappingError::NotConnected
  }
  if !self.gamepads_data[i].connected {
    raise MappingError::NotConnected
  }
  let mapping_name = match name {
    Some(s) => s
    None => self.gamepads_data[i].name
  }
  let (mapping, sdl_line) = Mapping::from_data(
    mapping_data,
    self.gamepads_data[i].buttons,
    self.gamepads_data[i].axes,
    mapping_name,
    self.gamepads_data[i].uuid,
  )
  self.gamepads_data[i].mapping = mapping
  sdl_line
}

///|
pub fn Gil::set_mapping_data_strict(
  self : Gil,
  id : GamepadId,
  mapping_data : MappingData,
  name? : String? = None,
) -> String raise MappingError {
  if mapping_data.button(Button::C) is Some(_) ||
    mapping_data.button(Button::Z) is Some(_) ||
    mapping_data.axis(Axis::LeftZ) is Some(_) ||
    mapping_data.axis(Axis::RightZ) is Some(_) {
    raise MappingError::NotSdl2Compatible
  }
  self.set_mapping_data(id, mapping_data, name~)
}

///|
pub fn Gil::set_mapping(self : Gil, id : GamepadId, mapping : Mapping) -> Unit {
  let i = id.value()
  if i < 0 || i >= self.gamepads_data.length() {
    return
  }
  self.gamepads_data[i].mapping = mapping
}

///|
pub fn Gil::mapping(self : Gil, id : GamepadId) -> Mapping? {
  let i = id.value()
  if i < 0 || i >= self.gamepads_data.length() {
    None
  } else {
    Some(self.gamepads_data[i].mapping)
  }
}

///|
pub fn Gil::axis_or_btn_name(
  self : Gil,
  id : GamepadId,
  code : Code,
) -> AxisOrBtn? {
  match self.mapping(id) {
    None => None
    Some(m) => m.map(code)
  }
}

///|
pub fn Gil::axis_code(self : Gil, id : GamepadId, axis : Axis) -> Code? {
  match self.mapping(id) {
    None => None
    Some(m) => m.map_rev(AxisOrBtn::Axis(axis))
  }
}

///|
pub fn Gil::button_code(self : Gil, id : GamepadId, btn : Button) -> Code? {
  match self.mapping(id) {
    None => None
    Some(m) => m.map_rev(AxisOrBtn::Btn(btn))
  }
}

///|
fn find_deadzone_idx(deadzones : Array[(Code, Double)], code : Code) -> Int? {
  for i in 0..<deadzones.length() {
    let (c, _) = deadzones[i]
    if c == code {
      return Some(i)
    }
  }
  None
}

///|
pub fn Gil::set_deadzone(
  self : Gil,
  id : GamepadId,
  code : Code,
  threshold : Double,
) -> Unit {
  let i = id.value()
  if i < 0 || i >= self.gamepads_data.length() {
    return
  }
  let dz = self.gamepads_data[i].deadzones
  match find_deadzone_idx(dz, code) {
    None => dz.push((code, threshold))
    Some(j) => dz[j] = (code, threshold)
  }
}

///|
pub fn Gil::deadzone(self : Gil, id : GamepadId, code : Code) -> Double? {
  let i = id.value()
  if i < 0 || i >= self.gamepads_data.length() {
    return None
  }
  let dz = self.gamepads_data[i].deadzones
  match find_deadzone_idx(dz, code) {
    None => {
      for pair in self.gamepads_data[i].axis_info {
        let (c, info) = pair
        if c != code {
          continue
        }
        let range_i64 = info.max.to_int64() - info.min.to_int64()
        if range_i64 <= 0L {
          return Some(0.0)
        }
        match info.deadzone {
          Some(d) =>
            return Some(
              clamp(d.to_double() / range_i64.to_double() * 2.0, 0.0, 1.0),
            )
          None => return Some(0.1)
        }
      }
      None
    }
    Some(j) => {
      let (_, t) = dz[j]
      Some(t)
    }
  }
}

///|
pub struct GilBuilder {
  mut update_state : Bool
  mut default_filters : Bool
  mut axis_to_btn_pressed : Double
  mut axis_to_btn_released : Double
  mut env_mappings : Bool
  mut included_mappings : Bool
  mut mock_gamepad_count : Int
  mut use_native_backend : Bool
  mapping_inputs : Array[String]
}

///|
pub fn GilBuilder::new() -> GilBuilder {
  {
    update_state: true,
    default_filters: true,
    axis_to_btn_pressed: 0.75,
    axis_to_btn_released: 0.65,
    env_mappings: true,
    included_mappings: true,
    mock_gamepad_count: 0,
    use_native_backend: true,
    mapping_inputs: [],
  }
}

///|
pub fn GilBuilder::set_update_state(self : GilBuilder, v : Bool) -> GilBuilder {
  self.update_state = v
  self
}

///|
pub fn GilBuilder::with_default_filters(
  self : GilBuilder,
  v : Bool,
) -> GilBuilder {
  self.default_filters = v
  self
}

///|
pub fn GilBuilder::with_mock_gamepad_count(
  self : GilBuilder,
  n : Int,
) -> GilBuilder {
  self.mock_gamepad_count = n
  self
}

///|
pub fn GilBuilder::with_native_backend(
  self : GilBuilder,
  v : Bool,
) -> GilBuilder {
  self.use_native_backend = v
  self
}

///|
pub fn GilBuilder::add_mappings(
  self : GilBuilder,
  mappings : String,
) -> GilBuilder {
  self.mapping_inputs.push(mappings)
  self
}

///|
pub fn GilBuilder::set_axis_to_btn(
  self : GilBuilder,
  pressed : Double,
  released : Double,
) -> GilBuilder {
  self.axis_to_btn_pressed = pressed
  self.axis_to_btn_released = released
  self
}

///|
pub fn GilBuilder::add_env_mappings(
  self : GilBuilder,
  env_mappings : Bool,
) -> GilBuilder {
  self.env_mappings = env_mappings
  self
}

///|
pub fn GilBuilder::add_included_mappings(
  self : GilBuilder,
  included_mappings : Bool,
) -> GilBuilder {
  self.included_mappings = included_mappings
  self
}

///|
pub fn GilBuilder::build(self : GilBuilder) -> Gil raise GilError {
  if self.axis_to_btn_pressed <= self.axis_to_btn_released ||
    self.axis_to_btn_pressed < 0.0 ||
    self.axis_to_btn_pressed > 1.0 ||
    self.axis_to_btn_released < 0.0 ||
    self.axis_to_btn_released > 1.0 {
    raise GilError::InvalidAxisToBtn
  }
  let use_native_backend = self.use_native_backend &&
    self.mock_gamepad_count <= 0
  let gil = if use_native_backend {
    Gil::new_native(
      update_state=self.update_state,
      default_filters=self.default_filters,
    )
  } else {
    Gil::new_mock(
      self.mock_gamepad_count,
      update_state=self.update_state,
      default_filters=self.default_filters,
    )
  }
  for s in self.mapping_inputs {
    gil.load_mappings(s)
  }
  if self.included_mappings {
    gil.mappings.add_included_mappings()
  }
  if self.env_mappings {
    gil.mappings.add_env_mappings()
  }
  gil.axis_to_btn_pressed = self.axis_to_btn_pressed
  gil.axis_to_btn_released = self.axis_to_btn_released
  gil.finish_gamepads_creation()
  gil
}

///|
pub fn Gil::new() -> Gil {
  let built : Result[Gil, GilError] = try? GilBuilder::new()
    .with_native_backend(true)
    .build()
  match built {
    Ok(g) => g
    Err(_) => Gil::new_native()
  }
}

///|
pub struct Gamepad {
  gil : Gil
  id : GamepadId
}

///|
pub enum MappingSource {
  SdlMappings
  Driver
  None
}

///|
let _mapping_source_keepalive : Array[MappingSource] = [MappingSource::None]

///|
pub fn Gil::gamepad(self : Gil, id : GamepadId) -> Gamepad? {
  let i = id.value()
  if i < 0 || i >= self.gamepads_data.length() {
    None
  } else {
    Some({ gil: self, id })
  }
}

///|
pub fn Gil::connected_gamepad(self : Gil, id : GamepadId) -> Gamepad? {
  match self.gamepad(id) {
    None => None
    Some(gp) => if gp.is_connected() { Some(gp) } else { None }
  }
}

///|
pub fn Gil::gamepads(self : Gil) -> Array[(GamepadId, Gamepad)] {
  let out : Array[(GamepadId, Gamepad)] = []
  for i in 0..<self.gamepads_data.length() {
    if !self.gamepads_data[i].connected {
      continue
    }
    let id = GamepadId::new(i)
    out.push((id, { gil: self, id }))
  }
  out
}

///|
pub fn Gamepad::id(self : Gamepad) -> GamepadId {
  self.id
}

///|
pub fn Gamepad::is_connected(self : Gamepad) -> Bool {
  self.gil.is_connected(self.id)
}

///|
pub fn Gamepad::name(self : Gamepad) -> String {
  match self.map_name() {
    Some(map_name) => map_name
    None => self.os_name()
  }
}

///|
pub fn Gamepad::map_name(self : Gamepad) -> String? {
  match self.mapping() {
    None => None
    Some(m) => if m.is_default() { None } else { Some(m.name()) }
  }
}

///|
pub fn Gamepad::os_name(self : Gamepad) -> String {
  let i = self.id.value()
  if i < 0 || i >= self.gil.gamepads_data.length() {
    ""
  } else {
    self.gil.gamepads_data[i].name
  }
}

///|
pub fn Gamepad::mapping_source(self : Gamepad) -> MappingSource {
  match self.mapping() {
    Some(m) =>
      if m.is_default() {
        MappingSource::Driver
      } else {
        MappingSource::SdlMappings
      }
    None => MappingSource::None
  }
}

///|
pub fn Gamepad::uuid(self : Gamepad) -> Uuid {
  let i = self.id.value()
  if i < 0 || i >= self.gil.gamepads_data.length() {
    Uuid::nil()
  } else {
    self.gil.gamepads_data[i].uuid
  }
}

///|
pub fn Gamepad::vendor_id(self : Gamepad) -> Int? {
  let i = self.id.value()
  if i < 0 || i >= self.gil.gamepads_data.length() {
    None
  } else {
    self.gil.gamepads_data[i].vendor_id
  }
}

///|
pub fn Gamepad::product_id(self : Gamepad) -> Int? {
  let i = self.id.value()
  if i < 0 || i >= self.gil.gamepads_data.length() {
    None
  } else {
    self.gil.gamepads_data[i].product_id
  }
}

///|
pub fn Gamepad::power_info(self : Gamepad) -> PowerInfo {
  let i = self.id.value()
  if i < 0 || i >= self.gil.gamepads_data.length() {
    PowerInfo::Unknown
  } else {
    self.gil.gamepads_data[i].power_info
  }
}

///|
pub fn Gamepad::axes(self : Gamepad) -> Array[Code] {
  let i = self.id.value()
  if i < 0 || i >= self.gil.gamepads_data.length() {
    []
  } else {
    self.gil.gamepads_data[i].axes.copy()
  }
}

///|
pub fn Gamepad::buttons(self : Gamepad) -> Array[Code] {
  let i = self.id.value()
  if i < 0 || i >= self.gil.gamepads_data.length() {
    []
  } else {
    self.gil.gamepads_data[i].buttons.copy()
  }
}

///|
pub fn Gamepad::axis_info(self : Gamepad, code : Code) -> AxisInfo? {
  let i = self.id.value()
  if i < 0 || i >= self.gil.gamepads_data.length() {
    return None
  }
  for pair in self.gil.gamepads_data[i].axis_info {
    let (c, info) = pair
    if c == code {
      return Some(info)
    }
  }
  None
}

///|
pub fn Gamepad::state(self : Gamepad) -> GamepadState {
  match self.gil.state(self.id) {
    None => GamepadState::new()
    Some(s) => s
  }
}

///|
pub fn Gamepad::is_pressed(self : Gamepad, btn : Button) -> Bool {
  let code = match self.button_code(btn) {
    Some(code) => Some(code)
    None => default_button_code(btn)
  }
  match code {
    None => false
    Some(code) => self.state().is_pressed(code)
  }
}

///|
pub fn Gamepad::value(self : Gamepad, axis : Axis) -> Double {
  match self.axis_code(axis) {
    None => 0.0
    Some(code) => self.state().value(code)
  }
}

///|
pub fn Gamepad::button_data(self : Gamepad, btn : Button) -> ButtonData? {
  match self.button_code(btn) {
    None => None
    Some(code) => self.state().button_data(code)
  }
}

///|
pub fn Gamepad::axis_data(self : Gamepad, axis : Axis) -> AxisData? {
  match self.axis_code(axis) {
    None => None
    Some(code) => self.state().axis_data(code)
  }
}

///|
pub fn Gamepad::axis_code(self : Gamepad, axis : Axis) -> Code? {
  self.gil.axis_code(self.id, axis)
}

///|
pub fn Gamepad::button_code(self : Gamepad, btn : Button) -> Code? {
  self.gil.button_code(self.id, btn)
}

///|
pub fn Gamepad::axis_or_btn_name(self : Gamepad, code : Code) -> AxisOrBtn? {
  self.gil.axis_or_btn_name(self.id, code)
}

///|
pub fn Gamepad::mapping(self : Gamepad) -> Mapping? {
  self.gil.mapping(self.id)
}

///|
pub fn Gamepad::deadzone(self : Gamepad, code : Code) -> Double? {
  self.gil.deadzone(self.id, code)
}

///|
pub fn Gamepad::is_ff_supported(self : Gamepad) -> Bool {
  let i = self.id.value()
  if i < 0 || i >= self.gil.gamepads_data.length() {
    false
  } else {
    self.gil.gamepads_data[i].ff_supported
  }
}

///|
pub fn Gamepad::set_listener_position(
  self : Gamepad,
  position : (Double, Double, Double),
) -> Unit raise FfError {
  if !self.is_connected() {
    raise FfError::Disconnected(self.id)
  } else if !self.is_ff_supported() {
    raise FfError::FfNotSupported(self.id)
  } else {
    let i = self.id.value()
    if i >= 0 && i < self.gil.gamepads_data.length() {
      self.gil.gamepads_data[i].listener_position = position
      self.gil.ff_tick_update(runtime_now_ms(), true)
    }
  }
}
