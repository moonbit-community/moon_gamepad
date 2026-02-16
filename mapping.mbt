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
suberror MappingError {
  InvalidCode(Code)
  InvalidName
  NotImplemented
  NotConnected
  DuplicatedEntry
  UnknownElement
  NotSdl2Compatible
}

///|
let _mapping_error_keepalive : Array[MappingError] = [
  MappingError::NotImplemented,
  MappingError::NotConnected,
  MappingError::DuplicatedEntry,
  MappingError::NotSdl2Compatible,
]

///|
suberror ParseSdlMappingError {
  UnknownHatDirection
  ParseError(ParserError)
}

///|
pub struct Mapping {
  mappings : Array[(Code, AxisOrBtn)]
  mut name : String
  default : Bool
  mut hats_mapped : Int
}

///|
pub fn Mapping::new() -> Mapping {
  { mappings: [], name: "", default: false, hats_mapped: 0 }
}

///|
pub fn Mapping::new_default() -> Mapping {
  { mappings: [], name: "", default: true, hats_mapped: 0 }
}

///|
fn axis_same(a : Axis, b : Axis) -> Bool {
  a.to_index() == b.to_index()
}

///|
fn button_same(a : Button, b : Button) -> Bool {
  a.to_index() == b.to_index()
}

///|
fn axis_or_btn_same(a : AxisOrBtn, b : AxisOrBtn) -> Bool {
  match a {
    AxisOrBtn::Axis(ax) =>
      match b {
        AxisOrBtn::Axis(bx) => axis_same(ax, bx)
        AxisOrBtn::Btn(_) => false
      }
    AxisOrBtn::Btn(btn) =>
      match b {
        AxisOrBtn::Axis(_) => false
        AxisOrBtn::Btn(bn) => button_same(btn, bn)
      }
  }
}

///|
fn insert_mapping(
  mappings : Array[(Code, AxisOrBtn)],
  code : Code,
  el : AxisOrBtn,
) -> Unit {
  for i in 0..<mappings.length() {
    let (c, _) = mappings[i]
    if c == code {
      mappings[i] = (code, el)
      return
    }
  }
  mappings.push((code, el))
}

///|
pub fn Mapping::insert(self : Mapping, code : Code, el : AxisOrBtn) -> Unit {
  insert_mapping(self.mappings, code, el)
}

///|
pub fn Mapping::set_hats_mapped(self : Mapping, hats : Int) -> Unit {
  self.hats_mapped = hats
}

///|
pub fn Mapping::map(self : Mapping, code : Code) -> AxisOrBtn? {
  for pair in self.mappings {
    let (c, v) = pair
    if c == code {
      return Some(v)
    }
  }
  None
}

///|
pub fn Mapping::map_rev(self : Mapping, el : AxisOrBtn) -> Code? {
  for pair in self.mappings {
    let (c, v) = pair
    if axis_or_btn_same(v, el) {
      return Some(c)
    }
  }
  None
}

///|
pub fn Mapping::name(self : Mapping) -> String {
  self.name
}

///|
pub fn Mapping::is_default(self : Mapping) -> Bool {
  self.default
}

///|
pub fn Mapping::hats_mapped(self : Mapping) -> Int {
  self.hats_mapped
}

///|
pub fn Mapping::entries(self : Mapping) -> Array[(Code, AxisOrBtn)] {
  self.mappings.copy()
}

