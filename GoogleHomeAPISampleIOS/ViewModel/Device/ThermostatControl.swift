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
import GoogleHomeTypes
import OSLog

/// An instance of `DeviceControl` for a Thermostat device.
final class ThermostatControl: DeviceControl {

  private var thermostatDeviceType: ThermostatDeviceType?
  var cancellable: AnyCancellable?

  // MARK: - Initialization

  public override init(device: HomeDevice) throws {
    guard device.types.contains(ThermostatDeviceType.self) else {
      throw HomeSampleError.unableToCreateControlForDeviceType(deviceType: "ThermostatControl")
    }
    try super.init(device: device)

    self.tileInfo = DeviceTileInfo.makeLoading(title: device.name, imageName: "thermostat_symbol")
  
    self.cancellable = self.device.types.subscribe(ThermostatDeviceType.self)
      .receive(on: DispatchQueue.main)
      .catch { error in
        Logger().error("Error getting ThermostatDeviceType: \(error)")
        return Empty<ThermostatDeviceType, Never>().eraseToAnyPublisher()
      }
      .sink { [weak self] thermostatDeviceType in
        self?.thermostatDeviceType = thermostatDeviceType
        self?.updateTileInfo()
      }
  }

  public override func primaryAction() {}

  // MARK: - Private

  private func updateTileInfo() {
    guard
      let thermostatDeviceType = self.thermostatDeviceType
    else {
      return
    }

    let hundredths = thermostatDeviceType.matterTraits.thermostatTrait?.attributes
      .localTemperature ?? 0
    let degrees = Float(hundredths) / 100.0

    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      imageName: "thermostat_symbol",
      isActive: true,
      isBusy: false,
      statusLabel: "\(degrees) °C",
      error: nil
    )
  }
}
