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
  private var coolingRangeCancellable: AnyCancellable?
  private var heatRangeCancellable: AnyCancellable?

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
        guard let thermostatTrait = thermostatDeviceType.matterTraits.thermostatTrait else {
          return
        }
        let systemMode = thermostatTrait.attributes.systemMode
        let supportedModes = thermostatTrait.supportedSystemModes
        let supportedModeStrings = supportedModes.compactMap {
          systemModeEnumToStringMap[$0]
        }

        self.thermostatDeviceType = thermostatDeviceType
        if self.dropdownControl == nil {
          self.dropdownControl = thermostatTrait.makeDropdownControl(
            options: supportedModeStrings.sorted(),
            selection: systemModeEnumToStringMap[systemMode ?? .unrecognized_] ?? "Unknown"
          )
          self.startDropdownSubscription()
        }

        self.setupRangeControl(
          setpoint: thermostatTrait.coolingSetpoint,
          control: &self.coolRangeControl,
          cancellable: self.coolingRangeCancellable,
          makeControl: { thermostatTrait.makeCoolRangeControl() },
          subscriptionStarter: { self.startCoolingRangeSubscription() }
        )

        self.setupRangeControl(
          setpoint: thermostatTrait.heatingSetpoint,
          control: &self.heatRangeControl,
          cancellable: self.heatRangeCancellable,
          makeControl: { thermostatTrait.makeHeatRangeControl() },
          subscriptionStarter: { self.startHeatRangeSubscription() }
        )

        self.updateTileInfo()
        self.setupButtonGroup()
      }
  }

  // MARK: - Private

  private func setupButtonGroup() {
    guard let thermostatTrait = self.thermostatDeviceType?.matterTraits.thermostatTrait,
          let coolingSetPoint = thermostatTrait.coolingSetpoint,
          let heatingSetpoint = thermostatTrait.heatingSetpoint
    else {
      return
    }
    let systemMode = thermostatTrait.systemMode
    let setpointAdjustmentAmount: Int8 = 5  // 0.5 degress

    let increaseCoolButton = ButtonGroupItem(

      label: "+0.5°C Cool",
      isDisplayed: systemMode.isModeCoolingRelated,
      disabled: coolingSetPoint == thermostatTrait.maxCoolSetpointLimit

    ) { [weak self] in
      self?.adjustSetpoint(mode: .cool, amount: setpointAdjustmentAmount)
    }
    let decreaseCoolButton = ButtonGroupItem(
      label: "-0.5°C Cool",
      isDisplayed: systemMode.isModeCoolingRelated,
      disabled: coolingSetPoint == thermostatTrait.minCoolSetpointLimit
    ) { [weak self] in
      self?.adjustSetpoint(mode: .cool, amount: -setpointAdjustmentAmount)
    }
    let increaseHeatButton = ButtonGroupItem(
      label: "+0.5°C Heat",
      isDisplayed: systemMode.isModeHeatingRelated,
      disabled: heatingSetpoint == thermostatTrait.maxHeatSetpointLimit
    ) { [weak self] in
      self?.adjustSetpoint(mode: .heat, amount: setpointAdjustmentAmount)
    }
    let decreaseHeatButton = ButtonGroupItem(
      label: "-0.5°C Heat",
      isDisplayed: systemMode.isModeHeatingRelated,
      disabled: heatingSetpoint == thermostatTrait.minHeatSetpointLimit
    ) { [weak self] in
      self?.adjustSetpoint(mode: .heat, amount: -setpointAdjustmentAmount)
    }
    let increaseBothButton = ButtonGroupItem(
      label: "+0.5°C Both",
      isDisplayed: systemMode == .auto,
      disabled: coolingSetPoint == thermostatTrait.maxCoolSetpointLimit
      || heatingSetpoint == thermostatTrait.maxHeatSetpointLimit
    ) { [weak self] in
      self?.adjustSetpoint(mode: .both, amount: setpointAdjustmentAmount)  // +0.5 degree
    }
    let decreaseBothButton = ButtonGroupItem(
      label: "-0.5°C Both",
      isDisplayed: systemMode == .auto,
      disabled: coolingSetPoint == thermostatTrait.minCoolSetpointLimit
        || heatingSetpoint == thermostatTrait.minHeatSetpointLimit
    ) { [weak self] in
      self?.adjustSetpoint(mode: .both, amount: -setpointAdjustmentAmount)  // -0.5 degree
    }

    self.buttonGroupControl = ButtonGroupControl(buttons: [
      decreaseCoolButton, increaseCoolButton,
      decreaseHeatButton, increaseHeatButton,
      decreaseBothButton, increaseBothButton,
    ])
  }

  private func adjustSetpoint(mode: Matter.ThermostatTrait.SetpointRaiseLowerModeEnum, amount: Int8)
  {
    self.updateTileInfo(isBusy: true)
    Task {@MainActor [weak self] in
      guard let self = self,
            let thermostatTrait = self.thermostatDeviceType?.matterTraits.thermostatTrait
      else {
        return
      }
      do {
        try await thermostatTrait.setpointRaiseLower(
          mode: mode, amount: amount)
      } catch {
        Logger().error("Cannot adjust setpoint. \(error)")
        self.updateTileInfo(isBusy: false)
      }
    }
  }

  private func updateTileInfo(isBusy: Bool = false) {
    guard let thermostatDeviceType = self.thermostatDeviceType,
      let thermostatTrait = thermostatDeviceType.matterTraits.thermostatTrait
    else {
      return
    }

    // Format temperatures
    let systemMode = thermostatTrait.systemMode
    let localTemperature = formatTemperature(thermostatTrait.attributes.localTemperature)
    let coolingSetpoint = formatTemperature(thermostatTrait.coolingSetpoint)
    let heatingSetpoint = formatTemperature(thermostatTrait.heatingSetpoint)

    // Status label
    let statusLabel = localTemperature

    // Attributes
    var attributes: [[String: String]] = []
    if let localTemperature = localTemperature {
      attributes.append(["Local Temperature": localTemperature])
    }
    if let coolingSetpoint = coolingSetpoint,
        systemMode.isModeCoolingRelated
    {
      attributes.append(["Cooling Setpoint": coolingSetpoint])
    }
    if let heatingSetpoint = heatingSetpoint,
       systemMode.isModeHeatingRelated
    {
      attributes.append(["Heating Setpoint": heatingSetpoint])
    }

    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      typeName: "Thermostat",
      imageName: "thermostat_symbol",
      isActive: true,
      isBusy: isBusy,
      statusLabel: statusLabel ?? "",
      attributes: attributes,
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

  private func startCoolingRangeSubscription() {
    guard let control = self.coolRangeControl else { return }
    self.coolingRangeCancellable?.cancel()

    self.coolingRangeCancellable = self.createRangePublisher(
      for: control,
      getCurrentSetpoint: { $0.coolingSetpoint },
      setSetpointAction: { try await $0.setOccupiedCoolingPoint(to: $1) },
      errorMessage: "Failed to set cool"
    )
  }

  private func startHeatRangeSubscription() {
    guard let control = self.heatRangeControl else { return }
    self.heatRangeCancellable?.cancel()

    self.heatRangeCancellable = self.createRangePublisher(
      for: control,
      getCurrentSetpoint: { $0.heatingSetpoint },
      setSetpointAction: { try await $0.setOccupiedHeatingPoint(to: $1) },
      errorMessage: "Failed to set heat"
    )
  }

  //  Mark: - Helper functions

  private func toSafeInt16(_ value: Float) -> Int16 {
    return value.isNaN ? 0 : Int16(max(Float(Int16.min), min(Float(Int16.max), value)))
  }

  private func formatTemperature(
    _ value: Int16?
  ) -> String? {
    guard let value = value else { return nil }
    let degrees = Float(value) / 100.0
    let unit = "°C"
    return String(format: "%.2f%@", degrees, unit)
  }

  private func setupRangeControl(
    setpoint: Int16?,
    control: inout RangeControl?,
    cancellable: AnyCancellable?,
    makeControl: () -> RangeControl?,
    subscriptionStarter: () -> Void
  ) {
    guard let setpoint = setpoint else {
      control = nil
      return
    }

    let target = Float(setpoint)
    if control == nil {
      guard let newControl = makeControl() else { return }
      control = newControl
      subscriptionStarter()
    } else if cancellable == nil {
      subscriptionStarter()
    }

    // Only update UI if difference is significant (prevents jitter while dragging)
    if abs((control?.rangeValue ?? target) - target) > 0.1 {
      control?.rangeValue = target
    }
  }

  private func createRangePublisher(
    for control: RangeControl,
    getCurrentSetpoint: @escaping (GoogleHomeTypes.Matter.ThermostatTrait) -> Int16?,
    setSetpointAction: @escaping (GoogleHomeTypes.Matter.ThermostatTrait, Int16) async throws -> Void,
    errorMessage: String
  ) -> AnyCancellable {
    return control.$rangeValue
    // Debounce to limit updates to the device until the user pauses slider interaction.
    // 150ms is a typical value to balance responsiveness and efficiency.
      .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
      .removeDuplicates()
      .sink { [weak self] value in
        guard let self = self,
              let thermostatTrait = self.thermostatDeviceType?.matterTraits.thermostatTrait,
              let current = getCurrentSetpoint(thermostatTrait) else { return }

        let safeValue = self.toSafeInt16(value)

        if safeValue != current {
          Task { @MainActor in
            do {
              try await setSetpointAction(thermostatTrait, safeValue)
            } catch {
              Logger().error("\(errorMessage): \(error)")
            }
          }
        }
      }
  }
}
