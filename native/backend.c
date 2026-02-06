#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

#include "backend.h"

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

static void bytes_to_hex32(const uint8_t in16[16], char out33[33]) {
  static const char HEX[16] = "0123456789abcdef";
  for (int i = 0; i < 16; i++) {
    uint8_t v = in16[i];
    out33[i * 2 + 0] = HEX[(v >> 4) & 0xF];
    out33[i * 2 + 1] = HEX[v & 0xF];
  }
  out33[32] = '\0';
}

static void uuid_simple_from_ids(uint16_t bustype, uint16_t vendor, uint16_t product, uint16_t version,
                                 char out33[33]) {
  uint8_t b[16];
  memset(b, 0, sizeof(b));
  b[0] = (uint8_t)(bustype & 0xFF);
  b[1] = (uint8_t)((bustype >> 8) & 0xFF);
  b[2] = (uint8_t)(vendor & 0xFF);
  b[3] = (uint8_t)((vendor >> 8) & 0xFF);
  b[4] = (uint8_t)(product & 0xFF);
  b[5] = (uint8_t)((product >> 8) & 0xFF);
  b[6] = (uint8_t)(version & 0xFF);
  b[7] = (uint8_t)((version >> 8) & 0xFF);
  bytes_to_hex32(b, out33);
}

// Match gilrs-core macOS UUID layout:
// bytes = [bustype(u32 le=0x03), vendor(u16 le), 0,0, product(u16 le), 0,0, version(u16 le), 0,0]
static void uuid_simple_macos(uint16_t vendor, uint16_t product, uint16_t version, char out33[33]) {
  uint8_t b[16];
  memset(b, 0, sizeof(b));
  if (vendor == 0 && product == 0 && version == 0) {
    bytes_to_hex32(b, out33);
    return;
  }
  b[0] = 0x03; // bustype (USB), little-endian u32
  b[4] = (uint8_t)(vendor & 0xFF);
  b[5] = (uint8_t)((vendor >> 8) & 0xFF);
  b[8] = (uint8_t)(product & 0xFF);
  b[9] = (uint8_t)((product >> 8) & 0xFF);
  b[12] = (uint8_t)(version & 0xFF);
  b[13] = (uint8_t)((version >> 8) & 0xFF);
  bytes_to_hex32(b, out33);
}

static moonbit_string_t moonbit_string_from_utf8_lossy(const char *s) {
  if (s == NULL) {
    return moonbit_make_string_raw(0);
  }
  size_t n = strlen(s);
  moonbit_string_t out = moonbit_make_string_raw((int32_t)n);
  if (out == NULL) {
    return moonbit_make_string_raw(0);
  }
  // Best-effort: treat bytes as ASCII and replace non-ASCII with '?'.
  for (size_t i = 0; i < n; i++) {
    unsigned char c = (unsigned char)s[i];
    out[i] = (c < 0x80) ? (uint16_t)c : (uint16_t)'?';
  }
  return out;
}

#if defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>
#include <errno.h>
#include <IOKit/hid/IOHIDLib.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/IOKitLib.h>
#include <pthread.h>
#include <time.h>
#endif

#if defined(__linux__)
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#endif

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <stdio.h>
#include <windows.h>
#endif

// -----------------------------------------------------------------------------
// Shared queue
// -----------------------------------------------------------------------------

typedef struct moon_gamepad_queue_t {
  moon_gamepad_event_t *buf;
  uint32_t cap;
  uint32_t head;
  uint32_t tail;
  uint32_t len;
#if defined(__APPLE__)
  pthread_mutex_t mu;
  pthread_cond_t cv;
#endif
} moon_gamepad_queue_t;

static void queue_init(moon_gamepad_queue_t *q, uint32_t cap) {
  q->buf = (moon_gamepad_event_t *)calloc((size_t)cap, sizeof(moon_gamepad_event_t));
  q->cap = cap;
  q->head = 0;
  q->tail = 0;
  q->len = 0;
#if defined(__APPLE__)
  pthread_mutex_init(&q->mu, NULL);
  pthread_cond_init(&q->cv, NULL);
#endif
}

static void queue_free(moon_gamepad_queue_t *q) {
  if (q->buf != NULL) {
    free(q->buf);
    q->buf = NULL;
  }
#if defined(__APPLE__)
  pthread_cond_destroy(&q->cv);
  pthread_mutex_destroy(&q->mu);
#endif
  q->cap = 0;
  q->head = q->tail = q->len = 0;
}

static uint32_t queue_len(moon_gamepad_queue_t *q) {
  if (q == NULL) {
    return 0;
  }
#if defined(__APPLE__)
  pthread_mutex_lock(&q->mu);
  uint32_t out = q->len;
  pthread_mutex_unlock(&q->mu);
  return out;
#else
  return q->len;
#endif
}

static int64_t now_ms(void) {
#if defined(__APPLE__)
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);
#elif defined(__linux__)
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);
#elif defined(_WIN32)
  FILETIME ft;
  GetSystemTimeAsFileTime(&ft);
  ULARGE_INTEGER uli;
  uli.LowPart = ft.dwLowDateTime;
  uli.HighPart = ft.dwHighDateTime;
  // 100ns since 1601 -> ms since 1601
  uint64_t ms1601 = uli.QuadPart / 10000ULL;
  // Unix epoch offset in ms.
  const uint64_t EPOCH_DIFF_MS = 11644473600000ULL;
  if (ms1601 < EPOCH_DIFF_MS) {
    return 0;
  }
  return (int64_t)(ms1601 - EPOCH_DIFF_MS);
#else
  return 0;
#endif
}

static void queue_push(moon_gamepad_queue_t *q, moon_gamepad_event_t ev) {
  if (q->buf == NULL || q->cap == 0) {
    return;
  }
#if defined(__APPLE__)
  pthread_mutex_lock(&q->mu);
#endif
  if (q->len == q->cap) {
    // Drop oldest.
    q->head = (q->head + 1) % q->cap;
    q->len--;
  }
  q->buf[q->tail] = ev;
  q->tail = (q->tail + 1) % q->cap;
  q->len++;
#if defined(__APPLE__)
  pthread_cond_signal(&q->cv);
  pthread_mutex_unlock(&q->mu);
#endif
}

static int queue_pop(moon_gamepad_queue_t *q, moon_gamepad_event_t *out) {
  if (q->buf == NULL || q->cap == 0 || out == NULL) {
    return 0;
  }
#if defined(__APPLE__)
  pthread_mutex_lock(&q->mu);
#endif
  if (q->len == 0) {
#if defined(__APPLE__)
    pthread_mutex_unlock(&q->mu);
#endif
    return 0;
  }
  *out = q->buf[q->head];
  q->head = (q->head + 1) % q->cap;
  q->len--;
#if defined(__APPLE__)
  pthread_mutex_unlock(&q->mu);
#endif
  return 1;
}

#if defined(__APPLE__)
static void queue_wait_nonempty(moon_gamepad_queue_t *q, int32_t timeout_ms) {
  if (q == NULL) {
    return;
  }
  pthread_mutex_lock(&q->mu);
  if (q->len != 0 || timeout_ms == 0) {
    pthread_mutex_unlock(&q->mu);
    return;
  }

  if (timeout_ms < 0) {
    while (q->len == 0) {
      pthread_cond_wait(&q->cv, &q->mu);
    }
    pthread_mutex_unlock(&q->mu);
    return;
  }

  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  int64_t nsec = (int64_t)ts.tv_nsec + (int64_t)(timeout_ms % 1000) * 1000000LL;
  ts.tv_sec += (time_t)(timeout_ms / 1000) + (time_t)(nsec / 1000000000LL);
  ts.tv_nsec = (long)(nsec % 1000000000LL);

  while (q->len == 0) {
    int rc = pthread_cond_timedwait(&q->cv, &q->mu, &ts);
    if (rc == ETIMEDOUT) {
      break;
    }
  }
  pthread_mutex_unlock(&q->mu);
}
#endif

// -----------------------------------------------------------------------------
// Backend
// -----------------------------------------------------------------------------

typedef struct moon_gamepad_backend_t {
  moon_gamepad_queue_t q;
  int32_t gamepad_count;

#if defined(__APPLE__)
  IOHIDManagerRef mgr;
  CFRunLoopRef rl;
  pthread_t thread;
  // Device slots: keep stable ids across reconnect.
  IOHIDDeviceRef devices[32];
  uint32_t device_ids[32];
  uint64_t entry_ids[32];
  uint32_t location_ids[32];
  uint8_t connected[32];
  int32_t vendors[32];
  int32_t products[32];
  char uuids[32][33];
  char names[32][256];
  // Number of allocated slots (may include disconnected ones).
  uint32_t devices_len;
  uint32_t next_id;
  // DPad hat state per device index.
  int8_t dpad_x[32];
  int8_t dpad_y[32];
	  // Device capabilities (best-effort).
	  int32_t axes_codes[32][32];
	  uint32_t axes_key[32][32];
	  uint8_t axes_len[32];
	  int32_t buttons_codes[32][64];
	  uint32_t buttons_key[32][64];
	  uint8_t buttons_len[32];
	  int32_t axis_info_codes[32][32];
	  int32_t axis_info_min[32][32];
	  int32_t axis_info_max[32][32];
	  uint8_t axis_info_len[32];
#endif

#if defined(__linux__)
  int fds[64];
  uint32_t fd_ids[64];
  char paths[64][256];
  int32_t vendors[64];
  int32_t products[64];
  char uuids[64][33];
  char names[64][256];
  uint8_t ff_supported[64];
  uint8_t rw[64];
  int32_t ff_id[64];
  int64_t ff_until_ms[64];
  uint32_t fds_len;
  uint32_t next_id;
#endif

#if defined(_WIN32)
  HMODULE xinput_dll;
  uint8_t win_connected[4];
  uint32_t win_packet[4];
  uint16_t win_buttons[4];
  int16_t win_lx[4], win_ly[4], win_rx[4], win_ry[4];
  uint8_t win_lt2[4], win_rt2[4];
  char win_names[4][64];
  char win_uuids[4][33];
  uint16_t win_rumble_l[4];
  uint16_t win_rumble_r[4];
  int64_t win_rumble_until_ms[4];
#endif
} moon_gamepad_backend_t;

// Internal logical codes (must match native_ev_codes.mbt).
enum {
  CODE_BTN_SOUTH = 0,
  CODE_BTN_EAST = 1,
  CODE_BTN_C = 2,
  CODE_BTN_NORTH = 3,
  CODE_BTN_WEST = 4,
  CODE_BTN_Z = 5,
  CODE_BTN_LT = 6,
  CODE_BTN_RT = 7,
  CODE_BTN_LT2 = 8,
  CODE_BTN_RT2 = 9,
  CODE_BTN_SELECT = 10,
  CODE_BTN_START = 11,
  CODE_BTN_MODE = 12,
  CODE_BTN_LTHUMB = 13,
  CODE_BTN_RTHUMB = 14,
  CODE_BTN_DPAD_UP = 15,
  CODE_BTN_DPAD_DOWN = 16,
  CODE_BTN_DPAD_LEFT = 17,
  CODE_BTN_DPAD_RIGHT = 18,

  CODE_AXIS_LSTICKX = 100,
  CODE_AXIS_LSTICKY = 101,
  CODE_AXIS_LEFTZ = 102,
	  CODE_AXIS_RSTICKX = 103,
	  CODE_AXIS_RSTICKY = 104,
	  CODE_AXIS_RIGHTZ = 105,
	  CODE_AXIS_DPADX = 106,
	  CODE_AXIS_DPADY = 107,
	  CODE_AXIS_RT = 108,
	  CODE_AXIS_LT = 109,
	  CODE_AXIS_RT2 = 110,
	  CODE_AXIS_LT2 = 111,
	};

