## Upstream Parity Matrix (`gilrs` / `gilrs-core`)

Pinned reference: `/Users/zhengyu/Documents/projects/gamepad/gilrs-reference`

### 1) Upstream Rust tests and MoonBit mapping

- [x] `gilrs/src/utils.rs::t_clamp` -> `utils_test.mbt` (`test "clamp"`)
- [x] `gilrs/src/ff/mod.rs::envelope` -> `ff_wbtest.mbt` (`test "envelope matches upstream checkpoints"`)
- [x] `gilrs/src/ff/mod.rs::envelope_default` -> `ff_wbtest.mbt` (`test "envelope default stays at unity"`)
- [x] `gilrs/src/ff/mod.rs::replay` -> `ff_wbtest.mbt` (`test "replay matches upstream checkpoints"`)
- [x] `gilrs-core/src/platform/linux/gamepad.rs::sdl_uuid` -> `native_backend_wbtest.mbt` (`test "uuid from ids matches gilrs SDL layout sample"`)
- [x] `gilrs/src/gamepad.rs::axis_value_documented_case` -> `axis_value_test.mbt`
- [x] `gilrs/src/gamepad.rs::axis_value_overflow` -> `axis_value_test.mbt`
- [x] `gilrs/src/gamepad.rs::btn_value_overflow` -> `axis_value_test.mbt`
- [x] `gilrs/src/mapping/parser.rs::test_all_sdl_mappings_for_parse_errors` -> `mapping_parser_wbtest.mbt`
- [x] `gilrs/src/mapping/mod.rs::mapping` -> `mapping_test.mbt` (`test "parse_sdl_mapping"`)
- [x] `gilrs/src/mapping/mod.rs::from_data` -> `mapping_test.mbt` (`test "from_data roundtrip + errors"`)
- [x] `gilrs/src/mapping/mod.rs::with_mappings` -> `mapping_test.mbt` (`mapping db/env/included coverage`)

### 2) Remaining API parity gaps (full migration scope)

- [x] `Gamepad::set_listener_position(...)` behavior from `gilrs/src/gamepad.rs`
- [x] `EffectBuilder` gamepad-id dedupe semantics (`gamepads` / `add_gamepad` / `add_gamepad_id`)
- [x] `ff::BaseEffectType`
- [x] `ff::BaseEffect`
- [x] `ff::Ticks`
- [x] `ff::Repeat` (implemented as `FfRepeat` to avoid collision with event-filter `Repeat`)
- [x] `ff::DistanceModel`
- [x] `ff::DistanceModelError`
- [x] `Effect::set_gamepads(...)`
- [x] `Effect::add_gamepad(...)`
- [x] `Effect::set_repeat(...)`
- [x] `Effect::set_distance_model(...)`
- [x] `Effect::set_position(...)`
- [x] `Effect::set_gain(...)`
- [x] `EffectBuilder::add_effect(...)`
- [x] `EffectBuilder::repeat(...)`
- [x] `EffectBuilder::distance_model(...)`
- [x] `EffectBuilder::position(...)`
- [x] `EffectBuilder::gain(...)`
