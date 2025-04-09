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
  private static let closedLiftPct: Float = 10_000
  private var windowCoveringDeviceType: WindowCoveringDeviceType?
  private var typeCancellable: AnyCancellable?
  private var rangeCancellable: AnyCancellable?

  private var liftPct100ths: UInt16 {
      self.windowCoveringDeviceType?.matterTraits.windowCoveringTrait?.attributes.currentPositionLiftPercent100ths ?? 0
  }

  // MARK: - Initialization

  override init(device: HomeDevice) throws {
    guard device.types.contains(WindowCoveringDeviceType.self) else {
      throw HomeSampleError.unableToCreateControlForDeviceType(deviceType: "WindowCoveringDeviceType")
    }
    try super.init(device: device)

    self.tileInfo = DeviceTileInfo.makeLoading(title: device.name, imageName: "blinds_symbol")

    self.typeCancellable = self.device.types.subscribe(WindowCoveringDeviceType.self)
      .receive(on: DispatchQueue.main)
      .catch { error in
        Logger().error("Error getting WindowCoveringDeviceType: \(error)")
        return Empty<WindowCoveringDeviceType, Never>().eraseToAnyPublisher()
      }
      .sink { [weak self] windowCoveringDeviceType in
        guard let self = self else { return }
        self.windowCoveringDeviceType = windowCoveringDeviceType
        self.updateTileInfo()
        self.rangeControl = RangeControl(
          rangeValue: (Self.closedLiftPct - Float(self.liftPct100ths)) / Self.closedLiftPct)
        self.startRangeSubscription()
      }
  }

  // MARK: - `DeviceControl`

  override func primaryAction() {
    self.updateTileInfo(isBusy: true)
    Task { @MainActor [weak self] in
      guard
        let self = self,
        let trait = self.windowCoveringDeviceType?.matterTraits.windowCoveringTrait
      else {
        return
      }

      do {
        let currentLiftPct = Float(trait.attributes.currentPositionLiftPercentage ?? 0)*100
        let isOpen = currentLiftPct < Self.closedLiftPct
        if isOpen {
          Logger().info("exe: downOrClose")
          try await trait.downOrClose()
        } else {
          Logger().info("exe: upOrOpen")
          try await trait.upOrOpen()
        }
      } catch {
        Logger().error("Failed to open/close blinds: \(error)")
        self.updateTileInfo(isBusy: false)
      }
    }
  }

  // MARK: - Private

  private func updateTileInfo(isBusy: Bool = false) {
    guard
      let windowCoveringDeviceType = self.windowCoveringDeviceType,
      let windowCoveringTrait = windowCoveringDeviceType.matterTraits.windowCoveringTrait
    else {
      let error = HomeSampleError.unableToUpdateControlForDeviceType(deviceType: "WindowCoveringDeviceType")
      self.tileInfo = DeviceTileInfo.make(forError: error)
      return
    }

    let currentLiftPct = Float(windowCoveringTrait.attributes.currentPositionLiftPercentage ?? 0)*100
    let isOpen = currentLiftPct < Self.closedLiftPct
    let openPct = (Self.closedLiftPct - currentLiftPct) / Self.closedLiftPct
    let status: String
    if isOpen,
        let formattedPct = NSNumber(value: openPct).percentFormatted()
    {
      status = "Open · \(formattedPct)"
    } else {
      status = "Closed"
    }
    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      imageName: isOpen
        ? "blinds_symbol" : "blinds_closed_symbol",
      isActive: isOpen,
      isBusy: isBusy,
      statusLabel: status,
      error: nil
    )
  }

  private func startRangeSubscription() {
    guard let rangeControl = self.rangeControl else { return }
    self.rangeCancellable?.cancel()
    self.rangeCancellable = rangeControl.$rangeValue.sink { [weak self] value in
      guard let self = self else { return }
      let liftPct100ths = UInt16(Self.closedLiftPct - value * Self.closedLiftPct)
      guard liftPct100ths != self.liftPct100ths else { return }

      self.updateTileInfo(isBusy: true)
      Task { @MainActor [weak self] in
        guard
          let self = self,
          let windowCoveringDeviceType = self.windowCoveringDeviceType,
          let windowCoveringTrait = windowCoveringDeviceType.matterTraits.windowCoveringTrait
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
}