#if defined(__APPLE__)

static int find_device_idx(moon_gamepad_backend_t *b, IOHIDDeviceRef dev) {
  if (b == NULL || dev == NULL) {
    return -1;
  }
  for (uint32_t i = 0; i < b->devices_len; i++) {
    if (b->devices[i] == dev) {
      return (int)i;
    }
  }
  return -1;
}

static uint32_t device_id_of(moon_gamepad_backend_t *b, IOHIDDeviceRef dev) {
  int idx = find_device_idx(b, dev);
  if (idx < 0) {
    return UINT32_MAX;
  }
  return b->device_ids[(uint32_t)idx];
}

static int mac_idx_by_entry_id(moon_gamepad_backend_t *b, uint64_t entry_id) {
  if (b == NULL) {
    return -1;
  }
  for (uint32_t i = 0; i < b->devices_len; i++) {
    if (b->connected[i] && b->entry_ids[i] == entry_id) {
      return (int)i;
    }
  }
  return -1;
}

static int mac_idx_by_location_id(moon_gamepad_backend_t *b, uint32_t location_id) {
  if (b == NULL) {
    return -1;
  }
  for (uint32_t i = 0; i < b->devices_len; i++) {
    if (b->connected[i] && b->location_ids[i] == location_id) {
      return (int)i;
    }
  }
  return -1;
}

static int mac_connected_count(moon_gamepad_backend_t *b) {
  if (b == NULL) {
    return 0;
  }
  int n = 0;
  for (uint32_t i = 0; i < b->devices_len; i++) {
    if (b->connected[i]) {
      n++;
    }
  }
  return n;
}

static uint32_t map_hid_button_usage(uint32_t usage) {
  // Best-effort, common HID gamepad layouts.
  switch (usage) {
  case 1:
    return CODE_BTN_SOUTH;
  case 2:
    return CODE_BTN_EAST;
  case 4:
    return CODE_BTN_WEST;
  case 5:
    return CODE_BTN_NORTH;
  case 7:
    return CODE_BTN_LT;
  case 8:
    return CODE_BTN_RT;
  case 9:
    return CODE_BTN_LT2;
  case 10:
    return CODE_BTN_RT2;
  case 11:
    return CODE_BTN_SELECT;
  case 12:
    return CODE_BTN_START;
  case 13:
    return CODE_BTN_MODE;
  case 14:
    return CODE_BTN_LTHUMB;
  case 15:
    return CODE_BTN_RTHUMB;
  case 20:
    return CODE_BTN_C;
  case 21:
    return CODE_BTN_Z;
  default:
    return UINT32_MAX;
  }
}

static uint32_t map_hid_gd_usage_to_axis(uint32_t usage) {
  // Generic Desktop usage IDs.
  // 0x30 X, 0x31 Y, 0x32 Z, 0x33 Rx, 0x34 Ry, 0x35 Rz, 0x39 HatSwitch.
  switch (usage) {
  case 0x30:
    return CODE_AXIS_LSTICKX;
  case 0x31:
    return CODE_AXIS_LSTICKY;
  case 0x32:
    return CODE_AXIS_RSTICKX;
  case 0x35:
    return CODE_AXIS_RSTICKY;
  case 0x33:
    return CODE_AXIS_LEFTZ;
  case 0x34:
    return CODE_AXIS_RIGHTZ;
  default:
    return UINT32_MAX;
  }
}

static uint32_t mac_hid_code(uint32_t page, uint32_t usage) {
  return (page << 16) | usage;
}

static int mac_get_i32_prop(IOHIDDeviceRef device, CFStringRef key, int32_t *out) {
  if (device == NULL || key == NULL || out == NULL) {
    return 0;
  }
  CFTypeRef ref = IOHIDDeviceGetProperty(device, key);
  if (ref == NULL || CFGetTypeID(ref) != CFNumberGetTypeID()) {
    return 0;
  }
  int32_t v = 0;
  if (!CFNumberGetValue((CFNumberRef)ref, kCFNumberSInt32Type, &v)) {
    return 0;
  }
  *out = v;
  return 1;
}

static int mac_type_is_input(IOHIDElementType type) {
  return (type == kIOHIDElementTypeInput_Misc) || (type == kIOHIDElementTypeInput_Button) ||
         (type == kIOHIDElementTypeInput_Axis);
}

static int mac_element_is_axis(IOHIDElementType type, uint32_t page, uint32_t usage) {
  if (!mac_type_is_input(type)) {
    return 0;
  }
  if (page == 0x01) {
    switch (usage) {
    case 0x30: // X
    case 0x31: // Y
    case 0x32: // Z
    case 0x33: // Rx
    case 0x34: // Ry
    case 0x35: // Rz
    case 0x36: // Slider
    case 0x37: // Dial
    case 0x38: // Wheel
      return 1;
    default:
      return 0;
    }
  }
  if (page == 0x02) {
    switch (usage) {
    case 0xBA: // Rudder
    case 0xBB: // Throttle
    case 0xC4: // Accelerator
    case 0xC5: // Brake
      return 1;
    default:
      return 0;
    }
  }
  return 0;
}

static int mac_element_is_button(IOHIDElementType type, uint32_t page, uint32_t usage) {
  if (!mac_type_is_input(type)) {
    return 0;
  }
  if (page == 0x01) {
    switch (usage) {
    case 0x90: // DPadUp
    case 0x91: // DPadDown
    case 0x92: // DPadRight
    case 0x93: // DPadLeft
    case 0x3D: // Start
    case 0x3E: // Select
    case 0x85: // SystemMainMenu
      return 1;
    default:
      return 0;
    }
  }
  // Button page / Consumer page.
  (void)usage;
  return (page == 0x09) || (page == 0x0C);
}

static int mac_element_is_hat(IOHIDElementType type, uint32_t page, uint32_t usage) {
  if (!mac_type_is_input(type)) {
    return 0;
  }
  // gilrs-core matches both hatswitch and "hatswitch+1".
  return (page == 0x01) && (usage == 0x39 || usage == 0x3A);
}

static double norm_i32(int32_t v, int32_t minv, int32_t maxv) {
  if (maxv == minv) {
    return 0.0;
  }
  // Normalize to [-1, 1] when min is negative, else [0, 1] scaled to [-1, 1].
  double dv = (double)v;
  double dmin = (double)minv;
  double dmax = (double)maxv;
  double t = (dv - dmin) / (dmax - dmin);
  if (t < 0.0) {
    t = 0.0;
  }
  if (t > 1.0) {
    t = 1.0;
  }
  return t * 2.0 - 1.0;
}

static double norm_btn_01_i32(int32_t v, int32_t minv, int32_t maxv) {
  if (maxv == minv) {
    return 0.0;
  }
  double dv = (double)v;
  double dmin = (double)minv;
  double dmax = (double)maxv;
  double t = (dv - dmin) / (dmax - dmin);
  if (t < 0.0) {
    t = 0.0;
  }
  if (t > 1.0) {
    t = 1.0;
  }
  return t;
}

static double clamp_f64(double v, double lo, double hi) {
  if (v < lo) {
    return lo;
  }
  if (v > hi) {
    return hi;
  }
  return v;
}

static double axis_value_like_gilrs(int32_t v, int32_t minv, int32_t maxv, int invert_y) {
  if (maxv == minv) {
    return 0.0;
  }
  int64_t range_i64 = (int64_t)maxv - (int64_t)minv;
  int64_t val_i64 = (int64_t)v - (int64_t)minv;
  double range = (double)range_i64;
  double val = (double)val_i64;

  // Mirror the odd-range centering adjustment in MoonBit axis_value().
  const int64_t INT_MAX_I64 = 2147483647LL;
  if (range_i64 <= INT_MAX_I64 && range_i64 >= 0) {
    if ((range_i64 % 2) == 1) {
      range += 1.0;
      val += 1.0;
    }
  }

  if (range == 0.0) {
    return 0.0;
  }

  double out = val / range * 2.0 - 1.0;
  if (invert_y && out != 0.0) {
    out = -out;
  }
  return clamp_f64(out, -1.0, 1.0);
}

static int is_y_axis_code(uint32_t code) {
  return (code == CODE_AXIS_LSTICKY) || (code == CODE_AXIS_RSTICKY) || (code == CODE_AXIS_DPADY);
}

static void mac_caps_clear(moon_gamepad_backend_t *b, uint32_t idx) {
  if (b == NULL || idx >= 32) {
    return;
  }
  b->axes_len[idx] = 0;
  b->buttons_len[idx] = 0;
  b->axis_info_len[idx] = 0;
  memset(b->axes_codes[idx], 0, sizeof(b->axes_codes[idx]));
  memset(b->axes_key[idx], 0, sizeof(b->axes_key[idx]));
  memset(b->buttons_codes[idx], 0, sizeof(b->buttons_codes[idx]));
  memset(b->buttons_key[idx], 0, sizeof(b->buttons_key[idx]));
  memset(b->axis_info_codes[idx], 0, sizeof(b->axis_info_codes[idx]));
  memset(b->axis_info_min[idx], 0, sizeof(b->axis_info_min[idx]));
  memset(b->axis_info_max[idx], 0, sizeof(b->axis_info_max[idx]));
}

static int mac_codes_contains(const int32_t *xs, uint8_t len, int32_t code) {
  for (uint8_t i = 0; i < len; i++) {
    if (xs[i] == code) {
      return 1;
    }
  }
  return 0;
}

typedef struct mac_cookie_set_t {
  uint32_t xs[512];
  uint16_t len;
} mac_cookie_set_t;

typedef struct mac_hat_axes_t {
  int32_t codes[32];
  uint32_t keys[32];
  uint8_t len;
} mac_hat_axes_t;

static int mac_cookie_contains(mac_cookie_set_t *s, uint32_t cookie) {
  if (s == NULL) {
    return 0;
  }
  for (uint16_t i = 0; i < s->len; i++) {
    if (s->xs[i] == cookie) {
      return 1;
    }
  }
  return 0;
}

static void mac_cookie_add(mac_cookie_set_t *s, uint32_t cookie) {
  if (s == NULL) {
    return;
  }
  if (s->len >= (uint16_t)(sizeof(s->xs) / sizeof(s->xs[0]))) {
    return;
  }
  s->xs[s->len++] = cookie;
}

static void mac_insert_sorted(int32_t *codes, uint32_t *keys, uint8_t *len, uint8_t cap, int32_t code,
                              uint32_t key) {
  if (codes == NULL || keys == NULL || len == NULL) {
    return;
  }
  uint8_t n = *len;
  if (n >= cap) {
    return;
  }
  // Stable insert by key.
  uint8_t pos = n;
  for (uint8_t i = 0; i < n; i++) {
    if (keys[i] > key) {
      pos = i;
      break;
    }
  }
  for (uint8_t j = n; j > pos; j--) {
    codes[j] = codes[j - 1];
    keys[j] = keys[j - 1];
  }
  codes[pos] = code;
  keys[pos] = key;
  *len = (uint8_t)(n + 1);
}

static void mac_push_code(int32_t *codes, uint32_t *keys, uint8_t *len, uint8_t cap, int32_t code, uint32_t key) {
  if (codes == NULL || keys == NULL || len == NULL) {
    return;
  }
  uint8_t n = *len;
  if (n >= cap) {
    return;
  }
  codes[n] = code;
  keys[n] = key;
  *len = (uint8_t)(n + 1);
}

