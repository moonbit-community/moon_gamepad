#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "moonbit.h"

#include "backend.h"

#if defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDLib.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <IOKit/hid/IOHIDManager.h>
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
#include <unistd.h>
#endif

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
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
#endif
}

static void queue_free(moon_gamepad_queue_t *q) {
  if (q->buf != NULL) {
    free(q->buf);
    q->buf = NULL;
  }
#if defined(__APPLE__)
  pthread_mutex_destroy(&q->mu);
#endif
  q->cap = 0;
  q->head = q->tail = q->len = 0;
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
  // Simple device list.
  IOHIDDeviceRef devices[32];
  uint32_t device_ids[32];
  uint32_t devices_len;
  uint32_t next_id;
  // DPad hat state per id.
  int8_t dpad_x[32];
  int8_t dpad_y[32];
#endif

#if defined(__linux__)
  int fds[64];
  uint32_t fd_ids[64];
  char paths[64][256];
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

static uint32_t map_hid_button_usage(uint32_t usage) {
  // Best-effort, common HID gamepad layouts.
  switch (usage) {
  case 1:
    return CODE_BTN_SOUTH;
  case 2:
    return CODE_BTN_EAST;
  case 3:
    return CODE_BTN_WEST;
  case 4:
    return CODE_BTN_NORTH;
  case 5:
    return CODE_BTN_LT;
  case 6:
    return CODE_BTN_RT;
  case 7:
    return CODE_BTN_LT2;
  case 8:
    return CODE_BTN_RT2;
  case 9:
    return CODE_BTN_SELECT;
  case 10:
    return CODE_BTN_START;
  case 11:
    return CODE_BTN_MODE;
  case 12:
    return CODE_BTN_LTHUMB;
  case 13:
    return CODE_BTN_RTHUMB;
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
    return CODE_AXIS_LEFTZ;
  case 0x33:
    return CODE_AXIS_RSTICKX;
  case 0x34:
    return CODE_AXIS_RSTICKY;
  case 0x35:
    return CODE_AXIS_RIGHTZ;
  default:
    return UINT32_MAX;
  }
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

static void push_dpad_buttons(moon_gamepad_backend_t *b, uint32_t id, int8_t x, int8_t y,
                              int64_t t) {
  if (id >= 32) {
    return;
  }
  int8_t ox = b->dpad_x[id];
  int8_t oy = b->dpad_y[id];
  b->dpad_x[id] = x;
  b->dpad_y[id] = y;

  // Left/right
  if (ox != x) {
    if (ox < 0) {
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_BUTTON_RELEASED, id, CODE_BTN_DPAD_LEFT, 0, 0.0,
                                 t};
      queue_push(&b->q, ev);
    } else if (ox > 0) {
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_BUTTON_RELEASED, id, CODE_BTN_DPAD_RIGHT, 0, 0.0,
                                 t};
      queue_push(&b->q, ev);
    }
    if (x < 0) {
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_BUTTON_PRESSED, id, CODE_BTN_DPAD_LEFT, 0, 0.0,
                                 t};
      queue_push(&b->q, ev);
    } else if (x > 0) {
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_BUTTON_PRESSED, id, CODE_BTN_DPAD_RIGHT, 0, 0.0,
                                 t};
      queue_push(&b->q, ev);
    }
  }

  // Up/down
  if (oy != y) {
    if (oy < 0) {
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_BUTTON_RELEASED, id, CODE_BTN_DPAD_UP, 0, 0.0, t};
      queue_push(&b->q, ev);
    } else if (oy > 0) {
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_BUTTON_RELEASED, id, CODE_BTN_DPAD_DOWN, 0, 0.0,
                                 t};
      queue_push(&b->q, ev);
    }
    if (y < 0) {
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_BUTTON_PRESSED, id, CODE_BTN_DPAD_UP, 0, 0.0, t};
      queue_push(&b->q, ev);
    } else if (y > 0) {
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_BUTTON_PRESSED, id, CODE_BTN_DPAD_DOWN, 0, 0.0, t};
      queue_push(&b->q, ev);
    }
  }
}

static void device_matching_cb(void *ctx, IOReturn res, void *sender, IOHIDDeviceRef device) {
  (void)res;
  (void)sender;
  moon_gamepad_backend_t *b = (moon_gamepad_backend_t *)ctx;
  if (b == NULL || device == NULL) {
    return;
  }
  if (b->devices_len >= 32) {
    return;
  }
  // Retain device while stored.
  CFRetain(device);
  uint32_t id = b->next_id++;
  b->devices[b->devices_len] = device;
  b->device_ids[b->devices_len] = id;
  b->devices_len++;
  b->gamepad_count = (int32_t)b->devices_len;
  b->dpad_x[id] = 0;
  b->dpad_y[id] = 0;
  moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_CONNECTED, id, 0, 0, 0.0, now_ms()};
  queue_push(&b->q, ev);
}

