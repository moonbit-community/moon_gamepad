# macOS Backend (Design)

Upstream gilrs uses a platform core (`gilrs-core`) for device IO. For MoonBit/native, the most
practical macOS options are:

## Option A: GameController.framework (preferred for standardized layout)

Pros:
- Apple-provided standardized mapping (`GCExtendedGamepad`), good for modern controllers.
- Hotplug notifications via `GCControllerDidConnect/DidDisconnectNotification`.

Cons:
- Requires a runloop/message pump.
- Some older HID devices may not be exposed as `GCController`.

Implementation sketch:

1) Objective-C `.m` glue that:
   - registers connect/disconnect notifications,
   - assigns/reuses IDs using a stable key (e.g. `controller.vendorName` + `productCategory` +
     `controller.deviceHash`, best-effort),
   - installs `valueChangedHandler` on `GCExtendedGamepad`.
2) Enqueue minimal `RawEvent`s (axis/button + code/value + time).
3) `poll()` pumps the runloop with `CFRunLoopRunInMode(..., 0, true)`.

Mapping:
- Map `GCExtendedGamepad` elements to gilrs logical `Axis`/`Button` directly (most accurate),
  or to stable `code`s and use `Mapping` (more general).

## Option B: IOHIDManager (fallback for generic HID)

Pros:
- Sees more devices.
- Lower-level access (can support more controllers).

Cons:
- Requires HID usage mapping + per-device heuristics.
- More work to match upstream mappings behavior.

Implementation sketch:
- Use `IOHIDManagerSetDeviceMatchingMultiple` for joystick/gamepad usages.
- Register `IOHIDValueCallback` to receive input.
- Encode `(usagePage, usage, elementCookie)` as `code`.

## Force feedback

Upstream gilrs has no macOS force feedback support by default. Keep this as `not supported` for
the first iteration.

