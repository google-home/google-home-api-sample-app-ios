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
import Foundation
import SwiftUI

@MainActor
struct AutomationView: View {
  @StateObject private var viewModel: AutomationViewModel
  @State public var isShowingEditNameView: Bool = false
  @State public var isShowingEditSaveError: Bool = false
  @State public var isShowingExecuteAutomationError: Bool = false
  @Environment(\.dismiss) var dismiss

  public var body: some View {
    NavigationView {
      VStack(alignment: .leading) {
        List {
          infoSection()
          startersSection()
          conditionsSection()
          actionsSection()
        }
        .listStyle(.inset)
        .listRowSeparator(.hidden)
        Spacer()
      }
      .navigationDestination(isPresented: $isShowingEditNameView) {
        EditNameView(
          name: $viewModel.automationName, description: $viewModel.automationDescription
        )
        .navigationTitle("Edit Name")
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .navigationBarTrailing) {
        Menu {
          createEditNameButton()
          createSaveAutomationButton()
          createExecuteAutomationButton()
        } label: {
          Image("settings_symbol")
        }.disabled(viewModel.isBusy)
      }
    }
  }

  init(viewModel: AutomationViewModel) {
    _viewModel = StateObject(wrappedValue: viewModel)
  }

  private func infoSection() -> some View {
    Section("Info") {
      Text(viewModel.automationName)
        .foregroundColor(Color("fontColor"))
        .font(.title)
      Text(viewModel.automationDescription)
        .foregroundColor(Color("fontColor"))
    }.listRowSeparator(.hidden)
  }

  private func createEditNameButton() -> some View {
    return Button {
      isShowingEditNameView = true
    } label: {
      Label("Edit name", image: "edit_symbol")
    }
  }

  private func createSaveAutomationButton() -> some View {
    Button {
      Task {
        do {
          try await viewModel.saveAutomation()
          dismiss()
        } catch {
          isShowingEditSaveError = true
        }
      }
    } label: {
      Label("Save", image: "save")
    }
    .alert("Unable to save automation", isPresented: $isShowingEditSaveError) {
      Button("Dismiss") {
       viewModel.saveError = nil
      }
    }
  }

  private func createExecuteAutomationButton() -> some View {
    Button {
      Task {
        do {
          try await viewModel.executeAutomation()
        } catch {
          isShowingExecuteAutomationError = true
        }
      }
    } label: {
      Label("Execute", image: "play_arrow_symbol")
    }
    .alert("Unable to execute automation", isPresented: $isShowingExecuteAutomationError) {
      Button("Dismiss") {
        viewModel.executionError = nil
      }
    }
    .disabled(!viewModel.isManuallyExecutable)
  }

  private func startersSection() -> some View {
    Section("Starters") {
      if !viewModel.automationModel.starters.isEmpty {
        ForEach(viewModel.automationModel.starters, id: \.self) { starterText in
          Text(starterText)
        }
      }
    }.listRowSeparator(.hidden)
  }

  private func conditionsSection() -> some View {
    Section("Conditions") {
      if !viewModel.automationModel.conditions.isEmpty {
        ForEach(viewModel.automationModel.conditions, id: \.self) { conditionText in
          Text(conditionText)
        }
      }
    }.listRowSeparator(.hidden)
  }

  private func actionsSection() -> some View {
    Section("Actions") {
      if !viewModel.automationModel.actions.isEmpty {
        ForEach(viewModel.automationModel.actions, id: \.self) { actionText in
          Text(actionText)
        }
      }
    }.listRowSeparator(.hidden)
  }
}

/// View for editing name and description for an automation.
public struct EditNameView: View {
  @Binding var name: String
  @Binding var description: String

  public var body: some View {
    VStack {
      Text("Name")
      TextField("name", text: $name)
        .border(.secondary)
        .textFieldStyle(.roundedBorder)
        .padding()
      Text("Description")
      TextField("description", text: $description,  axis: .vertical)
        .lineLimit(5...10)
        .border(.secondary)
        .textFieldStyle(.roundedBorder)
        .padding()
    }
    .padding(.horizontal, 16)
    .padding(.top, 16)
  }
}
