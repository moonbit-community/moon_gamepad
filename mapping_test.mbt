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
const TEST_STR : String = "03000000260900008888000000010001,GameCube {WiseGroup USB box},a:b0,b:b2,y:b3,x:b1,start:b7,rightshoulder:b6,dpup:h0.1,dpleft:h0.8,dpdown:h0.4,dpright:h0.2,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:a4,righttrigger:a5,"

///|
#borrow(s)
extern "C" fn runtime_set_sdl_gamecontrollerconfig_for_test(s : String) -> Unit = "moon_gamepad_set_sdl_gamecontrollerconfig_for_test"

///|
extern "C" fn runtime_clear_sdl_gamecontrollerconfig_for_test() -> Unit = "moon_gamepad_clear_sdl_gamecontrollerconfig_for_test"

///|
let buttons : Array[Code] = [
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
]

///|
let axes : Array[Code] = [
  AXIS_LSTICKX,
  AXIS_LSTICKY,
  AXIS_RSTICKX,
  AXIS_RSTICKY,
  AXIS_LT2,
  AXIS_RT2,
  LEGACY_AXIS_LEFTZ,
  LEGACY_AXIS_RIGHTZ,
]

///|
fn mapping_debug(m : Mapping) -> String {
  fn axis_name(ax : Axis) -> String {
    match ax {
      Axis::LeftStickX => "LeftStickX"
      Axis::LeftStickY => "LeftStickY"
      Axis::LeftZ => "LeftZ"
      Axis::RightStickX => "RightStickX"
      Axis::RightStickY => "RightStickY"
      Axis::RightZ => "RightZ"
      Axis::DPadX => "DPadX"
      Axis::DPadY => "DPadY"
      Axis::Unknown => "Unknown"
    }
  }

  fn button_name(btn : Button) -> String {
    match btn {
      Button::South => "South"
      Button::East => "East"
      Button::C => "C"
      Button::North => "North"
      Button::West => "West"
      Button::Z => "Z"
      Button::LeftTrigger => "LeftTrigger"
      Button::RightTrigger => "RightTrigger"
      Button::LeftTrigger2 => "LeftTrigger2"
      Button::RightTrigger2 => "RightTrigger2"
      Button::Select => "Select"
      Button::Start => "Start"
      Button::Mode => "Mode"
      Button::LeftThumb => "LeftThumb"
      Button::RightThumb => "RightThumb"
      Button::DPadUp => "DPadUp"
      Button::DPadDown => "DPadDown"
      Button::DPadLeft => "DPadLeft"
      Button::DPadRight => "DPadRight"
      Button::Unknown => "Unknown"
    }
  }

  fn el_name(el : AxisOrBtn) -> String {
    match el {
      AxisOrBtn::Axis(ax) => "Axis:" + axis_name(ax)
      AxisOrBtn::Btn(btn) => "Btn:" + button_name(btn)
    }
  }

  let entries = m
    .entries()
    .map(fn(pair : (Code, AxisOrBtn)) -> String {
      let (code, el) = pair
      "\{code}->\{el_name(el)}"
    })
  "name=\{m.name()};hats=\{m.hats_mapped()};" + entries.join(";")
}

///|
test "parse_sdl_mapping" {
  let res : Result[Mapping, Error] = try? Mapping::parse_sdl_mapping(
    TEST_STR,
    buttons,
    axes,
  )
  match res {
    Ok(m) =>
      inspect(
        mapping_debug(m),
        content="name=GameCube {WiseGroup USB box};hats=15;589825->Btn:South;589844->Btn:East;589829->Btn:North;589826->Btn:West;589832->Btn:Start;589831->Btn:RightTrigger;65594->Axis:DPadY;589840->Btn:DPadUp;65593->Axis:DPadX;589842->Btn:DPadLeft;589841->Btn:DPadDown;589843->Btn:DPadRight;65584->Axis:LeftStickX;65585->Axis:LeftStickY;65586->Axis:RightStickX;65589->Axis:RightStickY;131269->Btn:LeftTrigger2;131268->Btn:RightTrigger2",
      )
    Err(_) => fail("parse_sdl_mapping should not fail")
  }
}

///|
test "parse_sdl_mapping preserves unmapped button indices" {
  let uuid = Uuid::nil().simple()
  let line = uuid + ",Test,a:b2,"
  // Include an extra unmapped button usage (usage=3) at index 2.
  let buttons2 : Array[Code] = [
    hid_code(PAGE_BUTTON, 1),
    hid_code(PAGE_BUTTON, 2),
    hid_code(PAGE_BUTTON, 3),
  ]
  let res : Result[Mapping, Error] = try? Mapping::parse_sdl_mapping(
    line,
    buttons2,
    [],
  )
  match res {
    Ok(m) => {
      let code = hid_code(PAGE_BUTTON, 3)
      let ok = match m.map(code) {
        Some(AxisOrBtn::Btn(Button::South)) => true
        _ => false
      }
      inspect(ok, content="true")
    }
    Err(_) => fail("parse_sdl_mapping should not fail")
  }
}

