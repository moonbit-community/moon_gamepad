# Milky2018/gamepad

`Milky2018/gamepad` is a MoonBit gamepad input library for native targets. It provides `gil`-style events, state tracking, SDL controller mappings, input filters, force-feedback APIs, and a mock backend for tests.

## Install

```bash
moon add Milky2018/gamepad
```

Use the native target for real device input:

```bash
moon test --target native
moon run --target native
```

## Platform Support

Best support today is on macOS. Linux and Windows are available on native targets as well.

- [x] macOS native backend (`IOHIDManager`)
- [x] Linux native backend (`evdev`)
- [x] Windows native backend (`XInput`)
- [ ] Non-native targets for real device input

## Features

- Native gamepad discovery and hotplug events
- `Gil` event polling and blocking waits
- Per-device state tracking through `Gamepad` and `GamepadState`
- SDL controller mapping database support, including bundled mappings
- Input filters: `jitter`, `deadzone`, `axis_dpad_to_button`, `Repeat`
- Force-feedback APIs with platform-specific backend support
- Mock backend for deterministic tests

## API Notes

- **Errors**: `Gil::new()` does not raise. `GilBuilder::build()` may raise `GilError`.
- **Event time**: `Event::time()` is a millisecond timestamp. On native backends this comes from the OS clock; on the mock backend it is whatever you set in `Event::at(...)`.
- **Mappings (gil naming)**: Rust `gil` re-exports `MappingData` as `Mapping`. In this MoonBit port, the user-editable type is `MappingData`; `Mapping` is the parsed SDL mapping used by `Gil`.
- **Filters**: Compose filters with `filter_ev`. If you write a custom filter, it must not turn `Some(event)` into `None`; to drop an event return `Some(event.drop())`.

## Force Feedback

- macOS: not supported (will report `is_ff_supported = false`).
- Linux/Windows: supported when the backend/device supports rumble.

## Quick Start

```mbt nocheck
///|
test "quick start" {
  let gil = Gil::new()

  while true {
    match gil.next_event() {
      None => break
      Some(ev) => ...
    }
  }
}
```

## Mock Example

```mbt check
///|
test "mock button press" {
  let gil = GilBuilder::new()
    .with_mock_gamepad_count(1)
    .with_default_filters(false)
    .build()

  let id = @gamepad.GamepadId(0)
  gil.insert_event(Event::at(id, ButtonPressed(South, BTN_SOUTH), 0L))

  assert_true(gil.next_event() is Some(_))
}
```

## Notes

- `Code` values are backend-specific raw input codes.
- On macOS, some raw HID axes such as `Rx` and `Ry` may need SDL mappings before they resolve to semantic `Axis` values.
- On macOS, `PowerInfo` currently reports `Unknown`.
- On non-native targets, the package builds with a stub backend and does not provide real device events.
- Force-feedback repeat mode is exposed as `FfRepeat`.

## License

Apache-2.0.
