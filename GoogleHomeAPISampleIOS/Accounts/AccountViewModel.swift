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

  /// The current Home client.
  @Published var home: Home?
  @Published var isShowAboutView: Bool = false

  init() {
    Task {
      // If a session is not found, this method will return nil.
      self.home = await Home.restoreSession()
    }
  }

  /// The view to display in the toolbar accessory.
  @ViewBuilder
  var toolbarAccessoryView: any View {
    if self.home == nil {
      Button("Connect", action: self.connect)
    } else {
      Menu {
        Button("Disconnect", action: self.disconnect)
        Button("Update permissions", action: self.updatePermissions)
        Button("About") {
          self.isShowAboutView.toggle()
        }
      } label: {
        Image(systemName: "ellipsis")
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
      self.home?.presentPermissionsUpdate()
    }
  }
}