///|
test "from_data roundtrip + errors" {
  let uuid = Uuid::nil()
  let name = "Best Gamepad"
  let data = MappingData::new()
  data.insert_axis(AXIS_LSTICKX, Axis::LeftStickX) |> ignore
  data.insert_axis(AXIS_LSTICKY, Axis::LeftStickY) |> ignore
  data.insert_axis(LEGACY_AXIS_LEFTZ, Axis::LeftZ) |> ignore
  data.insert_axis(AXIS_RSTICKX, Axis::RightStickX) |> ignore
  data.insert_axis(AXIS_RSTICKY, Axis::RightStickY) |> ignore
  data.insert_axis(LEGACY_AXIS_RIGHTZ, Axis::RightZ) |> ignore
  data.insert_btn(buttons[0], Button::South) |> ignore
  data.insert_btn(buttons[1], Button::East) |> ignore
  data.insert_btn(buttons[3], Button::North) |> ignore
  data.insert_btn(buttons[4], Button::West) |> ignore
  data.insert_btn(buttons[5], Button::Select) |> ignore
  data.insert_btn(buttons[6], Button::Start) |> ignore
  data.insert_btn(buttons[7], Button::DPadDown) |> ignore
  data.insert_btn(buttons[8], Button::DPadLeft) |> ignore
  data.insert_btn(buttons[9], Button::RightThumb) |> ignore
  let ok_res : Result[(Mapping, String), Error] = try? Mapping::from_data(
    data, buttons, axes, name, uuid,
  )
  match ok_res {
    Ok((mappings, sdl)) => {
      let parsed : Result[Mapping, Error] = try? Mapping::parse_sdl_mapping(
        sdl, buttons, axes,
      )
      match parsed {
        Ok(m2) =>
          inspect(mapping_debug(mappings) == mapping_debug(m2), content="true")
        Err(_) => fail("roundtrip parse should not fail")
      }
    }
    Err(_) => fail("from_data should not fail")
  }
  let bad_name : Result[Unit, Error] = try? (Mapping::from_data(
    data, buttons, axes, "Inval,id name", uuid,
  )
  |> ignore)
  inspect(bad_name, content="Err(Milky2018/gamepad.MappingError.InvalidName)")
  data.insert_btn(BTN_DPAD_RIGHT, Button::DPadRight) |> ignore
  let invalid_code : Result[Unit, Error] = try? (Mapping::from_data(
    data, buttons, axes, name, uuid,
  )
  |> ignore)
  inspect(
    invalid_code,
    content="Err(Milky2018/gamepad.MappingError.InvalidCode)",
  )
  data.insert_btn(buttons[3], Button::Unknown) |> ignore
  let unknown_el : Result[Unit, Error] = try? (Mapping::from_data(
    data, buttons, axes, name, uuid,
  )
  |> ignore)
  inspect(
    unknown_el,
    content="Err(Milky2018/gamepad.MappingError.UnknownElement)",
  )
}

///|
test "mapping_db insert/get" {
  let mappings = "\nShould be ignored\nThis also should,be ignored\n\n" +
    TEST_STR
  let db = MappingDb::new()
  db.insert(mappings)
  let uuid = Uuid::parse("03000000260900008888000000010001")
  inspect(
    db.get(uuid),
    content=(
      #|Some("03000000260900008888000000010001,GameCube {WiseGroup USB box},a:b0,b:b2,y:b3,x:b1,start:b7,rightshoulder:b6,dpup:h0.1,dpleft:h0.8,dpdown:h0.4,dpright:h0.2,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:a4,righttrigger:a5,")
    ),
  )
}

///|
test "parse_sdl_mapping hat unknown direction" {
  let map_str = "03000000341a00003608000000010000,Test,platform:Linux,dpup:h0.16,"
  let res : Result[Mapping, Error] = try? Mapping::parse_sdl_mapping(
    map_str, buttons, axes,
  )
  let res2 : Result[Unit, Error] = match res {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
  inspect(
    res2,
    content="Err(Milky2018/gamepad.ParseSdlMappingError.UnknownHatDirection)",
  )
}

///|
test "parse_sdl_mapping invalid guid maps to InvalidGuid" {
  let map_str = "not-a-guid,Test,platform:Linux,a:b0,"
  let res : Result[Mapping, Error] = try? Mapping::parse_sdl_mapping(
    map_str, buttons, axes,
  )
  let mut is_err = false
  match res {
    Ok(_) => is_err = false
    Err(_) => is_err = true
  }
  inspect(is_err, content="true")
}

///|
test "mapping_db insert respects platform tag" {
  let db = MappingDb::new()
  let platform = runtime_sdl_platform_name()
  let other = if platform == "Mac OS X" { "Linux" } else { "Mac OS X" }
  let uuid = "22222222222222222222222222222222"
  let non_match = uuid + ",Wrong,a:b0,platform:" + other + ","
  let yes_match = uuid + ",Right,a:b0,platform:" + platform + ","
  db.insert(non_match + "\n" + yes_match)
  inspect(db.get(Uuid::parse(uuid)) == Some(yes_match), content="true")
}

///|
test "mapping_db add_env_mappings reads SDL_GAMECONTROLLERCONFIG" {
  runtime_set_sdl_gamecontrollerconfig_for_test(
    "33333333333333333333333333333333,Env Mapping,a:b0,",
  )
  let db = MappingDb::new()
  db.add_env_mappings()
  inspect(
    db.get(Uuid::parse("33333333333333333333333333333333")) is Some(_),
    content="true",
  )
  runtime_clear_sdl_gamecontrollerconfig_for_test()
}

///|
test "mapping_db add_included_mappings loads bundled mapping" {
  let db = MappingDb::new()
  db.add_included_mappings()
  inspect(
    db.get(Uuid::parse("030000005e0400008e02000002010000")) is Some(_),
    content="true",
  )
  inspect(db.len() >= 200, content="true")
  inspect(
    db.get(Uuid::parse("03000000c82d00001930000000000000")) is Some(_),
    content="true",
  )
}
