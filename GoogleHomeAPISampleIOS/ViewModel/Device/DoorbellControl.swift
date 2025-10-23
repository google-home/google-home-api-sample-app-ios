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

/// A `DeviceControl` instance representing a doorbell that has video streaming capabilities.
final class DoorbellControl: DeviceControl {
  private var doorbellDeviceType: GoogleDoorbellDeviceType?
  private var cancellables: Set<AnyCancellable> = []
  private var rangeCancellable: AnyCancellable?

  // MARK: - Initialization

  public override init(device: HomeDevice) throws {
    guard device.types.contains(GoogleDoorbellDeviceType.self) else {
      throw HomeError.notFound("Device does not support GoogleDoorbellDeviceType")
    }
    try super.init(device: device)

    self.tileInfo = .makeLoading(title: device.name, imageName: "doorbell_symbol")

    self.device.types.subscribe(GoogleDoorbellDeviceType.self)
      .receive(on: DispatchQueue.main)
      .catch { error in
        Logger().error("Error getting GoogleDoorbellDeviceType: \(error)")
        return Empty<GoogleDoorbellDeviceType, Never>().eraseToAnyPublisher()
      }
      .sink { [weak self] doorbellDeviceType in
        guard let self = self else { return }
        self.doorbellDeviceType = doorbellDeviceType
        self.updateTileInfo()
        self.toggleControl = nil
      }
      .store(in: &self.cancellables)
  }

  // MARK: - Private

  /// Provided to the generic publisher to convert from `pushAvStreamTransportTrait` to the `DeviceTileInfo` state.
  ///
  /// Also updates `self.trait`, which is used to perform actions.
  private func updateTileInfo(isBusy: Bool = false) {
    guard let doorbellDeviceType = self.doorbellDeviceType else { return }

    let isOn =
      doorbellDeviceType.googleTraits.pushAvStreamTransportTrait?
      .attributes.currentConnections?.contains(where: { $0.transportStatus == .active }) ?? false
    let imageName = isOn ? "nest_hello_doorbell_fill1_symbol" : "nest_hello_doorbell_symbol"
    let statusLabel = isOn ? "On" : "Off"

    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      typeName: "Doorbell",
      imageName: imageName,
      isActive: isOn,
      isBusy: isBusy,
      statusLabel: statusLabel,
      attributes: [],
      error: nil
    )
  }
}
