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

import MatterSupport
import GoogleHomeSDK
import OSLog

extension Logger {
  private static let subsystem = "GoogleHomeAPISampleIOS.MatterAddDeviceExtension"
  static let commissioning = Logger(subsystem: subsystem, category: "commissioning")
}


/// The extension is launched in response to `MatterAddDeviceRequest.perform()`.
final class RequestHandler: MatterAddDeviceExtensionRequestHandler {
  // The App Group ID defined by the application to share information between the extension and main app.
  private static let appGroup = "HOME_API_TODO_ADD_APP_GROUP"

  override init() {
    Logger.commissioning.info("Initializing RequestHandler")
    super.init()
  }

  deinit {
    Logger.commissioning.info("Deinitializing RequestHandler")
  }

  // MARK: - Default implementation handlers

  override func validateDeviceCredential(_ deviceCredential: MatterAddDeviceExtensionRequestHandler.DeviceCredential) async throws {
    Logger.commissioning.info("Received request to validate device credentials.")
  }

  override func selectWiFiNetwork(from wifiScanResults: [MatterAddDeviceExtensionRequestHandler.WiFiScanResult]) async throws -> MatterAddDeviceExtensionRequestHandler.WiFiNetworkAssociation {
    Logger.commissioning.info("Selecting Default System Wi-Fi Network.")
    return .defaultSystemNetwork
  }

  override func selectThreadNetwork(from threadScanResults: [MatterAddDeviceExtensionRequestHandler.ThreadScanResult]) async throws -> MatterAddDeviceExtensionRequestHandler.ThreadNetworkAssociation {
    Logger.commissioning.info("Selecting Default System Thread Network")
    return .defaultSystemNetwork
  }

  // MARK: - Home API commissioning handlers

  /// Commissions a device to the Google Home ecosystem.
  /// - Parameters:
  ///   - home: The home that the device will be added to.
  ///   - onboardingPayload: The payload to be sent to the Matter Commissioning SDK to commission the device.
  ///   - commissioningID: An identifier not used by the Home API SDK.
  override func commissionDevice(in home: MatterAddDeviceRequest.Home?, onboardingPayload: String, commissioningID: UUID) async throws {
    Logger.commissioning.info("Commission Matter device with payload: '\(onboardingPayload)'.")

    var onboardingPayloadForHub = onboardingPayload

    if self.was3PFabricCommissioningRequested() {
      guard #available(iOS 17.6, *) else {
        throw Error.unsupportedOSVersion
      }

      let thirdPartyFabricCommissioner = ThirdPartyFabricCommissioner()
      Logger.commissioning.info("Commission to 3p fabric.")
      try await thirdPartyFabricCommissioner.commissionDevice(payload: onboardingPayload)
      // If the device is commissioned to a 3P fabric, the hub needs to use the onboarding payload
      // from the new commissioning window that the 3P fabric opened, instead of the original
      // onboarding payload provided by the Apple API.
      onboardingPayloadForHub = try await thirdPartyFabricCommissioner.openNewCommissioningWindow()
    }

    let homeMatterCommissioner = try HomeMatterCommissioner(appGroup: RequestHandler.appGroup)
    Logger.commissioning.info("Commission to 1p fabric.")
    try await homeMatterCommissioner.commissionMatterDevice(
      onboardingPayload: onboardingPayloadForHub)
  }


  /// Obtains rooms from the Home Ecosystem to provide to the Apple commissioning flow.
  /// - Parameter home: The home that the device will be added to.
  /// - Returns: A list of rooms if obtained from the Google Home ecosystem or an empty list if there was an error in getting them.
  override func rooms(in home: MatterAddDeviceRequest.Home?) async -> [MatterAddDeviceRequest.Room] {
    do {
      let homeMatterCommissioner = try HomeMatterCommissioner(appGroup: RequestHandler.appGroup)
      let fetchedRooms = try homeMatterCommissioner.fetchRooms()
      Logger.commissioning.info("Returning \(fetchedRooms.count) fetched rooms.")
      return fetchedRooms
    } catch {
      Logger.commissioning.info("Failed to fetch rooms with error: \(error).")
      return []
    }
  }


  /// Pushes the device's configurations to the Google Home Ecosystem.
  /// - Parameters:
  ///   - name: The friendly name the user chose to set on the device.
  ///   - room: The room identifier that the user chose to put the device in.
  override func configureDevice(named name: String, in room: MatterAddDeviceRequest.Room?) async {
    Logger.commissioning.info("Configure Device name: '\(name)', room: \(room?.displayName ?? "").")
    do {
      let homeMatterCommissioner = try HomeMatterCommissioner(appGroup: RequestHandler.appGroup)
      try await homeMatterCommissioner.configureMatterDevice(
        deviceName: name, roomName: room?.displayName)
    } catch {
      Logger.commissioning.info("Configure Device failed with error: \(error).")
    }
  }

  private func was3PFabricCommissioningRequested() -> Bool {
      guard
        let userDefaults = UserDefaults(
          suiteName: RequestHandler.appGroup)
      else {
        return false
      }
      return userDefaults.bool(
        forKey: CommissioningUserDefaultsKeys.shouldPerform3PFabricCommissioning)
    }
}

// MARK: - `DemoMatterAddDeviceExtensionRequestHandler.Error`

extension MatterAddDeviceExtensionRequestHandler {
  public enum Error: Swift.Error {
    case unsupportedOSVersion
  }
}
