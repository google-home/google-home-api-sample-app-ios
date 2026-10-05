// Copyright 2026 Google LLC
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
import Foundation
import GoogleHomeSDK
import GoogleHomeTypes
import OSLog

/// A `DeviceControl` subclass representing a Matter Root Node (Endpoint 0 / Device Type 0x0016).
///
/// In Matter multi-endpoint devices (such as a Chime Hub), Endpoint 0 hosts system-wide traits:
/// - `Matter.BasicInformationTrait`: Contains hardware & software version strings, vendor name,
///   and product metadata.
/// - `Matter.OtaSoftwareUpdateRequestorTrait`: Coordinates firmware updates for the device.
final class RootNodeControl: DeviceControl {
  private enum Constants {
    static let controlIdentifier = "RootNodeControl"
    static let hubTypeName = "Hub"
    static let defaultImageName = "home_symbol"
    static let readyStatus = "Ready"
    static let vendorKey = "Vendor"
    static let productKey = "Product"
    static let firmwareVersionKey = "Firmware Version"
    static let hardwareVersionKey = "Hardware Version"
  }

  private var rootNodeDeviceType: RootNodeDeviceType?
  private var cancellables: Set<AnyCancellable> = []

  // MARK: - Initialization

  override init(device: HomeDevice) throws {
    guard device.types.contains(RootNodeDeviceType.self) else {
      throw HomeSampleError.unableToCreateControlForDeviceType(
        deviceType: Constants.controlIdentifier)
    }
    try super.init(device: device)

    self.tileInfo = DeviceTileInfo.makeLoading(
      title: device.name, imageName: Constants.defaultImageName)

    self.device.types.subscribe(RootNodeDeviceType.self)
      .receive(on: DispatchQueue.main)
      .catch { [weak self] error in
        Logger().error("Error subscribing to RootNodeDeviceType: \(error)")
        self?.updateTileInfo()
        return Empty<RootNodeDeviceType, Never>().eraseToAnyPublisher()
      }
      .sink { [weak self] rootNodeDeviceType in
        guard let self = self else { return }
        self.rootNodeDeviceType = rootNodeDeviceType
        self.updateTileInfo()
      }
      .store(in: &self.cancellables)
  }

  // MARK: - Private

  /// Updates the status card metadata from BasicInformationTrait.
  private func updateTileInfo(isBusy: Bool = false) {
    var attributes: [[String: String]] = []

    if let basicInfo = self.rootNodeDeviceType?.matterTraits.basicInformationTrait {
      if let vendorName = basicInfo.attributes.vendorName, !vendorName.isEmpty {
        attributes.append([Constants.vendorKey: vendorName])
      }
      if let productName = basicInfo.attributes.productName, !productName.isEmpty {
        attributes.append([Constants.productKey: productName])
      }
      if let softwareVersion = basicInfo.attributes.softwareVersionString, !softwareVersion.isEmpty {
        attributes.append([Constants.firmwareVersionKey: softwareVersion])
      }
      if let hardwareVersion = basicInfo.attributes.hardwareVersion {
        attributes.append([Constants.hardwareVersionKey: "\(hardwareVersion)"])
      }
    }

    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      typeName: Constants.hubTypeName,
      imageName: Constants.defaultImageName,
      isActive: true,
      isBusy: isBusy,
      statusLabel: Constants.readyStatus,
      attributes: attributes,
      error: nil
    )
  }
}
