# Milky2018/gamepad

`Milky2018/gamepad` is a MoonBit gamepad input library for native targets. It provides `gilrs`-style events, state tracking, SDL controller mappings, input filters, force-feedback APIs, and a mock backend for tests.

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
- `Gilrs` event polling and blocking waits
- Per-device state tracking through `Gamepad` and `GamepadState`
- SDL controller mapping database support, including bundled mappings
- Input filters: `jitter`, `deadzone`, `axis_dpad_to_button`, `Repeat`
- Force-feedback APIs with platform-specific backend support
- Mock backend for deterministic tests

## Quick Start

```moonbit nocheck
import Milky2018/gamepad

fn main {
  let gilrs = Gilrs::new()

  while true {
    match gilrs.next_event() {
      None => break
      Some(ev) => {
        println(ev)
      }
    }
  }
}
```

## Mock Example

```moonbit nocheck
import Milky2018/gamepad

test "mock button press" {
  let gilrs =
    GilrsBuilder::new()
    .with_mock_gamepad_count(1)
    .with_default_filters(false)
    .build()

  let id = GamepadId::new(0)
  gilrs.insert_event(
    Event::at(id, EventType::ButtonPressed(Button::South, BTN_SOUTH), 0L),
  )

  inspect(gilrs.next_event(), content="Some(...)")
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
