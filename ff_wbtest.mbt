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
test "effect play/stop without backend errors" {
  let g = Gilrs::new_mock(1)
  let e : Effect = {
    gilrs: g,
    gamepads: [GamepadId::new(0)],
    strong: 1.0,
    weak: 1.0,
    duration_ms: 100L,
    base_effects: [],
    repeat_mode: FfRepeat::Infinitely,
    distance_model: DistanceModel::None,
    position: (0.0, 0.0, 0.0),
    gain: 1.0,
  }
  let r1 : Result[Unit, FfError] = try? e.play()
  inspect(r1 is Err(_), content="true")
  let r2 : Result[Unit, FfError] = try? e.stop()
  inspect(r2 is Err(_), content="true")
}

///|
extern "C" fn backend_new_null_for_test() -> BackendOwner = "moon_gamepad_backend_new_null_for_test"

///|
fn native_backend_null_for_test() -> NativeBackend {
  { owner: backend_new_null_for_test() }
}

///|
fn new_ff_ready_mock(gamepad_count : Int) -> Gilrs {
  let g = Gilrs::new_mock(gamepad_count)
  for i in 0..<gamepad_count {
    g.gamepads_data[i].ff_supported = true
  }
  g
}

///|
fn new_ff_ready_with_null_backend(gamepad_count : Int) -> Gilrs {
  let data : Array[GamepadData] = []
  for _ in 0..<gamepad_count {
    let d = GamepadData::new()
    d.ff_supported = true
    data.push(d)
  }
  {
    counter: 0L,
    update_state: true,
    default_filters: true,
    axis_to_btn_pressed: 0.75,
    axis_to_btn_released: 0.65,
    events: [],
    events_head: 0,
    gamepads_data: data,
    mappings: MappingDb::new(),
    now_ms: 0L,
    backend: Some(native_backend_null_for_test()),
  }
}

///|
test "builder paths reach backend-not-supported branch" {
  let g = new_ff_ready_mock(2)
  let gp0 = match g.gamepad(GamepadId::new(0)) {
    None => return
    Some(gp) => gp
  }
  let er : Result[Effect, FfError] = try? EffectBuilder::new()
    .gamepads([GamepadId::new(1)])
    .add_gamepad(gp0)
    .duration(123L)
    .rumble(1.0, 0.25)
    .finish(g)
  inspect(
    match er {
      Err(FfError::NotSupported) => true
      _ => false
    },
    content="true",
  )
}

///|
test "finish succeeds with backend Some and play/stop fail path" {
  let g = new_ff_ready_with_null_backend(1)
  let er : Result[Effect, FfError] = try? EffectBuilder::new()
    .add_gamepad_id(GamepadId::new(0))
    .duration(-1L)
    .rumble(1.0, 0.0)
    .finish(g)
  inspect(er is Ok(_), content="true")
  let e = match er {
    Err(_) => return
    Ok(e) => e
  }
  let play_res : Result[Unit, FfError] = try? e.play()
  inspect(
    match play_res {
      Err(FfError::NotSupported) => true
      _ => false
    },
    content="true",
  )
  let stop_res : Result[Unit, FfError] = try? e.stop()
  inspect(
    match stop_res {
      Err(FfError::NotSupported) => true
      _ => false
    },
    content="true",
  )
}

///|
test "finish returns Disconnected for missing gamepad id" {
  let g = new_ff_ready_mock(0)
  let er : Result[Effect, FfError] = try? EffectBuilder::new()
    .add_gamepad_id(GamepadId::new(0))
    .finish(g)
  inspect(
    match er {
      Err(FfError::Disconnected(_)) => true
      _ => false
    },
    content="true",
  )
}

///|
test "finish returns Disconnected for not connected gamepad" {
  let g = new_ff_ready_mock(1)
  g.gamepads_data[0].connected = false
  let er : Result[Effect, FfError] = try? EffectBuilder::new()
    .add_gamepad_id(GamepadId::new(0))
    .finish(g)
  inspect(
    match er {
      Err(FfError::Disconnected(_)) => true
      _ => false
    },
    content="true",
  )
}

