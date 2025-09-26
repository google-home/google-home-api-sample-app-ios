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

/// A `DeviceControl` instance representing a camera that has video streaming capabilities.
final class CameraControl: DeviceControl {
  private var cameraDeviceType: GoogleCameraDeviceType?
  private var cancellables: Set<AnyCancellable> = []
  private var rangeCancellable: AnyCancellable?

  // MARK: - Initialization

  public override init(device: HomeDevice) throws {
    guard device.types.contains(GoogleCameraDeviceType.self) else {
      throw HomeError.notFound("Device does not support GoogleCameraDeviceType")
    }
    try super.init(device: device)

    self.tileInfo = .makeLoading(title: device.name, imageName: "camera_symbol")

    self.device.types.subscribe(GoogleCameraDeviceType.self)
      .receive(on: DispatchQueue.main)
      .catch { error in
        Logger().error("Error getting GoogleCameraDeviceType: \(error)")
        return Empty<GoogleCameraDeviceType, Never>().eraseToAnyPublisher()
      }
      .sink { [weak self] cameraDeviceType in
        guard let self = self else { return }
        self.cameraDeviceType = cameraDeviceType
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
    guard let cameraDeviceType = self.cameraDeviceType else { return }

    let isOn =
      cameraDeviceType.googleTraits.pushAvStreamTransportTrait?
      .attributes.currentConnections?.contains(where: { $0.transportStatus == .active }) ?? false
    let imageName = isOn ? "videocam_fill1_symbol" : "videocam_symbol"
    let statusLabel = isOn ? "Online" : "Offline"

    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      typeName: "Camera",
      imageName: imageName,
      isActive: isOn,
      isBusy: isBusy,
      statusLabel: statusLabel,
      attributes: [],
      error: nil
    )
  }
}
