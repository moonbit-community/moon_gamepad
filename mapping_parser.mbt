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
pub(all) enum AxisRange {
  LowerHalf
  UpperHalf
  Full
}

///|
pub(all) enum Token {
  Uuid(Uuid)
  Platform(String)
  Name(String)
  AxisMapping(Int32, AxisOrBtn, AxisRange, AxisRange, Bool)
  ButtonMapping(Int32, AxisOrBtn, AxisRange)
  HatMapping(Int32, Int32, AxisOrBtn, AxisRange)
}

///|
pub(all) enum ParserErrorKind {
  InvalidGuid
  InvalidKeyValPair
  InvalidValue
  EmptyValue
  UnknownAxis
  UnknownButton
  InvalidParserState
  UnexpectedEnd
}

///|
suberror ParserError {
  Error(ParserErrorKind, Int32)
}

///|
pub fn ParserError::kind(self : ParserError) -> ParserErrorKind {
  match self {
    Error(kind, _) => kind
  }
}

///|
pub fn ParserError::position(self : ParserError) -> Int32 {
  match self {
    Error(_, pos) => pos
  }
}

///|
priv enum State {
  Uuid
  Name
  KeyVal
  Invalid
}

///|
priv struct Parser {
  data : String
  mut pos : Int32
  mut state : State
}

///|
fn Parser::new(mapping : String) -> Parser {
  { data: mapping, pos: 0, state: Uuid, }
}

///|
fn next_comma_or_end(data : String, pos : Int32) -> Int32 {
  let n = data.length()
  for i in pos..<n {
    if data.code_unit_at(i).to_int() == ','.to_int() {
      return i
    }
  }
  n
}

///|
fn find_char(data : String, pos : Int32, end : Int32, needle : Char) -> Int32? {
  for i in pos..<end {
    if data.code_unit_at(i).to_int() == needle.to_int() {
      return Some(i)
    }
  }
  None
}

///|
fn slice_to_string(data : String, start : Int32, end : Int32) -> String {
  data.exact_view(start~, end~).to_owned()
}

///|
fn parse_u16_decimal(s : String, pos : Int32) -> Int32 raise ParserError {
  if s.length() == 0 {
    raise Error(InvalidValue, pos)
  }
  let mut acc = 0
  for c in s {
    if c is ('0'..<='9') {
      acc = acc * 10 + (c.to_int() - '0'.to_int())
      if acc > 65535 {
        raise Error(InvalidValue, pos)
      }
    } else {
      raise Error(InvalidValue, pos)
    }
  }
  acc
}

///|
let axes_sdl : Array[String] = [
  "a", "b", "back", "c", "dpdown", "dpleft", "dpright", "dpup", "guide", "leftshoulder",
  "leftstick", "lefttrigger", "leftx", "lefty", "leftz", "misc1", "paddle1", "paddle2",
  "paddle3", "paddle4", "rightshoulder", "rightstick", "righttrigger", "rightx",
  "righty", "rightz", "start", "touchpad", "x", "y", "z",
]

///|
let axes : Array[AxisOrBtn] = [
  Btn(South),
  Btn(East),
  Btn(Select),
  Btn(C),
  Btn(DPadDown),
  Btn(DPadLeft),
  Btn(DPadRight),
  Btn(DPadUp),
  Btn(Mode),
  Btn(LeftTrigger),
  Btn(LeftThumb),
  Btn(LeftTrigger2),
  Axis(LeftStickX),
  Axis(LeftStickY),
  Axis(LeftZ),
  Btn(Unknown),
  Btn(Unknown),
  Btn(Unknown),
  Btn(Unknown),
  Btn(Unknown),
  Btn(RightTrigger),
  Btn(RightThumb),
  Btn(RightTrigger2),
  Axis(RightStickX),
  Axis(RightStickY),
  Axis(RightZ),
  Btn(Start),
  Btn(Unknown),
  Btn(West),
  Btn(North),
  Btn(Z),
]

///|
fn lookup_axis_or_btn(
  key : String,
  kind : ParserErrorKind,
  pos : Int32,
) -> AxisOrBtn raise ParserError {
  for i in 0..<axes_sdl.length() {
    if axes_sdl[i] == key {
      return axes[i]
    }
  }
  raise Error(kind, pos)
}

///|
fn Parser::next_token(self : Parser) -> Token? raise ParserError {
  if self.pos >= self.data.length() {
    None
  } else {
    Some(
      match self.state {
        Uuid => self.parse_uuid()
        Name => self.parse_name()
        KeyVal => self.parse_key_val()
        Invalid => raise Error(InvalidParserState, self.pos)
      },
    )
  }
}