static void mac_axis_info_add(moon_gamepad_backend_t *b, uint32_t idx, int32_t code, int32_t minv, int32_t maxv) {
  if (b == NULL || idx >= 32) {
    return;
  }
  for (uint8_t i = 0; i < b->axis_info_len[idx]; i++) {
    if (b->axis_info_codes[idx][i] == code) {
      return;
    }
  }
  if (b->axis_info_len[idx] < 32) {
    uint8_t j = b->axis_info_len[idx]++;
    b->axis_info_codes[idx][j] = code;
    b->axis_info_min[idx][j] = minv;
    b->axis_info_max[idx][j] = maxv;
  }
}

static void mac_add_axis_code(moon_gamepad_backend_t *b, uint32_t idx, int32_t code, uint32_t sort_key, int32_t minv,
                              int32_t maxv) {
  if (b == NULL || idx >= 32) {
    return;
  }
  if (!mac_codes_contains(b->axes_codes[idx], b->axes_len[idx], code)) {
    mac_insert_sorted(b->axes_codes[idx], b->axes_key[idx], &b->axes_len[idx], 32, code, sort_key);
  }
  mac_axis_info_add(b, idx, code, minv, maxv);
}

static void mac_add_axis_code_append(moon_gamepad_backend_t *b, uint32_t idx, int32_t code, uint32_t sort_key,
                                     int32_t minv, int32_t maxv) {
  if (b == NULL || idx >= 32) {
    return;
  }
  if (!mac_codes_contains(b->axes_codes[idx], b->axes_len[idx], code)) {
    mac_push_code(b->axes_codes[idx], b->axes_key[idx], &b->axes_len[idx], 32, code, sort_key);
  }
  mac_axis_info_add(b, idx, code, minv, maxv);
}

static void mac_add_button_code(moon_gamepad_backend_t *b, uint32_t idx, int32_t code, uint32_t sort_key) {
  if (b == NULL || idx >= 32) {
    return;
  }
  if (!mac_codes_contains(b->buttons_codes[idx], b->buttons_len[idx], code)) {
    mac_insert_sorted(b->buttons_codes[idx], b->buttons_key[idx], &b->buttons_len[idx], 64, code, sort_key);
  }
}

static void mac_hat_axes_add(mac_hat_axes_t *hats, int32_t code, uint32_t key) {
  if (hats == NULL) {
    return;
  }
  if (!mac_codes_contains(hats->codes, hats->len, code)) {
    mac_insert_sorted(hats->codes, hats->keys, &hats->len, 32, code, key);
  }
}

static void mac_collect_elements(
  moon_gamepad_backend_t *b,
  uint32_t idx,
  CFArrayRef elements,
  mac_hat_axes_t *hats,
  mac_cookie_set_t *cookies
) {
  if (b == NULL || elements == NULL || idx >= 32) {
    return;
  }
  CFIndex n = CFArrayGetCount(elements);
  for (CFIndex i = 0; i < n; i++) {
    IOHIDElementRef el = (IOHIDElementRef)CFArrayGetValueAtIndex(elements, i);
    if (el == NULL) {
      continue;
    }
    IOHIDElementType type = IOHIDElementGetType(el);
    if (type == kIOHIDElementTypeCollection) {
      CFArrayRef children = IOHIDElementGetChildren(el);
      if (children != NULL) {
        mac_collect_elements(b, idx, children, hats, cookies);
      }
      continue;
    }
    uint32_t page = IOHIDElementGetUsagePage(el);
    uint32_t usage = IOHIDElementGetUsage(el);
    uint32_t cookie = (uint32_t)IOHIDElementGetCookie(el);

    if (mac_element_is_hat(type, page, usage)) {
      // Hat -> two axes (append after other axes to match SDL ordering).
      if (!mac_cookie_contains(cookies, cookie)) {
        mac_cookie_add(cookies, cookie);
        uint32_t code_x = mac_hid_code(page, usage);
        uint32_t code_y = mac_hid_code(page, usage + 1u);
        mac_axis_info_add(b, idx, (int32_t)code_x, -1, 1);
        mac_axis_info_add(b, idx, (int32_t)code_y, -1, 1);
        mac_hat_axes_add(hats, (int32_t)code_x, usage);
        mac_hat_axes_add(hats, (int32_t)code_y, usage + 1u);
      }
      continue;
    }

    if (mac_element_is_axis(type, page, usage)) {
      if (mac_cookie_contains(cookies, cookie)) {
        continue;
      }
      mac_cookie_add(cookies, cookie);
      int32_t minv = (int32_t)IOHIDElementGetLogicalMin(el);
      int32_t maxv = (int32_t)IOHIDElementGetLogicalMax(el);
      uint32_t code = mac_hid_code(page, usage);
      mac_add_axis_code(b, idx, (int32_t)code, usage, minv, maxv);
      continue;
    }

    if (mac_element_is_button(type, page, usage)) {
      if (mac_cookie_contains(cookies, cookie)) {
        continue;
      }
      mac_cookie_add(cookies, cookie);
      uint32_t code = mac_hid_code(page, usage);
      mac_add_button_code(b, idx, (int32_t)code, usage);
      continue;
    }
  }
}

static void mac_collect_device_caps(moon_gamepad_backend_t *b, uint32_t idx, IOHIDDeviceRef device) {
  if (b == NULL || device == NULL || idx >= 32) {
    return;
  }
  mac_caps_clear(b, idx);
  mac_hat_axes_t hats;
  memset(&hats, 0, sizeof(hats));
  mac_cookie_set_t cookies;
  memset(&cookies, 0, sizeof(cookies));
  CFArrayRef elements = IOHIDDeviceCopyMatchingElements(device, NULL, kIOHIDOptionsTypeNone);
  if (elements == NULL) {
    return;
  }
  mac_collect_elements(b, idx, elements, &hats, &cookies);
  CFRelease(elements);
  for (uint8_t i = 0; i < hats.len; i++) {
    mac_add_axis_code_append(b, idx, hats.codes[i], hats.keys[i], -1, 1);
  }
}

static void mac_fill_device_info(moon_gamepad_backend_t *b, uint32_t idx, IOHIDDeviceRef device) {
  if (b == NULL || device == NULL || idx >= 32) {
    return;
  }
  b->vendors[idx] = -1;
  b->products[idx] = -1;
  memset(b->uuids[idx], 0, sizeof(b->uuids[idx]));
  memset(b->names[idx], 0, sizeof(b->names[idx]));
  b->uuids[idx][0] = '\0';
  strncpy(b->names[idx], "Unknown", sizeof(b->names[idx]) - 1);
  b->names[idx][sizeof(b->names[idx]) - 1] = '\0';

  CFTypeRef vref = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDVendorIDKey));
  if (vref != NULL && CFGetTypeID(vref) == CFNumberGetTypeID()) {
    int32_t v = -1;
    if (CFNumberGetValue((CFNumberRef)vref, kCFNumberSInt32Type, &v)) {
      b->vendors[idx] = v;
    }
  }
  CFTypeRef pref = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductIDKey));
  if (pref != NULL && CFGetTypeID(pref) == CFNumberGetTypeID()) {
    int32_t p = -1;
    if (CFNumberGetValue((CFNumberRef)pref, kCFNumberSInt32Type, &p)) {
      b->products[idx] = p;
    }
  }
  int32_t ver = 0;
  CFTypeRef verref = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDVersionNumberKey));
  if (verref != NULL && CFGetTypeID(verref) == CFNumberGetTypeID()) {
    (void)CFNumberGetValue((CFNumberRef)verref, kCFNumberSInt32Type, &ver);
  }
  CFTypeRef nref = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
  if (nref != NULL && CFGetTypeID(nref) == CFStringGetTypeID()) {
    CFStringRef s = (CFStringRef)nref;
    (void)CFStringGetCString(s, b->names[idx], (CFIndex)sizeof(b->names[idx]), kCFStringEncodingUTF8);
  }

  uint16_t vendor = (b->vendors[idx] > 0) ? (uint16_t)b->vendors[idx] : 0;
  uint16_t product = (b->products[idx] > 0) ? (uint16_t)b->products[idx] : 0;
  uint16_t version = (ver > 0) ? (uint16_t)ver : 0;
  uuid_simple_macos(vendor, product, version, b->uuids[idx]);
}

static void device_matching_cb(void *ctx, IOReturn res, void *sender, IOHIDDeviceRef device) {
  (void)res;
  (void)sender;
  moon_gamepad_backend_t *b = (moon_gamepad_backend_t *)ctx;
  if (b == NULL || device == NULL) {
    return;
  }
  if (find_device_idx(b, device) >= 0) {
    return;
  }

  // Validate required properties, mirroring gilrs-core's early filtering.
  int32_t location_id_i32 = 0;
  if (!mac_get_i32_prop(device, CFSTR(kIOHIDLocationIDKey), &location_id_i32)) {
    return;
  }
  uint32_t location_id = (uint32_t)location_id_i32;

  int32_t page_i32 = 0;
  int32_t usage_i32 = 0;
  if (!mac_get_i32_prop(device, CFSTR(kIOHIDPrimaryUsagePageKey), &page_i32) ||
      !mac_get_i32_prop(device, CFSTR(kIOHIDPrimaryUsageKey), &usage_i32)) {
    return;
  }
  uint32_t page = (uint32_t)page_i32;
  uint32_t usage = (uint32_t)usage_i32;
  if (page >= 0xFF00u) { // kHIDPage_VendorDefinedStart
    return;
  }
  if (page != 0x01u) { // kHIDPage_GenericDesktop
    return;
  }
  if (!(usage == 0x04u || usage == 0x05u || usage == 0x08u)) { // Joystick/GamePad/MultiAxisController
    return;
  }

  // Compute registry entry id; if unavailable, skip the device.
  io_service_t svc = IOHIDDeviceGetService(device);
  uint64_t entry_id = 0;
  if (svc == IO_OBJECT_NULL || IORegistryEntryGetRegistryEntryID(svc, &entry_id) != KERN_SUCCESS) {
    return;
  }

  // Deduplicate only already-connected entry IDs. A reconnect after disconnect
  // allocates a new slot, matching gilrs-core device_infos behavior.
  for (uint32_t i = 0; i < b->devices_len; i++) {
    if (b->entry_ids[i] == entry_id && b->connected[i]) {
      return;
    }
  }
  if (b->devices_len >= 32) {
    return;
  }
  uint32_t idx = b->devices_len++;
  b->device_ids[idx] = b->next_id++;
  b->entry_ids[idx] = entry_id;

  // Retain device while stored.
  CFRetain(device);
  if (b->devices[idx] != NULL) {
    CFRelease(b->devices[idx]);
  }
  b->devices[idx] = device;
  b->location_ids[idx] = location_id;
  b->connected[idx] = 1;
  mac_collect_device_caps(b, idx, device);
  mac_fill_device_info(b, idx, device);
  b->dpad_x[idx] = 0;
  b->dpad_y[idx] = 0;
  b->gamepad_count = (int32_t)mac_connected_count(b);
  moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_CONNECTED, b->device_ids[idx], 0, 0, 0.0, now_ms()};
  queue_push(&b->q, ev);
}

