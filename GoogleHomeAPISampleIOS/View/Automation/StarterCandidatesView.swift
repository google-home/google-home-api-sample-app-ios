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

import CoreFoundation
import SwiftUI

@MainActor
/// Display starter candidates
struct StarterCandidatesView: View {
  @ObservedObject private var viewModel: CandidatesViewModel
  @Binding var navigationPath: NavigationPath

  init(viewModel: CandidatesViewModel, navigationPath: Binding<NavigationPath>) {
    self.viewModel = viewModel
    self._navigationPath = navigationPath
  }

  public var body: some View {
    VStack{
      conditionalCandidateList()
    }
    .listStyle(.inset)
    .navigationTitle("Starter Candidates")
    .navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder
  private func conditionalCandidateList() -> some View {
    if self.viewModel.hasLoaded && self.viewModel.roomEntries.isEmpty {
      Text("No devices in '\(self.viewModel.structure.name)'")
        .foregroundColor(Color("fontColor"))
        .padding()
    } else if self.viewModel.hasLoaded {
      actualCandidateList()
    }
  }

  /// Display candidate devices in the structure
  private func actualCandidateList() -> some View {
    List {
      ForEach(self.viewModel.roomEntries.sorted()) { entry in
        Section {
          ForEach(entry.devices, id: \.id) { device in
            CreateButtonView(imageName: device.iconName, text1: device.device.name, text2: "") {
              viewModel.selectedStarterDevice = device
              /// Redirect to the StarterCandidateDetailView with selected device
              navigationPath.append(Destination.StarterCandidateDetailView)
            }
            .padding(.bottom, 8)
          }.listRowSeparator(.hidden)
        } header: {
          HStack {
            Text(entry.room.name).foregroundColor(Color("fontColor"))
          }
        }.textCase(nil)
      }
    }
  }
}
