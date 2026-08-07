// Copyright 2026 Google LLC
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

import SwiftUI

/// A view of area presence state.
///
/// - Note: Separates structure occupancy (`AreaPresenceStateTrait`) from user device opt-in (`setPresenceOptIn`).
struct AreaPresenceStateView: View {
  @ObservedObject var viewModel: AreaPresenceStateViewModel

  private enum Constants {
    static let currentStateHeader = "Current State"
    static let presenceStateLabel = "Presence State"
    static let unknownValue = "Unknown"
    static let optInSectionHeader = "Opt-in to Presence"
    static let areaPresenceToggle = "Area Presence"
    static let deleteHistoryButton = "Delete Presence History"
    static let navigationTitle = "Area Presence"
  }

  var body: some View {
    List {
      // Displays aggregate structure occupancy (e.g., Home/Away).
      Section(header: Text(Constants.currentStateHeader)) {
        HStack {
          Text(Constants.presenceStateLabel)
          Spacer()
          Text(self.viewModel.areaPresenceState?.text ?? Constants.unknownValue)
            .foregroundColor(.secondary)
        }
      }
      // Controls whether this user's device contributes to presence sensing.
      Section(header: Text(Constants.optInSectionHeader)) {
        Toggle(
          isOn: Binding<Bool>(
            get: { self.viewModel.optInStatus },
            set: { isToggled in
              Task {
                await self.viewModel.optInToAreaPresence(optIn: isToggled)
              }
            }
          )
        ) {
          Text(Constants.areaPresenceToggle)
        }
      }
      // Clears historical presence transition events from storage.
      Section {
        Button(Constants.deleteHistoryButton, role: .destructive) {
          Task {
            await self.viewModel.deletePresenceHistory()
          }
        }
      }
    }
    .listStyle(.grouped)
    .navigationBarTitle(Constants.navigationTitle, displayMode: .inline)
    .task {
      self.viewModel.monitorAreaPresenceState()
      await self.viewModel.monitorOptInStatus()
    }
  }
}
