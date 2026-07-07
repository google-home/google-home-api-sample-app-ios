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
import SwiftUI

/// the error set for device errors, input deviceType
enum HomeSampleError: Error {
  case unableToCreateControlForDeviceType(deviceType: String)
  case unableToUpdateControlForDeviceType(deviceType: String)
  case unableToSaveAutomation(error: String)
  case unableToExecuteAutomation
  case noHubFound
  case errorSavingAutomation(error: String)
  case unableToLinkCloudAccount(error: String)
  case unableToSyncLinkedDevices(error: String)

  var title: String {
    alertInfo.title
  }

  private var alertInfo: (title: String, message: String) {
    switch self {
    case .unableToCreateControlForDeviceType(let deviceType):
      return ("Device Control Error", "Unable to create control for device type: \(deviceType)")
    case .unableToUpdateControlForDeviceType(let deviceType):
      return ("Device Control Error", "Unable to update control for device type: \(deviceType)")
    case .unableToSaveAutomation(let error), .errorSavingAutomation(let error):
      return ("Unable to save automation", "An error occurred:\n\n\(error)")
    case .unableToExecuteAutomation:
      return ("Unable to execute automation", "An error occurred while executing the automation.")
    case .noHubFound:
      return ("No hub found.", "Please ensure a hub is set up in your home.")
    case .unableToLinkCloudAccount(let error):
      return ("Link Cloud Account Error", "Unable to link cloud account: \(error)")
    case .unableToSyncLinkedDevices(let error):
      return ("Sync Linked Devices Error", "Unable to sync linked devices: \(error)")
    }
  }
}

extension HomeSampleError: LocalizedError {
  var errorDescription: String? {
    alertInfo.message
  }
}

struct ErrorAlertModifier: ViewModifier {
  @Binding var isPresented: Bool
  let error: HomeSampleError?
  var onDismiss: (() -> Void)? = nil

  func body(content: Content) -> some View {
    content
      .alert(error?.title ?? "Error", isPresented: $isPresented) {
        Button("Dismiss", role: .cancel) {
          onDismiss?()
        }
      } message: {
        if let description = error?.errorDescription {
          Text(description)
            .font(.system(.body, design: .monospaced))
        }
      }
  }
}

extension View {
  func errorAlert(isPresented: Binding<Bool>, error: HomeSampleError?, onDismiss: (() -> Void)? = nil) -> some View {
    modifier(ErrorAlertModifier(isPresented: isPresented, error: error, onDismiss: onDismiss))
  }
}