///|
test "finish returns FfNotSupported when gamepad has no ff capability" {
  let g = new_ff_ready_mock(1)
  g.gamepads_data[0].ff_supported = false
  let er : Result[Effect, FfError] = try? EffectBuilder::new()
    .add_gamepad_id(GamepadId::new(0))
    .finish(g)
  inspect(
    match er {
      Err(FfError::FfNotSupported(_)) => true
      _ => false
    },
    content="true",
  )
}

///|
test "duration conversion branches" {
  inspect(to_duration_int(-1L), content="0")
  inspect(to_duration_int(123L), content="123")
  inspect(to_duration_int(0x8FFF_FFFFL), content="2147483647")
}

///|
fn approx(a : Double, b : Double, eps : Double) -> Bool {
  Double::abs(a - b) <= eps
}

///|
test "envelope matches upstream checkpoints" {
  let env = {
    attack_length: 10,
    attack_level: 0.2,
    fade_length: 10,
    fade_level: 0.2,
  }
  let dur = 40
  inspect(approx(env.at(0, dur), 0.2, 0.000000001), content="true")
  inspect(approx(env.at(5, dur), 0.6, 0.000000001), content="true")
  inspect(approx(env.at(10, dur), 1.0, 0.000000001), content="true")
  inspect(approx(env.at(20, dur), 1.0, 0.000000001), content="true")
  inspect(approx(env.at(30, dur), 1.0, 0.000000001), content="true")
  inspect(approx(env.at(35, dur), 0.6, 0.000000001), content="true")
  inspect(approx(env.at(40, dur), 0.2, 0.000001), content="true")
}

///|
test "envelope default stays at unity" {
  let env = Envelope::default()
  let dur = 40
  inspect(approx(env.at(0, dur), 1.0, 0.000000001), content="true")
  inspect(approx(env.at(20, dur), 1.0, 0.000000001), content="true")
  inspect(approx(env.at(40, dur), 1.0, 0.000000001), content="true")
}

///|
test "replay matches upstream checkpoints" {
  let replay = { after: 10, play_for: 50, with_delay: 20 }
  inspect(approx(replay.at(0), 1.0, 0.000000001), content="true")
  inspect(approx(replay.at(9), 1.0, 0.000000001), content="true")
  inspect(approx(replay.at(10), 1.0, 0.000000001), content="true")
  inspect(approx(replay.at(30), 1.0, 0.000000001), content="true")
  inspect(approx(replay.at(59), 0.0, 0.000000001), content="true")
  inspect(approx(replay.at(60), 0.0, 0.000000001), content="true")
  inspect(approx(replay.at(70), 0.0, 0.000000001), content="true")
}

///|
test "set_listener_position returns Disconnected for disconnected gamepad" {
  let g = new_ff_ready_mock(1)
  g.gamepads_data[0].connected = false
  let gp = match g.gamepad(GamepadId::new(0)) {
    None => return
    Some(gp) => gp
  }
  let r : Result[Unit, FfError] = try? gp.set_listener_position((0.0, 0.0, 0.0))
  inspect(
    match r {
      Err(FfError::Disconnected(_)) => true
      _ => false
    },
    content="true",
  )
}

///|
test "set_listener_position returns FfNotSupported for unsupported gamepad" {
  let g = Gilrs::new_mock(1)
  let gp = match g.gamepad(GamepadId::new(0)) {
    None => return
    Some(gp) => gp
  }
  let r : Result[Unit, FfError] = try? gp.set_listener_position((0.0, 0.0, 0.0))
  inspect(
    match r {
      Err(FfError::FfNotSupported(_)) => true
      _ => false
    },
    content="true",
  )
}

///|
test "set_listener_position succeeds for connected ff-supported gamepad" {
  let g = new_ff_ready_mock(1)
  let gp = match g.gamepad(GamepadId::new(0)) {
    None => return
    Some(gp) => gp
  }
  let r : Result[Unit, FfError] = try? gp.set_listener_position((0.0, 0.0, 0.0))
  inspect(r is Ok(_), content="true")
}