static void device_removal_cb(void *ctx, IOReturn res, void *sender, IOHIDDeviceRef device) {
  (void)res;
  (void)sender;
  moon_gamepad_backend_t *b = (moon_gamepad_backend_t *)ctx;
  if (b == NULL || device == NULL) {
    return;
  }
  int idx = find_device_idx(b, device);
  if (idx < 0) {
    return;
  }
  uint32_t id = b->device_ids[(uint32_t)idx];
  // Remove by swap-with-last.
  uint32_t last = b->devices_len - 1;
  IOHIDDeviceRef d = b->devices[(uint32_t)idx];
  if (d != NULL) {
    CFRelease(d);
  }
  if ((uint32_t)idx != last) {
    b->devices[(uint32_t)idx] = b->devices[last];
    b->device_ids[(uint32_t)idx] = b->device_ids[last];
  }
  b->devices[last] = NULL;
  b->device_ids[last] = 0;
  b->devices_len--;
  b->gamepad_count = (int32_t)b->devices_len;
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
  uint32_t id = device_id_of(b, dev);
  if (id == UINT32_MAX) {
    return;
  }
  IOHIDElementRef el = IOHIDValueGetElement(value);
  if (el == NULL) {
    return;
  }
  uint32_t page = IOHIDElementGetUsagePage(el);
  uint32_t usage = IOHIDElementGetUsage(el);
  int64_t t = now_ms();

  // Buttons page 0x09
  if (page == 0x09) {
    uint32_t code = map_hid_button_usage(usage);
    if (code == UINT32_MAX) {
      return;
    }
    int32_t v = (int32_t)IOHIDValueGetIntegerValue(value);
    moon_gamepad_event_t ev;
    if (v != 0) {
      ev.tag = MOON_GAMEPAD_EV_BUTTON_PRESSED;
    } else {
      ev.tag = MOON_GAMEPAD_EV_BUTTON_RELEASED;
    }
    ev.id = id;
    ev.code = code;
    ev.pad = 0;
    ev.value = (v != 0) ? 1.0 : 0.0;
    ev.time_ms = t;
    queue_push(&b->q, ev);
    return;
  }

  // Generic Desktop page 0x01
  if (page == 0x01) {
    if (usage == 0x39) {
      // Hat switch: 0..7 directions, 8 == neutral.
      int32_t v = (int32_t)IOHIDValueGetIntegerValue(value);
      int8_t x = 0;
      int8_t y = 0;
      // map: 0 up, 1 up-right, 2 right, 3 down-right, 4 down, 5 down-left, 6 left, 7 up-left.
      switch (v) {
      case 0:
        y = -1;
        break;
      case 1:
        y = -1;
        x = 1;
        break;
      case 2:
        x = 1;
        break;
      case 3:
        y = 1;
        x = 1;
        break;
      case 4:
        y = 1;
        break;
      case 5:
        y = 1;
        x = -1;
        break;
      case 6:
        x = -1;
        break;
      case 7:
        y = -1;
        x = -1;
        break;
      default:
        x = 0;
        y = 0;
        break;
      }
      push_dpad_buttons(b, id, x, y, t);
      // Also expose axes for filters/consumers.
      moon_gamepad_event_t ex = {MOON_GAMEPAD_EV_AXIS_CHANGED, id, CODE_AXIS_DPADX, 0, (double)x, t};
      moon_gamepad_event_t ey = {MOON_GAMEPAD_EV_AXIS_CHANGED, id, CODE_AXIS_DPADY, 0, (double)y, t};
      queue_push(&b->q, ex);
      queue_push(&b->q, ey);
      return;
    }

    uint32_t code = map_hid_gd_usage_to_axis(usage);
    if (code == UINT32_MAX) {
      return;
    }
    int32_t v = (int32_t)IOHIDValueGetIntegerValue(value);
    int32_t minv = (int32_t)IOHIDElementGetLogicalMin(el);
    int32_t maxv = (int32_t)IOHIDElementGetLogicalMax(el);
    double nv = norm_i32(v, minv, maxv);
    moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_AXIS_CHANGED, id, code, 0, nv, t};
    queue_push(&b->q, ev);
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
  memset(b->devices, 0, sizeof(b->devices));
  memset(b->device_ids, 0, sizeof(b->device_ids));
  memset(b->dpad_x, 0, sizeof(b->dpad_x));
  memset(b->dpad_y, 0, sizeof(b->dpad_y));
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
    int fd = open(path, O_RDONLY | O_NONBLOCK);
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
  linux_backend_scan(b);
}

static void linux_backend_shutdown(moon_gamepad_backend_t *b) {
  if (b == NULL) {
    return;
  }
  for (uint32_t i = 0; i < b->fds_len; i++) {
    if (b->fds[i] >= 0) {
      close(b->fds[i]);
      b->fds[i] = -1;
    }
  }
  memset(b->paths, 0, sizeof(b->paths));
  b->fds_len = 0;
}

static void linux_backend_poll(moon_gamepad_backend_t *b) {
  if (b == NULL) {
    return;
  }
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
  int n = poll(pfds, (nfds_t)b->fds_len, 0);
  if (n <= 0) {
    return;
  }
  for (uint32_t i = 0; i < b->fds_len; i++) {
    if ((pfds[i].revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
      uint32_t id = b->fd_ids[i];
      moon_gamepad_event_t ev = {MOON_GAMEPAD_EV_DISCONNECTED, id, 0, 0, 0.0, now_ms()};
      queue_push(&b->q, ev);
      close(b->fds[i]);
      b->fds[i] = -1;
      memset(b->paths[i], 0, sizeof(b->paths[i]));
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
      close(b->fds[i]);
      b->fds[i] = -1;
      memset(b->paths[i], 0, sizeof(b->paths[i]));
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

int32_t moon_gamepad_backend_gamepad_count(void *owner) {
  moon_gamepad_backend_t *b = backend_of(owner);
  if (b == NULL) {
    return 0;
  }
  return b->gamepad_count;
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
