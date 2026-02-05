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
suberror GilrsError {
  NotImplemented
  InvalidAxisToBtn
}

///|
pub struct GamepadData {
  state : GamepadState
  mut connected : Bool
  mut mapping : Mapping
  deadzones : Array[(Code, Double)]
  have_sent_nonzero_for_axis : Array[Bool]
}

///|
fn GamepadData::new() -> GamepadData {
  {
    state: GamepadState::new(),
    connected: true,
    mapping: Mapping::new(),
    deadzones: [],
    have_sent_nonzero_for_axis: Array::make(6, false),
  }
}

///|
pub struct Gilrs {
  mut counter : Int64
  update_state : Bool
  mut default_filters : Bool
  events : Array[Event]
  mut events_head : Int
  gamepads_data : Array[GamepadData]
  mut now_ms : Int64
  backend : NativeBackend?
}

///|
pub fn Gilrs::new_mock(
  gamepad_count : Int,
  update_state? : Bool = true,
  default_filters? : Bool = true,
) -> Gilrs {
  let data : Array[GamepadData] = []
  for _ in 0..<gamepad_count {
    data.push(GamepadData::new())
  }
  {
    counter: 0L,
    update_state,
    default_filters,
    events: [],
    events_head: 0,
    gamepads_data: data,
    now_ms: 0L,
    backend: None,
  }
}

///|
pub fn Gilrs::new_native(
  update_state? : Bool = true,
  default_filters? : Bool = true,
) -> Gilrs {
  {
    counter: 0L,
    update_state,
    default_filters,
    events: [],
    events_head: 0,
    gamepads_data: [],
    now_ms: 0L,
    backend: Some(NativeBackend::new()),
  }
}

///|
pub fn Gilrs::with_default_filters(self : Gilrs, enabled : Bool) -> Gilrs {
  self.default_filters = enabled
  self
}

///|
pub fn Gilrs::default_filters_enabled(self : Gilrs) -> Bool {
  self.default_filters
}

///|
pub fn Gilrs::update_state_enabled(self : Gilrs) -> Bool {
  self.update_state
}

///|
pub fn Gilrs::set_time(self : Gilrs, now_ms : Int64) -> Unit {
  self.now_ms = now_ms
}

///|
pub fn Gilrs::time(self : Gilrs) -> Int64 {
  self.now_ms
}

///|
pub fn Gilrs::insert_event(self : Gilrs, ev : Event) -> Unit {
  self.events.push(ev)
}

///|
fn Gilrs::ensure_gamepad_data(self : Gilrs, id : Int) -> Unit {
  if id < 0 {
    return
  }
  while self.gamepads_data.length() <= id {
    self.gamepads_data.push(GamepadData::new())
  }
}

///|
fn Gilrs::set_connected(self : Gilrs, id : Int, connected : Bool) -> Unit {
  self.ensure_gamepad_data(id)
  if id < 0 || id >= self.gamepads_data.length() {
    return
  }
  self.gamepads_data[id].connected = connected
}

///|
fn Gilrs::apply_identity_mapping(self : Gilrs, id : Int) -> Unit {
  self.ensure_gamepad_data(id)
  if id < 0 || id >= self.gamepads_data.length() {
    return
  }
  let m = Mapping::new()
  for
    code in [
      BTN_SOUTH,
      BTN_EAST,
      BTN_C,
      BTN_NORTH,
      BTN_WEST,
      BTN_Z,
      BTN_LT,
      BTN_RT,
      BTN_LT2,
      BTN_RT2,
      BTN_SELECT,
      BTN_START,
      BTN_MODE,
      BTN_LTHUMB,
      BTN_RTHUMB,
      BTN_DPAD_UP,
      BTN_DPAD_DOWN,
      BTN_DPAD_LEFT,
      BTN_DPAD_RIGHT,
      AXIS_LSTICKX,
      AXIS_LSTICKY,
      AXIS_LEFTZ,
      AXIS_RSTICKX,
      AXIS_RSTICKY,
      AXIS_RIGHTZ,
      AXIS_DPADX,
      AXIS_DPADY,
    ] {
    match axis_or_btn_from_code(code) {
      None => ()
      Some(el) => m.insert(code, el)
    }
  }
  self.gamepads_data[id].mapping = m
}

