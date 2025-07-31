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

/// A `DeviceControl` instance representing a TV that can be toggled on and off.
final class TVControl: DeviceControl {
  private var tvDeviceType: GoogleTVDeviceType?
  private var cancellables: Set<AnyCancellable> = []
  private var rangeCancellable: AnyCancellable?

  // MARK: - Initialization

  public override init(device: HomeDevice) throws {
    guard device.types.contains(GoogleTVDeviceType.self) else {
      throw HomeError.notFound("Device does not support GoogleTVDeviceType")
    }
    try super.init(device: device)

    self.tileInfo = .makeLoading(title: device.name, imageName: "tv_symbol")

    self.device.types.subscribe(GoogleTVDeviceType.self)
      .receive(on: DispatchQueue.main)
      .catch { error in
        Logger().error("Error getting GoogleTVDeviceType: \(error)")
        return Empty<GoogleTVDeviceType, Never>().eraseToAnyPublisher()
      }
      .sink { [weak self] tvDeviceType in
        guard let self = self else { return }
        self.tvDeviceType = tvDeviceType
        self.updateTileInfo()
        if tvDeviceType.matterTraits.onOffTrait != nil {
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
      .store(in: &self.cancellables)
  }

  // MARK: - `DeviceControl`

  /// Toggles the TV; usually provided as the `action` callback on a Button.
  private func toggleAction() {
    self.updateTileInfo(isBusy: true)
    Task { @MainActor [weak self] in
      guard
        let self = self,
        let tvDeviceType = self.tvDeviceType,
        let onOffTrait = tvDeviceType.matterTraits.onOffTrait
      else { return }

      do {
        try await onOffTrait.toggle()
      } catch {
        Logger().error("Failed to to toggle TV on/off trait: \(error)")
        self.updateTileInfo(isBusy: false)
      }
    }
  }

  // MARK: - Private

  /// Provided to the generic publisher to convert from `OnOffTrait` to the `DeviceTileInfo` state.
  ///
  /// Also updates `self.trait`, which is used to perform actions.
  private func updateTileInfo(isBusy: Bool = false) {
    guard let tvDeviceType = self.tvDeviceType else { return }

    let isOn = tvDeviceType.matterTraits.onOffTrait?.attributes.onOff ?? false
    let imageName = isOn ? "tv_symbol" : "tv_off_symbol"
    let statusLabel = isOn ? "On" : "Off"

    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      typeName: "TV",
      imageName: imageName,
      isActive: isOn,
      isBusy: isBusy,
      statusLabel: statusLabel,
      attributes: [],
      error: nil
    )
  }
}
