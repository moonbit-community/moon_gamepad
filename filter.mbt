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
  filter : (Event?, Gilrs) -> Event?,
  gilrs : Gilrs,
) -> Event? {
  let out = filter(ev, gilrs)
  // Mirror gilrs' contract: Some(event) must not become None.
  match ev {
    Some(e) =>
      match out {
        None => Some(e.drop())
        Some(_) => out
      }
    None => out
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
pub fn jitter(ev : Event?, gilrs : Gilrs, threshold : Double) -> Event? {
  match ev {
    Some(e) =>
      match e.event() {
        EventType::AxisChanged(_, val, axis_code) => {
          let old_val = match gilrs.state(e.id()) {
            None => 0.0
            Some(s) => s.value(axis_code)
          }
          if val != 0.0 && Double::abs(val - old_val) < threshold {
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
pub fn Jitter::filter(self : Jitter, ev : Event?, gilrs : Gilrs) -> Event? {
  jitter(ev, gilrs, self.threshold)
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
pub fn deadzone(ev : Event?, gilrs : Gilrs) -> Event? {
  match ev {
    Some(e) =>
      match e.event() {
        EventType::AxisChanged(axis, val, code) =>
          deadzone_axis(e, axis, val, code, gilrs)
        EventType::ButtonChanged(btn, val, code) =>
          deadzone_button(e, btn, val, code, gilrs)
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
  gilrs : Gilrs,
) -> Event? {
  let threshold = match gilrs.deadzone(e.id(), code) {
    None => return Some(e)
    Some(t) => t
  }
  let id = e.id()
  let time = e.time()
  let other_axis_code : (Axis, Code)? = match axis.second_axis() {
    None => None
    Some(other_axis) =>
      match gilrs.axis_code(id, other_axis) {
        None => None
        Some(other_code) => Some((other_axis, other_code))
      }
  }
  match other_axis_code {
    None => {
      let new_val = apply_deadzone(val, 0.0, threshold).0
      let cur = match gilrs.state(id) {
        None => 0.0
        Some(s) => s.value(code)
      }
      if cur == new_val {
        Some(e.drop())
      } else {
        match deadzone_nonzero_axis_idx(axis) {
          None => ()
          Some(axis_idx) =>
            gilrs.gamepads_data[id.value()].have_sent_nonzero_for_axis[axis_idx] = new_val !=
              0.0
        }
        Some(Event::at(id, EventType::AxisChanged(axis, new_val, code), time))
      }
    }
    Some((other_axis, other_code)) => {
      let other_val = match gilrs.state(id) {
        None => 0.0
        Some(s) => s.value(other_code)
      }
      let (new_val, new_other_val) = apply_deadzone(val, other_val, threshold)
      match deadzone_nonzero_axis_idx(other_axis) {
        None => ()
        Some(other_axis_idx) => {
          let sent_nonzero = gilrs.gamepads_data[id.value()].have_sent_nonzero_for_axis[other_axis_idx]
          let other_state_val = match gilrs.state(id) {
            None => 0.0
            Some(s) => s.value(other_code)
          }
          if new_val == 0.0 &&
            new_other_val == 0.0 &&
            sent_nonzero &&
            other_state_val != 0.0 {
            gilrs.insert_event(
              Event::at(
                id,
                EventType::AxisChanged(other_axis, 0.0, other_code),
                time,
              ),
            )
            gilrs.gamepads_data[id.value()].have_sent_nonzero_for_axis[other_axis_idx] = false
          }
        }
      }
      let cur = match gilrs.state(id) {
        None => 0.0
        Some(s) => s.value(code)
      }
      if cur == new_val {
        Some(e.drop())
      } else {
        match deadzone_nonzero_axis_idx(axis) {
          None => ()
          Some(axis_idx) =>
            gilrs.gamepads_data[id.value()].have_sent_nonzero_for_axis[axis_idx] = new_val !=
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
  gilrs : Gilrs,
) -> Event? {
  let threshold = match gilrs.deadzone(e.id(), code) {
    None => return Some(e)
    Some(t) => t
  }
  let new_val = apply_deadzone(val, 0.0, threshold).0
  let cur = match gilrs.state(e.id()) {
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
pub fn axis_dpad_to_button(ev : Event?, gilrs : Gilrs) -> Event? {
  match ev {
    None => None
    Some(e) =>
      match e.event() {
        EventType::AxisChanged(axis, val, _) =>
          match axis {
            Axis::DPadX => axis_dpad_x_to_buttons(e, val, gilrs)
            Axis::DPadY => axis_dpad_y_to_buttons(e, val, gilrs)
            _ => ev
          }
        _ => ev
      }
  }
}

///|
fn can_map_axis_dpad_to_button(id : GamepadId, gilrs : Gilrs) -> Bool {
  match gilrs.mapping(id) {
    None => false
    Some(m) => {
      let hats = m.hats_mapped()
      if hats == 0b1111 {
        true
      } else if hats == 0 {
        gilrs.axis_or_btn_name(id, BTN_DPAD_RIGHT) is None &&
        gilrs.axis_or_btn_name(id, BTN_DPAD_LEFT) is None &&
        gilrs.axis_or_btn_name(id, BTN_DPAD_DOWN) is None &&
        gilrs.axis_or_btn_name(id, BTN_DPAD_UP) is None &&
        gilrs.button_code(id, Button::DPadRight) is None
      } else {
        false
      }
    }
  }
}

///|
fn axis_dpad_x_to_buttons(e : Event, val : Double, gilrs : Gilrs) -> Event? {
  if !can_map_axis_dpad_to_button(e.id(), gilrs) {
    return Some(e)
  }
  let id = e.id()
  let time = e.time()
  let mut out = e.drop()
  let mut release_left = false
  let mut release_right = false
  let pressed_left = match gilrs.state(id) {
    None => false
    Some(s) => s.is_pressed(BTN_DPAD_LEFT)
  }
  let pressed_right = match gilrs.state(id) {
    None => false
    Some(s) => s.is_pressed(BTN_DPAD_RIGHT)
  }
  if val == 1.0 {
    release_left = pressed_left
    gilrs.insert_event(
      Event::at(
        id,
        EventType::ButtonChanged(Button::DPadRight, 1.0, BTN_DPAD_RIGHT),
        time,
      ),
    )
    out = Event::at(
      id,
      EventType::ButtonPressed(Button::DPadRight, BTN_DPAD_RIGHT),
      time,
    )
  } else if val == -1.0 {
    release_right = pressed_right
    gilrs.insert_event(
      Event::at(
        id,
        EventType::ButtonChanged(Button::DPadLeft, 1.0, BTN_DPAD_LEFT),
        time,
      ),
    )
    out = Event::at(
      id,
      EventType::ButtonPressed(Button::DPadLeft, BTN_DPAD_LEFT),
      time,
    )
  } else {
    release_left = pressed_left
    release_right = pressed_right
  }
  if release_right {
    if !out.is_dropped() {
      gilrs.insert_event(out)
    }
    gilrs.insert_event(
      Event::at(
        id,
        EventType::ButtonChanged(Button::DPadRight, 0.0, BTN_DPAD_RIGHT),
        time,
      ),
    )
    out = Event::at(
      id,
      EventType::ButtonReleased(Button::DPadRight, BTN_DPAD_RIGHT),
      time,
    )
  }
  if release_left {
    if !out.is_dropped() {
      gilrs.insert_event(out)
    }
    gilrs.insert_event(
      Event::at(
        id,
        EventType::ButtonChanged(Button::DPadLeft, 0.0, BTN_DPAD_LEFT),
        time,
      ),
    )
    out = Event::at(
      id,
      EventType::ButtonReleased(Button::DPadLeft, BTN_DPAD_LEFT),
      time,
    )
  }
  Some(out)
}

///|
fn axis_dpad_y_to_buttons(e : Event, val : Double, gilrs : Gilrs) -> Event? {
  if !can_map_axis_dpad_to_button(e.id(), gilrs) {
    return Some(e)
  }
  let id = e.id()
  let time = e.time()
  let mut out = e.drop()
  let mut release_up = false
  let mut release_down = false
  let pressed_up = match gilrs.state(id) {
    None => false
    Some(s) => s.is_pressed(BTN_DPAD_UP)
  }
  let pressed_down = match gilrs.state(id) {
    None => false
    Some(s) => s.is_pressed(BTN_DPAD_DOWN)
  }
  if val == 1.0 {
    release_down = pressed_down
    gilrs.insert_event(
      Event::at(
        id,
        EventType::ButtonChanged(Button::DPadUp, 1.0, BTN_DPAD_UP),
        time,
      ),
    )
    out = Event::at(
      id,
      EventType::ButtonPressed(Button::DPadUp, BTN_DPAD_UP),
      time,
    )
  } else if val == -1.0 {
    release_up = pressed_up
    gilrs.insert_event(
      Event::at(
        id,
        EventType::ButtonChanged(Button::DPadDown, 1.0, BTN_DPAD_DOWN),
        time,
      ),
    )
    out = Event::at(
      id,
      EventType::ButtonPressed(Button::DPadDown, BTN_DPAD_DOWN),
      time,
    )
  } else {
    release_up = pressed_up
    release_down = pressed_down
  }
  if release_up {
    if !out.is_dropped() {
      gilrs.insert_event(out)
    }
    gilrs.insert_event(
      Event::at(
        id,
        EventType::ButtonChanged(Button::DPadUp, 0.0, BTN_DPAD_UP),
        time,
      ),
    )
    out = Event::at(
      id,
      EventType::ButtonReleased(Button::DPadUp, BTN_DPAD_UP),
      time,
    )
  }
  if release_down {
    if !out.is_dropped() {
      gilrs.insert_event(out)
    }
    gilrs.insert_event(
      Event::at(
        id,
        EventType::ButtonChanged(Button::DPadDown, 0.0, BTN_DPAD_DOWN),
        time,
      ),
    )
    out = Event::at(
      id,
      EventType::ButtonReleased(Button::DPadDown, BTN_DPAD_DOWN),
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
fn code_to_button_name(id : GamepadId, code : Code, gilrs : Gilrs) -> Button {
  match gilrs.axis_or_btn_name(id, code) {
    Some(AxisOrBtn::Btn(b)) => b
    _ => Button::Unknown
  }
}

///|
pub fn Repeat::filter(self : Repeat, ev : Event?, gilrs : Gilrs) -> Event? {
  match ev {
    Some(_) => ev
    None => {
      let now = gilrs.time()
      for i in 0..<gilrs.gamepads_data.length() {
        if !gilrs.gamepads_data[i].connected {
          continue
        }
        let id = GamepadId::new(i)
        match gilrs.state(id) {
          None => ()
          Some(state) =>
            for pair in state.buttons_entries() {
              let (code, data) = pair
              let pressed = data.is_pressed()
              let repeating = data.is_repeating()
              let dur = now - data.timestamp()
              if pressed && !repeating && dur >= self.after_ms {
                let btn = code_to_button_name(id, code, gilrs)
                return Some(
                  Event::at(
                    id,
                    EventType::ButtonRepeated(btn, code),
                    data.timestamp() + self.after_ms,
                  ),
                )
              }
              if pressed && repeating && dur >= self.every_ms {
                let btn = code_to_button_name(id, code, gilrs)
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
