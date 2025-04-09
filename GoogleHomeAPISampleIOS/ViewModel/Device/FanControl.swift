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

/// An instance of `DeviceControl` representing a fan that can simply toggle on and off.
final class FanControl: DeviceControl {
  private var fanDeviceType: FanDeviceType?
  private var cancellable: AnyCancellable?
  private var rangeCancellable: AnyCancellable?

  // MARK: - Initialization

  override init(device: HomeDevice) throws {
    guard device.types.contains(FanDeviceType.self) else {
      throw HomeSampleError.unableToCreateControlForDeviceType(deviceType: "FanControl")
    }
    try super.init(device: device)

    self.tileInfo = DeviceTileInfo.makeLoading(title: device.name, imageName: "mode_fan_symbol")

    self.cancellable = self.device.types.subscribe(FanDeviceType.self)
      .receive(on: DispatchQueue.main)
      .catch { error in
        Logger().error("Error getting FanDeviceType: \(error)")
        return Empty<FanDeviceType, Never>().eraseToAnyPublisher()
      }
      .sink { [weak self] fanDeviceType in
        guard let self = self else { return }
        self.fanDeviceType = fanDeviceType
        self.rangeControl = fanDeviceType.matterTraits.fanControlTrait?.makeRangeControl()
        self.updateTileInfo()
        self.startRangeSubscription()
      }
  }

  // MARK: - `DeviceControl`

  /// Toggles the fan; usually provided as the `action` callback on a Button.
  override func primaryAction() {
    self.updateTileInfo(isBusy: true)
    Task { @MainActor [weak self] in
      do {
        try await self?.toggleFan()
      } catch {
        Logger().error("Failed to to toggle fan mode: \(error)")
        self?.updateTileInfo(isBusy: false)
      }
    }
  }

  // MARK: - Private

  /// Provided to the generic publisher to convert from `OnOffTrait` to the `DeviceTileInfo` state.
  ///
  /// Also updates `self.trait`, which is used to perform actions.
  private func updateTileInfo(isBusy: Bool = false) {
    guard let fanDeviceType = self.fanDeviceType else { return }
    let isOn = self.fanIsOn()
    var statusLabel = isOn ? "On" : "Off"
    if isOn {
      if let percentValue = fanDeviceType.matterTraits.fanControlTrait?.calculateRangeValue(),
        let percentFormatted = NSNumber(value: percentValue).percentFormatted()
      {
        statusLabel += " • \(percentFormatted)"
      }
    }
    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      imageName: isOn
        ? "mode_fan_fill_symbol" : "mode_fan_symbol",
      isActive: isOn,
      isBusy: isBusy,
      statusLabel: statusLabel,
      error: nil
    )
  }

  /// Subscribes to range control value updates and updates sends the updates the speed traits
  /// accordingly.
  private func startRangeSubscription() {
    guard let rangeControl = self.rangeControl else { return }
    self.rangeCancellable?.cancel()
    self.rangeCancellable = rangeControl.$rangeValue.sink { [weak self] value in
      guard
        let fanControlTrait = self?.fanDeviceType?.matterTraits.fanControlTrait,
        fanControlTrait.attributes.$percentSetting.isSupported,
        let currentValue = fanControlTrait.calculateRangeValue(),
        value != currentValue
      else {
        return
      }

      self?.updateTileInfo(isBusy: true)
      Task { @MainActor [weak self] in
        guard let self = self else { return }

        do {
          _ = try await fanControlTrait.update {
            $0.setPercentSetting(UInt8(value * 100))
          }
        } catch {
          Logger().error("Failed to adjust brightness: \(error)")
          self.updateTileInfo(isBusy: false)
        }
      }
    }
  }

  private func fanIsOn() -> Bool {
    guard let fanDeviceType = self.fanDeviceType else {
      return false
    }

    // Check if the device supports OnOffTrait.
    if let onOffTrait = fanDeviceType.traits[Matter.OnOffTrait.self] {
      return onOffTrait.attributes.onOff ?? false
    } else if let fanControlTrait = fanDeviceType.matterTraits.fanControlTrait {
      // Otherwise, use the FanControlTrait.
      return fanControlTrait.attributes.fanMode != .off
    } else {
      return false
    }
  }

  private func toggleFan() async throws {
    guard let fanDeviceType = self.fanDeviceType else {
      throw HomeError.notFound("Device does not support FanControl")
    }

    // Check if the device supports OnOffTrait.
    if let onOffTrait = fanDeviceType.traits[Matter.OnOffTrait.self] {
      try await onOffTrait.toggle()
    } else if let fanControlTrait = fanDeviceType.matterTraits.fanControlTrait {
      // Otherwise, use the FanControlTrait.
      let fanMode = fanControlTrait.attributes.fanMode
      let newFanMode: Matter.FanControlTrait.FanModeEnum = fanMode == .off ? .high : .off
      _ = try await fanControlTrait.update {
        $0.setFanMode(newFanMode)
      }
    } else {
      Logger().error("Cannot toggle fan. Device does not support OnOffTrait or FanControlTrait.")
    }
  }
}
