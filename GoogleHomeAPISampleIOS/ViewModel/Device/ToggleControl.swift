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

import Foundation
import SwiftUI

// An 'add-on' to the DeviceControl that handles toggle functions.
class ToggleControl: ObservableObject {
  let label: String
  let description: String
  let action: () -> Void
  @Published var isOn: Bool

  init(isOn: Bool, label: String, description: String, action: @escaping () -> Void) {
    self.isOn = isOn
    self.label = label
    self.description = description
    self.action = action
  }
}