///|
fn Gilrs::push_native_event(self : Gilrs, ne : NativeEvent) -> Unit {
  let id = ne.id
  self.ensure_gamepad_data(id)
  let gid = GamepadId::new(id)
  match ne.tag {
    NativeEventTag::Connected => {
      self.set_connected(id, true)
      self.apply_identity_mapping(id)
      self.insert_event(Event::at(gid, EventType::Connected, ne.time_ms))
    }
    NativeEventTag::Disconnected => {
      self.set_connected(id, false)
      self.insert_event(Event::at(gid, EventType::Disconnected, ne.time_ms))
    }
    NativeEventTag::AxisChanged =>
      match axis_from_code(ne.code) {
        None => ()
        Some(axis) =>
          self.insert_event(
            Event::at(
              gid,
              EventType::AxisChanged(axis, ne.value, ne.code),
              ne.time_ms,
            ),
          )
      }
    NativeEventTag::ButtonPressed =>
      match button_from_code(ne.code) {
        None => ()
        Some(btn) =>
          self.insert_event(
            Event::at(gid, EventType::ButtonPressed(btn, ne.code), ne.time_ms),
          )
      }
    NativeEventTag::ButtonReleased =>
      match button_from_code(ne.code) {
        None => ()
        Some(btn) =>
          self.insert_event(
            Event::at(gid, EventType::ButtonReleased(btn, ne.code), ne.time_ms),
          )
      }
    NativeEventTag::ButtonChanged =>
      match button_from_code(ne.code) {
        None => ()
        Some(btn) =>
          self.insert_event(
            Event::at(
              gid,
              EventType::ButtonChanged(btn, ne.value, ne.code),
              ne.time_ms,
            ),
          )
      }
  }
}

///|
pub fn Gilrs::poll(self : Gilrs) -> Unit {
  match self.backend {
    None => ()
    Some(b) => {
      b.poll()
      while true {
        match b.next_event() {
          None => break
          Some(ne) => self.push_native_event(ne)
        }
      }
    }
  }
}

///|
pub fn Gilrs::next_event(self : Gilrs) -> Event? {
  let jitter_filter = Jitter::new()
  while true {
    if self.events_head >= self.events.length() {
      self.poll()
    }
    let raw = if self.events_head >= self.events.length() {
      None
    } else {
      let ev = self.events[self.events_head]
      self.events_head = self.events_head + 1
      Some(ev)
    }
    let mut ev = raw
    if self.default_filters {
      ev = filter_ev(ev, axis_dpad_to_button, self)
      ev = filter_ev(ev, fn(ev, g) { jitter_filter.filter(ev, g) }, self)
      ev = filter_ev(ev, deadzone, self)
    }
    match ev {
      Some(e) =>
        if e.is_dropped() {
          continue
        } else {
          if self.update_state {
            self.update(e)
          }
          return Some(e)
        }
      None => return None
    }
  } else {
    None
  }
}

