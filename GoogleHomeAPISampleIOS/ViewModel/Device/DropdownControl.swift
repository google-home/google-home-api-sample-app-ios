// Copyright 2025 Google LLC
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

import Combine
import Foundation
import GoogleHomeSDK
import GoogleHomeTypes

// An 'add-on' to the DeviceControl that handles dropdown selection functions.
class DropdownControl: ObservableObject {
  let label: String
  let options: [String]
  @Published var selection: String

  init(label: String, options: [String], selection: String) {
    self.label = label
    self.options = options
    self.selection = selection
  }
}

extension Matter.FanControlTrait {
  func makeDropdownControl(options: [String], selection: String)
    -> DropdownControl?
  {
    guard self.attributes.$fanMode.isSupported else {
      return nil
    }

    return DropdownControl(
      label: "Fan mode",
      options: options,
      selection: selection
    )
  }
}

extension Matter.ThermostatTrait {
  func makeDropdownControl(options: [String], selection: String)
    -> DropdownControl?
  {
    guard self.attributes.$systemMode.isSupported else {
      return nil
    }

    return DropdownControl(
      label: "System mode",
      options: options,
      selection: selection
    )
  }
}
