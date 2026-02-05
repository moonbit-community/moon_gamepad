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
  AXIS_LEFTZ,
  AXIS_RSTICKX,
  AXIS_RSTICKY,
  AXIS_RIGHTZ,
  AXIS_DPADX,
  AXIS_DPADY,
  AXIS_RT,
  AXIS_LT,
  AXIS_RT2,
  AXIS_LT2,
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
        content="name=GameCube {WiseGroup USB box};hats=15;0->Btn:South;2->Btn:East;3->Btn:North;1->Btn:West;7->Btn:Start;6->Btn:RightTrigger;107->Axis:DPadY;15->Btn:DPadUp;106->Axis:DPadX;17->Btn:DPadLeft;16->Btn:DPadDown;18->Btn:DPadRight;100->Axis:LeftStickX;101->Axis:LeftStickY;102->Axis:RightStickX;103->Axis:RightStickY;104->Btn:LeftTrigger2;105->Btn:RightTrigger2",
      )
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
  data.insert_axis(AXIS_LEFTZ, Axis::LeftZ) |> ignore
  data.insert_axis(AXIS_RSTICKX, Axis::RightStickX) |> ignore
  data.insert_axis(AXIS_RSTICKY, Axis::RightStickY) |> ignore
  data.insert_axis(AXIS_RIGHTZ, Axis::RightZ) |> ignore
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
