# Windows Backend (Design)

Upstream gilrs supports both XInput and Windows Gaming Input (WGI).

## Option A: XInput (simplest)

- Poll `XInputGetState` for up to 4 controllers.
- Convert thumbsticks/triggers/buttons to `RawEvent` diffs.
- ID mapping: slot index (0..3) is stable enough; optionally reuse IDs when slots swap.

Pros:
- Easy to implement, no window requirement.
Cons:
- Only supports XInput devices.

## Option B: Windows Gaming Input (WGI)

- Use `Windows.Gaming.Input.Gamepad` APIs.
- Needs an active window for some environments (upstream notes).

Pros:
- Supports more devices.
Cons:
- More complex COM/WinRT binding; may require C++/WinRT glue.

## Force feedback

- XInput: `XInputSetState` for rumble (limited but widely supported).
- WGI: richer haptics APIs.

