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
