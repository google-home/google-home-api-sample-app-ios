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

struct MainView: View {
  @StateObject private var accountViewModel: AccountViewModel
  @StateObject private var mainViewModel: MainViewModel

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
          self.mainViewModel.selectedStructure?.name ?? "Google Home SDK Demo",
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
              Menu(selectedStructure?.name ?? "Select Structure") {
                ForEach(sortedStructures) { structure in
                  let isSelected = structure.id == selectedID
                  Button(
                    structure.name,
                    systemImage: isSelected ? "checkmark" : "house"
                  ) {
                    self.mainViewModel.updateSelectedStructureID(structure.id)
                  }
                }
              }
            }
          }

          ToolbarItemGroup(placement: .navigationBarTrailing) {
            AnyView(self.accountViewModel.toolbarAccessoryView)
          }
        }.sheet(isPresented: self.$accountViewModel.isShowAboutView) {
          AboutView(accountViewModel: self.accountViewModel)
        }
    }
  }

  @ViewBuilder
  var conditionalStructureView: some View {
    let structureViewModel =
      self.mainViewModel.structureViewModel(
        structureID: self.mainViewModel.selectedStructureID)

    if let structureViewModel {
      StructureView(viewModel: structureViewModel)
        .environmentObject(self.mainViewModel)
    } else if accountViewModel.home == nil {
      Text("Sign In Required")
    } else {
      Text("No available structures.")
    }
  }
}
