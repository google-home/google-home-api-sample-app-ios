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
  private var dropdownCancellable: AnyCancellable?

  private var systemModeStringToEnumMap:
    [String: GoogleHomeTypes.Matter.ThermostatTrait.SystemModeEnum] = [
      "Off": .off,
      "Auto": .auto,
      "Cool": .cool,
      "Heat": .heat,
      "Emergency Heat": .emergencyHeat,
      "Precooling": .precooling,
      "Fan Only": .fanOnly,
      "Dry": .dry,
      "Sleep": .sleep,
    ]

  // MARK: - Initialization

  public override init(device: HomeDevice) throws {
    guard device.types.contains(ThermostatDeviceType.self) else {
      throw HomeSampleError.unableToCreateControlForDeviceType(
        deviceType: "ThermostatControl")
    }
    try super.init(device: device)

    self.tileInfo = DeviceTileInfo.makeLoading(
      title: device.name, imageName: "thermostat_symbol")

    let systemModeEnumToStringMap = self.systemModeStringToEnumMap
      .reduce(
        into: [GoogleHomeTypes.Matter.ThermostatTrait.SystemModeEnum: String]()
      ) { result, element in
        result[element.value] = element.key
      }

    self.cancellable = self.device.types.subscribe(ThermostatDeviceType.self)
      .receive(on: DispatchQueue.main)
      .catch { error in
        Logger().error("Error getting ThermostatDeviceType: \(error)")
        return Empty<ThermostatDeviceType, Never>().eraseToAnyPublisher()
      }
      .sink { [weak self] thermostatDeviceType in
        guard let self = self else { return }
        let systemMode = thermostatDeviceType.matterTraits.thermostatTrait?
          .attributes.systemMode
        self.thermostatDeviceType = thermostatDeviceType
        self.dropdownControl = thermostatDeviceType.matterTraits
          .thermostatTrait?.makeDropdownControl(
            options: Array(self.systemModeStringToEnumMap.keys),
            selection: systemModeEnumToStringMap[systemMode ?? .unrecognized_]
              ?? "Unknown"
          )
        self.updateTileInfo()
        self.startDropdownSubscription()

      }
  }

  // MARK: - Private

  private func updateTileInfo(isBusy: Bool = false) {
    guard
      let thermostatDeviceType = self.thermostatDeviceType
    else {
      return
    }

    let hundredths =
      thermostatDeviceType.matterTraits.thermostatTrait?.attributes
      .localTemperature ?? 0
    let degrees = Float(hundredths) / 100.0
    let unit =
      switch thermostatDeviceType.matterTraits
        .thermostatUserInterfaceConfigurationTrait?.attributes
        .temperatureDisplayMode
      {
      case .celsius: "°C"
      case .fahrenheit: "°F"
      default: "unkown"
      }

    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      typeName: "Thermostat",
      imageName: "thermostat_symbol",
      isActive: true,
      isBusy: isBusy,
      statusLabel: "\(degrees) \(unit)",
      attributes: [
        ["Temperature": "\(degrees) \(unit)"]
      ],
      error: nil
    )
  }

  private func startDropdownSubscription() {
    guard let dropdownControl = self.dropdownControl else { return }
    self.dropdownCancellable?.cancel()
    self.dropdownCancellable = dropdownControl.$selection.sink {
      [weak self] value in
      guard
        let self = self,
        let thermostatTrait = self.thermostatDeviceType?.matterTraits
          .thermostatTrait,
        let selection = self.systemModeStringToEnumMap[value],
        selection != thermostatTrait.attributes.systemMode
      else {
        return
      }
      self.updateTileInfo(isBusy: true)
      Task {
        do {
          _ = try await thermostatTrait.update {
            $0.setSystemMode(selection)
          }

        } catch {
          Logger().error("Cannot set system mode. \(error)")
        }
      }
    }
  }

}
