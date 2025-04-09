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
import Dispatch
import Foundation
import GoogleHomeSDK
import OSLog

class DeviceControl: ObservableObject {
  /// Unique identifier to tag the device in collection views
  let id: String

  /// The device this is controlling.
  let device: HomeDevice

  /// Color palette to use in UI elements.
  var colorPalette: ColorPalette { .default }

  /// Whether the device requires a PIN code for the primary action.
  var requiresPINCode: Bool { false }

  /// Range information for the device. Used for devices with a level control.
  @Published var rangeControl: RangeControl?

  /// Represents the device's current state that should be presented in the UI.
  @Published var tileInfo: DeviceTileInfo =
    DeviceTileInfo(
      title: "Loading",
      imageName: "",
      isActive: false,
      isBusy: true,
      statusLabel: "Loading",
      error: nil)

  // MARK: - Abstract Methods

  /// Performs the action associated with a simple tap on the device view's main button, e.g.
  /// toggling lights. Should be implemented by subclasses.
  func primaryAction() {
    fatalError("Must be implemented by subclass")
  }

  /// Set the PIN code. Only applicable if `requiresPINCode` is `true`.
  open func setPINCode(_ code: String) {
    fatalError("\(self) does not support PIN Codes.")
  }

  init(device: HomeDevice) throws {
    self.device = device
    self.id = device.id
  }

}
