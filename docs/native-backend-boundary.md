# Native Backend Boundary (Design)

This package currently provides the *gilrs* high-level model (events/state/mappings/filters) and a
mock event source. Native backends are implemented as an internal event source that can:

1) enumerate gamepads,
2) produce raw input events,
3) optionally expose force feedback capabilities.

## Proposed API surface

Keep a small internal contract that is easy to implement in C (or platform APIs) and easy to bind
from MoonBit:

- `backend_init() -> BackendHandle`
- `backend_poll(handle) -> Unit` (non-blocking; pumps platform message loop if needed)
- `backend_next_event(handle) -> RawEvent?`
- `backend_gamepad_count(handle) -> Int`
- `backend_gamepad_info(handle, idx) -> (uuid/name/vendor/product/...)`

`RawEvent` should be minimal and platform-friendly:

- `Connected(id)`
- `Disconnected(id)`
- `Button(code, value)`
- `Axis(code, value)`

MoonBit then:

- maps `code` to `AxisOrBtn` using `Mapping`,
- turns it into `EventType`,
- runs default filters (`axis_dpad_to_button` → `jitter` → `deadzone`),
- updates `GamepadState` (when enabled).

## ID and hotplug semantics

Follow upstream `gilrs` behavior:

- IDs are reused after disconnect when the *same physical* device reconnects (best-effort).
- Otherwise allocate a new ID.

Practical implementation:

- use a stable device key when available (`GUID`, `IORegistryEntryID`, `udev` syspath, etc.),
- maintain `disconnected_devices: key -> old_id`,
- on connect: if key present, reuse; else allocate next.

## Threading

Prefer single-threaded `poll()` + `next_event()` with internal queue:

- macOS: callbacks enqueue, `poll()` pumps the runloop (`CFRunLoopRunInMode`).
- Linux: `poll()` reads from file descriptors (non-blocking) and enqueues events.
- Windows: `poll()` calls XInput/WGI APIs and enqueues state diffs.

## Testing strategy

Native backends are hard to test in CI without devices. Keep backend tests limited to:

- pure mapping/filter/state logic (MoonBit tests),
- a fake backend that feeds `RawEvent` vectors,
- platform glue sanity tests (compile/link) where possible.

