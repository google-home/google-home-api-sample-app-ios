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
import GoogleHomeTypes
import SwiftUI
import UIKit

struct MainView: View {

  private enum Constants {
    static let defaultNavigationTitle = "Google Home SDK Demo"
    static let selectedStructureIcon = "checkmark"
    static let unselectedStructureIcon = "house"
    static let selectStructurePlaceholder = "Select Structure"
    static let chevronIcon = "chevron.up.chevron.down"
    static let signInRequiredText = "Sign In Required"
    static let noStructuresText = "No available structures."
    static let snapshotSuccessAlertTitle = "Structure Snapshot UUID"
    static let snapshotCopyButtonTitle = "Copy UUID"
    static let snapshotCloseButtonTitle = "Close"
    static let snapshotFailureAlertTitle = "Structure Snapshot Failed"
    static let snapshotFailureAlertMessage = "Failed to request structure snapshot."
    static let snapshotOKButtonTitle = "OK"

    static func snapshotSuccessAlertMessage(uuid: String) -> String {
      "Snapshot requested successfully.\nUUID: \(uuid)"
    }
  }

  @StateObject private var accountViewModel: AccountViewModel
  @StateObject private var mainViewModel: MainViewModel
  @State private var snapshotUUID: String = ""
  @State private var isShowSnapshotSuccessAlert: Bool = false
  @State private var isShowSnapshotFailureAlert: Bool = false

  init() {
    let accountViewModel = AccountViewModel()
    _accountViewModel = StateObject(wrappedValue: accountViewModel)

    let mainViewModel = MainViewModel(homePublisher: accountViewModel.$home)
    _mainViewModel = StateObject(wrappedValue: mainViewModel)
  }

  var body: some View {
    NavigationView {
      conditionalStructureView
        .navigationBarTitle(
          self.mainViewModel.selectedStructure?.name ?? Constants.defaultNavigationTitle,
          displayMode: .inline
        )
        .toolbar {
          if mainViewModel.structures.count > 0 {
            ToolbarItemGroup(placement: .principal) {
              // Sort the menu entries alphabetically.
              let sortedStructures = self.mainViewModel.structures.sorted {
                $0.name < $1.name
              }
              let selectedID = self.mainViewModel.selectedStructureID
              let selectedStructure = self.mainViewModel.structure(
                structureID: selectedID)
              let areaPresenceStateText = self.mainViewModel.areaPresenceState?.text
              Menu {
                ForEach(sortedStructures) { structure in
                  let isSelected = structure.id == selectedID
                  Button(
                    structure.name,
                    systemImage: isSelected
                      ? Constants.selectedStructureIcon : Constants.unselectedStructureIcon
                  ) {
                    self.mainViewModel.updateSelectedStructureID(structure.id)
                  }
                }
              } label: {
                let name = selectedStructure?.name ?? Constants.selectStructurePlaceholder
                if let areaPresenceStateText {
                  Text(
                    "\(name) (\(areaPresenceStateText)) \(Image(systemName: Constants.chevronIcon))"
                  )
                } else {
                  Text("\(name) \(Image(systemName: Constants.chevronIcon))")
                }
              }
            }
          }

          ToolbarItemGroup(placement: .navigationBarTrailing) {
            self.accountViewModel.toolbarAccessoryView(
              onCollectSnapshot: self.mainViewModel.selectedStructure != nil
                ? self.handleCollectSnapshot : nil
            )
          }
        }
        .sheet(isPresented: self.$accountViewModel.isShowAboutView) {
          AboutView(accountViewModel: self.accountViewModel)
        }
        .alert(
          Constants.snapshotSuccessAlertTitle,
          isPresented: self.$isShowSnapshotSuccessAlert
        ) {
          Button(Constants.snapshotCopyButtonTitle) {
            UIPasteboard.general.string = self.snapshotUUID
          }
          Button(Constants.snapshotCloseButtonTitle, role: .cancel) {}
        } message: {
          Text(Constants.snapshotSuccessAlertMessage(uuid: self.snapshotUUID))
        }
        .alert(
          Constants.snapshotFailureAlertTitle,
          isPresented: self.$isShowSnapshotFailureAlert
        ) {
          Button(Constants.snapshotOKButtonTitle, role: .cancel) {}
        } message: {
          Text(Constants.snapshotFailureAlertMessage)
        }
    }
  }

  @ViewBuilder
  var conditionalStructureView: some View {
    let structureViewModel =
      self.mainViewModel.structureViewModel(
        structureID: self.mainViewModel.selectedStructureID)

    Group {
      if let structureViewModel {
        StructureView(viewModel: structureViewModel)
          .environmentObject(self.mainViewModel)
      } else if accountViewModel.home == nil {
        Text(Constants.signInRequiredText)
      } else {
        Text(Constants.noStructuresText)
      }
    }
    .sheet(isPresented: self.$accountViewModel.isShowUserManagementView) {
      if let home = self.accountViewModel.home {
        NavigationStack {
          UserManagementView(home: home) {
            self.accountViewModel.isShowUserManagementView = false
          }
        }
      }
    }
  }

  private func handleCollectSnapshot() {
    Task {
      if let uuid = await self.mainViewModel.sendStructureSnapshot() {
        self.snapshotUUID = uuid
        self.isShowSnapshotSuccessAlert = true
      } else {
        self.isShowSnapshotFailureAlert = true
      }
    }
  }
}