///|
pub fn Mapping::parse_sdl_mapping(
  line : String,
  buttons : Array[Code],
  axes : Array[Code],
) -> Mapping raise ParseSdlMappingError {
  let mapping = Mapping::new()
  let parser = Parser::new(line)
  while true {
    let res : Result[Token?, ParserError] = try? parser.next_token()
    match res {
      Ok(token_opt) =>
        match token_opt {
          None => break
          Some(token) =>
            match token {
              Token::Uuid(_) => ()
              Token::Platform(_) => ()
              Token::Name(n) => mapping.name = n
              Token::AxisMapping(idx, to, _, _, _) =>
                if idx >= 0 && idx < axes.length() {
                  insert_mapping(mapping.mappings, axes[idx], to)
                }
              Token::ButtonMapping(idx, to, _) =>
                if idx >= 0 && idx < buttons.length() {
                  insert_mapping(mapping.mappings, buttons[idx], to)
                }
              Token::HatMapping(hat, direction, to, _) => {
                if hat != 0 {
                  continue
                }
                let (from_axis, from_btn) = match direction {
                  1 => (AXIS_DPADY, BTN_DPAD_UP)
                  4 => (AXIS_DPADY, BTN_DPAD_DOWN)
                  2 => (AXIS_DPADX, BTN_DPAD_RIGHT)
                  8 => (AXIS_DPADX, BTN_DPAD_LEFT)
                  0 => continue
                  _ => raise ParseSdlMappingError::UnknownHatDirection
                }
                if to.is_button() {
                  match to {
                    AxisOrBtn::Btn(Button::DPadLeft | Button::DPadRight) =>
                      insert_mapping(
                        mapping.mappings,
                        from_axis,
                        AxisOrBtn::Axis(Axis::DPadX),
                      )
                    AxisOrBtn::Btn(Button::DPadUp | Button::DPadDown) =>
                      insert_mapping(
                        mapping.mappings,
                        from_axis,
                        AxisOrBtn::Axis(Axis::DPadY),
                      )
                    _ => ()
                  }
                  insert_mapping(mapping.mappings, from_btn, to)
                } else {
                  insert_mapping(mapping.mappings, from_axis, to)
                }
                mapping.hats_mapped = mapping.hats_mapped | direction
              }
            }
        }
      Err(e) =>
        match e {
          ParserError::Error(ParserErrorKind::EmptyValue, _) => continue
          _ => raise ParseSdlMappingError::ParseError(e)
        }
    }
  }
  mapping
}

///|
pub struct MappingData {
  buttons : Array[Code?]
  axes : Array[Code?]
}

///|
pub fn MappingData::new() -> MappingData {
  {
    buttons: Array::make(BUTTON_COUNT, None),
    axes: Array::make(AXIS_COUNT, None),
  }
}

///|
pub fn MappingData::button(self : MappingData, idx : Button) -> Code? {
  self.buttons[idx.to_index()]
}

///|
pub fn MappingData::axis(self : MappingData, idx : Axis) -> Code? {
  self.axes[idx.to_index()]
}

///|
pub fn MappingData::insert_btn(
  self : MappingData,
  from : Code,
  to : Button,
) -> Code? {
  let i = to.to_index()
  let prev = self.buttons[i]
  self.buttons[i] = Some(from)
  prev
}

///|
pub fn MappingData::insert_axis(
  self : MappingData,
  from : Code,
  to : Axis,
) -> Code? {
  let i = to.to_index()
  let prev = self.axes[i]
  self.axes[i] = Some(from)
  prev
}

///|
pub fn MappingData::remove_button(self : MappingData, idx : Button) -> Code? {
  let i = idx.to_index()
  let prev = self.buttons[i]
  self.buttons[i] = None
  prev
}

///|
pub fn MappingData::remove_axis(self : MappingData, idx : Axis) -> Code? {
  let i = idx.to_index()
  let prev = self.axes[i]
  self.axes[i] = None
  prev
}

///|
fn is_name_valid(name : String) -> Bool {
  for c in name {
    if c == ',' {
      return false
    }
  }
  true
}

///|
fn index_of_code(list : Array[Code], code : Code) -> Int? {
  for i in 0..<list.length() {
    if list[i] == code {
      return Some(i)
    }
  }
  None
}

///|
fn add_button(
  ident : String,
  ev_code : Code,
  mapped_btn : Button,
  buttons : Array[Code],
  sdl_mappings : String,
  mappings : Array[(Code, AxisOrBtn)],
) -> String raise MappingError {
  let idx = match index_of_code(buttons, ev_code) {
    Some(i) => i
    None => raise MappingError::InvalidCode(ev_code)
  }
  insert_mapping(mappings, ev_code, AxisOrBtn::Btn(mapped_btn))
  sdl_mappings + "\{ident}:b\{idx},"
}

