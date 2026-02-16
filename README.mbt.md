# Milky2018/gamepad

MoonBit port of core `gilrs` concepts (mappings, events, state, and filters), with a native-first focus.

## Status

- Core types: `Axis`, `Button`, `Event`, `EventType`, `GamepadState`
- SDL mapping parser + mapping utilities
- Filters: `jitter`, `deadzone`, `axis_dpad_to_button`, `Repeat`
- Mockable core: `Gilrs::new_mock`, `GilrsBuilder` (mock), `Gamepad` handle
- Blocking event wait: `Gilrs::next_event_blocking(timeout_ms)`

## Platform Support (Checklist)

This project is **macOS-first**. Linux/Windows are tracked as follow-ups and may have behavioral gaps.

- macOS (native / IOHIDManager)
  - [x] Enumeration + hotplug events
  - [x] Buttons + axes events
  - [x] Device identity (`name`, `uuid`, `vendor_id`, `product_id`)
  - [x] SDL mapping DB lookup on connect (full mapping)
  - [ ] Force feedback (upstream gilrs-core macOS reports unsupported)
  - [ ] Power info (currently always `Unknown`)
- Linux (native / evdev) *(planned to harden later)*
  - [x] Enumeration + hotplug events (best-effort)
  - [x] Basic rumble (`FF_RUMBLE`) when device can be opened read-write
  - [ ] Permissions/udev guidance + broader device coverage
- Windows (native / XInput) *(planned to harden later)*
  - [x] Basic input + rumble (via `XInputSetState` when available)
  - [ ] CI coverage and device identity parity

## Notes / Limitations (vs upstream `gilrs`)

- `Code` is backend-specific. On macOS it matches gilrs-core's HID `EvCode` encoding: `(usage_page << 16) | usage`.
- On macOS, some HID axes (e.g. GenericDesktop `Rx`/`Ry`) are intentionally left **unmapped** to `Axis` by default (matching gilrs-core's "unconfirmed" constants). Use the SDL mapping DB to get semantic axis/button names for these codes.
- `PowerInfo` is exposed but currently defaults to `Unknown` on native backends.

## Quickstart (native)

```moonbit nocheck
let gilrs = Gilrs::new()

while true {
  match gilrs.next_event() {
    None => break
    Some(ev) => println(ev)
  }
}
```

## Quickstart (mock)

```moonbit nocheck
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
