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
import GoogleHomeSDK
import GoogleHomeTypes

/// An instance of `DeviceControl` representing a generic instance, provided a device type.
final class GenericDeviceControl: DeviceControl {
  @Published private(set) var isBusy = false

  // MARK: - Initialization

  override init(device: HomeDevice) throws {
    try super.init(device: device)
    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      imageName: self.imageName,
      isActive: false,
      isBusy: false,
      statusLabel: "Unsupported",
      error: nil
    )
  }

  // MARK: - DeviceControl

  override func primaryAction() {
    // Intentionally empty, no actions are supported by generic control.
  }

  // MARK: - Private

  // A mapping from any provided device types to icon names.
  private var imageName: String {
    return "devices_other_symbol"

  }
}