///|
test "builder deduplicates gamepad ids across gamepads/add calls" {
  let g = new_ff_ready_with_null_backend(2)
  let gp0 = match g.gamepad(GamepadId::new(0)) {
    None => return
    Some(gp) => gp
  }
  let er : Result[Effect, FfError] = try? EffectBuilder::new()
    .gamepads([GamepadId::new(0), GamepadId::new(0), GamepadId::new(1)])
    .add_gamepad_id(GamepadId::new(1))
    .add_gamepad(gp0)
    .finish(g)
  let ids = match er {
    Err(_) => return
    Ok(e) => e.gamepads
  }
  inspect(ids.map(fn(id) { id.value() }), content="[0, 1]")
}

///|
test "effect set_gamepads validates and deduplicates target ids" {
  let g = new_ff_ready_with_null_backend(2)
  let built : Result[Effect, FfError] = try? EffectBuilder::new()
    .add_gamepad_id(GamepadId::new(0))
    .finish(g)
  let effect = match built {
    Err(_) => return
    Ok(e) => e
  }
  let set_ok : Result[Unit, FfError] = try? effect.set_gamepads(
    [GamepadId::new(1), GamepadId::new(1)],
    g,
  )
  inspect(set_ok is Ok(_), content="true")
  inspect(effect.gamepads.map(fn(id) { id.value() }), content="[1]")
}

///|
test "effect set_gamepads returns FfNotSupported for unsupported id" {
  let g = new_ff_ready_with_null_backend(2)
  g.gamepads_data[1].ff_supported = false
  let built : Result[Effect, FfError] = try? EffectBuilder::new()
    .add_gamepad_id(GamepadId::new(0))
    .finish(g)
  let effect = match built {
    Err(_) => return
    Ok(e) => e
  }
  let set_res : Result[Unit, FfError] = try? effect.set_gamepads(
    [GamepadId::new(1)],
    g,
  )
  inspect(
    match set_res {
      Err(FfError::FfNotSupported(_)) => true
      _ => false
    },
    content="true",
  )
}

///|
test "effect add_gamepad deduplicates and validates" {
  let g = new_ff_ready_with_null_backend(2)
  let built : Result[Effect, FfError] = try? EffectBuilder::new()
    .add_gamepad_id(GamepadId::new(0))
    .finish(g)
  let effect = match built {
    Err(_) => return
    Ok(e) => e
  }
  let gp0 = match g.gamepad(GamepadId::new(0)) {
    None => return
    Some(gp) => gp
  }
  let gp1 = match g.gamepad(GamepadId::new(1)) {
    None => return
    Some(gp) => gp
  }
  inspect((try? effect.add_gamepad(gp0)) is Ok(_), content="true")
  inspect((try? effect.add_gamepad(gp1)) is Ok(_), content="true")
  inspect(effect.gamepads.map(fn(id) { id.value() }), content="[0, 1]")
}

///|
test "effect add_gamepad returns Disconnected when handle is disconnected" {
  let g = new_ff_ready_with_null_backend(1)
  let built : Result[Effect, FfError] = try? EffectBuilder::new()
    .add_gamepad_id(GamepadId::new(0))
    .finish(g)
  let effect = match built {
    Err(_) => return
    Ok(e) => e
  }
  g.gamepads_data[0].connected = false
  let gp = match g.gamepad(GamepadId::new(0)) {
    None => return
    Some(gp) => gp
  }
  let add_res : Result[Unit, FfError] = try? effect.add_gamepad(gp)
  inspect(
    match add_res {
      Err(FfError::Disconnected(_)) => true
      _ => false
    },
    content="true",
  )
}

///|
test "set_gain clamps lower bound and updates effect gain" {
  let g = new_ff_ready_with_null_backend(1)
  let built : Result[Effect, FfError] = try? EffectBuilder::new()
    .add_gamepad_id(GamepadId::new(0))
    .finish(g)
  let effect = match built {
    Err(_) => return
    Ok(e) => e
  }
  effect.set_gain(-1.0)
  inspect(effect.gain, content="0")
  effect.set_gain(1.5)
  inspect(effect.gain, content="1.5")
}

