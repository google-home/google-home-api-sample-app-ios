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

class DeviceControl: ObservableObject, Identifiable {
  /// Unique identifier to tag the device in collection views
  let id: String

  /// The device this is controlling.
  let device: HomeDevice

  /// Color palette to use in UI elements.
  var colorPalette: ColorPalette { .default }

  /// Whether the device requires a PIN code for the primary action.
  var requiresPINCode: Bool { false }

  /// An optional binding to a boolean value representing the state of the device.
  /// If nil, the device does not have a toggle control.
  @Published var toggleControl: ToggleControl?

  /// Range information for the device. Used for devices with a level control.
  @Published var rangeControl: RangeControl?

  /// Additional RangeControl.
  @Published var rangeControl2: RangeControl?

  /// Dropdown information for the device. Used for devices with a mode control.
  @Published var dropdownControl: DropdownControl?

  /// Button group information for the device.
  @Published var buttonGroupControl: ButtonGroupControl?

  /// Represents the device's current state that should be presented in the UI.
  @Published var tileInfo: DeviceTileInfo =
    DeviceTileInfo(
      title: "Loading",
      typeName: "Loading",
      imageName: "",
      isActive: false,
      isBusy: true,
      statusLabel: "Loading",
      attributes: [],
      error: nil)

  // MARK: - Abstract Methods

  /// Set the PIN code. Only applicable if `requiresPINCode` is `true`.
  open func setPINCode(_ code: String) {
    fatalError("\(self) does not support PIN Codes.")
  }

  init(device: HomeDevice) throws {
    self.device = device
    self.id = device.id
  }
}