///|
pub fn Gilrs::next_event_blocking(self : Gilrs, timeout_ms : Int64?) -> Event? {
  let jitter_filter = Jitter::new()
  let mut timeout2 = timeout_ms
  while true {
    if self.events_head >= self.events.length() {
      match self.backend {
        None => ()
        Some(b) => {
          let t : Int = match timeout2 {
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
          b.poll_timeout(t)
          while true {
            match b.next_event() {
              None => break
              Some(ne) => self.push_native_event(ne)
            }
          }
        }
      }
      timeout2 = match timeout2 {
        None => None
        Some(_) => Some(0L)
      }
    }
    let raw = if self.events_head >= self.events.length() {
      None
    } else {
      let ev = self.events[self.events_head]
      self.events_head = self.events_head + 1
      Some(ev)
    }
    let mut ev = raw
    if self.default_filters {
      ev = filter_ev(ev, axis_dpad_to_button, self)
      ev = filter_ev(ev, fn(ev, g) { jitter_filter.filter(ev, g) }, self)
      ev = filter_ev(ev, deadzone, self)
    }
    match ev {
      Some(e) =>
        if e.is_dropped() {
          continue
        } else {
          if self.update_state {
            self.update(e)
          }
          return Some(e)
        }
      None => return None
    }
  } else {
    None
  }
}

///|
pub fn Gilrs::update(self : Gilrs, event : Event) -> Unit {
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
    EventType::Connected => data.connected = true
    EventType::Disconnected => data.connected = false
    EventType::Dropped | EventType::ForceFeedbackEffectCompleted => ()
  }
}

///|
pub fn Gilrs::inc(self : Gilrs) -> Unit {
  if self.counter == 0x3FFF_FFFF_FFFF_FFFFL {
    self.counter = 0L
  } else {
    self.counter = self.counter + 1L
  }
}

///|
pub fn Gilrs::counter(self : Gilrs) -> Int64 {
  self.counter
}

///|
pub fn Gilrs::reset_counter(self : Gilrs) -> Unit {
  self.counter = 0L
}

///|
pub fn Gilrs::state(self : Gilrs, id : GamepadId) -> GamepadState? {
  let i = id.value()
  if i < 0 || i >= self.gamepads_data.length() {
    None
  } else {
    Some(self.gamepads_data[i].state)
  }
}

///|
pub fn Gilrs::is_connected(self : Gilrs, id : GamepadId) -> Bool {
  let i = id.value()
  if i < 0 || i >= self.gamepads_data.length() {
    false
  } else {
    self.gamepads_data[i].connected
  }
}

///|
pub fn Gilrs::set_mapping(
  self : Gilrs,
  id : GamepadId,
  mapping : Mapping,
) -> Unit {
  let i = id.value()
  if i < 0 || i >= self.gamepads_data.length() {
    return
  }
  self.gamepads_data[i].mapping = mapping
}

///|
pub fn Gilrs::mapping(self : Gilrs, id : GamepadId) -> Mapping? {
  let i = id.value()
  if i < 0 || i >= self.gamepads_data.length() {
    None
  } else {
    Some(self.gamepads_data[i].mapping)
  }
}

///|
pub fn Gilrs::axis_or_btn_name(
  self : Gilrs,
  id : GamepadId,
  code : Code,
) -> AxisOrBtn? {
  match self.mapping(id) {
    None => None
    Some(m) => m.map(code)
  }
}

///|
pub fn Gilrs::axis_code(self : Gilrs, id : GamepadId, axis : Axis) -> Code? {
  match self.mapping(id) {
    None => None
    Some(m) => m.map_rev(AxisOrBtn::Axis(axis))
  }
}

