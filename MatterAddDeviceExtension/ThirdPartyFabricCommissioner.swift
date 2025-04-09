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

import Dispatch
import Foundation
import Matter
import OSLog
import Security

/// Helper class responsible for commissioning a device onto a "3P" fabric.
///
/// This is really just using an arbitrary test fabric and only storing the keypair/IPK in memory,
/// the fabric is not functional to control the device. It's only use is for testing the
/// commissioning flow in which a 3P will first commission a device onto their fabric, then use the
/// Home APIs to commission the device onto the Google fabric.
@available(iOS 17.6, *)
class ThirdPartyFabricCommissioner: NSObject {

  /// this is a test fabric
  private let fabricID: NSNumber = 0xABCD_0123_4567
  private let newNodeID: NSNumber = 1
  private let storage = InMemoryMatterStorage()
  private let workQueue = DispatchQueue(label: "3P-Fabric-Commissioner")
  private let attestationDelegate = AttestationDelegate()

  private var ipk: Data?
  private var keypair: MatterKeypair?
  private var controller: MTRDeviceController?
  private var commissioningContinuation: CheckedContinuation<Void, Swift.Error>?

  /// Store the VID/PID of the device being commissioned from the payload passed to
  /// `commissionDevice`. These values are then used to create the QR code string from the re-opened
  /// commissioning window.
  private var vendorID: NSNumber?
  private var productID: NSNumber?

  func commissionDevice(payload: String) async throws {
    Logger().info("3P Fabric Commissioner - commissionDevice with payload: \(payload)")
    let factory = MTRDeviceControllerFactory.sharedInstance()
    let factoryParams = MTRDeviceControllerFactoryParams(storage: self.storage)

    // Leave `factoryParams.productAttestationAuthorityCertificates` as nil to use the default test
    // PAA certificates.
    factoryParams.productAttestationAuthorityCertificates = nil

    try factory.start(factoryParams)

    let ipk = NSMutableData(length: 16)!
    let status = SecRandomCopyBytes(kSecRandomDefault, ipk.count, ipk.mutableBytes)
    guard status == errSecSuccess else {
      throw Error.failedToGenerateIPK
    }
    self.ipk = ipk as Data

    let rootKeypair = MatterKeypair()
    try rootKeypair.initialize()
    self.keypair = rootKeypair

    let params = MTRDeviceControllerStartupParams(
      ipk: ipk as Data,
      fabricID: self.fabricID,
      nocSigner: rootKeypair)
    params.vendorID = 0xFFF1  // Test Vendor ID

    let controller = try factory.createController(onNewFabric: params)
    controller.setDeviceControllerDelegate(self, queue: self.workQueue)
    self.controller = controller

    let setupPayload = try MTRSetupPayload(onboardingPayload: payload)
    self.vendorID = setupPayload.vendorID
    self.productID = setupPayload.productID
    Logger().debug("Storing the vendorID: \(self.vendorID) and productID: \(self.productID).")

    Logger().info("3P Fabric Commissioner - starting setupCommissioningSession.")
    try controller.setupCommissioningSession(with: setupPayload, newNodeID: self.newNodeID)

    try await withCheckedThrowingContinuation { continuation in
      self.commissioningContinuation = continuation
    }
  }

  func openNewCommissioningWindow() async throws -> String {
    guard let controller = self.controller else {
      throw Error.missingDeviceController
    }

    let device = MTRDevice(nodeID: self.newNodeID, controller: controller)

    let discriminator = NSNumber(value: UInt16.random(in: 0...0x0FFF))

    let setupPayload = try await device.openCommissioningWindow(
      withDiscriminator: discriminator,
      duration: 480,
      queue: self.workQueue)

    if let vendorID = self.vendorID, let productID = self.productID, vendorID != 0, productID != 0 {
      setupPayload.vendorID = vendorID
      setupPayload.productID = productID
    }

    guard let qrCodeString = try? setupPayload.qrCodeString() else {
      throw Error.missingSetupPayload
    }
    return qrCodeString
  }

  // MARK: - Private

  private func finishCommissioning() {
    let continuation = self.commissioningContinuation
    self.commissioningContinuation = nil
    continuation?.resume()
  }

  private func failCommissioning(error: Swift.Error) {
    let continuation = self.commissioningContinuation
    self.commissioningContinuation = nil
    continuation?.resume(throwing: error)
  }
}

// MARK: - `MTRDeviceControllerDelegate`

@available(iOS 17.6, *)
extension ThirdPartyFabricCommissioner: MTRDeviceControllerDelegate {

  func controller(
    _: MTRDeviceController,
    statusUpdate status: MTRCommissioningStatus
  ) {
    if status == .failed {
      self.failCommissioning(error: Error.commissioningFailedStatus)
    }
    Logger().info("Commissioning status update")
  }

  func controller(
    _ controller: MTRDeviceController,
    commissioningSessionEstablishmentDone error: Swift.Error?
  ) {
    if let error = error {
      Logger().error("Failed to establish commissioning session for 3P fabric: \(error)")
      self.failCommissioning(error: error)
      return
    }

    Logger().info("Commissioning session established for 3P fabric")

    let commissioningParams = MTRCommissioningParameters()
    commissioningParams.deviceAttestationDelegate = self.attestationDelegate

    do {
      // `newNodeID` must match the node ID passed to `setupCommissioningSessionWithPayload`.
      try controller.commissionNode(
        withID: self.newNodeID,
        commissioningParams: commissioningParams)
    } catch {
      Logger().error("Failed to start commissioning node for 3P fabric: \(error)")
      self.failCommissioning(error: error)
    }
  }

  func controller(
    _: MTRDeviceController,
    commissioningComplete error: Swift.Error?,
    nodeID: NSNumber?
  ) {
    if let error = error {
      Logger().error("Failed to complete commissioning for 3P fabric: \(error)")
      self.failCommissioning(error: error)
      return
    }

    Logger().info("Commissioning complete for 3P fabric")
    self.finishCommissioning()
  }
}

// MARK: - `ThirdPartyFabricCommissioner.Error`

@available(iOS 17.6, *)
extension ThirdPartyFabricCommissioner {

  enum Error: Swift.Error {
    case commissioningFailedStatus
    case failedToGenerateIPK
    case missingDeviceController
    case missingSetupPayload

    var errorDescription: String? {
      switch self {
      case .commissioningFailedStatus:
        return "commissioning status is failed"
      case .failedToGenerateIPK:
        return "failed to generate IPK"
      case .missingDeviceController:
        return "DeviceController is missing"
      case .missingSetupPayload:
        return "SetupPayload is missing"
      }
    }
  }
}
