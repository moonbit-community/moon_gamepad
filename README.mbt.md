# Milky2018/gamepad

MoonBit port of core `gilrs` concepts (mappings, events, state, and filters), with a native-first focus.

## Status

- Core types: `Axis`, `Button`, `Event`, `EventType`, `GamepadState`
- SDL mapping parser + mapping utilities
- Filters: `jitter`, `deadzone`, `axis_dpad_to_button`, `Repeat`
- Mockable core: `Gilrs::new_mock`, `GilrsBuilder` (mock), `Gamepad` handle

- Native backend (best-effort):
  - macOS: IOHIDManager (events + hotplug)
  - Linux: evdev `/dev/input/event*` (capability-based filtering + polling)
  - Windows: XInput (polling)

Limitations (compared to upstream `gilrs`):

- No force feedback implementation yet (API exists but is stubbed).
- No vendor/product/UUID/power-info discovery in the native backend yet.
- SDL mapping support is available (parser + utilities), but native events currently use a built-in logical layout.

## Quickstart (native)

```moonbit
let gilrs = Gilrs::new()

while true {
  match gilrs.next_event() {
    None => break
    Some(ev) => println(ev)
  }
}
```

## Quickstart (mock)

```moonbit
let gilrs =
  GilrsBuilder::new()
  .with_mock_gamepad_count(1)
  .with_default_filters(true)
  .build()

let id = GamepadId::new(0)
gilrs.insert_event(Event::at(id, EventType::ButtonPressed(Button::South, BTN_SOUTH), 0L))

match gilrs.next_event() {
  None => ()
  Some(ev) => println(ev.id().value())
}
```
