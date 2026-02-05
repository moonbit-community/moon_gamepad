# Linux Backend (Design, evdev)

Upstream gilrs (evdev) reads `/dev/input/event*` and uses udev for enumeration.

## Enumeration

- Use `libudev` to enumerate input devices with `ID_INPUT_JOYSTICK=1` (or similar heuristics).
- Track stable syspath for reconnect (`/sys/...`) and reuse IDs.

## IO

- Open each device's `event*` node O_NONBLOCK.
- Read `struct input_event` and translate:
  - `EV_KEY` → button (value 0/1)
  - `EV_ABS` → axis (normalize using `input_absinfo` min/max/flat)

## Mapping

- Encode `code` as native evdev key/abs code.
- Populate `Mapping` using SDL mappings database when available; fallback to Linux Gamepad API
  layout when the device follows it.

## Force feedback

- Use `EV_FF` ioctls and write effect structs to the device.
- Implement as a separate layer; keep core `RawEvent` path independent.

