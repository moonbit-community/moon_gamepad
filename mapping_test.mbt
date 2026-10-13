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
let buttons : Array[@gamepad.Code] = [
  @gamepad.BTN_SOUTH,
  @gamepad.BTN_EAST,
  @gamepad.BTN_C,
  @gamepad.BTN_NORTH,
  @gamepad.BTN_WEST,
  @gamepad.BTN_Z,
  @gamepad.BTN_LT,
  @gamepad.BTN_RT,
  @gamepad.BTN_LT2,
  @gamepad.BTN_RT2,
  @gamepad.BTN_SELECT,
  @gamepad.BTN_START,
  @gamepad.BTN_MODE,
  @gamepad.BTN_LTHUMB,
  @gamepad.BTN_RTHUMB,
]

///|
let axes : Array[@gamepad.Code] = [
  @gamepad.AXIS_LSTICKX,
  @gamepad.AXIS_LSTICKY,
  @gamepad.AXIS_RSTICKX,
  @gamepad.AXIS_RSTICKY,
  @gamepad.AXIS_LT2,
  @gamepad.AXIS_RT2,
  @gamepad.LEGACY_AXIS_LEFTZ,
  @gamepad.LEGACY_AXIS_RIGHTZ,
]

///|
fn mapping_debug(m : @gamepad.Mapping) -> String {
  fn axis_name(ax : @gamepad.Axis) -> String {
    match ax {
      LeftStickX => "LeftStickX"
      LeftStickY => "LeftStickY"
      LeftZ => "LeftZ"
      RightStickX => "RightStickX"
      RightStickY => "RightStickY"
      RightZ => "RightZ"
      DPadX => "DPadX"
      DPadY => "DPadY"
      Unknown => "Unknown"
    }
  }

  fn button_name(btn : @gamepad.Button) -> String {
    match btn {
      South => "South"
      East => "East"
      C => "C"
      North => "North"
      West => "West"
      Z => "Z"
      LeftTrigger => "LeftTrigger"
      RightTrigger => "RightTrigger"
      LeftTrigger2 => "LeftTrigger2"
      RightTrigger2 => "RightTrigger2"
      Select => "Select"
      Start => "Start"
      Mode => "Mode"
      LeftThumb => "LeftThumb"
      RightThumb => "RightThumb"
      DPadUp => "DPadUp"
      DPadDown => "DPadDown"
      DPadLeft => "DPadLeft"
      DPadRight => "DPadRight"
      Unknown => "Unknown"
    }
  }

  fn el_name(el : @gamepad.AxisOrBtn) -> String {
    match el {
      Axis(ax) => "Axis:" + axis_name(ax)
      Btn(btn) => "Btn:" + button_name(btn)
    }
  }

  let entries = m
    .entries()
    .map(fn(pair : (@gamepad.Code, @gamepad.AxisOrBtn)) -> String {
      let (code, el) = pair
      "\{code}->\{el_name(el)}"
    })
  "name=\{m.name()};hats=\{m.hats_mapped()};" + entries.join(";")
}

///|
test "parse_sdl_mapping" {
  let res : Result[@gamepad.Mapping, Error] = try
    @gamepad.Mapping::parse_sdl_mapping(TEST_STR, buttons, axes) |> Ok
  catch {
    e => Err(e)
  }
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
  let uuid = @gamepad.Uuid::nil().simple()
  let line = uuid + ",Test,a:b2,"
  // Include an extra unmapped button usage (usage=3) at index 2.
  let buttons2 : Array[@gamepad.Code] = [
    @gamepad.hid_code(@gamepad.PAGE_BUTTON, 1),
    @gamepad.hid_code(@gamepad.PAGE_BUTTON, 2),
    @gamepad.hid_code(@gamepad.PAGE_BUTTON, 3),
  ]
  let res : Result[@gamepad.Mapping, Error] = try
    @gamepad.Mapping::parse_sdl_mapping(line, buttons2, []) |> Ok
  catch {
    e => Err(e)
  }
  match res {
    Ok(m) => {
      let code = @gamepad.hid_code(@gamepad.PAGE_BUTTON, 3)
      let ok = match m.map(code) {
        Some(Btn(South)) => true
        _ => false
      }
      inspect(ok, content="true")
    }
    Err(_) => fail("parse_sdl_mapping should not fail")
  }
}

