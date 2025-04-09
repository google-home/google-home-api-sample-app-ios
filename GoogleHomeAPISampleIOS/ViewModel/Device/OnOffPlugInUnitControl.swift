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
import GoogleHomeTypes
import OSLog

/// A `DeviceControl` instance representing an OnOffPluginUnitDeviceType (an "on/off plug-in unit") that can be toggled
/// on and off.
final class OnOffPlugInUnitControl: DeviceControl {
  private var onOffPluginUnitDeviceType: OnOffPluginUnitDeviceType?
  private var cancellables: Set<AnyCancellable> = []

  // MARK: - Initialization

  public override init(device: HomeDevice) throws {
    guard device.types.contains(OnOffPluginUnitDeviceType.self) else {
      throw HomeError.notFound("Device does not support OnOffPluginUnitDeviceType")
    }
    try super.init(device: device)

    self.tileInfo = .makeLoading(title: device.name, imageName: "outlet_symbol")

    self.device.types.subscribe(OnOffPluginUnitDeviceType.self)
      .receive(on: DispatchQueue.main)
      .catch { error in
        Logger().error("Error getting OnOffPluginUnitDeviceType: \(error)")
        return Empty<OnOffPluginUnitDeviceType, Never>().eraseToAnyPublisher()
      }
      .sink { [weak self] onOffPluginUnitDeviceType in
        self?.onOffPluginUnitDeviceType = onOffPluginUnitDeviceType
        self?.updateTileInfo()
      }
      .store(in: &self.cancellables)
  }

  // MARK: - `DeviceControl`

  /// TODO: primary action of OnOffPlug
  /// Toggles the plug; usually provided as the `action` callback on a Button.
  public override func primaryAction() {
//    self.updateTileInfo(isBusy: true)
//    Task { @MainActor [weak self] in
//      guard
//        let self = self,
//        let onOffPluginUnitDeviceType = self.onOffPluginUnitDeviceType,
//        let onOffTrait = onOffPluginUnitDeviceType.matterTraits.onOffTrait
//      else { return }
//
//      do {
//        try await onOffTrait.toggle()
//      } catch {
//        Logger().error("Failed to to toggle OnOffPluginUnit on/off trait: \(error)")
//        self.updateTileInfo(isBusy: false)
//      }
//    }

    AlertHelper.showAlert(text: "TODO: primary action of OnOffPlug")
  }

  // MARK: - Private

  /// Provided to the generic publisher to convert from `OnOffTrait` to the `DeviceTileInfo` state.
  ///
  /// Also updates `self.trait`, which is used to perform actions.
  private func updateTileInfo(isBusy: Bool = false) {
    guard
      let onOffPluginUnitDeviceType = self.onOffPluginUnitDeviceType
    else {
      return
    }

    let isOn = onOffPluginUnitDeviceType.matterTraits.onOffTrait?.attributes.onOff ?? false
    let imageName = isOn ? "outlet_fill_symbol" : "outlet_symbol"
    let statusLabel = isOn ? "On" : "Off"

    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      imageName: imageName,
      isActive: isOn,
      isBusy: isBusy,
      statusLabel: statusLabel,
      error: nil
    )
  }
}