static void device_removal_cb(void *ctx, IOReturn res, void *sender, IOHIDDeviceRef device) {
  (void)res;
  (void)sender;
  moon_gamepad_backend_t *b = (moon_gamepad_backend_t *)ctx;
  if (b == NULL || device == NULL) {
    return;
  }
  int32_t location_id_i32 = 0;
  if (!mac_get_i32_prop(device, CFSTR(kIOHIDLocationIDKey), &location_id_i32)) {
    return;
  }
  uint32_t location_id = (uint32_t)location_id_i32;
  int idx = mac_idx_by_location_id(b, location_id);
  if (idx < 0) {
    return;
  }
  uint32_t id = b->device_ids[(uint32_t)idx];
  if (b->devices[(uint32_t)idx] != NULL) {
    CFRelease(b->devices[(uint32_t)idx]);
    b->devices[(uint32_t)idx] = NULL;
  }
  b->connected[(uint32_t)idx] = 0;
  b->dpad_x[(uint32_t)idx] = 0;
  b->dpad_y[(uint32_t)idx] = 0;
  b->gamepad_count = (int32_t)mac_connected_count(b);
  moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_DISCONNECTED, id, 0, 0, 0.0, now_ms()};
  queue_push(&b->q, ev);
}

static void input_value_cb(void *ctx, IOReturn res, void *sender, IOHIDValueRef value) {
  (void)res;
  moon_gamepad_backend_t *b = (moon_gamepad_backend_t *)ctx;
  if (b == NULL || value == NULL) {
    return;
  }
  IOHIDDeviceRef dev = (IOHIDDeviceRef)sender;
  if (dev == NULL) {
    return;
  }
  io_service_t svc = IOHIDDeviceGetService(dev);
  uint64_t entry_id = 0;
  if (svc == IO_OBJECT_NULL || IORegistryEntryGetRegistryEntryID(svc, &entry_id) != KERN_SUCCESS) {
    return;
  }
  int dev_idx = mac_idx_by_entry_id(b, entry_id);
  if (dev_idx < 0) {
    return;
  }
  uint32_t id = b->device_ids[(uint32_t)dev_idx];
  IOHIDElementRef el = IOHIDValueGetElement(value);
  if (el == NULL) {
    return;
  }
  IOHIDElementType type = IOHIDElementGetType(el);
  uint32_t page = IOHIDElementGetUsagePage(el);
  uint32_t usage = IOHIDElementGetUsage(el);
  int64_t t = now_ms();

  if (mac_element_is_axis(type, page, usage)) {
    uint32_t code = mac_hid_code(page, usage);
    int32_t v = (int32_t)IOHIDValueGetIntegerValue(value);
    moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_AXIS_CHANGED, id, code, 0, (double)v, t};
    queue_push(&b->q, ev);
    return;
  }

  if (mac_element_is_button(type, page, usage)) {
    uint32_t code = mac_hid_code(page, usage);
    int32_t v = (int32_t)IOHIDValueGetIntegerValue(value);
    moon_gamepad_event_t ev;
    ev.tag = (v != 0) ? MOON_GAMEPAD_EV_BUTTON_PRESSED : MOON_GAMEPAD_EV_BUTTON_RELEASED;
    ev.id = id;
    ev.code = code;
    ev.pad = 0;
    ev.value = (v != 0) ? 1.0 : 0.0;
    ev.time_ms = t;
    queue_push(&b->q, ev);
    return;
  }

  // Hat: normalize and emit 2 axes only, matching gilrs-core.
  if (mac_element_is_hat(type, page, usage)) {
      int32_t hat_v = (int32_t)IOHIDValueGetIntegerValue(value);
      int32_t hat_min = (int32_t)IOHIDElementGetLogicalMin(el);
      int32_t hat_max = (int32_t)IOHIDElementGetLogicalMax(el);
      int32_t range = hat_max - hat_min + 1;
      int32_t shifted = hat_v - hat_min;
      int32_t dpad_value;
      if (range == 4) {
        dpad_value = shifted * 2;
      } else if (range == 8) {
        dpad_value = shifted;
      } else {
        dpad_value = -1; // treat as centered/unknown
      }

      int32_t x_raw;
      if (dpad_value >= 5 && dpad_value <= 7) {
        x_raw = -1;
      } else if (dpad_value >= 1 && dpad_value <= 3) {
        x_raw = 1;
      } else {
        x_raw = 0;
      }

      // gilrs-core emits an inverted macOS axis here (down positive, up negative) and lets the Y
      // inversion stage fix it.
      int32_t y_raw;
      if (dpad_value >= 3 && dpad_value <= 5) {
        y_raw = 1; // down (pre-inversion)
      } else if (dpad_value == 0 || dpad_value == 1 || dpad_value == 7) {
        y_raw = -1; // up (pre-inversion)
      } else {
        y_raw = 0;
      }

      double x = (double)x_raw;
      double y = (double)y_raw;

      uint32_t code_x = mac_hid_code(page, 0x39u);
      uint32_t code_y = mac_hid_code(page, 0x3Au);
      moon_gamepad_event_t ex = {MOON_GAMEPAD_EV_AXIS_CHANGED, id, code_x, 0, x, t};
      moon_gamepad_event_t ey = {MOON_GAMEPAD_EV_AXIS_CHANGED, id, code_y, 0, y, t};
      queue_push(&b->q, ex);
      queue_push(&b->q, ey);
      return;
  }
}

static CFDictionaryRef make_matching_dict(uint32_t page, uint32_t usage) {
  CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                         &kCFTypeDictionaryKeyCallBacks,
                                                         &kCFTypeDictionaryValueCallBacks);
  if (dict == NULL) {
    return NULL;
  }
  CFNumberRef page_n = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &page);
  CFNumberRef usage_n = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &usage);
  if (page_n != NULL) {
    CFDictionarySetValue(dict, kIOHIDDeviceUsagePageKey, page_n);
    CFRelease(page_n);
  }
  if (usage_n != NULL) {
    CFDictionarySetValue(dict, kIOHIDDeviceUsageKey, usage_n);
    CFRelease(usage_n);
  }
  return dict;
}

static void *mac_thread_main(void *arg) {
  moon_gamepad_backend_t *b = (moon_gamepad_backend_t *)arg;
  if (b == NULL) {
    return NULL;
  }
  b->mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
  if (b->mgr == NULL) {
    return NULL;
  }

  // Match GamePad, Joystick, MultiAxisController.
  CFDictionaryRef m1 = make_matching_dict(0x01, 0x05);
  CFDictionaryRef m2 = make_matching_dict(0x01, 0x04);
  CFDictionaryRef m3 = make_matching_dict(0x01, 0x08);
  CFMutableArrayRef arr = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
  if (arr != NULL) {
    if (m1 != NULL)
      CFArrayAppendValue(arr, m1);
    if (m2 != NULL)
      CFArrayAppendValue(arr, m2);
    if (m3 != NULL)
      CFArrayAppendValue(arr, m3);
    IOHIDManagerSetDeviceMatchingMultiple(b->mgr, arr);
    CFRelease(arr);
  }
  if (m1 != NULL)
    CFRelease(m1);
  if (m2 != NULL)
    CFRelease(m2);
  if (m3 != NULL)
    CFRelease(m3);

  IOHIDManagerRegisterDeviceMatchingCallback(b->mgr, device_matching_cb, b);
  IOHIDManagerRegisterDeviceRemovalCallback(b->mgr, device_removal_cb, b);
  IOHIDManagerRegisterInputValueCallback(b->mgr, input_value_cb, b);

  IOHIDManagerScheduleWithRunLoop(b->mgr, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
  IOHIDManagerOpen(b->mgr, kIOHIDOptionsTypeNone);

  b->rl = CFRunLoopGetCurrent();
  CFRunLoopRun();

  return NULL;
}

static void mac_backend_init(moon_gamepad_backend_t *b) {
  b->mgr = NULL;
  b->rl = NULL;
  b->devices_len = 0;
  b->next_id = 0;
  b->gamepad_count = 0;
  memset(b->devices, 0, sizeof(b->devices));
  memset(b->device_ids, 0, sizeof(b->device_ids));
  memset(b->entry_ids, 0, sizeof(b->entry_ids));
  memset(b->location_ids, 0, sizeof(b->location_ids));
  memset(b->connected, 0, sizeof(b->connected));
  for (int i = 0; i < 32; i++) {
    b->vendors[i] = -1;
    b->products[i] = -1;
    memset(b->uuids[i], 0, sizeof(b->uuids[i]));
    memset(b->names[i], 0, sizeof(b->names[i]));
  }
	  memset(b->dpad_x, 0, sizeof(b->dpad_x));
	  memset(b->dpad_y, 0, sizeof(b->dpad_y));
	  memset(b->axes_codes, 0, sizeof(b->axes_codes));
	  memset(b->axes_key, 0, sizeof(b->axes_key));
	  memset(b->axes_len, 0, sizeof(b->axes_len));
	  memset(b->buttons_codes, 0, sizeof(b->buttons_codes));
	  memset(b->buttons_key, 0, sizeof(b->buttons_key));
	  memset(b->buttons_len, 0, sizeof(b->buttons_len));
	  memset(b->axis_info_codes, 0, sizeof(b->axis_info_codes));
	  memset(b->axis_info_min, 0, sizeof(b->axis_info_min));
	  memset(b->axis_info_max, 0, sizeof(b->axis_info_max));
  memset(b->axis_info_len, 0, sizeof(b->axis_info_len));
  pthread_create(&b->thread, NULL, mac_thread_main, b);
}

static void mac_backend_shutdown(moon_gamepad_backend_t *b) {
  if (b == NULL) {
    return;
  }
  if (b->rl != NULL) {
    CFRunLoopStop(b->rl);
  }
  // Best-effort join.
  pthread_join(b->thread, NULL);
  if (b->mgr != NULL) {
    IOHIDManagerClose(b->mgr, kIOHIDOptionsTypeNone);
    CFRelease(b->mgr);
    b->mgr = NULL;
  }
  for (uint32_t i = 0; i < b->devices_len; i++) {
    if (b->devices[i] != NULL) {
      CFRelease(b->devices[i]);
      b->devices[i] = NULL;
    }
  }
  b->devices_len = 0;
  b->gamepad_count = 0;
}

#endif // __APPLE__

#if defined(__linux__)
#define BITS_PER_LONG (sizeof(unsigned long) * 8)
#define NBITS(x) ((((x) + 1) + BITS_PER_LONG - 1) / BITS_PER_LONG)
#define BIT_WORD(nr) ((nr) / BITS_PER_LONG)
#define BIT_MASK(nr) (1UL << ((nr) % BITS_PER_LONG))

static int test_bit(int nr, const unsigned long *addr) {
  return (addr[BIT_WORD(nr)] & BIT_MASK(nr)) != 0;
}

static uint32_t map_linux_btn(uint16_t code) {
  switch (code) {
  case BTN_SOUTH:
    return CODE_BTN_SOUTH;
  case BTN_EAST:
    return CODE_BTN_EAST;
  case BTN_C:
    return CODE_BTN_C;
  case BTN_NORTH:
    return CODE_BTN_NORTH;
  case BTN_WEST:
    return CODE_BTN_WEST;
  case BTN_Z:
    return CODE_BTN_Z;
  case BTN_TL:
    return CODE_BTN_LT;
  case BTN_TR:
    return CODE_BTN_RT;
  case BTN_TL2:
    return CODE_BTN_LT2;
  case BTN_TR2:
    return CODE_BTN_RT2;
  case BTN_SELECT:
    return CODE_BTN_SELECT;
  case BTN_START:
    return CODE_BTN_START;
  case BTN_MODE:
    return CODE_BTN_MODE;
  case BTN_THUMBL:
    return CODE_BTN_LTHUMB;
  case BTN_THUMBR:
    return CODE_BTN_RTHUMB;
  case BTN_DPAD_UP:
    return CODE_BTN_DPAD_UP;
  case BTN_DPAD_DOWN:
    return CODE_BTN_DPAD_DOWN;
  case BTN_DPAD_LEFT:
    return CODE_BTN_DPAD_LEFT;
  case BTN_DPAD_RIGHT:
    return CODE_BTN_DPAD_RIGHT;
  default:
    return UINT32_MAX;
  }
}

static uint32_t map_linux_abs(uint16_t code) {
  switch (code) {
  case ABS_X:
    return CODE_AXIS_LSTICKX;
  case ABS_Y:
    return CODE_AXIS_LSTICKY;
  case ABS_Z:
    return CODE_AXIS_LEFTZ;
  case ABS_RX:
    return CODE_AXIS_RSTICKX;
  case ABS_RY:
    return CODE_AXIS_RSTICKY;
  case ABS_RZ:
    return CODE_AXIS_RIGHTZ;
  case ABS_HAT0X:
    return CODE_AXIS_DPADX;
  case ABS_HAT0Y:
    return CODE_AXIS_DPADY;
  default:
    return UINT32_MAX;
  }
}

static double norm_linux_abs(int32_t v, uint16_t code) {
  // Hat axes are already -1/0/1 typically.
  if (code == ABS_HAT0X || code == ABS_HAT0Y) {
    if (v < 0)
      return -1.0;
    if (v > 0)
      return 1.0;
    return 0.0;
  }
  // Best-effort: treat as signed 16-bit centered.
  // Many controllers report in [-32768, 32767].
  const double denom = 32767.0;
  double dv = (double)v;
  if (dv < -32768.0)
    dv = -32768.0;
  if (dv > 32767.0)
    dv = 32767.0;
  return dv / denom;
}

static int linux_is_gamepad_fd(int fd) {
  unsigned long evbit[NBITS(EV_MAX)];
  unsigned long keybit[NBITS(KEY_MAX)];
  unsigned long absbit[NBITS(ABS_MAX)];

  memset(evbit, 0, sizeof(evbit));
  memset(keybit, 0, sizeof(keybit));
  memset(absbit, 0, sizeof(absbit));

  if (ioctl(fd, EVIOCGBIT(0, sizeof(evbit)), evbit) < 0) {
    return 0;
  }

  int has_key = test_bit(EV_KEY, evbit);
  int has_abs = test_bit(EV_ABS, evbit);

  if (!has_key && !has_abs) {
    return 0;
  }

  if (has_key) {
    (void)ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keybit)), keybit);
  }
  if (has_abs) {
    (void)ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(absbit)), absbit);
  }

  int has_gamepad_key =
      test_bit(BTN_GAMEPAD, keybit) || test_bit(BTN_JOYSTICK, keybit) || test_bit(BTN_SOUTH, keybit) ||
      test_bit(BTN_EAST, keybit) || test_bit(BTN_NORTH, keybit) || test_bit(BTN_WEST, keybit) ||
      test_bit(BTN_TL, keybit) || test_bit(BTN_TR, keybit) || test_bit(BTN_START, keybit) ||
      test_bit(BTN_SELECT, keybit) || test_bit(BTN_MODE, keybit) || test_bit(BTN_DPAD_UP, keybit) ||
      test_bit(BTN_DPAD_DOWN, keybit) || test_bit(BTN_DPAD_LEFT, keybit) || test_bit(BTN_DPAD_RIGHT, keybit);

  int has_sticks = test_bit(ABS_X, absbit) && test_bit(ABS_Y, absbit);
  int has_hat = test_bit(ABS_HAT0X, absbit) || test_bit(ABS_HAT0Y, absbit);

  if (!has_gamepad_key) {
    return 0;
  }
  if (!has_sticks && !has_hat) {
    return 0;
  }

  return 1;
}