///|
fn add_axis(
  ident : String,
  ev_code : Code,
  mapped_axis : Axis,
  axes : Array[Code],
  sdl_mappings : String,
  mappings : Array[(Code, AxisOrBtn)],
) -> String raise MappingError {
  let idx = match index_of_code(axes, ev_code) {
    Some(i) => i
    None => raise MappingError::InvalidCode(ev_code)
  }
  insert_mapping(mappings, ev_code, AxisOrBtn::Axis(mapped_axis))
  sdl_mappings + "\{ident}:a\{idx},"
}

///|
pub fn Mapping::from_data(
  data : MappingData,
  buttons : Array[Code],
  axes : Array[Code],
  name : String,
  uuid : Uuid,
) -> (Mapping, String) raise MappingError {
  if !is_name_valid(name) {
    raise MappingError::InvalidName
  }
  if data.button(Button::Unknown) is Some(_) ||
    data.axis(Axis::Unknown) is Some(_) {
    raise MappingError::UnknownElement
  }
  let mappings : Array[(Code, AxisOrBtn)] = []
  let mut sdl_mappings = "\{uuid.simple()},\{name},"
  if data.axis(Axis::LeftStickX) is Some(code) {
    sdl_mappings = add_axis(
      "leftx",
      code,
      Axis::LeftStickX,
      axes,
      sdl_mappings,
      mappings,
    )
  }
  if data.axis(Axis::LeftStickY) is Some(code) {
    sdl_mappings = add_axis(
      "lefty",
      code,
      Axis::LeftStickY,
      axes,
      sdl_mappings,
      mappings,
    )
  }
  if data.axis(Axis::LeftZ) is Some(code) {
    sdl_mappings = add_axis(
      "leftz",
      code,
      Axis::LeftZ,
      axes,
      sdl_mappings,
      mappings,
    )
  }
  if data.axis(Axis::RightStickX) is Some(code) {
    sdl_mappings = add_axis(
      "rightx",
      code,
      Axis::RightStickX,
      axes,
      sdl_mappings,
      mappings,
    )
  }
  if data.axis(Axis::RightStickY) is Some(code) {
    sdl_mappings = add_axis(
      "righty",
      code,
      Axis::RightStickY,
      axes,
      sdl_mappings,
      mappings,
    )
  }
  if data.axis(Axis::RightZ) is Some(code) {
    sdl_mappings = add_axis(
      "rightz",
      code,
      Axis::RightZ,
      axes,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::South) is Some(code) {
    sdl_mappings = add_button(
      "a",
      code,
      Button::South,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::East) is Some(code) {
    sdl_mappings = add_button(
      "b",
      code,
      Button::East,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::West) is Some(code) {
    sdl_mappings = add_button(
      "x",
      code,
      Button::West,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::North) is Some(code) {
    sdl_mappings = add_button(
      "y",
      code,
      Button::North,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::LeftTrigger) is Some(code) {
    sdl_mappings = add_button(
      "leftshoulder",
      code,
      Button::LeftTrigger,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::RightTrigger) is Some(code) {
    sdl_mappings = add_button(
      "rightshoulder",
      code,
      Button::RightTrigger,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::LeftTrigger2) is Some(code) {
    sdl_mappings = add_button(
      "lefttrigger",
      code,
      Button::LeftTrigger2,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::RightTrigger2) is Some(code) {
    sdl_mappings = add_button(
      "righttrigger",
      code,
      Button::RightTrigger2,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::Select) is Some(code) {
    sdl_mappings = add_button(
      "back",
      code,
      Button::Select,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::Start) is Some(code) {
    sdl_mappings = add_button(
      "start",
      code,
      Button::Start,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::Mode) is Some(code) {
    sdl_mappings = add_button(
      "guide",
      code,
      Button::Mode,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::LeftThumb) is Some(code) {
    sdl_mappings = add_button(
      "leftstick",
      code,
      Button::LeftThumb,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::RightThumb) is Some(code) {
    sdl_mappings = add_button(
      "rightstick",
      code,
      Button::RightThumb,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::DPadUp) is Some(code) {
    sdl_mappings = add_button(
      "dpup",
      code,
      Button::DPadUp,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::DPadDown) is Some(code) {
    sdl_mappings = add_button(
      "dpdown",
      code,
      Button::DPadDown,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::DPadLeft) is Some(code) {
    sdl_mappings = add_button(
      "dpleft",
      code,
      Button::DPadLeft,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  if data.button(Button::DPadRight) is Some(code) {
    sdl_mappings = add_button(
      "dpright",
      code,
      Button::DPadRight,
      buttons,
      sdl_mappings,
      mappings,
    )
  }
  ({ mappings, name, default: false, hats_mapped: 0 }, sdl_mappings)
}

///|
pub struct MappingDb {
  mappings : Array[(Uuid, String)]
}

///|
const INCLUDED_MAPPINGS : String = "030000005e0400008e02000002010000,Xbox 360 Controller,a:b0,b:b1,back:b6,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,leftshoulder:b4,leftstick:b9,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b10,righttrigger:a5,rightx:a3,righty:a4,start:b7,x:b2,y:b3,"

///|
pub fn MappingDb::new() -> MappingDb {
  { mappings: [] }
}

///|
fn index_of_substring(s : String, pat : String) -> Int? {
  let n = s.length()
  let m = pat.length()
  if m == 0 {
    return Some(0)
  }
  if n < m {
    return None
  }
  for i in 0..<(n - m + 1) {
    let mut ok = true
    for j in 0..<m {
      if s.code_unit_at(i + j) != pat.code_unit_at(j) {
        ok = false
        break
      }
    }
    if ok {
      return Some(i)
    }
  }
  None
}

///|
fn find_first_comma(s : String) -> Int? {
  for i in 0..<s.length() {
    if s.code_unit_at(i).to_int() == ','.to_int() {
      return Some(i)
    }
  }
  None
}

///|
fn mapping_line_platform(line : String) -> String? {
  match index_of_substring(line, "platform:") {
    None => None
    Some(idx) => {
      let start = idx + "platform:".length()
      if start >= line.length() {
        return Some("")
      }
      let tail = (try! line[start:line.length()]).to_string()
      let end = match find_first_comma(tail) {
        None => tail.length()
        Some(i) => i
      }
      Some((try! tail[0:end]).to_string())
    }
  }
}

///|
fn mapping_line_matches_platform(line : String) -> Bool {
  let current = runtime_sdl_platform_name()
  match mapping_line_platform(line) {
    None => true
    Some(p) => p == current
  }
}

///|
fn upsert_mapping(db : MappingDb, uuid : Uuid, line : String) -> Unit {
  for i in 0..<db.mappings.length() {
    let (u, _) = db.mappings[i]
    if u.simple() == uuid.simple() {
      db.mappings[i] = (uuid, line)
      return
    }
  }
  db.mappings.push((uuid, line))
}

///|
pub fn MappingDb::insert(self : MappingDb, s : String) -> Unit {
  for line_view in s.split("\n") {
    let line = line_view.to_string()
    if line.length() == 0 {
      continue
    }
    if !mapping_line_matches_platform(line) {
      continue
    }
    match find_first_comma(line) {
      None => continue
      Some(i) => {
        let guid = (try! line[0:i]).to_string()
        try {
          let uuid = Uuid::parse(guid)
          upsert_mapping(self, uuid, line)
        } catch {
          _ => ()
        }
      }
    }
  }
}

///|
pub fn MappingDb::add_included_mappings(self : MappingDb) -> Unit {
  self.insert(INCLUDED_MAPPINGS)
}

///|
pub fn MappingDb::add_env_mappings(self : MappingDb) -> Unit {
  let env = runtime_env_sdl_gamecontrollerconfig()
  if env.length() != 0 {
    self.insert(env)
  }
}

///|
pub fn MappingDb::get(self : MappingDb, uuid : Uuid) -> String? {
  for pair in self.mappings {
    let (u, v) = pair
    if u.simple() == uuid.simple() {
      return Some(v)
    }
  }
  None
}

///|
pub fn MappingDb::len(self : MappingDb) -> Int {
  self.mappings.length()
}
