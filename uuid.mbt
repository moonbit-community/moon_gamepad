///|
suberror UuidError {
  InvalidGuid
}

///|
pub struct Uuid {
  simple : String
}

///|
pub fn Uuid::nil() -> Uuid {
  { simple: "00000000000000000000000000000000" }
}

///|
pub fn Uuid::simple(self : Uuid) -> String {
  self.simple
}

///|
fn is_hex_char(c : Char) -> Bool {
  match c {
    '0'..='9' => true
    'a'..='f' => true
    'A'..='F' => true
    _ => false
  }
}

///|
fn to_lower_hex(c : Char) -> Char {
  match c {
    'A' => 'a'
    'B' => 'b'
    'C' => 'c'
    'D' => 'd'
    'E' => 'e'
    'F' => 'f'
    _ => c
  }
}

///|
pub fn Uuid::parse(s : String) -> Uuid raise UuidError {
  if s == "xinput" {
    return Uuid::nil()
  }
  let mut buf = ""
  for c in s {
    if c == '-' {
      continue
    }
    if !is_hex_char(c) {
      raise UuidError::InvalidGuid
    }
    buf = buf + [to_lower_hex(c)]
  }
  if buf.length() != 32 {
    raise UuidError::InvalidGuid
  }
  { simple: buf }
}