static int linux_has_path(moon_gamepad_backend_t *b, const char *path) {
  if (b == NULL || path == NULL) {
    return 0;
  }
  for (uint32_t i = 0; i < b->fds_len; i++) {
    if (strncmp(b->paths[i], path, sizeof(b->paths[i])) == 0) {
      return 1;
    }
  }
  return 0;
}

static void linux_ff_stop_idx(moon_gamepad_backend_t *b, uint32_t idx) {
  if (b == NULL || idx >= b->fds_len) {
    return;
  }
  if (b->fds[idx] < 0) {
    return;
  }
  if (!b->rw[idx] || !b->ff_supported[idx] || b->ff_id[idx] < 0) {
    b->ff_until_ms[idx] = 0;
    return;
  }
  struct input_event ie;
  memset(&ie, 0, sizeof(ie));
  ie.type = EV_FF;
  ie.code = (uint16_t)b->ff_id[idx];
  ie.value = 0;
  (void)write(b->fds[idx], &ie, sizeof(ie));
  b->ff_until_ms[idx] = 0;
}

static void linux_ff_remove_idx(moon_gamepad_backend_t *b, uint32_t idx) {
  if (b == NULL || idx >= b->fds_len) {
    return;
  }
  if (b->fds[idx] < 0) {
    b->ff_id[idx] = -1;
    b->ff_until_ms[idx] = 0;
    return;
  }
  linux_ff_stop_idx(b, idx);
  if (!b->rw[idx] || !b->ff_supported[idx] || b->ff_id[idx] < 0) {
    b->ff_id[idx] = -1;
    return;
  }
  (void)ioctl(b->fds[idx], EVIOCRMFF, b->ff_id[idx]);
  b->ff_id[idx] = -1;
}

static void linux_ff_tick(moon_gamepad_backend_t *b) {
  if (b == NULL) {
    return;
  }
  int64_t t = now_ms();
  for (uint32_t i = 0; i < b->fds_len; i++) {
    if (b->ff_until_ms[i] != 0 && t >= b->ff_until_ms[i]) {
      linux_ff_stop_idx(b, i);
    }
  }
}

static int32_t linux_ff_set_rumble_idx(moon_gamepad_backend_t *b, uint32_t idx, uint16_t strong,
                                      uint16_t weak, int32_t duration_ms) {
  if (b == NULL || idx >= b->fds_len) {
    return 0;
  }
  if (b->fds[idx] < 0) {
    return 0;
  }
  if (!b->rw[idx] || !b->ff_supported[idx]) {
    return 0;
  }
  if (duration_ms <= 0 || (strong == 0 && weak == 0)) {
    linux_ff_stop_idx(b, idx);
    return 1;
  }
  if (duration_ms > 0xFFFF) {
    duration_ms = 0xFFFF;
  }
  struct ff_effect effect;
  memset(&effect, 0, sizeof(effect));
  effect.type = FF_RUMBLE;
  effect.id = (b->ff_id[idx] >= 0) ? b->ff_id[idx] : -1;
  effect.u.rumble.strong_magnitude = strong;
  effect.u.rumble.weak_magnitude = weak;
  effect.replay.length = (uint16_t)duration_ms;
  effect.replay.delay = 0;
  if (ioctl(b->fds[idx], EVIOCSFF, &effect) < 0) {
    return 0;
  }
  b->ff_id[idx] = effect.id;
  struct input_event ie;
  memset(&ie, 0, sizeof(ie));
  ie.type = EV_FF;
  ie.code = (uint16_t)effect.id;
  ie.value = 1;
  if (write(b->fds[idx], &ie, sizeof(ie)) != (ssize_t)sizeof(ie)) {
    return 0;
  }
  b->ff_until_ms[idx] = now_ms() + (int64_t)duration_ms;
  return 1;
}

static void linux_compact(moon_gamepad_backend_t *b) {
  if (b == NULL) {
    return;
  }
  uint32_t out = 0;
  for (uint32_t i = 0; i < b->fds_len; i++) {
    if (b->fds[i] < 0) {
      continue;
    }
    if (out != i) {
      b->fds[out] = b->fds[i];
      b->fd_ids[out] = b->fd_ids[i];
      memcpy(b->paths[out], b->paths[i], sizeof(b->paths[out]));
      b->vendors[out] = b->vendors[i];
      b->products[out] = b->products[i];
      memcpy(b->uuids[out], b->uuids[i], sizeof(b->uuids[out]));
      memcpy(b->names[out], b->names[i], sizeof(b->names[out]));
      b->ff_supported[out] = b->ff_supported[i];
      b->rw[out] = b->rw[i];
      b->ff_id[out] = b->ff_id[i];
      b->ff_until_ms[out] = b->ff_until_ms[i];
    }
    out++;
  }
  b->fds_len = out;
  b->gamepad_count = (int32_t)b->fds_len;
}

static void linux_backend_scan(moon_gamepad_backend_t *b) {
  DIR *dir = opendir("/dev/input");
  if (dir == NULL) {
    return;
  }
  struct dirent *ent;
  while ((ent = readdir(dir)) != NULL) {
    if (strncmp(ent->d_name, "event", 5) != 0) {
      continue;
    }
    if (b->fds_len >= 64) {
      break;
    }
    char path[256];
    snprintf(path, sizeof(path), "/dev/input/%s", ent->d_name);
    if (linux_has_path(b, path)) {
      continue;
    }
    int rw = 1;
    int fd = open(path, O_RDWR | O_NONBLOCK);
    if (fd < 0) {
      rw = 0;
      fd = open(path, O_RDONLY | O_NONBLOCK);
    }
    if (fd < 0) {
      continue;
    }
    if (!linux_is_gamepad_fd(fd)) {
      close(fd);
      continue;
    }
    // Keep.
    uint32_t id = b->next_id++;
    b->fds[b->fds_len] = fd;
    b->fd_ids[b->fds_len] = id;
    memset(b->paths[b->fds_len], 0, sizeof(b->paths[b->fds_len]));
    strncpy(b->paths[b->fds_len], path, sizeof(b->paths[b->fds_len]) - 1);
    b->rw[b->fds_len] = (uint8_t)rw;
    b->vendors[b->fds_len] = -1;
    b->products[b->fds_len] = -1;
    b->ff_supported[b->fds_len] = 0;
    memset(b->uuids[b->fds_len], 0, sizeof(b->uuids[b->fds_len]));
    memset(b->names[b->fds_len], 0, sizeof(b->names[b->fds_len]));
    b->ff_id[b->fds_len] = -1;
    b->ff_until_ms[b->fds_len] = 0;

    struct input_id iid;
    memset(&iid, 0, sizeof(iid));
    if (ioctl(fd, EVIOCGID, &iid) >= 0) {
      b->vendors[b->fds_len] = (int32_t)iid.vendor;
      b->products[b->fds_len] = (int32_t)iid.product;
      uuid_simple_from_ids(iid.bustype, iid.vendor, iid.product, iid.version, b->uuids[b->fds_len]);
    } else {
      uuid_simple_from_ids(0, 0, 0, 0, b->uuids[b->fds_len]);
    }

    char name[256];
    memset(name, 0, sizeof(name));
    if (ioctl(fd, EVIOCGNAME((int)sizeof(name)), name) >= 0) {
      strncpy(b->names[b->fds_len], name, sizeof(b->names[b->fds_len]) - 1);
    }

    unsigned long ffbit[NBITS(FF_MAX)];
    memset(ffbit, 0, sizeof(ffbit));
    if (ioctl(fd, EVIOCGBIT(EV_FF, sizeof(ffbit)), ffbit) >= 0) {
      if (test_bit(FF_RUMBLE, ffbit)) {
        b->ff_supported[b->fds_len] = 1;
      }
    }
    if (!rw) {
      b->ff_supported[b->fds_len] = 0;
    }
    b->fds_len++;
    b->gamepad_count = (int32_t)b->fds_len;
    moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_CONNECTED, id, 0, 0, 0.0, now_ms()};
    queue_push(&b->q, ev);
  }
  closedir(dir);
}

