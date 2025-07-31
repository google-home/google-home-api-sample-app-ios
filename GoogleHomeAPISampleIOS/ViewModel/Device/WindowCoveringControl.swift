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

final class WindowCoveringControl: DeviceControl {
  // The percentage value representing a fully closed window covering.
  private static let closedLiftPct: UInt16 = 10_000

  private var windowCoveringDeviceType: WindowCoveringDeviceType?
  private var typeCancellable: AnyCancellable?
  private var rangeCancellable: AnyCancellable?

  // MARK: - Initialization

  override init(device: HomeDevice) throws {
    guard device.types.contains(WindowCoveringDeviceType.self) else {
      throw HomeSampleError.unableToCreateControlForDeviceType(deviceType: "WindowCoveringDeviceType")
    }
    try super.init(device: device)

    self.tileInfo = DeviceTileInfo.makeLoading(title: device.name, imageName: "blinds_symbol")

    // Subscribe to the device's type to receive updates.
    self.typeCancellable = self.device.types.subscribe(
      WindowCoveringDeviceType.self
    )
    .receive(on: DispatchQueue.main)
    .catch { error in
      Logger().error("Error getting WindowCoveringDeviceType: \(error)")
      return Empty<WindowCoveringDeviceType, Never>().eraseToAnyPublisher()
    }
    .sink { [weak self] windowCoveringDeviceType in
      guard let self = self else { return }
      self.windowCoveringDeviceType = windowCoveringDeviceType
      self.updateTileInfo()
      // Initialize the range control with the current lift position.
      self.rangeControl = RangeControl(
        rangeValue: Float(Self.closedLiftPct - self.liftPct100ths(windowCoveringDeviceType))
          / Float(Self.closedLiftPct),
        label: "Open percentage")
      self.startRangeSubscription()
    }
  }

  // MARK: - `DeviceControl`

  // MARK: - Private

  private func updateTileInfo(isBusy: Bool = false) {
    guard
      let windowCoveringDeviceType = self.windowCoveringDeviceType
    else {
      // Set an error state if the device type is not available.
      let error = HomeSampleError.unableToUpdateControlForDeviceType(
        deviceType: "WindowCoveringDeviceType")
      self.tileInfo = DeviceTileInfo.make(forError: error)
      return
    }

    // Calculate the current open percentage and determine the device's status.
    let listPct100ths = self.liftPct100ths(windowCoveringDeviceType)
    let isOpen = listPct100ths < Self.closedLiftPct
    let openPct =
      Float(Self.closedLiftPct - listPct100ths) / Float(Self.closedLiftPct)
    let status =
      if isOpen,
        let formattedPct = NSNumber(value: openPct).percentFormatted()
      {
        "Open · \(formattedPct)"
      } else {
        "Closed"
      }

    // Update the tile info with the new state.
    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      typeName: "Window covering",
      imageName: isOpen
        ? "blinds_symbol" : "blinds_closed_symbol",
      isActive: isOpen,
      isBusy: isBusy,
      statusLabel: status,
      attributes: [],
      error: nil
    )
  }

  private func startRangeSubscription() {
    guard let rangeControl = self.rangeControl else { return }
    self.rangeCancellable?.cancel()
    self.rangeCancellable = rangeControl.$rangeValue.sink { [weak self] value in
      guard let self = self else { return }
      let liftPct100ths = Self.closedLiftPct - UInt16(value * Float(Self.closedLiftPct))
      guard liftPct100ths != self.liftPct100ths(self.windowCoveringDeviceType) else { return }

      self.updateTileInfo(isBusy: true)
      Task { @MainActor [weak self] in
        guard
          let self = self,
          let windowCoveringDeviceType = self.windowCoveringDeviceType,
          let windowCoveringTrait = windowCoveringDeviceType.matterTraits
            .windowCoveringTrait
        else {
          return
        }
        do {
          try await windowCoveringTrait.goToLiftPercentage(
            liftPercent100thsValue: liftPct100ths)
        } catch {
          Logger().error("Failed to adjust lift percentage: \(error)")
          self.updateTileInfo(isBusy: false)
        }
      }
    }
  }

  private func liftPct100ths(_ deviceType: WindowCoveringDeviceType?) -> UInt16 {
    guard
      let windowCoveringDeviceType = deviceType,
      let trait = windowCoveringDeviceType.matterTraits.windowCoveringTrait else {
      return 0
    }

    // Prefer target position and fallback to current position if it's not supported.
    if trait.attributes.$targetPositionLiftPercent100ths.isSupported {
      return trait.attributes.targetPositionLiftPercent100ths ?? 0
    } else {
      return trait.attributes.currentPositionLiftPercent100ths ?? 0
    }
  }
}
