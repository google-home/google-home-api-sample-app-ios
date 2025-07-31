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

protocol LightDeviceType: DeviceType {
  var onOffTrait: Matter.OnOffTrait? { get }
  var levelControlTrait: Matter.LevelControlTrait? { get }
}

extension OnOffLightDeviceType: LightDeviceType {
  var onOffTrait: GoogleHomeTypes.Matter.OnOffTrait? {
    self.matterTraits.onOffTrait
  }

  var levelControlTrait: GoogleHomeTypes.Matter.LevelControlTrait? {
    nil
  }
}

extension DimmableLightDeviceType: LightDeviceType {
  var onOffTrait: GoogleHomeTypes.Matter.OnOffTrait? {
    self.matterTraits.onOffTrait
  }

  var levelControlTrait: GoogleHomeTypes.Matter.LevelControlTrait? {
    self.matterTraits.levelControlTrait
  }
}

extension ColorTemperatureLightDeviceType: LightDeviceType {
  var onOffTrait: GoogleHomeTypes.Matter.OnOffTrait? {
    self.matterTraits.onOffTrait
  }

  var levelControlTrait: GoogleHomeTypes.Matter.LevelControlTrait? {
    self.matterTraits.levelControlTrait
  }
}

extension ExtendedColorLightDeviceType: LightDeviceType {
  var onOffTrait: GoogleHomeTypes.Matter.OnOffTrait? {
    self.matterTraits.onOffTrait
  }

  var levelControlTrait: GoogleHomeTypes.Matter.LevelControlTrait? {
    self.matterTraits.levelControlTrait
  }
}

/// An instance of `DeviceControl` representing a light that can simply toggle on and off.
class LightControl<LightType: LightDeviceType>: DeviceControl {
  // MARK: - Private

  private var lightDeviceType: LightType?
  private var typeCancellable: AnyCancellable?
  private var rangeCancellable: AnyCancellable?

  // MARK: - `DeviceControl`

  override var colorPalette: ColorPalette { .light }

  override init(device: HomeDevice) throws {
    guard device.types.contains(LightType.self) else {
      throw HomeSampleError.unableToCreateControlForDeviceType(
        deviceType: LightType.identifier)
    }
    try super.init(device: device)

    self.tileInfo = DeviceTileInfo.makeLoading(
      title: device.name, imageName: "lightbulb_symbol")

    self.typeCancellable = self.device.types.subscribe(LightType.self)
      .receive(on: DispatchQueue.main)
      .catch { error in
        Logger().error("Error getting LigthDeviceType: \(error)")
        return Empty<LightType, Never>().eraseToAnyPublisher()
      }
      .sink { [weak self] lightDeviceType in
        guard let self = self else { return }
        self.lightDeviceType = lightDeviceType
        self.rangeControl = lightDeviceType.levelControlTrait?
          .makeRangeControl()
        self.updateTileInfo()
        self.startRangeSubscription()

        if lightDeviceType.onOffTrait != nil {
          self.toggleControl = ToggleControl(
            isOn: self.tileInfo.isActive,
            label: "Switch",
            description: self.tileInfo.isActive ? "On" : "Off"
          ) {
            self.toggleAction()
          }
        } else {
          self.toggleControl = nil
        }
      }
  }

  /// Toggles the light; usually provided as the `action` callback on a Button.
  private func toggleAction() {
    self.updateTileInfo(isBusy: true)
    Task { @MainActor [weak self] in
      guard
        let self = self,
        let lightDeviceType = self.lightDeviceType,
        let onOffTrait = lightDeviceType.onOffTrait
      else {
        return
      }
      do {
        try await onOffTrait.toggle()
      } catch {
        Logger().error("Failed to toggle OnOffTrait: \(error)")
        self.updateTileInfo(isBusy: false)
      }
    }
  }

  // MARK: - Private

  /// Provided to the generic publisher to convert from `OnOffTrait` to the `DeviceTileInfo` state.
  ///
  /// Also updates `self.trait`, which is used to perform actions.
  ///
  private func updateTileInfo(isBusy: Bool = false) {
    guard let lightDeviceType = self.lightDeviceType else { return }
    let isOn = lightDeviceType.onOffTrait?.attributes.onOff ?? false
    var statusLabel = ""
    if isOn {
      statusLabel = "On"
      if let rangeControl = self.rangeControl {
        let percent =
          NSNumber(value: rangeControl.rangeValue).percentFormatted() ?? ""
        statusLabel += " • \(percent)"
      }
    } else {
      statusLabel = "Off"
    }
    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      typeName: "Light",
      imageName: isOn
        ? "lightbulb_fill_symbol" : "lightbulb_symbol",
      isActive: isOn,
      isBusy: isBusy,
      statusLabel: statusLabel,
      attributes: [],
      error: nil
    )
  }

  /// Subscribes to range control value updates and updates sends the updates the level control
  /// trait accordingly.
  private func startRangeSubscription() {
    guard let rangeControl = self.rangeControl else { return }
    self.rangeCancellable?.cancel()
    self.rangeCancellable = rangeControl.$rangeValue.sink { [weak self] value in
      guard let levelControlTrait = self?.lightDeviceType?.levelControlTrait
      else { return }

      let level = levelControlTrait.currentLevelFromPercentage(value)
      guard level != levelControlTrait.attributes.currentLevel else { return }

      self?.updateTileInfo(isBusy: true)
      Task { @MainActor [weak self] in
        guard
          let self = self,
          let lightDeviceType = self.lightDeviceType,
          let levelControlTrait = lightDeviceType.levelControlTrait
        else {
          return
        }
        do {
          try await levelControlTrait.moveToLevelWithOnOff(
            level: level,
            transitionTime: nil,
            optionsMask: [],
            optionsOverride: [])
        } catch {
          Logger().error("Failed to adjust brightness: \(error)")
          self.updateTileInfo(isBusy: false)
        }
      }
    }
  }
}