///|
pub fn Gilrs::button_code(self : Gilrs, id : GamepadId, btn : Button) -> Code? {
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
pub fn Gilrs::set_deadzone(
  self : Gilrs,
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
pub fn Gilrs::deadzone(self : Gilrs, id : GamepadId, code : Code) -> Double? {
  let i = id.value()
  if i < 0 || i >= self.gamepads_data.length() {
    return None
  }
  let dz = self.gamepads_data[i].deadzones
  match find_deadzone_idx(dz, code) {
    None => None
    Some(j) => {
      let (_, t) = dz[j]
      Some(t)
    }
  }
}

///|
pub struct GilrsBuilder {
  mut update_state : Bool
  mut default_filters : Bool
  mut mock_gamepad_count : Int
  mut use_native_backend : Bool
}

///|
pub fn GilrsBuilder::new() -> GilrsBuilder {
  {
    update_state: true,
    default_filters: true,
    mock_gamepad_count: 0,
    use_native_backend: false,
  }
}

///|
pub fn GilrsBuilder::set_update_state(
  self : GilrsBuilder,
  v : Bool,
) -> GilrsBuilder {
  self.update_state = v
  self
}

///|
pub fn GilrsBuilder::with_default_filters(
  self : GilrsBuilder,
  v : Bool,
) -> GilrsBuilder {
  self.default_filters = v
  self
}

///|
pub fn GilrsBuilder::with_mock_gamepad_count(
  self : GilrsBuilder,
  n : Int,
) -> GilrsBuilder {
  self.mock_gamepad_count = n
  self
}

///|
pub fn GilrsBuilder::with_native_backend(
  self : GilrsBuilder,
  v : Bool,
) -> GilrsBuilder {
  self.use_native_backend = v
  self
}

///|
pub fn GilrsBuilder::build(self : GilrsBuilder) -> Gilrs {
  if self.use_native_backend {
    Gilrs::new_native(
      update_state=self.update_state,
      default_filters=self.default_filters,
    )
  } else {
    Gilrs::new_mock(
      self.mock_gamepad_count,
      update_state=self.update_state,
      default_filters=self.default_filters,
    )
  }
}

///|
pub fn Gilrs::new() -> Gilrs {
  GilrsBuilder::new().with_native_backend(true).build()
}

///|
pub struct Gamepad {
  gilrs : Gilrs
  id : GamepadId
}

///|
pub fn Gilrs::gamepad(self : Gilrs, id : GamepadId) -> Gamepad? {
  let i = id.value()
  if i < 0 || i >= self.gamepads_data.length() {
    None
  } else {
    Some({ gilrs: self, id })
  }
}

///|
pub fn Gilrs::gamepads(self : Gilrs) -> Array[(GamepadId, Gamepad)] {
  let out : Array[(GamepadId, Gamepad)] = []
  for i in 0..<self.gamepads_data.length() {
    if !self.gamepads_data[i].connected {
      continue
    }
    let id = GamepadId::new(i)
    out.push((id, { gilrs: self, id }))
  }
  out
}

///|
pub fn Gamepad::id(self : Gamepad) -> GamepadId {
  self.id
}

///|
pub fn Gamepad::is_connected(self : Gamepad) -> Bool {
  self.gilrs.is_connected(self.id)
}

///|
pub fn Gamepad::name(self : Gamepad) -> String {
  match self.gilrs.mapping(self.id) {
    None => ""
    Some(m) => m.name()
  }
}

///|
pub fn Gamepad::state(self : Gamepad) -> GamepadState {
  match self.gilrs.state(self.id) {
    None => GamepadState::new()
    Some(s) => s
  }
}

///|
pub fn Gamepad::is_pressed(self : Gamepad, code : Code) -> Bool {
  self.state().is_pressed(code)
}

///|
pub fn Gamepad::value(self : Gamepad, code : Code) -> Double {
  self.state().value(code)
}

///|
pub fn Gamepad::axis_code(self : Gamepad, axis : Axis) -> Code? {
  self.gilrs.axis_code(self.id, axis)
}

///|
pub fn Gamepad::button_code(self : Gamepad, btn : Button) -> Code? {
  self.gilrs.button_code(self.id, btn)
}

///|
pub fn Gamepad::axis_or_btn_name(self : Gamepad, code : Code) -> AxisOrBtn? {
  self.gilrs.axis_or_btn_name(self.id, code)
}

///|
pub fn Gamepad::mapping(self : Gamepad) -> Mapping? {
  self.gilrs.mapping(self.id)
}

///|
pub fn Gamepad::deadzone(self : Gamepad, code : Code) -> Double? {
  self.gilrs.deadzone(self.id, code)
}

///|
pub fn Gamepad::is_ff_supported(self : Gamepad) -> Bool {
  let _ = self
  false
}