///|
test "from_data roundtrip + errors" {
  let uuid = @gamepad.Uuid::nil()
  let name = "Best Gamepad"
  let data = @gamepad.MappingData::new()
  data.insert_axis(@gamepad.AXIS_LSTICKX, LeftStickX) |> ignore
  data.insert_axis(@gamepad.AXIS_LSTICKY, LeftStickY) |> ignore
  data.insert_axis(@gamepad.LEGACY_AXIS_LEFTZ, LeftZ) |> ignore
  data.insert_axis(@gamepad.AXIS_RSTICKX, RightStickX) |> ignore
  data.insert_axis(@gamepad.AXIS_RSTICKY, RightStickY) |> ignore
  data.insert_axis(@gamepad.LEGACY_AXIS_RIGHTZ, RightZ) |> ignore
  data.insert_btn(buttons[0], South) |> ignore
  data.insert_btn(buttons[1], East) |> ignore
  data.insert_btn(buttons[3], North) |> ignore
  data.insert_btn(buttons[4], West) |> ignore
  data.insert_btn(buttons[5], Select) |> ignore
  data.insert_btn(buttons[6], Start) |> ignore
  data.insert_btn(buttons[7], DPadDown) |> ignore
  data.insert_btn(buttons[8], DPadLeft) |> ignore
  data.insert_btn(buttons[9], RightThumb) |> ignore
  data.insert_btn(buttons[2], C) |> ignore
  data.insert_btn(buttons[10], Z) |> ignore
  let ok_res : Result[(@gamepad.Mapping, String), Error] = try
    @gamepad.Mapping::from_data(data, buttons, axes, name, uuid) |> Ok
  catch {
    e => Err(e)
  }
  match ok_res {
    Ok((mappings, sdl)) => {
      let parsed : Result[@gamepad.Mapping, Error] = try
        @gamepad.Mapping::parse_sdl_mapping(sdl, buttons, axes) |> Ok
      catch {
        e => Err(e)
      }
      match parsed {
        Ok(m2) =>
          inspect(mapping_debug(mappings) == mapping_debug(m2), content="true")
        Err(_) => fail("roundtrip parse should not fail")
      }
    }
    Err(_) => fail("from_data should not fail")
  }
  let bad_name : Result[Unit, Error] = try
    @gamepad.Mapping::from_data(data, buttons, axes, "Inval,id name", uuid)
    |> ignore
    |> Ok
  catch {
    e => Err(e)
  }
  debug_inspect(
    bad_name,
    content="Err(<Milky2018/gamepad.MappingError.InvalidName: ...>)",
  )
  data.insert_btn(@gamepad.BTN_DPAD_RIGHT, DPadRight) |> ignore
  let invalid_code : Result[Unit, @gamepad.MappingError] = try
    @gamepad.Mapping::from_data(data, buttons, axes, name, uuid) |> ignore |> Ok
  catch {
    e => Err(e)
  }
  let invalid_code_payload = match invalid_code {
    Ok(_) => None
    Err(e) => e.invalid_code()
  }
  inspect(invalid_code_payload == Some(@gamepad.BTN_DPAD_RIGHT), content="true")
  data.insert_btn(buttons[3], Unknown) |> ignore
  let unknown_el : Result[Unit, Error] = try
    @gamepad.Mapping::from_data(data, buttons, axes, name, uuid) |> ignore |> Ok
  catch {
    e => Err(e)
  }
  debug_inspect(
    unknown_el,
    content="Err(<Milky2018/gamepad.MappingError.UnknownElement: ...>)",
  )
}

///|
test "mapping_db insert/get" {
  let mappings = "\nShould be ignored\nThis also should,be ignored\n\n" +
    TEST_STR
  let db = @gamepad.MappingDb::new()
  db.insert(mappings)
  let uuid = @gamepad.Uuid::parse("03000000260900008888000000010001")
  debug_inspect(
    db.get(uuid),
    content=(
      #|Some("03000000260900008888000000010001,GameCube {WiseGroup USB box},a:b0,b:b2,y:b3,x:b1,start:b7,rightshoulder:b6,dpup:h0.1,dpleft:h0.8,dpdown:h0.4,dpright:h0.2,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:a4,righttrigger:a5,")
    ),
  )
}

///|
test "mapping_db insert works after preloading included mappings" {
  let db = @gamepad.MappingDb::new()
  db.add_included_mappings()
  let platform = @gamepad.runtime_sdl_platform_name()
  let mapping = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,AfterInclude,a:b0,platform:" +
    platform +
    ","
  db.insert(mapping)
  inspect(
    db.get(@gamepad.Uuid::parse("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")) ==
    Some(mapping),
    content="true",
  )
}

///|
test "mapping_db insert accepts CRLF-separated mappings" {
  let db = @gamepad.MappingDb::new()
  let platform = @gamepad.runtime_sdl_platform_name()
  let line = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,CRLF Pad,a:b0,platform:" +
    platform +
    ","
  db.insert(line + "\r\n")
  inspect(
    db.get(@gamepad.Uuid::parse("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")) ==
    Some(line),
    content="true",
  )
}

