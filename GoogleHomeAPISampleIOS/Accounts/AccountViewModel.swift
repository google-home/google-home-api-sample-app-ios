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
import OSLog
import SwiftUI

/// ViewModel for account data.
@MainActor
class AccountViewModel: ObservableObject {

  private enum Constants {
    static let connectTitle = "Connect"
    static let disconnectTitle = "Disconnect"
    static let userManagementTitle = "User Management"
    static let updatePermissionsTitle = "Update permissions"
    static let aboutTitle = "About"
    static let ellipsisIcon = "ellipsis"
    static let sendStructureSnapshotTitle = "Send Structure Snapshot"
  }

  /// The current Home client.
  @Published var home: Home?
  @Published var isShowAboutView: Bool = false
  @Published var isShowUserManagementView: Bool = false

  init() {
    Task {
      // If a session is not found, this method will return nil.
      self.home = await Home.restoreSession()
    }
  }

  /// The view to display in the toolbar accessory.
  var toolbarAccessoryView: any View {
    self.toolbarAccessoryView(onCollectSnapshot: nil)
  }

  /// Creates the view to display in the toolbar accessory.
  ///
  /// - Parameter onCollectSnapshot: Called when the user taps "Send Structure Snapshot". Pass
  ///   `nil` to hide the menu item, for example when no structure is selected.
  /// - Returns: A "Connect" button when signed out, otherwise the account actions menu.
  @ViewBuilder
  func toolbarAccessoryView(onCollectSnapshot: (() -> Void)? = nil) -> some View {
    if self.home == nil {
      Button(Constants.connectTitle, action: self.connect)
    } else {
      Menu {
        if let onCollectSnapshot {
          Button(Constants.sendStructureSnapshotTitle) {
            onCollectSnapshot()
          }
        }
        Button(Constants.disconnectTitle, action: self.disconnect)
        Button(Constants.userManagementTitle) {
          self.isShowUserManagementView.toggle()
        }
        Button(Constants.updatePermissionsTitle, action: self.updatePermissions)
        Button(Constants.aboutTitle) {
          self.isShowAboutView.toggle()
        }
      } label: {
        Image(systemName: Constants.ellipsisIcon)
      }
    }
  }

  private func connect() {
    Task {
      do {
        self.home = try await Home.connect()
      } catch {
        Logger().error("Auth error: \(error).")
      }
    }
  }

  public func disconnect() {
    Task {
      await self.home?.disconnect()
      self.home = nil
    }
  }

  private func updatePermissions() {
    Task {
      await self.home?.permissions.presentPermissionsUpdate()
    }
  }
}
