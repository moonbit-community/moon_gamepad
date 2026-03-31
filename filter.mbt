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
pub fn filter_ev(
  ev : Event?,
  filter : (Event?, Gil) -> Event?,
  gil : Gil,
) -> Event? {
  let out = filter(ev, gil)
  match ev {
    None => out
    Some(e) =>
      match out {
        None => Some(e.drop())
        _ => out
      }
  }
}

///|
pub struct Jitter {
  threshold : Double
}

///|
pub fn Jitter::new() -> Jitter {
  { threshold: 0.01 }
}

///|
pub fn jitter(ev : Event?, gil : Gil, threshold : Double) -> Event? {
  match ev {
    Some(e) =>
      match e.event() {
        EventType::AxisChanged(_, val, axis_code) => {
          let old_data = match gil.state(e.id()) {
            None => 0.0
            Some(s) =>
              match s.axis_data(axis_code) {
                None => return ev
                Some(d) => d.value()
              }
          }
          if val != 0.0 && Double::abs(val - old_data) < threshold {
            Some(e.drop())
          } else {
            ev
          }
        }
        _ => ev
      }
    None => None
  }
}

///|
pub fn Jitter::filter(self : Jitter, ev : Event?, gil : Gil) -> Event? {
  jitter(ev, gil, self.threshold)
}

///|
fn apply_deadzone(
  x : Double,
  y : Double,
  threshold : Double,
) -> (Double, Double) {
  let magnitude = clamp(Double::sqrt(x * x + y * y), 0.0, 1.0)
  if magnitude <= threshold {
    (0.0, 0.0)
  } else {
    let norm = (magnitude - threshold) / (1.0 - threshold) / magnitude
    (x * norm, y * norm)
  }
}

///|
fn deadzone_nonzero_axis_idx(axis : Axis) -> Int? {
  Some(
    match axis {
      Axis::DPadX => 0
      Axis::DPadY => 1
      Axis::LeftStickX => 2
      Axis::LeftStickY => 3
      Axis::RightStickX => 4
      Axis::RightStickY => 5
      _ => return None
    },
  )
}

///|
pub fn deadzone(ev : Event?, gil : Gil) -> Event? {
  match ev {
    Some(e) =>
      match e.event() {
        EventType::AxisChanged(axis, val, code) =>
          deadzone_axis(e, axis, val, code, gil)
        EventType::ButtonChanged(btn, val, code) =>
          deadzone_button(e, btn, val, code, gil)
        _ => ev
      }
    None => None
  }
}

///|
fn deadzone_axis(
  e : Event,
  axis : Axis,
  val : Double,
  code : Code,
  gil : Gil,
) -> Event? {
  let threshold = match gil.deadzone(e.id(), code) {
    None => return Some(e)
    Some(t) => t
  }
  let id = e.id()
  let time = e.time()
  let other_axis_code : (Axis, Code)? = match axis.second_axis() {
    None => None
    Some(other_axis) =>
      match gil.axis_code(id, other_axis) {
        None => None
        Some(other_code) => Some((other_axis, other_code))
      }
  }
  match other_axis_code {
    None => {
      let new_val = apply_deadzone(val, 0.0, threshold).0
      let cur = match gil.state(id) {
        None => 0.0
        Some(s) => s.value(code)
      }
      if cur == new_val {
        Some(e.drop())
      } else {
        match deadzone_nonzero_axis_idx(axis) {
          None => ()
          Some(axis_idx) =>
            gil.gamepads_data[id.value()].have_sent_nonzero_for_axis[axis_idx] = new_val !=
              0.0
        }
        Some(Event::at(id, EventType::AxisChanged(axis, new_val, code), time))
      }
    }
    Some((other_axis, other_code)) => {
      let other_val = match gil.state(id) {
        None => 0.0
        Some(s) => s.value(other_code)
      }
      let (new_val, new_other_val) = apply_deadzone(val, other_val, threshold)
      match deadzone_nonzero_axis_idx(other_axis) {
        None => ()
        Some(other_axis_idx) => {
          let sent_nonzero = gil.gamepads_data[id.value()].have_sent_nonzero_for_axis[other_axis_idx]
          let other_state_val = match gil.state(id) {
            None => 0.0
            Some(s) => s.value(other_code)
          }
          if new_val == 0.0 &&
            new_other_val == 0.0 &&
            sent_nonzero &&
            other_state_val != 0.0 {
            gil.insert_event(
              Event::at(
                id,
                EventType::AxisChanged(other_axis, 0.0, other_code),
                time,
              ),
            )
            gil.gamepads_data[id.value()].have_sent_nonzero_for_axis[other_axis_idx] = false
          }
        }
      }
      let cur = match gil.state(id) {
        None => 0.0
        Some(s) => s.value(code)
      }
      if cur == new_val {
        Some(e.drop())
      } else {
        match deadzone_nonzero_axis_idx(axis) {
          None => ()
          Some(axis_idx) =>
            gil.gamepads_data[id.value()].have_sent_nonzero_for_axis[axis_idx] = new_val !=
              0.0
        }
        Some(Event::at(id, EventType::AxisChanged(axis, new_val, code), time))
      }
    }
  }
}

