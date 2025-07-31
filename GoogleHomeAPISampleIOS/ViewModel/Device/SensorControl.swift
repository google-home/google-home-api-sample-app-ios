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
import GoogleHomeSDK

/// An instance of `DeviceControl` that serves as the base class for all sensor controls.
/// Should NOT be instantiated directly.
class SensorControl<T: DeviceType>: DeviceControl {
  var cancellable: AnyCancellable?
  var sensorDeviceType: T?
  // MARK: - Initialization
  public override init(device: HomeDevice) throws {
    try super.init(device: device)

    self.tileInfo = DeviceTileInfo(
      title: device.name,
      typeName: "Sensor",
      imageName: "sensors_symbol",
      isActive: false,
      isBusy: true,
      statusLabel: "Loading",
      attributes: [],
      error: nil
    )

    self.cancellable = self.device.types.subscribe(T.self)
      .receive(on: DispatchQueue.main)
      .catch { [weak self] error in
        self?.tileInfo = DeviceTileInfo.make(forError: error)
        return Empty<T, Never>()
      }
      .sink { [weak self] deviceType in
        guard let self = self else { return }
        self.sensorDeviceType = deviceType
        self.updateTileInfo()
      }
  }
  // MARK: - DeviceControl

  /// Provided to the generic publisher to convert from an event to the `DeviceTileInfo` state.
  func updateTileInfo() {
    fatalError("Must be implemented by subclass.")
  }
}
