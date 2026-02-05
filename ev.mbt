///|
pub type Code = Int

///|
pub(all) enum Axis {
  LeftStickX
  LeftStickY
  LeftZ
  RightStickX
  RightStickY
  RightZ
  DPadX
  DPadY
  Unknown
}

///|
pub fn Axis::is_stick(self : Axis) -> Bool {
  match self {
    Axis::LeftStickX
    | Axis::LeftStickY
    | Axis::RightStickX
    | Axis::RightStickY => true
    _ => false
  }
}

///|
pub fn Axis::second_axis(self : Axis) -> Axis? {
  match self {
    Axis::LeftStickX => Some(Axis::LeftStickY)
    Axis::LeftStickY => Some(Axis::LeftStickX)
    Axis::RightStickX => Some(Axis::RightStickY)
    Axis::RightStickY => Some(Axis::RightStickX)
    Axis::DPadX => Some(Axis::DPadY)
    Axis::DPadY => Some(Axis::DPadX)
    _ => None
  }
}

///|
pub fn Axis::to_index(self : Axis) -> Int {
  match self {
    LeftStickX => 0
    LeftStickY => 1
    LeftZ => 2
    RightStickX => 3
    RightStickY => 4
    RightZ => 5
    DPadX => 6
    DPadY => 7
    Unknown => 8
  }
}

///|
pub const AXIS_COUNT : Int = 9

///|
pub(all) enum Button {
  South
  East
  C
  North
  West
  Z
  LeftTrigger
  RightTrigger
  LeftTrigger2
  RightTrigger2
  Select
  Start
  Mode
  LeftThumb
  RightThumb
  DPadUp
  DPadDown
  DPadLeft
  DPadRight
  Unknown
}

///|
pub fn Button::is_action(self : Button) -> Bool {
  match self {
    Button::South
    | Button::East
    | Button::North
    | Button::West
    | Button::C
    | Button::Z => true
    _ => false
  }
}

///|
pub fn Button::is_trigger(self : Button) -> Bool {
  match self {
    Button::LeftTrigger
    | Button::LeftTrigger2
    | Button::RightTrigger
    | Button::RightTrigger2 => true
    _ => false
  }
}

///|
pub fn Button::is_menu(self : Button) -> Bool {
  match self {
    Button::Select | Button::Start | Button::Mode => true
    _ => false
  }
}

///|
pub fn Button::is_stick(self : Button) -> Bool {
  match self {
    Button::LeftThumb | Button::RightThumb => true
    _ => false
  }
}

///|
pub fn Button::is_dpad(self : Button) -> Bool {
  match self {
    Button::DPadUp | Button::DPadDown | Button::DPadLeft | Button::DPadRight =>
      true
    _ => false
  }
}

///|
pub fn Button::to_index(self : Button) -> Int {
  match self {
    South => 0
    East => 1
    C => 2
    North => 3
    West => 4
    Z => 5
    LeftTrigger => 6
    RightTrigger => 7
    LeftTrigger2 => 8
    RightTrigger2 => 9
    Select => 10
    Start => 11
    Mode => 12
    LeftThumb => 13
    RightThumb => 14
    DPadUp => 15
    DPadDown => 16
    DPadLeft => 17
    DPadRight => 18
    Unknown => 19
  }
}

///|
pub const BUTTON_COUNT : Int = 20

///|
pub(all) enum AxisOrBtn {
  Axis(Axis)
  Btn(Button)
}

///|
pub fn AxisOrBtn::is_button(self : AxisOrBtn) -> Bool {
  match self {
    Btn(_) => true
    Axis(_) => false
  }
}
