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

import GoogleHomeSDK
import SwiftUI
import UIKit

struct AboutView: View {
  /// The view model for account-related data.
  @ObservedObject private var accountViewModel: AccountViewModel
  @Environment(\.openURL) var openURL

  init(accountViewModel: AccountViewModel) {
    self.accountViewModel = accountViewModel
  }

  var body: some View {
    List {
      Section {
        HStack {
          Text("App Version")
          Spacer()
          Text(appVersionString())
        }
        HStack {
          Text("SDK Version")
          Spacer()
          Text("\(Home.version)")
        }
      }

      Section {
        if let url = URL(
          string:
            "https://myaccount.google.com/connections/link?project_number=\(projectNumberString())"
        ) {
          Button(action: {
            openURL(url) { accept in
              if accept {
                accountViewModel.disconnect()
              }
            }
          }) {
            HStack {
              Text("Revoke app permission")
              Spacer()
              Image(systemName: "link")
            }
          }
        } else {
          HStack {
            Text("Revoke app permission")
            Spacer()
            Text("Unavailable")
              .foregroundColor(.secondary)
          }
        }
      }
    }
  }

  /// Constructs a string representing the application's marketing version.
  ///
  /// This function retrieves the `CFBundleShortVersionString` from the app's main bundle `Info.plist`.
  /// If the version string cannot be found, it defaults to "Unknown".
  /// - Returns: A string formatted as "App Version: [marketingVersion]" or "App Version: Unknown".

  private func appVersionString() -> String {
    let marketingVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
      ?? "Unknown"
    return marketingVersion
  }

  /// Retrieves the Google Cloud Project Number from the app's `Info.plist`.
  ///
  /// This function looks for a key named "Cloud Project Number" in the main bundle's `Info.plist`.
  /// This project number is then used to construct the URL for revoking app permissions.
  /// If the project number cannot be found or is not a string, it defaults to "Unknown".
  ///
  /// - Important: Ensure that "Cloud Project Number" is correctly defined in your `Info.plist` for this function to work as expected.
  /// - Returns: The project number as a String, or "Unknown" if not found.
  private func projectNumberString() -> String {
    let projectNumber =
      Bundle.main.infoDictionary?["Cloud Project Number"] as? String
      ?? "Unknown"
    return projectNumber
  }
}
