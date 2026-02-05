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
pub struct GamepadId {
  value : Int
}

///|
pub fn GamepadId::new(value : Int) -> GamepadId {
  { value, }
}

///|
pub fn GamepadId::value(self : GamepadId) -> Int {
  self.value
}

///|
pub(all) enum EventType {
  ButtonPressed(Button, Code)
  ButtonRepeated(Button, Code)
  ButtonReleased(Button, Code)
  ButtonChanged(Button, Double, Code)
  AxisChanged(Axis, Double, Code)
  Connected
  Disconnected
  Dropped
  ForceFeedbackEffectCompleted
}

///|
pub struct Event {
  id : GamepadId
  event : EventType
  time : Int64
}

///|
pub fn Event::new(id : GamepadId, event : EventType) -> Event {
  { id, event, time: 0L }
}

///|
pub fn Event::at(id : GamepadId, event : EventType, time : Int64) -> Event {
  { id, event, time }
}

///|
pub fn Event::id(self : Event) -> GamepadId {
  self.id
}

///|
pub fn Event::event(self : Event) -> EventType {
  self.event
}

///|
pub fn Event::time(self : Event) -> Int64 {
  self.time
}

///|
pub fn Event::drop(self : Event) -> Event {
  { id: self.id, event: EventType::Dropped, time: self.time }
}

///|
pub fn Event::is_dropped(self : Event) -> Bool {
  match self.event {
    EventType::Dropped => true
    _ => false
  }
}
