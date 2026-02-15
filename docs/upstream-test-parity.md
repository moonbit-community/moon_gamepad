# Upstream Gilrs Test Parity Matrix

Pinned upstream snapshot in this workspace:
- `gilrs-reference/gilrs`
- `gilrs-reference/gilrs-core`

Counted upstream unit tests (`#[test]`): **12**.

## 1:1 Mapping

| Upstream test | MoonBit equivalent | Status |
|---|---|---|
| `gilrs/src/utils.rs::t_clamp` | `utils_test.mbt::test "clamp"` | Covered |
| `gilrs/src/ff/mod.rs::envelope` | `ff_wbtest.mbt::test "envelope matches upstream checkpoints"` | Covered |
| `gilrs/src/ff/mod.rs::envelope_default` | `ff_wbtest.mbt::test "envelope default stays at unity"` | Covered |
| `gilrs/src/ff/mod.rs::replay` | `ff_wbtest.mbt::test "replay matches upstream checkpoints"` | Covered |
| `gilrs/src/gamepad.rs::axis_value_documented_case` | `axis_value_test.mbt::test "axis_value documented case"` | Covered |
| `gilrs/src/gamepad.rs::axis_value_overflow` | `axis_value_test.mbt::test "axis_value overflow behavior"` | Covered |
| `gilrs/src/gamepad.rs::btn_value_overflow` | `axis_value_test.mbt::test "btn_value overflow behavior"` | Covered |
| `gilrs/src/mapping/parser.rs::test_all_sdl_mappings_for_parse_errors` | `mapping_parser_wbtest.mbt::test "full SDL corpus parses without non-empty parser errors"` | Covered |
| `gilrs/src/mapping/mod.rs::mapping` | `mapping_test.mbt::test "parse_sdl_mapping"` | Covered |
| `gilrs/src/mapping/mod.rs::from_data` | `mapping_test.mbt::test "from_data roundtrip + errors"` | Covered |
| `gilrs/src/mapping/mod.rs::with_mappings` | `mapping_test.mbt::test "mapping_db insert/get"` | Covered |
| `gilrs-core/src/platform/linux/gamepad.rs::sdl_uuid` | `native_backend_wbtest.mbt::test "uuid from ids matches gilrs SDL layout sample"` | Covered |

## Notes

- The local upstream snapshot still misses the `SDL_GameControllerDB` submodule content.  
- This repository now vendors the SDL corpus as generated MoonBit test data in `mapping_parser_corpus_data_wbtest.mbt`, sourced from [`gabomdq/SDL_GameControllerDB`](https://github.com/gabomdq/SDL_GameControllerDB).
