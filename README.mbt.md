# username/gamepad

MoonBit port of core `gilrs` concepts (mappings, events, state, and filters), with a native-first roadmap.

MoonBit port of core `gilrs` concepts (mappings, events, state, and filters), with a native-first roadmap.

## Status

- Core types: `Axis`, `Button`, `Event`, `EventType`, `GamepadState`
- SDL mapping parser + mapping utilities
- Filters: `jitter`, `deadzone`, `axis_dpad_to_button`, `Repeat`
- Mockable core: `Gilrs::new_mock`, `GilrsBuilder` (mock), `Gamepad` handle

Native backends and force feedback are tracked in `bd` tasks and are not complete yet.

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
