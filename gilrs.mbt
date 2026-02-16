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
let _gilrs_error_keepalive : Array[GilrsError] = [GilrsError::NotImplemented]

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
    power_info: PowerInfo::Unknown,
    axes: [],
    buttons: [],
    axis_info: [],
    deadzones: [],
    have_sent_nonzero_for_axis: Array::make(6, false),
  }
}

///|
pub struct Gilrs {
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
    axis_to_btn_pressed: 0.75,
    axis_to_btn_released: 0.65,
    events: [],
    events_head: 0,
    gamepads_data: data,
    mappings: MappingDb::new(),
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
    axis_to_btn_pressed: 0.75,
    axis_to_btn_released: 0.65,
    events: [],
    events_head: 0,
    gamepads_data: [],
    mappings: MappingDb::new(),
    now_ms: 0L,
    backend: Some(NativeBackend::new()),
  }
}

///|
pub fn Gilrs::load_mappings(self : Gilrs, s : String) -> Unit {
  self.mappings.insert(s)
}

///|
pub fn Gilrs::set_axis_to_btn(
  self : Gilrs,
  pressed : Double,
  released : Double,
) -> Unit raise GilrsError {
  if pressed <= released ||
    pressed < 0.0 ||
    pressed > 1.0 ||
    released < 0.0 ||
    released > 1.0 {
    raise GilrsError::InvalidAxisToBtn
  }
  self.axis_to_btn_pressed = pressed
  self.axis_to_btn_released = released
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
fn Gilrs::refresh_gamepad_data_on_connected(
  self : Gilrs,
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
      data.power_info = PowerInfo::Unknown
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
fn Gilrs::push_native_event(self : Gilrs, ne : NativeEvent) -> Unit {
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
pub fn Gilrs::poll(self : Gilrs) -> Unit {
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
pub fn Gilrs::next_event(self : Gilrs) -> Event? {
  let jitter_filter = Jitter::new()
  while true {
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
    let mut ev : Event? = raw
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
  } nobreak {
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
          match b.next_event() {
            None => ()
            Some(ne) => self.push_native_event(ne)
          }
        }
      }
      timeout2 = match timeout2 {
        None => None
        Some(_) => Some(0L)
      }
    }
    let raw : Event? = if self.events_head >= self.events.length() {
      None
    } else {
      let ev = self.events[self.events_head]
      self.events_head = self.events_head + 1
      Some(ev)
    }
    let mut ev : Event? = raw
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
  } nobreak {
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
pub fn Gilrs::set_mapping_data(
  self : Gilrs,
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
pub fn Gilrs::set_mapping_data_strict(
  self : Gilrs,
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
  mut axis_to_btn_pressed : Double
  mut axis_to_btn_released : Double
  mut env_mappings : Bool
  mut included_mappings : Bool
  mut mock_gamepad_count : Int
  mut use_native_backend : Bool
  mapping_inputs : Array[String]
}

///|
pub fn GilrsBuilder::new() -> GilrsBuilder {
  {
    update_state: true,
    default_filters: true,
    axis_to_btn_pressed: 0.75,
    axis_to_btn_released: 0.65,
    env_mappings: true,
    included_mappings: true,
    mock_gamepad_count: 0,
    use_native_backend: false,
    mapping_inputs: [],
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
pub fn GilrsBuilder::add_mappings(
  self : GilrsBuilder,
  mappings : String,
) -> GilrsBuilder {
  self.mapping_inputs.push(mappings)
  self
}

///|
pub fn GilrsBuilder::set_axis_to_btn(
  self : GilrsBuilder,
  pressed : Double,
  released : Double,
) -> GilrsBuilder {
  self.axis_to_btn_pressed = pressed
  self.axis_to_btn_released = released
  self
}

///|
pub fn GilrsBuilder::add_env_mappings(
  self : GilrsBuilder,
  env_mappings : Bool,
) -> GilrsBuilder {
  self.env_mappings = env_mappings
  self
}

///|
pub fn GilrsBuilder::add_included_mappings(
  self : GilrsBuilder,
  included_mappings : Bool,
) -> GilrsBuilder {
  self.included_mappings = included_mappings
  self
}

///|
pub fn GilrsBuilder::build(self : GilrsBuilder) -> Gilrs {
  let gilrs = if self.use_native_backend {
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
  for s in self.mapping_inputs {
    gilrs.load_mappings(s)
  }
  if self.included_mappings {
    gilrs.mappings.add_included_mappings()
  }
  if self.env_mappings {
    gilrs.mappings.add_env_mappings()
  }
  gilrs.axis_to_btn_pressed = self.axis_to_btn_pressed
  gilrs.axis_to_btn_released = self.axis_to_btn_released
  gilrs
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
pub enum MappingSource {
  SdlMappings
  Driver
  None
}

///|
let _mapping_source_keepalive : Array[MappingSource] = [MappingSource::None]

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
pub fn Gilrs::connected_gamepad(self : Gilrs, id : GamepadId) -> Gamepad? {
  match self.gamepad(id) {
    None => None
    Some(gp) => if gp.is_connected() { Some(gp) } else { None }
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
  if i < 0 || i >= self.gilrs.gamepads_data.length() {
    ""
  } else {
    self.gilrs.gamepads_data[i].name
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
  if i < 0 || i >= self.gilrs.gamepads_data.length() {
    Uuid::nil()
  } else {
    self.gilrs.gamepads_data[i].uuid
  }
}

///|
pub fn Gamepad::vendor_id(self : Gamepad) -> Int? {
  let i = self.id.value()
  if i < 0 || i >= self.gilrs.gamepads_data.length() {
    None
  } else {
    self.gilrs.gamepads_data[i].vendor_id
  }
}

///|
pub fn Gamepad::product_id(self : Gamepad) -> Int? {
  let i = self.id.value()
  if i < 0 || i >= self.gilrs.gamepads_data.length() {
    None
  } else {
    self.gilrs.gamepads_data[i].product_id
  }
}

///|
pub fn Gamepad::power_info(self : Gamepad) -> PowerInfo {
  let i = self.id.value()
  if i < 0 || i >= self.gilrs.gamepads_data.length() {
    PowerInfo::Unknown
  } else {
    self.gilrs.gamepads_data[i].power_info
  }
}

///|
pub fn Gamepad::axes(self : Gamepad) -> Array[Code] {
  let i = self.id.value()
  if i < 0 || i >= self.gilrs.gamepads_data.length() {
    []
  } else {
    self.gilrs.gamepads_data[i].axes.copy()
  }
}

///|
pub fn Gamepad::buttons(self : Gamepad) -> Array[Code] {
  let i = self.id.value()
  if i < 0 || i >= self.gilrs.gamepads_data.length() {
    []
  } else {
    self.gilrs.gamepads_data[i].buttons.copy()
  }
}

///|
pub fn Gamepad::axis_info(self : Gamepad, code : Code) -> AxisInfo? {
  let i = self.id.value()
  if i < 0 || i >= self.gilrs.gamepads_data.length() {
    return None
  }
  for pair in self.gilrs.gamepads_data[i].axis_info {
    let (c, info) = pair
    if c == code {
      return Some(info)
    }
  }
  None
}

///|
pub fn Gamepad::state(self : Gamepad) -> GamepadState {
  match self.gilrs.state(self.id) {
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
  let code = match self.axis_code(axis) {
    Some(code) => Some(code)
    None => default_axis_code(axis)
  }
  match code {
    None => 0.0
    Some(code) => self.state().value(code)
  }
}

///|
pub fn Gamepad::button_data(self : Gamepad, btn : Button) -> ButtonData? {
  let code = match self.button_code(btn) {
    Some(code) => Some(code)
    None => default_button_code(btn)
  }
  match code {
    None => None
    Some(code) => self.state().button_data(code)
  }
}

///|
pub fn Gamepad::axis_data(self : Gamepad, axis : Axis) -> AxisData? {
  let code = match self.axis_code(axis) {
    Some(code) => Some(code)
    None => default_axis_code(axis)
  }
  match code {
    None => None
    Some(code) => self.state().axis_data(code)
  }
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
  let i = self.id.value()
  if i < 0 || i >= self.gilrs.gamepads_data.length() {
    false
  } else {
    self.gilrs.gamepads_data[i].ff_supported
  }
}

///|
pub fn Gamepad::set_listener_position(
  self : Gamepad,
  position : (Double, Double, Double),
) -> Unit raise FfError {
  ignore(position)
  if !self.is_connected() {
    raise FfError::Disconnected(self.id)
  } else if !self.is_ff_supported() {
    raise FfError::FfNotSupported(self.id)
  } else {
    ()
  }
}
