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
  AxisMapping(Int, AxisOrBtn, AxisRange, AxisRange, Bool)
  ButtonMapping(Int, AxisOrBtn, AxisRange)
  HatMapping(Int, Int, AxisOrBtn, AxisRange)
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
  Error(ParserErrorKind, Int)
}

///|
pub fn ParserError::kind(self : ParserError) -> ParserErrorKind {
  match self {
    Error(kind, _) => kind
  }
}

///|
pub fn ParserError::position(self : ParserError) -> Int {
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
  mut pos : Int
  mut state : State
}

///|
fn Parser::new(mapping : String) -> Parser {
  { data: mapping, pos: 0, state: State::Uuid }
}

///|
fn next_comma_or_end(data : String, pos : Int) -> Int {
  let n = data.length()
  for i in pos..<n {
    if data.code_unit_at(i).to_int() == ','.to_int() {
      return i
    }
  }
  n
}

///|
fn find_char(data : String, pos : Int, end : Int, needle : Char) -> Int? {
  for i in pos..<end {
    if data.code_unit_at(i).to_int() == needle.to_int() {
      return Some(i)
    }
  }
  None
}

///|
fn slice_to_string(
  data : String,
  start : Int,
  end : Int,
) -> String raise ParserError {
  data.sub(start~, end~).to_string() catch {
    _ => raise ParserError::Error(ParserErrorKind::InvalidParserState, start)
  }
}

