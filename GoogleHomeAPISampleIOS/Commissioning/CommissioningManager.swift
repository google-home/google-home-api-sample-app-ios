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
import Foundation
import GoogleHomeSDK
import Matter
import MatterSupport
import OSLog

/// Manages the matter device commissioning flow to add a new matter device.
public class CommissioningManager: NSObject, ObservableObject {

  private static let appGroup = "HOME_API_TODO_ADD_APP_GROUP"

  // MARK: - Initialization

  public override init() {}

  // MARK: - Public

  /// Starts the Matter device commissioning flow to add the device to the user's home.
  /// - Parameters:
  ///   - structure: The structure to add the device to.
  ///   - add3PFabricFirst: Whether to add the device to a third party fabric first.
  ///   - setupPayload: The custom payload to be used to bypass the QR code scanning process.
  /// - Returns: The IDs of the commissioned devices. A set is returned because a single
  ///   commissioned entity (e.g., a bridge) may expose multiple devices.
  /// - Throws: An error if the commissioning flow fails.
  public func addMatterDevice(
    to structure: Structure, add3PFabricFirst: Bool, setupPayload: String? = nil
  ) async throws -> Set<String> {
    /// pass if it's 1p or 3p commissioning
    let userDefaults = UserDefaults(
      suiteName: CommissioningManager.appGroup)
    userDefaults?.set(
    add3PFabricFirst, forKey: CommissioningUserDefaultsKeys.shouldPerform3PFabricCommissioning)

    do {
      try await structure.prepareForMatterCommissioning()
    } catch {
      Logger().error("Failed to prepare for Matter Commissioning: \(error).")
      throw error
    }

    // Prepare the Matter request by providing the ecosystem name and home to be added to.
    let topology = MatterAddDeviceRequest.Topology(
      ecosystemName: "Google Home",
      homes: [MatterAddDeviceRequest.Home(displayName: structure.name)]
    )
    let payload = self.createMatterSetupPayload(from: setupPayload)
    let request = MatterAddDeviceRequest(topology: topology, setupPayload: payload)

    do {
      Logger().info("Starting MatterAddDeviceRequest.")
      try await request.perform()
      Logger().info("Completed MatterAddDeviceRequest.")
      let commissionedDeviceIDs = try await structure.completeMatterCommissioning()
      Logger().info("Commissioned device IDs: \(commissionedDeviceIDs).")
      return commissionedDeviceIDs
    } catch let error {
      let result = structure.markMatterCommissioningFailed(error: error)
      Logger().error("Failed to complete MatterAddDeviceRequest: \(result.detailedError).")
      throw error
    }
  }

  private func createMatterSetupPayload(from setupPayload: String?) -> MTRSetupPayload? {
    guard let setupPayload = setupPayload else {
      return nil
    }
    return MatterCommissioningUtils.matterSetupPayload(from: setupPayload)
  }
}