///|
test "mapping_db insert accepts UUID-only line" {
  let db = @gamepad.MappingDb::new()
  let line = "cccccccccccccccccccccccccccccccc"
  db.insert(line)
  inspect(db.get(@gamepad.Uuid::parse(line)) == Some(line), content="true")
}

///|
test "parse_sdl_mapping hat unknown direction" {
  let map_str = "03000000341a00003608000000010000,Test,platform:Linux,dpup:h0.16,"
  let res : Result[@gamepad.Mapping, Error] = try
    @gamepad.Mapping::parse_sdl_mapping(map_str, buttons, axes) |> Ok
  catch {
    e => Err(e)
  }
  let res2 : Result[Unit, Error] = match res {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
  debug_inspect(
    res2,
    content="Err(<Milky2018/gamepad.ParseSdlMappingError.UnknownHatDirection: ...>)",
  )
}

///|
test "parse_sdl_mapping rejects out-of-range u16 numbers" {
  let map_str = "03000000341a00003608000000010000,Test,platform:Linux,a:h70000.1,"
  let res : Result[@gamepad.Mapping, Error] = try
    @gamepad.Mapping::parse_sdl_mapping(map_str, buttons, axes) |> Ok
  catch {
    e => Err(e)
  }
  inspect(res is Err(_), content="true")
}

///|
test "parse_sdl_mapping accepts xinput pseudo-guid" {
  let map_str = "xinput,Test,a:b0,"
  let res : Result[@gamepad.Mapping, Error] = try
    @gamepad.Mapping::parse_sdl_mapping(map_str, buttons, axes) |> Ok
  catch {
    e => Err(e)
  }
  inspect(res is Ok(_), content="true")
}

///|
test "parse_sdl_mapping invalid guid maps to InvalidGuid" {
  let map_str = "not-a-guid,Test,platform:Linux,a:b0,"
  let res : Result[@gamepad.Mapping, Error] = try
    @gamepad.Mapping::parse_sdl_mapping(map_str, buttons, axes) |> Ok
  catch {
    e => Err(e)
  }
  let mut is_err = false
  match res {
    Ok(_) => is_err = false
    Err(_) => is_err = true
  }
  inspect(is_err, content="true")
}

///|
test "mapping_db insert respects platform tag" {
  let db = @gamepad.MappingDb::new()
  let platform = @gamepad.runtime_sdl_platform_name()
  let other = if platform == "Mac OS X" { "Linux" } else { "Mac OS X" }
  let uuid = "22222222222222222222222222222222"
  let non_match = uuid + ",Wrong,a:b0,platform:" + other + ","
  let yes_match = uuid + ",Right,a:b0,platform:" + platform + ","
  db.insert(non_match + "\n" + yes_match)
  inspect(db.get(@gamepad.Uuid::parse(uuid)) == Some(yes_match), content="true")
}

///|
test "mapping_db add_env_mappings reads SDL_GAMECONTROLLERCONFIG" {
  runtime_set_sdl_gamecontrollerconfig_for_test(
    "33333333333333333333333333333333,Env Mapping,a:b0,",
  )
  let db = @gamepad.MappingDb::new()
  db.add_env_mappings()
  inspect(
    db.get(@gamepad.Uuid::parse("33333333333333333333333333333333")) is Some(_),
    content="true",
  )
  runtime_clear_sdl_gamecontrollerconfig_for_test()
}

///|
test "mapping_db add_included_mappings loads bundled mapping" {
  let db = @gamepad.MappingDb::new()
  db.add_included_mappings()
  let platform = @gamepad.runtime_sdl_platform_name()
  if platform == "Mac OS X" {
    inspect(db.len() >= 200, content="true")
    inspect(
      db.get(@gamepad.Uuid::parse("03000000c82d00001930000000000000"))
      is Some(_),
      content="true",
    )
  } else if platform == "Linux" {
    inspect(db.len() >= 500, content="true")
    inspect(
      db.get(@gamepad.Uuid::parse("03000000c82d00001930000011010000"))
      is Some(_),
      content="true",
    )
  } else if platform == "Windows" {
    inspect(db.len() >= 500, content="true")
    inspect(
      db.get(@gamepad.Uuid::parse("03000000300f00000a01000000000000"))
      is Some(_),
      content="true",
    )
  } else {
    inspect(
      db.get(@gamepad.Uuid::parse("030000005e0400008e02000002010000"))
      is Some(_),
      content="true",
    )
  }
}