///|
fn parse_u16_decimal(s : String, pos : Int) -> Int raise ParserError {
  if s.length() == 0 {
    raise ParserError::Error(ParserErrorKind::InvalidValue, pos)
  }
  let mut acc = 0
  for c in s {
    if c is ('0'..='9') {
      acc = acc * 10 + (c.to_int() - '0'.to_int())
    } else {
      raise ParserError::Error(ParserErrorKind::InvalidValue, pos)
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
  AxisOrBtn::Btn(Button::South),
  AxisOrBtn::Btn(Button::East),
  AxisOrBtn::Btn(Button::Select),
  AxisOrBtn::Btn(Button::C),
  AxisOrBtn::Btn(Button::DPadDown),
  AxisOrBtn::Btn(Button::DPadLeft),
  AxisOrBtn::Btn(Button::DPadRight),
  AxisOrBtn::Btn(Button::DPadUp),
  AxisOrBtn::Btn(Button::Mode),
  AxisOrBtn::Btn(Button::LeftTrigger),
  AxisOrBtn::Btn(Button::LeftThumb),
  AxisOrBtn::Btn(Button::LeftTrigger2),
  AxisOrBtn::Axis(Axis::LeftStickX),
  AxisOrBtn::Axis(Axis::LeftStickY),
  AxisOrBtn::Axis(Axis::LeftZ),
  AxisOrBtn::Btn(Button::Unknown),
  AxisOrBtn::Btn(Button::Unknown),
  AxisOrBtn::Btn(Button::Unknown),
  AxisOrBtn::Btn(Button::Unknown),
  AxisOrBtn::Btn(Button::Unknown),
  AxisOrBtn::Btn(Button::RightTrigger),
  AxisOrBtn::Btn(Button::RightThumb),
  AxisOrBtn::Btn(Button::RightTrigger2),
  AxisOrBtn::Axis(Axis::RightStickX),
  AxisOrBtn::Axis(Axis::RightStickY),
  AxisOrBtn::Axis(Axis::RightZ),
  AxisOrBtn::Btn(Button::Start),
  AxisOrBtn::Btn(Button::Unknown),
  AxisOrBtn::Btn(Button::West),
  AxisOrBtn::Btn(Button::North),
  AxisOrBtn::Btn(Button::Z),
]

///|
fn lookup_axis_or_btn(
  key : String,
  kind : ParserErrorKind,
  pos : Int,
) -> AxisOrBtn raise ParserError {
  for i in 0..<axes_sdl.length() {
    if axes_sdl[i] == key {
      return axes[i]
    }
  }
  raise ParserError::Error(kind, pos)
}

///|
fn Parser::next_token(self : Parser) -> Token? raise ParserError {
  if self.pos >= self.data.length() {
    None
  } else {
    Some(
      match self.state {
        State::Uuid => self.parse_uuid()
        State::Name => self.parse_name()
        State::KeyVal => self.parse_key_val()
        State::Invalid =>
          raise ParserError::Error(
            ParserErrorKind::InvalidParserState,
            self.pos,
          )
      },
    )
  }
}

///|
fn Parser::parse_uuid(self : Parser) -> Token raise ParserError {
  let next_comma = next_comma_or_end(self.data, self.pos)
  let uuid_field = slice_to_string(self.data, self.pos, next_comma)
  let uuid = Token::Uuid(Uuid::parse(uuid_field)) catch {
    _ => {
      self.state = State::Invalid
      raise ParserError::Error(ParserErrorKind::InvalidGuid, self.pos)
    }
  }
  if next_comma == self.data.length() {
    self.state = State::Invalid
    raise ParserError::Error(ParserErrorKind::UnexpectedEnd, self.pos)
  }
  self.state = State::Name
  self.pos = next_comma + 1
  uuid
}

///|
fn Parser::parse_name(self : Parser) -> Token raise ParserError {
  let next_comma = next_comma_or_end(self.data, self.pos)
  let name = slice_to_string(self.data, self.pos, next_comma)
  self.state = State::KeyVal
  self.pos = next_comma + 1
  Token::Name(name)
}

///|
fn Parser::parse_key_val(self : Parser) -> Token raise ParserError {
  let next_comma = next_comma_or_end(self.data, self.pos)
  let pos = self.pos
  let _pair = slice_to_string(self.data, self.pos, next_comma)
  self.pos = next_comma + 1
  let colon = match find_char(self.data, pos, next_comma, ':') {
    Some(i) => i
    None => raise ParserError::Error(ParserErrorKind::InvalidKeyValPair, pos)
  }
  if find_char(self.data, colon + 1, next_comma, ':') is Some(_) {
    raise ParserError::Error(ParserErrorKind::InvalidKeyValPair, pos)
  }
  let key = slice_to_string(self.data, pos, colon)
  let value = slice_to_string(self.data, colon + 1, next_comma)
  if value.length() == 0 {
    raise ParserError::Error(ParserErrorKind::EmptyValue, pos)
  }
  if key == "platform" {
    return Token::Platform(value)
  }
  let (key, output) = match key {
    ['+', .. rest] => (rest.to_string(), AxisRange::UpperHalf)
    ['-', .. rest] => (rest.to_string(), AxisRange::LowerHalf)
    _ => (key, AxisRange::Full)
  }
  let (from_str, input, inverted, is_axis) = match value {
    ['+', 'a', .. rest] => {
      let mut body = rest.to_string()
      let mut inv = false
      if body.length() > 0 &&
        body.code_unit_at(body.length() - 1).to_int() == '~'.to_int() {
        inv = true
        body = (try! body[0:body.length() - 1]).to_string()
      }
      (body, AxisRange::UpperHalf, inv, true)
    }
    ['-', 'a', .. rest] => {
      let mut body = rest.to_string()
      let mut inv = false
      if body.length() > 0 &&
        body.code_unit_at(body.length() - 1).to_int() == '~'.to_int() {
        inv = true
        body = (try! body[0:body.length() - 1]).to_string()
      }
      (body, AxisRange::LowerHalf, inv, true)
    }
    ['a', .. rest] => {
      let mut body = rest.to_string()
      let mut inv = false
      if body.length() > 0 &&
        body.code_unit_at(body.length() - 1).to_int() == '~'.to_int() {
        inv = true
        body = (try! body[0:body.length() - 1]).to_string()
      }
      (body, AxisRange::Full, inv, true)
    }
    ['b', .. rest] => (rest.to_string(), AxisRange::Full, false, false)
    ['h', .. rest] => {
      let body = rest.to_string()
      let dot = match find_char(body, 0, body.length(), '.') {
        Some(i) => i
        None => raise ParserError::Error(ParserErrorKind::InvalidValue, pos)
      }
      let hat = parse_u16_decimal((try! body[0:dot]).to_string(), pos + 1)
      let direction = parse_u16_decimal(
        (try! body[dot + 1:body.length()]).to_string(),
        pos + dot + 1,
      )
      let to = lookup_axis_or_btn(key, ParserErrorKind::UnknownButton, pos)
      return Token::HatMapping(hat, direction, to, output)
    }
    _ => raise ParserError::Error(ParserErrorKind::InvalidValue, pos)
  }
  let from = parse_u16_decimal(from_str, pos)
  if is_axis {
    let to = lookup_axis_or_btn(key, ParserErrorKind::UnknownAxis, pos)
    Token::AxisMapping(from, to, input, output, inverted)
  } else {
    let to = lookup_axis_or_btn(key, ParserErrorKind::UnknownButton, pos)
    Token::ButtonMapping(from, to, output)
  }
}
