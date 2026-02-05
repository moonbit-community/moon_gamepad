#pragma once

#include <stdint.h>

// Binary encoding for events (little-endian):
// u32 tag, u32 id, u32 code, u32 pad, f64 value, i64 time_ms (total 32 bytes)
typedef struct moon_gamepad_event_t {
  uint32_t tag;
  uint32_t id;
  uint32_t code;
  uint32_t pad;
  double value;
  int64_t time_ms;
} moon_gamepad_event_t;

enum {
  MOON_GAMEPAD_EV_CONNECTED = 0,
  MOON_GAMEPAD_EV_DISCONNECTED = 1,
  MOON_GAMEPAD_EV_BUTTON_PRESSED = 2,
  MOON_GAMEPAD_EV_BUTTON_RELEASED = 3,
  MOON_GAMEPAD_EV_AXIS_CHANGED = 4,
  MOON_GAMEPAD_EV_BUTTON_CHANGED = 5,
};