///|
test "distance_model validate follows upstream guard branches" {
  inspect((try? DistanceModel::None.validate()) is Ok(_), content="true")
  let bad_inv : Result[Unit, DistanceModelError] = try? DistanceModel::Inverse(
    ref_distance=0.0,
    rolloff_factor=1.0,
  ).validate()
  inspect(
    match bad_inv {
      Err(DistanceModelError::InvalidModelParameter) => true
      _ => false
    },
    content="true",
  )
  let bad_lin : Result[Unit, DistanceModelError] = try? DistanceModel::Linear(
    ref_distance=1.0,
    rolloff_factor=1.0,
    max_distance=1.0,
  ).validate()
  inspect(
    match bad_lin {
      Err(DistanceModelError::InvalidModelParameter) => true
      _ => false
    },
    content="true",
  )
}

///|
test "builder advanced setters persist into effect" {
  let g = new_ff_ready_with_null_backend(1)
  let base = {
    kind: BaseEffectType::Strong(60_000),
    scheduling: Replay::default(),
    envelope: Envelope::default(),
  }
  let built : Result[Effect, FfError] = try? EffectBuilder::new()
    .add_gamepad_id(GamepadId::new(0))
    .add_effect(base)
    .repeat(FfRepeat::For(10L))
    .distance_model(
      DistanceModel::Linear(
        ref_distance=1.0,
        rolloff_factor=1.0,
        max_distance=2.0,
      ),
    )
    .position((1.0, 2.0, 3.0))
    .gain(-1.0)
    .finish(g)
  let effect = match built {
    Err(_) => return
    Ok(e) => e
  }
  inspect(effect.base_effects.length(), content="1")
  inspect(effect.gain, content="0")
  inspect(
    match effect.repeat_mode {
      FfRepeat::For(ms) => ms == 10L
      _ => false
    },
    content="true",
  )
  inspect(effect.position, content="(1, 2, 3)")
}

///|
test "builder finish returns InvalidDistanceModel on invalid model" {
  let g = new_ff_ready_with_null_backend(1)
  let built : Result[Effect, FfError] = try? EffectBuilder::new()
    .add_gamepad_id(GamepadId::new(0))
    .distance_model(
      DistanceModel::Linear(
        ref_distance=1.0,
        rolloff_factor=1.0,
        max_distance=1.0,
      ),
    )
    .finish(g)
  inspect(
    match built {
      Err(FfError::InvalidDistanceModel(_)) => true
      _ => false
    },
    content="true",
  )
}

///|
test "effect set_repeat/set_position/set_distance_model update state" {
  let g = new_ff_ready_with_null_backend(1)
  let built : Result[Effect, FfError] = try? EffectBuilder::new()
    .add_gamepad_id(GamepadId::new(0))
    .finish(g)
  let effect = match built {
    Err(_) => return
    Ok(e) => e
  }
  effect.set_repeat(FfRepeat::For(7L))
  effect.set_position((4.0, 5.0, 6.0))
  inspect(
    match effect.repeat_mode {
      FfRepeat::For(ms) => ms == 7L
      _ => false
    },
    content="true",
  )
  inspect(effect.position, content="(4, 5, 6)")
  let ok : Result[Unit, FfError] = try? effect.set_distance_model(
    DistanceModel::Linear(
      ref_distance=1.0,
      rolloff_factor=1.0,
      max_distance=3.0,
    ),
  )
  inspect(ok is Ok(_), content="true")
  let bad : Result[Unit, FfError] = try? effect.set_distance_model(
    DistanceModel::Linear(
      ref_distance=1.0,
      rolloff_factor=1.0,
      max_distance=1.0,
    ),
  )
  inspect(
    match bad {
      Err(FfError::InvalidDistanceModel(_)) => true
      _ => false
    },
    content="true",
  )
}
