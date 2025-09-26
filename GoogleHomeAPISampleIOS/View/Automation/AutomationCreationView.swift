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

struct AutomationCreationView: View {

  @Environment(\.presentationMode) var presentationMode
  let viewModel: AutomationCreationViewModel
  @Binding var navigationPath: NavigationPath
  @State var showProgressView = false

  public var body: some View {
    VStack {
      /// Read starters, conditions, and actions from the data model and display them
      List {
        inputSection()
        if !viewModel.automationModel.starters.isEmpty {
          startersSection()
        }
        if !viewModel.automationModel.conditions.isEmpty {
          conditionsSection()
        }
        if !viewModel.automationModel.actions.isEmpty {
          actionsSection()
        }
      }
      .listStyle(.inset)
      .listRowSeparator(.hidden)
      .padding(.top, .lg)

      saveButtonView()
    }
    .listStyle(.inset)
    .navigationTitle("Add Automations")
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
    Section {
      Text(viewModel.automationModel.name)
      Text(viewModel.automationModel.description)
            .font(.footnote)
    }
    .listRowSeparator(.hidden)
  }
  private func startersSection() -> some View {
    Section("Starters") {
      ForEach(viewModel.automationModel.starters, id: \.self) { starterText in
        CreateButtonView(imageName: "bolt_symbol", text1: starterText, text2: "") {}
      }
    }.listRowSeparator(.hidden)
  }

  private func conditionsSection() -> some View {
    Section("Conditions") {
      ForEach(viewModel.automationModel.conditions, id: \.self) { conditionText in
        CreateButtonView(imageName: "checklist_symbol", text1: conditionText, text2: "") {}
      }
    }.listRowSeparator(.hidden)
  }

  private func actionsSection() -> some View {
    Section("Actions") {
      ForEach(viewModel.automationModel.actions, id: \.self) { actionText in
        CreateButtonView(imageName: "play_arrow_symbol", text1: actionText, text2: "") {}
      }
    }.listRowSeparator(.hidden)
  }

  private func saveButtonView() -> some View {
    HStack {
      Spacer()
      Button(action: {
        showProgressView = true
        Task {
          try await viewModel.createAutomation()
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
      .alignmentGuide(.bottom) { $0[.bottom] }
      .background(Color.clear)
    }
  }
}