static void linux_backend_init(moon_gamepad_backend_t *b) {
  b->fds_len = 0;
  b->next_id = 0;
  memset(b->fds, -1, sizeof(b->fds));
  memset(b->fd_ids, 0, sizeof(b->fd_ids));
  memset(b->paths, 0, sizeof(b->paths));
  memset(b->vendors, 0, sizeof(b->vendors));
  memset(b->products, 0, sizeof(b->products));
  memset(b->uuids, 0, sizeof(b->uuids));
  memset(b->names, 0, sizeof(b->names));
  memset(b->ff_supported, 0, sizeof(b->ff_supported));
  memset(b->rw, 0, sizeof(b->rw));
  for (int i = 0; i < 64; i++) {
    b->ff_id[i] = -1;
    b->ff_until_ms[i] = 0;
  }
  for (int i = 0; i < 64; i++) {
    b->vendors[i] = -1;
    b->products[i] = -1;
  }
  linux_backend_scan(b);
}

static void linux_backend_shutdown(moon_gamepad_backend_t *b) {
  if (b == NULL) {
    return;
  }
  for (uint32_t i = 0; i < b->fds_len; i++) {
    if (b->fds[i] >= 0) {
      linux_ff_remove_idx(b, i);
      close(b->fds[i]);
      b->fds[i] = -1;
    }
  }
  memset(b->paths, 0, sizeof(b->paths));
  for (int i = 0; i < 64; i++) {
    b->vendors[i] = -1;
    b->products[i] = -1;
    memset(b->uuids[i], 0, sizeof(b->uuids[i]));
    memset(b->names[i], 0, sizeof(b->names[i]));
    b->ff_supported[i] = 0;
    b->rw[i] = 0;
    b->ff_id[i] = -1;
    b->ff_until_ms[i] = 0;
  }
  b->fds_len = 0;
}

static void linux_backend_poll_timeout(moon_gamepad_backend_t *b, int32_t timeout_ms);

static void linux_backend_poll(moon_gamepad_backend_t *b) {
  linux_backend_poll_timeout(b, 0);
}

static void linux_backend_poll_timeout(moon_gamepad_backend_t *b, int32_t timeout_ms) {
  if (b == NULL) {
    return;
  }
  linux_ff_tick(b);
  // Best-effort rescan for hotplug.
  linux_backend_scan(b);
  linux_compact(b);
  if (b->fds_len == 0) {
    return;
  }
  struct pollfd pfds[64];
  for (uint32_t i = 0; i < b->fds_len; i++) {
    pfds[i].fd = b->fds[i];
    pfds[i].events = POLLIN | POLLERR | POLLHUP | POLLNVAL;
    pfds[i].revents = 0;
  }
  int n = poll(pfds, (nfds_t)b->fds_len, timeout_ms);
  linux_ff_tick(b);
  if (n <= 0) {
    return;
  }
  for (uint32_t i = 0; i < b->fds_len; i++) {
    if ((pfds[i].revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
      uint32_t id = b->fd_ids[i];
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_DISCONNECTED, id, 0, 0, 0.0, now_ms()};
      queue_push(&b->q, ev);
      linux_ff_remove_idx(b, i);
      close(b->fds[i]);
      b->fds[i] = -1;
      memset(b->paths[i], 0, sizeof(b->paths[i]));
      b->vendors[i] = -1;
      b->products[i] = -1;
      memset(b->uuids[i], 0, sizeof(b->uuids[i]));
      memset(b->names[i], 0, sizeof(b->names[i]));
      b->ff_supported[i] = 0;
      b->rw[i] = 0;
      b->ff_id[i] = -1;
      b->ff_until_ms[i] = 0;
      continue;
    }
    if ((pfds[i].revents & POLLIN) == 0) {
      continue;
    }
    struct input_event ev;
    ssize_t r;
    while ((r = read(pfds[i].fd, &ev, sizeof(ev))) == (ssize_t)sizeof(ev)) {
      uint32_t id = b->fd_ids[i];
      int64_t t = now_ms();
      if (ev.type == EV_KEY) {
        uint32_t code = map_linux_btn((uint16_t)ev.code);
        if (code == UINT32_MAX) {
          continue;
        }
        moon_gamepad_event_t out;
        out.tag = (ev.value != 0) ? MOON_GAMEPAD_EV_BUTTON_PRESSED : MOON_GAMEPAD_EV_BUTTON_RELEASED;
        out.id = id;
        out.code = code;
        out.pad = 0;
        out.value = (ev.value != 0) ? 1.0 : 0.0;
        out.time_ms = t;
        queue_push(&b->q, out);
      } else if (ev.type == EV_ABS) {
        uint32_t code = map_linux_abs((uint16_t)ev.code);
        if (code == UINT32_MAX) {
          continue;
        }
        double nv = norm_linux_abs((int32_t)ev.value, (uint16_t)ev.code);
        moon_gamepad_event_t out = {MOON_GAMEPAD_EV_AXIS_CHANGED, id, code, 0, nv, t};
        queue_push(&b->q, out);
      }
    }
    if (r == 0 || (r < 0 && errno != EAGAIN && errno != EWOULDBLOCK)) {
      uint32_t id = b->fd_ids[i];
      moon_gamepad_event_t dv = {MOON_GAMEPAD_EV_DISCONNECTED, id, 0, 0, 0.0, now_ms()};
      queue_push(&b->q, dv);
      linux_ff_remove_idx(b, i);
      close(b->fds[i]);
      b->fds[i] = -1;
      memset(b->paths[i], 0, sizeof(b->paths[i]));
      b->vendors[i] = -1;
      b->products[i] = -1;
      memset(b->uuids[i], 0, sizeof(b->uuids[i]));
      memset(b->names[i], 0, sizeof(b->names[i]));
      b->ff_supported[i] = 0;
      b->rw[i] = 0;
      b->ff_id[i] = -1;
      b->ff_until_ms[i] = 0;
      continue;
    }
  }
  linux_compact(b);
}

#endif // __linux__

#if defined(_WIN32)

typedef struct XINPUT_GAMEPAD {
  uint16_t wButtons;
  uint8_t bLeftTrigger;
  uint8_t bRightTrigger;
  int16_t sThumbLX;
  int16_t sThumbLY;
  int16_t sThumbRX;
  int16_t sThumbRY;
} XINPUT_GAMEPAD;

typedef struct XINPUT_STATE {
  uint32_t dwPacketNumber;
  XINPUT_GAMEPAD Gamepad;
} XINPUT_STATE;

typedef struct XINPUT_VIBRATION {
  uint16_t wLeftMotorSpeed;
  uint16_t wRightMotorSpeed;
} XINPUT_VIBRATION;

enum {
  XINPUT_GAMEPAD_DPAD_UP = 0x0001,
  XINPUT_GAMEPAD_DPAD_DOWN = 0x0002,
  XINPUT_GAMEPAD_DPAD_LEFT = 0x0004,
  XINPUT_GAMEPAD_DPAD_RIGHT = 0x0008,
  XINPUT_GAMEPAD_START = 0x0010,
  XINPUT_GAMEPAD_BACK = 0x0020,
  XINPUT_GAMEPAD_LEFT_THUMB = 0x0040,
  XINPUT_GAMEPAD_RIGHT_THUMB = 0x0080,
  XINPUT_GAMEPAD_LEFT_SHOULDER = 0x0100,
  XINPUT_GAMEPAD_RIGHT_SHOULDER = 0x0200,
  XINPUT_GAMEPAD_A = 0x1000,
  XINPUT_GAMEPAD_B = 0x2000,
  XINPUT_GAMEPAD_X = 0x4000,
  XINPUT_GAMEPAD_Y = 0x8000,
};

typedef uint32_t(WINAPI *XInputGetStateFn)(uint32_t, XINPUT_STATE *);
typedef uint32_t(WINAPI *XInputSetStateFn)(uint32_t, XINPUT_VIBRATION *);

static XInputGetStateFn load_xinput_get_state(moon_gamepad_backend_t *b) {
  if (b == NULL) {
    return NULL;
  }
  if (b->xinput_dll == NULL) {
    b->xinput_dll = LoadLibraryA("xinput1_4.dll");
    if (b->xinput_dll == NULL) {
      b->xinput_dll = LoadLibraryA("xinput9_1_0.dll");
    }
    if (b->xinput_dll == NULL) {
      b->xinput_dll = LoadLibraryA("xinput1_3.dll");
    }
  }
  if (b->xinput_dll == NULL) {
    return NULL;
  }
  return (XInputGetStateFn)GetProcAddress(b->xinput_dll, "XInputGetState");
}

static XInputSetStateFn load_xinput_set_state(moon_gamepad_backend_t *b) {
  if (b == NULL) {
    return NULL;
  }
  if (b->xinput_dll == NULL) {
    (void)load_xinput_get_state(b);
  }
  if (b->xinput_dll == NULL) {
    return NULL;
  }
  return (XInputSetStateFn)GetProcAddress(b->xinput_dll, "XInputSetState");
}

static void windows_rumble_apply(moon_gamepad_backend_t *b, uint32_t idx, uint16_t l, uint16_t r) {
  if (b == NULL || idx >= 4) {
    return;
  }
  XInputSetStateFn set_state = load_xinput_set_state(b);
  if (set_state == NULL) {
    return;
  }
  XINPUT_VIBRATION vib;
  memset(&vib, 0, sizeof(vib));
  vib.wLeftMotorSpeed = l;
  vib.wRightMotorSpeed = r;
  (void)set_state(idx, &vib);
}

static void windows_rumble_tick(moon_gamepad_backend_t *b) {
  if (b == NULL) {
    return;
  }
  int64_t t = now_ms();
  for (uint32_t i = 0; i < 4; i++) {
    if (!b->win_connected[i]) {
      continue;
    }
    if (b->win_rumble_until_ms[i] != 0 && t >= b->win_rumble_until_ms[i]) {
      b->win_rumble_l[i] = 0;
      b->win_rumble_r[i] = 0;
      b->win_rumble_until_ms[i] = 0;
      windows_rumble_apply(b, i, 0, 0);
    }
  }
}

static int32_t windows_rumble_set_idx(moon_gamepad_backend_t *b, uint32_t idx, uint16_t l, uint16_t r,
                                     int32_t duration_ms) {
  if (b == NULL || idx >= 4) {
    return 0;
  }
  if (load_xinput_set_state(b) == NULL) {
    return 0;
  }
  if (!b->win_connected[idx]) {
    return 0;
  }
  if (duration_ms <= 0 || (l == 0 && r == 0)) {
    b->win_rumble_l[idx] = 0;
    b->win_rumble_r[idx] = 0;
    b->win_rumble_until_ms[idx] = 0;
    windows_rumble_apply(b, idx, 0, 0);
    return 1;
  }
  if (duration_ms > 600000) {
    duration_ms = 600000;
  }
  b->win_rumble_l[idx] = l;
  b->win_rumble_r[idx] = r;
  b->win_rumble_until_ms[idx] = now_ms() + (int64_t)duration_ms;
  windows_rumble_apply(b, idx, l, r);
  return 1;
}

