# Wasm Backend (Optional, Design)

Upstream gilrs generates events on web by polling the Web Gamepad API when `next_event()` is
called.

For MoonBit, the recommended approach is:

- `js` target: bind to `navigator.getGamepads()` and diff per-gamepad state to produce `RawEvent`s.
- `wasm` + `wasm-bindgen` style targets: similarly bind via host JS glue.

Notes:
- The Web Gamepad API is *polling-based*; there are no native push events.
- Timestamps are browser-provided and may be coarse.
- Mapping should prefer the browser's standardized layout (`standard` mapping) when present; else
  fall back to SDL mappings.

