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
import GoogleHomeTypes
import SwiftUI

struct GenericEditorView: View {

  @ObservedObject private var viewModel: GenericEditorViewModel
  /// For Discovery API to fetch candidates and to store selected components
  @ObservedObject private var candidatesViewModel: CandidatesViewModel
  private let automationRepository: AutomationsRepository
  @Binding var navigationPath: NavigationPath
  @State var showProgressView = false

  init(viewModel: GenericEditorViewModel, candidatesViewModel: CandidatesViewModel, automationRepository: AutomationsRepository, navigationPath: Binding<NavigationPath>) {
    self.viewModel = viewModel
    self.candidatesViewModel = candidatesViewModel
    self.automationRepository = automationRepository
    self._navigationPath = navigationPath
    /// Clear anything previously stored
    candidatesViewModel.clearSelected()
  }

  public var body: some View {
    VStack {
      List {
        inputSection()
        startersSection()
        actionSection()
      }
      .listStyle(.inset)
      .listRowSeparator(.hidden)
      .padding(.top, .lg)

      saveButtonView()

    }
    .listStyle(.inset)
    .navigationTitle("Generic Editor")
    .navigationBarTitleDisplayMode(.inline)
    .overlay {
      if showProgressView {
        Color.black.opacity(0.35)
          .overlay {
            ProgressView()
              .tint(.white)
          }
      }
    }
  }

  private func inputSection() -> some View {
    Section("Info") {
      VStack {
        Text("Name")
        TextField("name", text: $viewModel.name)
          .border(.secondary)
          .textFieldStyle(.roundedBorder)
          .padding()
        Text("Description")
        TextField("description", text: $viewModel.description,  axis: .vertical)
          .lineLimit(3)
          .border(.secondary)
          .textFieldStyle(.roundedBorder)
          .padding()

      }.toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") {
              UIApplication.shared.endEditing()
          }
        }
    }

    }.listRowSeparator(.hidden)
  }

  private func startersSection() -> some View {
    Section("Starter and Condition") {
      if let device = candidatesViewModel.selectedStarters.first {
        /// If there's a selected one, display it
        if device.traitType is Matter.OnOffTrait.Type {
          let valueOnOff = device.valueOnOff ? "On": "Off"
          CreateButtonView(imageName: "astrophotography_mode_symbol", text1: device.device.name,
                           text2: valueOnOff) {}
                .padding(.bottom, .sm)
        } else if device.traitType is Matter.LevelControlTrait.Type {
          let subTitle = "\(device.operation)  \(device.levelValue)"
          CreateButtonView(imageName: "astrophotography_mode_symbol", text1: device.device.name,
                           text2: subTitle) {}
            .padding(.bottom, .sm)
        }
      } else {
        /// If there's no selected one, display a button for selection
        CreateButtonView(imageName: "astrophotography_mode_symbol", text1: "Add Starter and Condition",
                         text2: "") {
          navigationPath.append(Destination.StarterCandidatesView)
        }
        .padding(.bottom, .sm)
      }
    }.listRowSeparator(.hidden)
  }

  private func actionSection() -> some View {
    Section("Action") {
      if let device = candidatesViewModel.selectedActions.first {
        /// If there's a selected one, display it
        if device.traitType is Matter.OnOffTrait.Type {
          let valueOnOff = device.valueOnOff ? "On": "Off"
          CreateButtonView(imageName: "astrophotography_mode_symbol", text1: device.device.name, text2: valueOnOff) {}
          .padding(.bottom, .sm)
        }
      } else {
        /// If there's no selected one, display a button for selection
        CreateButtonView(imageName: "astrophotography_mode_symbol", text1: "Add Action", text2: "") {
          navigationPath.append(Destination.ActionCandidatesView)
        }
        .padding(.bottom, .sm)
      }
    }.listRowSeparator(.hidden)
  }

  private func saveButtonView() -> some View {
    HStack {
      Spacer()
      Button(action: {
        showProgressView = true
        Task {
          /// Create a DraftAutomation object
          let draftAutomation = try await automationRepository.genericAutomation(name: viewModel.name, description: viewModel.description, starters: candidatesViewModel.selectedStarters, actions: candidatesViewModel.selectedActions)
          /// Create the automation
          try await viewModel.createAutomation(draftAutomation: draftAutomation)
          /// Clear selected starter and action
          candidatesViewModel.clearSelected()
          /// Redirect back to AutomationsView
          navigationPath.removeLast(navigationPath.count)
        }
      }) {
        Text("Save")
          .frame(width: Dimensions.buttonWidth, height: Dimensions.buttonHeight)
          .background(Color.blue)
          .foregroundColor(.white)
          .cornerRadius(.md)
          .padding(.bottom, .lg)
          .padding(.trailing, .smd)
      }
      .disabled(candidatesViewModel.selectedStarters.isEmpty || candidatesViewModel.selectedActions.isEmpty)
      .alignmentGuide(.bottom) { $0[.bottom] }
      .background(Color.clear)
    }
  }
}

extension UIApplication {
  func endEditing() {
      sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}
