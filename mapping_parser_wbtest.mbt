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
test "full SDL corpus parses without non-empty parser errors" {
  let mut errors = 0
  let mut parsed = 0
  for line in sdl_gamecontrollerdb_lines {
    if line.is_blank() || line.has_prefix("#") {
      continue
    }
    parsed = parsed + 1
    errors = errors + non_empty_parser_errors(line)
  }
  inspect(parsed > 1000, content="true")
  inspect(errors, content="0")
}