static double norm_i16(int16_t v) {
  if (v == (int16_t)-32768) {
    return -1.0;
  }
  return (double)v / 32767.0;
}

static double norm_u8(uint8_t v) {
  return (double)v / 255.0;
}

static void push_btn_edge(moon_gamepad_backend_t *b, uint32_t id, int pressed, uint32_t code,
                          int64_t t) {
  moon_gamepad_event_t ev;
  ev.tag = pressed ? MOON_GAMEPAD_EV_BUTTON_PRESSED : MOON_GAMEPAD_EV_BUTTON_RELEASED;
  ev.id = id;
  ev.code = code;
  ev.pad = 0;
  ev.value = pressed ? 1.0 : 0.0;
  ev.time_ms = t;
  queue_push(&b->q, ev);
}

static void push_btn_diff_mask(moon_gamepad_backend_t *b, uint32_t id, uint16_t oldv, uint16_t newv,
                               uint16_t mask, uint32_t code, int64_t t) {
  int was = (oldv & mask) != 0;
  int is = (newv & mask) != 0;
  if (was == is) {
    return;
  }
  push_btn_edge(b, id, is, code, t);
}

static void windows_backend_init(moon_gamepad_backend_t *b) {
  b->xinput_dll = NULL;
  for (int i = 0; i < 4; i++) {
    b->win_connected[i] = 0;
    b->win_packet[i] = 0;
    b->win_buttons[i] = 0;
    b->win_lx[i] = b->win_ly[i] = b->win_rx[i] = b->win_ry[i] = 0;
    b->win_lt2[i] = b->win_rt2[i] = 0;
    b->win_rumble_l[i] = 0;
    b->win_rumble_r[i] = 0;
    b->win_rumble_until_ms[i] = 0;
    memset(b->win_names[i], 0, sizeof(b->win_names[i]));
    memset(b->win_uuids[i], 0, sizeof(b->win_uuids[i]));
    strncpy(b->win_uuids[i], "xinput", sizeof(b->win_uuids[i]) - 1);
    snprintf(b->win_names[i], sizeof(b->win_names[i]), "XInput Gamepad %d", i);
  }
  b->gamepad_count = 0;
}

static void windows_backend_shutdown(moon_gamepad_backend_t *b) {
  if (b == NULL) {
    return;
  }
  if (b->xinput_dll != NULL) {
    FreeLibrary(b->xinput_dll);
    b->xinput_dll = NULL;
  }
}

static void windows_backend_poll(moon_gamepad_backend_t *b) {
  if (b == NULL) {
    return;
  }
  windows_rumble_tick(b);
  XInputGetStateFn get_state = load_xinput_get_state(b);
  if (get_state == NULL) {
    return;
  }

  int32_t connected_count = 0;
  for (uint32_t idx = 0; idx < 4; idx++) {
    XINPUT_STATE st;
    memset(&st, 0, sizeof(st));
    uint32_t res = get_state(idx, &st);
    int is_connected = (res == 0);

    if (is_connected) {
      connected_count++;
    }

    if (!b->win_connected[idx] && is_connected) {
      b->win_connected[idx] = 1;
      b->win_packet[idx] = st.dwPacketNumber;
      b->win_buttons[idx] = st.Gamepad.wButtons;
      b->win_lx[idx] = st.Gamepad.sThumbLX;
      b->win_ly[idx] = st.Gamepad.sThumbLY;
      b->win_rx[idx] = st.Gamepad.sThumbRX;
      b->win_ry[idx] = st.Gamepad.sThumbRY;
      b->win_lt2[idx] = st.Gamepad.bLeftTrigger;
      b->win_rt2[idx] = st.Gamepad.bRightTrigger;
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_CONNECTED, idx, 0, 0, 0.0, now_ms()};
      queue_push(&b->q, ev);
      continue;
    }

    if (b->win_connected[idx] && !is_connected) {
      b->win_connected[idx] = 0;
      b->win_rumble_l[idx] = 0;
      b->win_rumble_r[idx] = 0;
      b->win_rumble_until_ms[idx] = 0;
      windows_rumble_apply(b, idx, 0, 0);
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_DISCONNECTED, idx, 0, 0, 0.0, now_ms()};
      queue_push(&b->q, ev);
      continue;
    }

    if (!is_connected) {
      continue;
    }

    if (b->win_packet[idx] == st.dwPacketNumber) {
      continue;
    }
    b->win_packet[idx] = st.dwPacketNumber;

    int64_t t = now_ms();

    // Digital buttons diff.
    uint16_t old_buttons = b->win_buttons[idx];
    uint16_t new_buttons = st.Gamepad.wButtons;
    b->win_buttons[idx] = new_buttons;

    push_btn_diff_mask(b, idx, old_buttons, new_buttons, XINPUT_GAMEPAD_A, CODE_BTN_SOUTH, t);
    push_btn_diff_mask(b, idx, old_buttons, new_buttons, XINPUT_GAMEPAD_B, CODE_BTN_EAST, t);
    push_btn_diff_mask(b, idx, old_buttons, new_buttons, XINPUT_GAMEPAD_X, CODE_BTN_WEST, t);
    push_btn_diff_mask(b, idx, old_buttons, new_buttons, XINPUT_GAMEPAD_Y, CODE_BTN_NORTH, t);

    push_btn_diff_mask(b, idx, old_buttons, new_buttons, XINPUT_GAMEPAD_BACK, CODE_BTN_SELECT, t);
    push_btn_diff_mask(b, idx, old_buttons, new_buttons, XINPUT_GAMEPAD_START, CODE_BTN_START, t);

    push_btn_diff_mask(b, idx, old_buttons, new_buttons, XINPUT_GAMEPAD_LEFT_SHOULDER, CODE_BTN_LT, t);
    push_btn_diff_mask(b, idx, old_buttons, new_buttons, XINPUT_GAMEPAD_RIGHT_SHOULDER, CODE_BTN_RT, t);

    push_btn_diff_mask(b, idx, old_buttons, new_buttons, XINPUT_GAMEPAD_LEFT_THUMB, CODE_BTN_LTHUMB, t);
    push_btn_diff_mask(b, idx, old_buttons, new_buttons, XINPUT_GAMEPAD_RIGHT_THUMB, CODE_BTN_RTHUMB, t);

    push_btn_diff_mask(b, idx, old_buttons, new_buttons, XINPUT_GAMEPAD_DPAD_UP, CODE_BTN_DPAD_UP, t);
    push_btn_diff_mask(b, idx, old_buttons, new_buttons, XINPUT_GAMEPAD_DPAD_DOWN, CODE_BTN_DPAD_DOWN, t);
    push_btn_diff_mask(b, idx, old_buttons, new_buttons, XINPUT_GAMEPAD_DPAD_LEFT, CODE_BTN_DPAD_LEFT, t);
    push_btn_diff_mask(b, idx, old_buttons, new_buttons, XINPUT_GAMEPAD_DPAD_RIGHT, CODE_BTN_DPAD_RIGHT, t);

    // Analog triggers -> ButtonChanged in [0, 1].
    if (b->win_lt2[idx] != st.Gamepad.bLeftTrigger) {
      b->win_lt2[idx] = st.Gamepad.bLeftTrigger;
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_BUTTON_CHANGED, idx, CODE_BTN_LT2, 0,
                                 norm_u8(st.Gamepad.bLeftTrigger), t};
      queue_push(&b->q, ev);
    }
    if (b->win_rt2[idx] != st.Gamepad.bRightTrigger) {
      b->win_rt2[idx] = st.Gamepad.bRightTrigger;
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_BUTTON_CHANGED, idx, CODE_BTN_RT2, 0,
                                 norm_u8(st.Gamepad.bRightTrigger), t};
      queue_push(&b->q, ev);
    }

    // Sticks -> AxisChanged in [-1, 1].
    if (b->win_lx[idx] != st.Gamepad.sThumbLX) {
      b->win_lx[idx] = st.Gamepad.sThumbLX;
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_AXIS_CHANGED, idx, CODE_AXIS_LSTICKX, 0,
                                 norm_i16(st.Gamepad.sThumbLX), t};
      queue_push(&b->q, ev);
    }
    if (b->win_ly[idx] != st.Gamepad.sThumbLY) {
      b->win_ly[idx] = st.Gamepad.sThumbLY;
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_AXIS_CHANGED, idx, CODE_AXIS_LSTICKY, 0,
                                 norm_i16(st.Gamepad.sThumbLY), t};
      queue_push(&b->q, ev);
    }
    if (b->win_rx[idx] != st.Gamepad.sThumbRX) {
      b->win_rx[idx] = st.Gamepad.sThumbRX;
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_AXIS_CHANGED, idx, CODE_AXIS_RSTICKX, 0,
                                 norm_i16(st.Gamepad.sThumbRX), t};
      queue_push(&b->q, ev);
    }
    if (b->win_ry[idx] != st.Gamepad.sThumbRY) {
      b->win_ry[idx] = st.Gamepad.sThumbRY;
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_AXIS_CHANGED, idx, CODE_AXIS_RSTICKY, 0,
                                 norm_i16(st.Gamepad.sThumbRY), t};
      queue_push(&b->q, ev);
    }
  }
  b->gamepad_count = connected_count;
  windows_rumble_tick(b);
}

static void windows_backend_poll_timeout(moon_gamepad_backend_t *b, int32_t timeout_ms) {
  if (b == NULL) {
    return;
  }
  if (timeout_ms == 0) {
    windows_backend_poll(b);
    return;
  }
  int64_t start = now_ms();
  while (1) {
    windows_backend_poll(b);
    if (queue_len(&b->q) != 0) {
      return;
    }
    if (timeout_ms < 0) {
      Sleep(8);
      continue;
    }
    int64_t elapsed = now_ms() - start;
    if (elapsed >= (int64_t)timeout_ms) {
      return;
    }
    int64_t remaining = (int64_t)timeout_ms - elapsed;
    DWORD sleep_ms = (remaining > 8) ? 8 : (DWORD)remaining;
    Sleep(sleep_ms);
  }
}

#endif // _WIN32

// -----------------------------------------------------------------------------
// MoonBit extern API
// -----------------------------------------------------------------------------

typedef struct moon_gamepad_backend_owner_payload_t {
  moon_gamepad_backend_t *b;
} moon_gamepad_backend_owner_payload_t;

static void backend_finalize(void *self) {
  moon_gamepad_backend_owner_payload_t *p = (moon_gamepad_backend_owner_payload_t *)self;
  if (p == NULL) {
    return;
  }
  if (p->b != NULL) {
#if defined(__APPLE__)
    mac_backend_shutdown(p->b);
#endif
#if defined(__linux__)
    linux_backend_shutdown(p->b);
#endif
#if defined(_WIN32)
    windows_backend_shutdown(p->b);
#endif
    queue_free(&p->b->q);
    free(p->b);
    p->b = NULL;
  }
}

void *moon_gamepad_backend_new(void) {
  moon_gamepad_backend_owner_payload_t *p = (moon_gamepad_backend_owner_payload_t *)moonbit_make_external_object(
      backend_finalize, (uint32_t)sizeof(*p));
  if (p == NULL) {
    return NULL;
  }
  p->b = (moon_gamepad_backend_t *)calloc(1, sizeof(moon_gamepad_backend_t));
  if (p->b == NULL) {
    return p;
  }
  queue_init(&p->b->q, 1024);
  p->b->gamepad_count = 0;

#if defined(__APPLE__)
  mac_backend_init(p->b);
#elif defined(__linux__)
  linux_backend_init(p->b);
#elif defined(_WIN32)
  windows_backend_init(p->b);
#else
  // Other native targets: not implemented.
  (void)p;
#endif
  return p;
}