///|
fn deadzone_button(
  e : Event,
  btn : Button,
  val : Double,
  code : Code,
  gil : Gil,
) -> Event? {
  let threshold = match gil.deadzone(e.id(), code) {
    None => return Some(e)
    Some(t) => t
  }
  let new_val = apply_deadzone(val, 0.0, threshold).0
  let cur = match gil.state(e.id()) {
    None => 0.0
    Some(s) => s.value(code)
  }
  if cur == new_val {
    Some(e.drop())
  } else {
    Some(
      Event::at(e.id(), EventType::ButtonChanged(btn, new_val, code), e.time()),
    )
  }
}

///|
pub fn axis_dpad_to_button(ev : Event?, gil : Gil) -> Event? {
  match ev {
    None => None
    Some(e) =>
      match e.event() {
        EventType::AxisChanged(axis, val, axis_code) =>
          match axis {
            Axis::DPadX => axis_dpad_x_to_buttons(e, val, axis_code, gil)
            Axis::DPadY => axis_dpad_y_to_buttons(e, val, axis_code, gil)
            _ => ev
          }
        _ => ev
      }
  }
}

///|
fn dpad_btn_codes_for_axis_code(axis_code : Code) -> (Code, Code, Code, Code) {
  if hid_page(axis_code) == 0 {
    (
      LEGACY_BTN_DPAD_UP,
      LEGACY_BTN_DPAD_DOWN,
      LEGACY_BTN_DPAD_LEFT,
      LEGACY_BTN_DPAD_RIGHT,
    )
  } else {
    (BTN_DPAD_UP, BTN_DPAD_DOWN, BTN_DPAD_LEFT, BTN_DPAD_RIGHT)
  }
}

///|
fn can_map_axis_dpad_to_button(
  id : GamepadId,
  axis_code : Code,
  gil : Gil,
) -> Bool {
  match gil.mapping(id) {
    None => false
    Some(m) => {
      let (btn_up, btn_down, btn_left, btn_right) = dpad_btn_codes_for_axis_code(
        axis_code,
      )
      let hats = m.hats_mapped()
      if hats == 0b1111 {
        true
      } else if hats == 0 {
        gil.axis_or_btn_name(id, btn_right) is None &&
        gil.axis_or_btn_name(id, btn_left) is None &&
        gil.axis_or_btn_name(id, btn_down) is None &&
        gil.axis_or_btn_name(id, btn_up) is None &&
        gil.button_code(id, Button::DPadRight) is None
      } else {
        false
      }
    }
  }
}

///|
fn axis_dpad_x_to_buttons(
  e : Event,
  val : Double,
  axis_code : Code,
  gil : Gil,
) -> Event? {
  if !can_map_axis_dpad_to_button(e.id(), axis_code, gil) {
    return Some(e)
  }
  let (_, _, btn_left, btn_right) = dpad_btn_codes_for_axis_code(axis_code)
  let id = e.id()
  let time = e.time()
  let mut out = e.drop()
  let mut release_left = false
  let mut release_right = false
  let pressed_left = match gil.state(id) {
    None => false
    Some(s) => s.is_pressed(btn_left)
  }
  let pressed_right = match gil.state(id) {
    None => false
    Some(s) => s.is_pressed(btn_right)
  }
  if val == 1.0 {
    release_left = pressed_left
    gil.insert_event(
      Event::at(
        id,
        EventType::ButtonChanged(Button::DPadRight, 1.0, btn_right),
        time,
      ),
    )
    out = Event::at(
      id,
      EventType::ButtonPressed(Button::DPadRight, btn_right),
      time,
    )
  } else if val == -1.0 {
    release_right = pressed_right
    gil.insert_event(
      Event::at(
        id,
        EventType::ButtonChanged(Button::DPadLeft, 1.0, btn_left),
        time,
      ),
    )
    out = Event::at(
      id,
      EventType::ButtonPressed(Button::DPadLeft, btn_left),
      time,
    )
  } else {
    release_left = pressed_left
    release_right = pressed_right
  }
  if release_right {
    if !out.is_dropped() {
      gil.insert_event(out)
    }
    gil.insert_event(
      Event::at(
        id,
        EventType::ButtonChanged(Button::DPadRight, 0.0, btn_right),
        time,
      ),
    )
    out = Event::at(
      id,
      EventType::ButtonReleased(Button::DPadRight, btn_right),
      time,
    )
  }
  if release_left {
    if !out.is_dropped() {
      gil.insert_event(out)
    }
    gil.insert_event(
      Event::at(
        id,
        EventType::ButtonChanged(Button::DPadLeft, 0.0, btn_left),
        time,
      ),
    )
    out = Event::at(
      id,
      EventType::ButtonReleased(Button::DPadLeft, btn_left),
      time,
    )
  }
  Some(out)
}

