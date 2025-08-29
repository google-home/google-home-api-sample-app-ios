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

/// An 'add-on' to the DeviceControl that trigger action after user tap on buttons.
struct ButtonGroupItem: Identifiable {
  let id = UUID()
  let label: String
  let isDisplayed: Bool
  let disabled: Bool
  let action: () -> Void
}

class ButtonGroupControl: ObservableObject {
  @Published var buttons: [ButtonGroupItem]

  init(buttons: [ButtonGroupItem]) {
    self.buttons = buttons
  }
}
