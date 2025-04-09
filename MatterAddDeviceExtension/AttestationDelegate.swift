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

import Foundation
import Matter
import OSLog

class AttestationDelegate: NSObject, MTRDeviceAttestationDelegate {

  // MARK: - MTRDeviceAttestationDelegate

  func deviceAttestationCompleted(
    for controller: MTRDeviceController,
    opaqueDeviceHandle: UnsafeMutableRawPointer,
    attestationDeviceInfo: MTRDeviceAttestationDeviceInfo,
    error: (any Error)?
  ) {
    Logger().info("AttestationDelegate - deviceAttestationCompleted (error: \(error)).")
    do {
      /// the AttestationDelegate is optional, so we can set ignoreAttestationFailure as true here
      /// detail see the document of MTRDeviceAttestationDelegate from Apple
      try controller.continueCommissioningDevice(opaqueDeviceHandle, ignoreAttestationFailure: true)
    } catch {
      Logger().error("AttestationDelegate - failed to continue commissioning device error: \(error).")
    }
  }

  func deviceAttestationFailed(
    for controller: MTRDeviceController,
    opaqueDeviceHandle: UnsafeMutableRawPointer,
    error: any Error
  ) {
    Logger().error("AttestationDelegate - deviceAttestationFailed with error: \(error).")
    do {
      /// the AttestationDelegate is optional, so we can set ignoreAttestationFailure as true here
      /// detail see the document of MTRDeviceAttestationDelegate from Apple
      try controller.continueCommissioningDevice(opaqueDeviceHandle, ignoreAttestationFailure: true)
    } catch {
      Logger().error("AttestationDelegate - failed to continue commissioning device error: \(error).")
    }
  }
}