///|
fn axis_dpad_y_to_buttons(
  e : Event,
  val : Double,
  axis_code : Code,
  gil : Gil,
) -> Event? {
  if !can_map_axis_dpad_to_button(e.id(), axis_code, gil) {
    return Some(e)
  }
  let (btn_up, btn_down, _, _) = dpad_btn_codes_for_axis_code(axis_code)
  let id = e.id()
  let time = e.time()
  let mut out = e.drop()
  let mut release_up = false
  let mut release_down = false
  let pressed_up = match gil.state(id) {
    None => false
    Some(s) => s.is_pressed(btn_up)
  }
  let pressed_down = match gil.state(id) {
    None => false
    Some(s) => s.is_pressed(btn_down)
  }
  if val == 1.0 {
    release_down = pressed_down
    gil.insert_event(
      Event::at(id, EventType::ButtonChanged(Button::DPadUp, 1.0, btn_up), time),
    )
    out = Event::at(id, EventType::ButtonPressed(Button::DPadUp, btn_up), time)
  } else if val == -1.0 {
    release_up = pressed_up
    gil.insert_event(
      Event::at(
        id,
        EventType::ButtonChanged(Button::DPadDown, 1.0, btn_down),
        time,
      ),
    )
    out = Event::at(
      id,
      EventType::ButtonPressed(Button::DPadDown, btn_down),
      time,
    )
  } else {
    release_up = pressed_up
    release_down = pressed_down
  }
  if release_up {
    if !out.is_dropped() {
      gil.insert_event(out)
    }
    gil.insert_event(
      Event::at(id, EventType::ButtonChanged(Button::DPadUp, 0.0, btn_up), time),
    )
    out = Event::at(id, EventType::ButtonReleased(Button::DPadUp, btn_up), time)
  }
  if release_down {
    if !out.is_dropped() {
      gil.insert_event(out)
    }
    gil.insert_event(
      Event::at(
        id,
        EventType::ButtonChanged(Button::DPadDown, 0.0, btn_down),
        time,
      ),
    )
    out = Event::at(
      id,
      EventType::ButtonReleased(Button::DPadDown, btn_down),
      time,
    )
  }
  Some(out)
}

///|
pub struct Repeat {
  after_ms : Int64
  every_ms : Int64
}

///|
pub fn Repeat::new() -> Repeat {
  { after_ms: 500L, every_ms: 30L }
}

///|
fn code_to_button_name(id : GamepadId, code : Code, gil : Gil) -> Button {
  match gil.axis_or_btn_name(id, code) {
    Some(AxisOrBtn::Btn(b)) => b
    _ => Button::Unknown
  }
}

///|
pub fn Repeat::filter(self : Repeat, ev : Event?, gil : Gil) -> Event? {
  match ev {
    Some(_) => ev
    None => {
      let now = runtime_now_ms()
      for i in 0..<gil.gamepads_data.length() {
        if !gil.gamepads_data[i].connected {
          continue
        }
        let id = GamepadId::new(i)
        match gil.state(id) {
          None => ()
          Some(state) =>
            for pair in state.buttons_entries() {
              let (code, data) = pair
              let pressed = data.is_pressed()
              let repeating = data.is_repeating()
              let dur = now - data.timestamp()
              if pressed && !repeating && dur >= self.after_ms {
                let btn = code_to_button_name(id, code, gil)
                return Some(
                  Event::at(
                    id,
                    EventType::ButtonRepeated(btn, code),
                    data.timestamp() + self.after_ms,
                  ),
                )
              }
              if pressed && repeating && dur >= self.every_ms {
                let btn = code_to_button_name(id, code, gil)
                return Some(
                  Event::at(
                    id,
                    EventType::ButtonRepeated(btn, code),
                    data.timestamp() + self.every_ms,
                  ),
                )
              }
            }
        }
      }
      None
    }
  }
}
