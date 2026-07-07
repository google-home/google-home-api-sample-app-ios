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
struct AreaPresenceStateView: View {
  @ObservedObject var viewModel: AreaPresenceStateViewModel

  var body: some View {
    List {
      Section(header: Text("Opt-in to Presence")) {
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
          Text("Area Presence")
        }
      }
      Section {
        Button("Delete Presence History", role: .destructive) {
          Task {
            await self.viewModel.deletePresenceHistory()
          }
        }
      }
    }
    .listStyle(.grouped)
    .navigationBarTitle("Area Presence", displayMode: .inline)
    .task {
      await self.viewModel.monitorOptInStatus()
    }
  }
}
