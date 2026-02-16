// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
extern "C" fn uuid_simple_from_ids_for_test(
  bustype : Int,
  vendor : Int,
  product : Int,
  version : Int,
) -> String = "moon_gamepad_uuid_simple_from_ids"

///|
test "uuid from ids matches gilrs SDL layout sample" {
  let got = uuid_simple_from_ids_for_test(0x3, 0x045e, 0x028e, 0x2020)
  inspect(got, content="030000005e0400008e02000020200000")
}

///|
extern "C" fn macos_hat_pack_for_test(
  hat_v : Int,
  hat_min : Int,
  hat_max : Int,
) -> Int = "moon_gamepad_macos_hat_pack_for_test"

///|
fn unpack_hat(pack : Int) -> (Int, Int) {
  let x = (pack & 0x3) - 2
  let y = ((pack >> 2) & 0x3) - 2
  (x, y)
}

///|
test "macOS hat mapping (8 positions) matches gilrs-core directional layout" {
  if runtime_sdl_platform_name() != "Mac OS X" {
    inspect(true, content="true")
    return
  }
  inspect(
    [
      unpack_hat(macos_hat_pack_for_test(0, 0, 7)),
      unpack_hat(macos_hat_pack_for_test(1, 0, 7)),
      unpack_hat(macos_hat_pack_for_test(2, 0, 7)),
      unpack_hat(macos_hat_pack_for_test(3, 0, 7)),
      unpack_hat(macos_hat_pack_for_test(4, 0, 7)),
      unpack_hat(macos_hat_pack_for_test(5, 0, 7)),
      unpack_hat(macos_hat_pack_for_test(6, 0, 7)),
      unpack_hat(macos_hat_pack_for_test(7, 0, 7)),
    ],
    content="[(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]",
  )
}

///|
test "macOS hat mapping (4 positions) is scaled to 8-position semantics" {
  if runtime_sdl_platform_name() != "Mac OS X" {
    inspect(true, content="true")
    return
  }
  inspect(
    [
      unpack_hat(macos_hat_pack_for_test(0, 0, 3)),
      unpack_hat(macos_hat_pack_for_test(1, 0, 3)),
      unpack_hat(macos_hat_pack_for_test(2, 0, 3)),
      unpack_hat(macos_hat_pack_for_test(3, 0, 3)),
    ],
    content="[(0, -1), (1, 0), (0, 1), (-1, 0)]",
  )
}

///|
test "macOS hat mapping supports shifted min/max ranges" {
  if runtime_sdl_platform_name() != "Mac OS X" {
    inspect(true, content="true")
    return
  }
  inspect(
    [
      unpack_hat(macos_hat_pack_for_test(1, 1, 8)),
      unpack_hat(macos_hat_pack_for_test(5, 1, 8)),
    ],
    content="[(0, -1), (0, 1)]",
  )
}

///|
test "macOS hat mapping falls back to center for unsupported range sizes" {
  if runtime_sdl_platform_name() != "Mac OS X" {
    inspect(true, content="true")
    return
  }
  inspect(unpack_hat(macos_hat_pack_for_test(3, 0, 5)), content="(0, 0)")
}