///|
fn Parser::parse_uuid(self : Parser) -> Token raise ParserError {
  let next_comma = next_comma_or_end(self.data, self.pos)
  let uuid_field = slice_to_string(self.data, self.pos, next_comma)
  if uuid_field == "xinput" {
    if next_comma == self.data.length() {
      self.state = Invalid
      raise Error(UnexpectedEnd, self.pos)
    }
    self.state = Name
    self.pos = next_comma + 1
    return Uuid(Uuid::nil())
  }
  let uuid = Token::Uuid(Uuid::parse(uuid_field)) catch {
    _ => {
      self.state = Invalid
      raise Error(InvalidGuid, self.pos)
    }
  }
  if next_comma == self.data.length() {
    self.state = Invalid
    raise Error(UnexpectedEnd, self.pos)
  }
  self.state = Name
  self.pos = next_comma + 1
  uuid
}

///|
fn Parser::parse_name(self : Parser) -> Token {
  let next_comma = next_comma_or_end(self.data, self.pos)
  let name = slice_to_string(self.data, self.pos, next_comma)
  self.state = KeyVal
  self.pos = next_comma + 1
  Name(name)
}

///|
fn Parser::parse_key_val(self : Parser) -> Token raise ParserError {
  let next_comma = next_comma_or_end(self.data, self.pos)
  let pos = self.pos
  let _pair = slice_to_string(self.data, self.pos, next_comma)
  self.pos = next_comma + 1
  let colon = match find_char(self.data, pos, next_comma, ':') {
    Some(i) => i
    None => raise Error(InvalidKeyValPair, pos)
  }
  if find_char(self.data, colon + 1, next_comma, ':') is Some(_) {
    raise Error(InvalidKeyValPair, pos)
  }
  let key = slice_to_string(self.data, pos, colon)
  let value = slice_to_string(self.data, colon + 1, next_comma)
  if value.length() == 0 {
    raise Error(EmptyValue, pos)
  }
  if key == "platform" {
    return Platform(value)
  }
  let (key, output) = match key {
    ['+', .. rest] => (rest.to_owned(), AxisRange::UpperHalf)
    ['-', .. rest] => (rest.to_owned(), LowerHalf)
    _ => (key, Full)
  }
  let (from_str, input, inverted, is_axis) = match value {
    ['+', 'a', .. rest] => {
      let mut body = rest.to_owned()
      let mut inv = false
      if body.length() > 0 &&
        body.code_unit_at(body.length() - 1).to_int() == '~'.to_int() {
        inv = true
        body = body[0:body.length() - 1].to_owned()
      }
      (body, AxisRange::UpperHalf, inv, true)
    }
    ['-', 'a', .. rest] => {
      let mut body = rest.to_owned()
      let mut inv = false
      if body.length() > 0 &&
        body.code_unit_at(body.length() - 1).to_int() == '~'.to_int() {
        inv = true
        body = body[0:body.length() - 1].to_owned()
      }
      (body, LowerHalf, inv, true)
    }
    ['a', .. rest] => {
      let mut body = rest.to_owned()
      let mut inv = false
      if body.length() > 0 &&
        body.code_unit_at(body.length() - 1).to_int() == '~'.to_int() {
        inv = true
        body = body[0:body.length() - 1].to_owned()
      }
      (body, Full, inv, true)
    }
    ['b', .. rest] => (rest.to_owned(), Full, false, false)
    ['h', .. rest] => {
      let body = rest.to_owned()
      let dot = match find_char(body, 0, body.length(), '.') {
        Some(i) => i
        None => raise Error(InvalidValue, pos)
      }
      let hat = parse_u16_decimal(body[0:dot].to_owned(), pos + 1)
      let direction = parse_u16_decimal(
        body[dot + 1:body.length()].to_owned(),
        pos + dot + 2,
      )
      let to = lookup_axis_or_btn(key, UnknownButton, pos)
      return HatMapping(hat, direction, to, output)
    }
    _ => raise Error(InvalidValue, pos)
  }
  let from = parse_u16_decimal(from_str, pos)
  if is_axis {
    let to = lookup_axis_or_btn(key, UnknownAxis, pos)
    AxisMapping(from, to, input, output, inverted)
  } else {
    let to = lookup_axis_or_btn(key, UnknownButton, pos)
    ButtonMapping(from, to, output)
  }
}
