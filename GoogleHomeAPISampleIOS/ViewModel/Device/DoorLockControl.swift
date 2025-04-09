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
import SwiftUI

// An instance of `DeviceControl` representing a simple door lock with pincode.
final class DoorLockControl: DeviceControl {
  // Empty string is a valid PIN code, it is sematically different from nil.
  private var userEnteredPINCode: String?
  private var doorLockDeviceType: DoorLockDeviceType?
  private var cancellable: AnyCancellable?

  // MARK: - Initialization

  public override init(device: HomeDevice) throws {
    guard device.types.contains(DoorLockDeviceType.self) else {
      throw HomeError.notFound("Device does not support DoorLockDeviceType")
    }
    try super.init(device: device)

    self.tileInfo = DeviceTileInfo.makeLoading(title: device.name, imageName: "lock_lock_symbol")

    self.cancellable = self.device.types.subscribe(DoorLockDeviceType.self)
      .receive(on: DispatchQueue.main)
      .catch { error in
        Logger().error("Error getting DoorLockDeviceType: \(error)")
        return Empty<DoorLockDeviceType, Never>().eraseToAnyPublisher()
      }
      .sink { [weak self] doorLockDeviceType in
        self?.doorLockDeviceType = doorLockDeviceType
        self?.updateTileInfo()
      }
  }

  // MARK: - `DeviceControl`

  // Toggles the locked / unlocked state; usually provided as the `action` callback on a Button.
  public override func primaryAction() {
    self.updateTileInfo(isBusy: true)
    Task { @MainActor [weak self] in
      guard let self = self,
        let doorLockTrait = self.doorLockDeviceType?.matterTraits.doorLockTrait
      else {
        return
      }
      if requiresPINCode {
        guard
          let userEnteredPINCode,
          let userEnteredPINCodeData = userEnteredPINCode.data(using: .utf8)
        else {
          Logger().error("PIN code expected to be set before primaryAction is called.")
          return
        }
        do {Logger().info("pin code: \(userEnteredPINCode)")
          switch doorLockTrait.attributes.lockState {
          case .locked:
            try await doorLockTrait.unlockDoor { $0.setPinCode(userEnteredPINCodeData) }
          default:
            try await doorLockTrait.lockDoor { $0.setPinCode(userEnteredPINCodeData) }
          }
        } catch {
          Logger().error("Failed to toggle DoorLockTrait: \(error)")
          self.updateTileInfo(isBusy: false)
        }
      } else {
        do {
          switch doorLockTrait.attributes.lockState {
          case .locked:
            try await doorLockTrait.unlockDoor()
          default:
            try await doorLockTrait.lockDoor()
          }
        } catch {
          Logger().error("Failed to toggle DoorLockTrait: \(error)")
          self.updateTileInfo(isBusy: false)
        }
      }
    }
  }

  public override var requiresPINCode: Bool { isRequiresPinCode() }

  public override func setPINCode(_ code: String) { self.userEnteredPINCode = code }

  // MARK: - Private

  private func updateTileInfo(isBusy: Bool = false) {
    guard
      let doorLockDeviceType = self.doorLockDeviceType,
      let trait = doorLockDeviceType.matterTraits.doorLockTrait
    else {
      return
    }

    let imageName: String
    let statusLabel: String
    let isLocked: Bool
    if case .locked = trait.attributes.lockState {
      imageName = "lock_lock_symbol"
      statusLabel = "Locked"
      isLocked = true
    } else {
      imageName = "lock_open_lock_open_symbol"
      statusLabel = "Unlocked"
      isLocked = false
    }
    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      imageName: imageName,
      isActive: isLocked,
      isBusy: isBusy,
      statusLabel: statusLabel,
      error: nil
    )
  }

  private func isRequiresPinCode()  -> Bool {
    guard
      let doorLockDeviceType = self.doorLockDeviceType,
      let trait = doorLockDeviceType.matterTraits.doorLockTrait,
      let isPin = trait.attributes.requirePinforRemoteOperation
    else { return false}
    Logger().info("requires pin: \(isPin)")
    return isPin
  }
}
