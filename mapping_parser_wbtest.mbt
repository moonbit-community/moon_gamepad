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
fn non_empty_parser_errors(line : String) -> Int {
  let parser = Parser::new(line)
  let mut errors = 0
  while true {
    let token : Result[Token?, ParserError] = try? parser.next_token()
    match token {
      Ok(None) => break
      Ok(Some(_)) => ()
      Err(e) =>
        match e {
          ParserError::Error(ParserErrorKind::EmptyValue, _) => ()
          ParserError::Error(ParserErrorKind::InvalidParserState, _) => {
            errors += 1
            break
          }
          _ => errors += 1
        }
    }
  }
  errors
}

///|
test "representative SDL lines parse without non-empty parser errors" {
  let lines = [
    "03000000260900008888000000010001,GameCube {WiseGroup USB box},a:b0,b:b2,y:b3,x:b1,start:b7,rightshoulder:b6,dpup:h0.1,dpleft:h0.8,dpdown:h0.4,dpright:h0.2,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:a4,righttrigger:a5,",
    "030000005e0400008e02000010010000,Microsoft X-Box 360 pad,a:b0,b:b1,x:b2,y:b3,start:b7,guide:,back:b6,leftshoulder:b4,rightshoulder:b5,leftx:a0,lefty:a1,rightx:a3,righty:a4,dpup:h0.1,dpright:h0.2,dpdown:h0.4,dpleft:h0.8,",
    "03000000c82d00000190000011010000,8BitDo SN30 Pro,a:b1,b:b0,x:b4,y:b3,start:b11,back:b10,leftshoulder:b6,rightshoulder:b7,lefttrigger:b8,righttrigger:b9,leftx:a0,lefty:a1,rightx:a2,righty:a5,dpup:b13,dpright:b16,dpdown:b14,dpleft:b15,platform:Mac OS X,",
    "03000000de280000ff11000001000000,Example Controller,a:b0,b:b1,x:b2,y:b3,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:a4,righttrigger:a5,",
  ]
  let mut errors = 0
  for line in lines {
    errors = errors + non_empty_parser_errors(line)
  }
  inspect(errors, content="0")
}