static moon_gamepad_backend_t *backend_of(void *owner) {
  moon_gamepad_backend_owner_payload_t *p = (moon_gamepad_backend_owner_payload_t *)owner;
  if (p == NULL) {
    return NULL;
  }
  return p->b;
}

void moon_gamepad_backend_poll(void *owner) {
  moon_gamepad_backend_t *b = backend_of(owner);
  if (b == NULL) {
    return;
  }
#if defined(__linux__)
  linux_backend_poll(b);
#elif defined(_WIN32)
  windows_backend_poll(b);
#else
  (void)b;
#endif
}

void moon_gamepad_backend_poll_timeout(void *owner, int32_t timeout_ms) {
  moon_gamepad_backend_t *b = backend_of(owner);
  if (b == NULL) {
    return;
  }
#if defined(__APPLE__)
  queue_wait_nonempty(&b->q, timeout_ms);
#elif defined(__linux__)
  linux_backend_poll_timeout(b, timeout_ms);
#elif defined(_WIN32)
  windows_backend_poll_timeout(b, timeout_ms);
#else
  (void)b;
  (void)timeout_ms;
#endif
}

int32_t moon_gamepad_backend_gamepad_count(void *owner) {
  moon_gamepad_backend_t *b = backend_of(owner);
  if (b == NULL) {
    return 0;
  }
  return b->gamepad_count;
}

static int idx_by_id_u32(const uint32_t *ids, uint32_t len, uint32_t id) {
  for (uint32_t i = 0; i < len; i++) {
    if (ids[i] == id) {
      return (int)i;
    }
  }
  return -1;
}

moonbit_string_t moon_gamepad_backend_name(void *owner, int32_t id) {
  moon_gamepad_backend_t *b = backend_of(owner);
  if (b == NULL || id < 0) {
    return moonbit_make_string_raw(0);
  }
#if defined(__APPLE__)
  int idx = idx_by_id_u32(b->device_ids, b->devices_len, (uint32_t)id);
  if (idx < 0) {
    return moonbit_make_string_raw(0);
  }
  return moonbit_string_from_utf8_lossy(b->names[(uint32_t)idx]);
#elif defined(__linux__)
  int idx = idx_by_id_u32(b->fd_ids, b->fds_len, (uint32_t)id);
  if (idx < 0) {
    return moonbit_make_string_raw(0);
  }
  return moonbit_string_from_utf8_lossy(b->names[(uint32_t)idx]);
#elif defined(_WIN32)
  if ((uint32_t)id >= 4) {
    return moonbit_make_string_raw(0);
  }
  return moonbit_string_from_utf8_lossy(b->win_names[(uint32_t)id]);
#else
  (void)b;
  (void)id;
  return moonbit_make_string_raw(0);
#endif
}

moonbit_string_t moon_gamepad_backend_uuid_simple(void *owner, int32_t id) {
  moon_gamepad_backend_t *b = backend_of(owner);
  if (b == NULL || id < 0) {
    return moonbit_make_string_raw(0);
  }
#if defined(__APPLE__)
  int idx = idx_by_id_u32(b->device_ids, b->devices_len, (uint32_t)id);
  if (idx < 0) {
    return moonbit_make_string_raw(0);
  }
  return moonbit_string_from_utf8_lossy(b->uuids[(uint32_t)idx]);
#elif defined(__linux__)
  int idx = idx_by_id_u32(b->fd_ids, b->fds_len, (uint32_t)id);
  if (idx < 0) {
    return moonbit_make_string_raw(0);
  }
  return moonbit_string_from_utf8_lossy(b->uuids[(uint32_t)idx]);
#elif defined(_WIN32)
  if ((uint32_t)id >= 4) {
    return moonbit_make_string_raw(0);
  }
  return moonbit_string_from_utf8_lossy(b->win_uuids[(uint32_t)id]);
#else
  (void)b;
  (void)id;
  return moonbit_make_string_raw(0);
#endif
}

int32_t moon_gamepad_backend_vendor_id(void *owner, int32_t id) {
  moon_gamepad_backend_t *b = backend_of(owner);
  if (b == NULL || id < 0) {
    return -1;
  }
#if defined(__APPLE__)
  int idx = idx_by_id_u32(b->device_ids, b->devices_len, (uint32_t)id);
  if (idx < 0) {
    return -1;
  }
  return b->vendors[(uint32_t)idx];
#elif defined(__linux__)
  int idx = idx_by_id_u32(b->fd_ids, b->fds_len, (uint32_t)id);
  if (idx < 0) {
    return -1;
  }
  return b->vendors[(uint32_t)idx];
#else
  (void)b;
  (void)id;
  return -1;
#endif
}

int32_t moon_gamepad_backend_product_id(void *owner, int32_t id) {
  moon_gamepad_backend_t *b = backend_of(owner);
  if (b == NULL || id < 0) {
    return -1;
  }
#if defined(__APPLE__)
  int idx = idx_by_id_u32(b->device_ids, b->devices_len, (uint32_t)id);
  if (idx < 0) {
    return -1;
  }
  return b->products[(uint32_t)idx];
#elif defined(__linux__)
  int idx = idx_by_id_u32(b->fd_ids, b->fds_len, (uint32_t)id);
  if (idx < 0) {
    return -1;
  }
  return b->products[(uint32_t)idx];
#else
  (void)b;
  (void)id;
  return -1;
#endif
}

int32_t moon_gamepad_backend_is_ff_supported(void *owner, int32_t id) {
  moon_gamepad_backend_t *b = backend_of(owner);
  if (b == NULL || id < 0) {
    return 0;
  }
#if defined(__linux__)
  int idx = idx_by_id_u32(b->fd_ids, b->fds_len, (uint32_t)id);
  if (idx < 0) {
    return 0;
  }
  return (int32_t)b->ff_supported[(uint32_t)idx];
#elif defined(_WIN32)
  if ((uint32_t)id >= 4) {
    return 0;
  }
  return load_xinput_set_state(b) != NULL;
#else
  (void)b;
  (void)id;
  return 0;
#endif
}

moonbit_bytes_t moon_gamepad_backend_axes_bin(void *owner, int32_t id) {
  moon_gamepad_backend_t *b = backend_of(owner);
  if (b == NULL || id < 0) {
    return moonbit_make_bytes_raw(0);
  }
#if defined(__APPLE__)
  int idx = idx_by_id_u32(b->device_ids, b->devices_len, (uint32_t)id);
  if (idx < 0) {
    return moonbit_make_bytes_raw(0);
  }
  uint8_t len = b->axes_len[(uint32_t)idx];
  moonbit_bytes_t out = moonbit_make_bytes_raw((int32_t)len * 4);
  if (out == NULL) {
    return moonbit_make_bytes_raw(0);
  }
  for (uint8_t i = 0; i < len; i++) {
    int32_t v = b->axes_codes[(uint32_t)idx][i];
    memcpy(out + (int32_t)i * 4, &v, 4);
  }
  return out;
#else
  (void)b;
  (void)id;
  return moonbit_make_bytes_raw(0);
#endif
}

moonbit_bytes_t moon_gamepad_backend_buttons_bin(void *owner, int32_t id) {
  moon_gamepad_backend_t *b = backend_of(owner);
  if (b == NULL || id < 0) {
    return moonbit_make_bytes_raw(0);
  }
#if defined(__APPLE__)
  int idx = idx_by_id_u32(b->device_ids, b->devices_len, (uint32_t)id);
  if (idx < 0) {
    return moonbit_make_bytes_raw(0);
  }
  uint8_t len = b->buttons_len[(uint32_t)idx];
  moonbit_bytes_t out = moonbit_make_bytes_raw((int32_t)len * 4);
  if (out == NULL) {
    return moonbit_make_bytes_raw(0);
  }
  for (uint8_t i = 0; i < len; i++) {
    int32_t v = b->buttons_codes[(uint32_t)idx][i];
    memcpy(out + (int32_t)i * 4, &v, 4);
  }
  return out;
#else
  (void)b;
  (void)id;
  return moonbit_make_bytes_raw(0);
#endif
}

moonbit_bytes_t moon_gamepad_backend_axis_info_bin(void *owner, int32_t id, int32_t code) {
  moon_gamepad_backend_t *b = backend_of(owner);
  if (b == NULL || id < 0) {
    return moonbit_make_bytes_raw(0);
  }
#if defined(__APPLE__)
  int idx = idx_by_id_u32(b->device_ids, b->devices_len, (uint32_t)id);
  if (idx < 0) {
    return moonbit_make_bytes_raw(0);
  }
  int32_t present = 0;
  int32_t minv = 0;
  int32_t maxv = 0;
  uint8_t len = b->axis_info_len[(uint32_t)idx];
  for (uint8_t i = 0; i < len; i++) {
    if (b->axis_info_codes[(uint32_t)idx][i] == code) {
      present = 1;
      minv = b->axis_info_min[(uint32_t)idx][i];
      maxv = b->axis_info_max[(uint32_t)idx][i];
      break;
    }
  }
  moonbit_bytes_t out = moonbit_make_bytes_raw(12);
  if (out == NULL) {
    return moonbit_make_bytes_raw(0);
  }
  memcpy(out + 0, &present, 4);
  memcpy(out + 4, &minv, 4);
  memcpy(out + 8, &maxv, 4);
  return out;
#else
  (void)b;
  (void)id;
  (void)code;
  return moonbit_make_bytes_raw(0);
#endif
}

static uint16_t amp_to_u16(double x) {
  if (x < 0.0) {
    x = 0.0;
  }
  if (x > 1.0) {
    x = 1.0;
  }
  double v = x * 65535.0;
  if (v < 0.0) {
    v = 0.0;
  }
  if (v > 65535.0) {
    v = 65535.0;
  }
  return (uint16_t)(v + 0.5);
}

int32_t moon_gamepad_backend_set_rumble(void *owner, int32_t id, double strong, double weak, int32_t duration_ms) {
  moon_gamepad_backend_t *b = backend_of(owner);
  if (b == NULL || id < 0) {
    return 0;
  }
  uint16_t s = amp_to_u16(strong);
  uint16_t w = amp_to_u16(weak);
#if defined(__linux__)
  int idx = idx_by_id_u32(b->fd_ids, b->fds_len, (uint32_t)id);
  if (idx < 0) {
    return 0;
  }
  return linux_ff_set_rumble_idx(b, (uint32_t)idx, s, w, duration_ms);
#elif defined(_WIN32)
  if ((uint32_t)id >= 4) {
    return 0;
  }
  return windows_rumble_set_idx(b, (uint32_t)id, s, w, duration_ms);
#else
  (void)s;
  (void)w;
  (void)duration_ms;
  return 0;
#endif
}

// Returns Bytes. Empty bytes => None.
moonbit_bytes_t moon_gamepad_backend_next_event_bin(void *owner) {
  moon_gamepad_backend_t *b = backend_of(owner);
  if (b == NULL) {
    return moonbit_make_bytes_raw(0);
  }
  moon_gamepad_event_t ev;
  if (!queue_pop(&b->q, &ev)) {
    return moonbit_make_bytes_raw(0);
  }
  moonbit_bytes_t out = moonbit_make_bytes_raw((int32_t)sizeof(ev));
  if (out == NULL) {
    return moonbit_make_bytes_raw(0);
  }
  memcpy(out, &ev, sizeof(ev));
  return out;
}
