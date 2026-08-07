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
  // For Discovery API to fetch candidates and to store selected components
  @ObservedObject private var candidatesViewModel: CandidatesViewModel
  private let automationRepository: AutomationsRepository
  @Binding var navigationPath: NavigationPath
  @State var isShowingProgressView = false

  @State private var isShowingErrorAlert = false

  @State private var isShowingCameraEditSheet = false
  @State private var editedCameraDescription = ""
  @State private var selectedQueryOption = CandidatesViewModel.queryOptions.first ?? ""

  private static let sheetHeightFraction = 0.65

  @FocusState private var isSheetCameraDescriptionFocused: Bool

  let cameraOnly: Bool
  let editorTitle: String

  init(
    viewModel: GenericEditorViewModel,
    candidatesViewModel: CandidatesViewModel,
    automationRepository: AutomationsRepository,
    cameraOnly: Bool = false,
    editorTitle: String = "Generic Editor",
    navigationPath: Binding<NavigationPath>
  ) {
    self.viewModel = viewModel
    self.candidatesViewModel = candidatesViewModel
    self.automationRepository = automationRepository
    self.cameraOnly = cameraOnly
    self.editorTitle = editorTitle
    self._navigationPath = navigationPath
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
    .navigationTitle(editorTitle)
    .navigationBarTitleDisplayMode(.inline)
    .overlay {
      if isShowingProgressView {
        Color.black.opacity(0.35)
          .overlay {
            ProgressView()
              .tint(.white)
          }
      }
    }
    .errorAlert(
      isPresented: $isShowingErrorAlert,
      error: viewModel.error.map { .errorSavingAutomation(error: $0.localizedDescription) }
    ) {
      viewModel.error = nil
    }
    .sheet(isPresented: $isShowingCameraEditSheet) {
      cameraEditSheetView
    }
  }

  @ViewBuilder
  private var cameraEditSheetView: some View {
    VStack(alignment: .leading, spacing: .mmd) {
      Text("Detect Custom Activity")
        .font(.title2)
        .bold()
        .padding(.top, .xl)

      Text("Select or describe the activity or object that should trigger this automation.")
        .font(.body)
        .foregroundColor(.secondary)

      Picker("Activity Type", selection: $selectedQueryOption) {
        ForEach(CandidatesViewModel.queryOptions, id: \.self) { option in
          Text(option).tag(option)
        }
      }
      .pickerStyle(.wheel)
      .frame(height: Dimensions.CameraPicker.height)
      .padding(.top, .md)
      .padding(.bottom, Dimensions.CameraPicker.bottomPadding)

      if selectedQueryOption == "custom text" {
        TextField("Enter description...", text: $editedCameraDescription)
          .focused($isSheetCameraDescriptionFocused)
          .textFieldStyle(.roundedBorder)
          .padding(.vertical, .sm)
          .autocorrectionDisabled(true)
          .textInputAutocapitalization(.never)
      }

      Spacer()

      HStack {
        Spacer()
        Button(action: {
          let description = (selectedQueryOption == "custom text") ? editedCameraDescription : selectedQueryOption
          if let starter = candidatesViewModel.selectedStarters.first {
            candidatesViewModel.selectedStarters[0] = SelectedEntry(
              device: starter.device,
              deviceType: starter.deviceType,
              traitType: starter.traitType,
              eventType: starter.eventType,
              valueOnOff: starter.valueOnOff,
              operation: starter.operation,
              levelValue: starter.levelValue,
              cameraDescription: description
            )
          }
          isShowingCameraEditSheet = false
        }) {
          let finalDescription = (selectedQueryOption == "custom text") ? editedCameraDescription : selectedQueryOption
          let isDisabled = finalDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          Text("Done")
            .frame(width: Dimensions.buttonWidth, height: Dimensions.buttonHeight)
            .background(isDisabled ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(.md)
            .padding(.bottom, .lg)
            .padding(.trailing, .smd)
        }
        .disabled(
          ((selectedQueryOption == "custom text") ? editedCameraDescription : selectedQueryOption)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
      }
    }
    .padding(.horizontal, .xl)
    .contentShape(Rectangle())
    .onTapGesture {
      UIApplication.shared.endEditing()
    }
    .presentationDetents([.fraction(Self.sheetHeightFraction)])
    .presentationCornerRadius(.lg)
    .contentShape(Rectangle())
    .onTapGesture {
      UIApplication.shared.endEditing()
    }
    .onAppear {
      if !CandidatesViewModel.queryOptions.contains(editedCameraDescription) {
        selectedQueryOption = "custom text"
      } else {
        selectedQueryOption = editedCameraDescription
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
        // If there's a selected one, display it
        if device.traitType is Matter.OnOffTrait.Type || device.traitType is Google.SimplifiedOnOffTrait.Type {
          let valueOnOff = device.valueOnOff ? "On": "Off"
          CreateButtonView(imageName: "astrophotography_mode_symbol", text1: device.device.name,
                           text2: valueOnOff) {}
                .padding(.bottom, .sm)
        } else if device.traitType is Matter.LevelControlTrait.Type || device.traitType is Google.BrightnessTrait.Type {
          let subTitle = "\(device.operation)  \(device.levelValue)"
          CreateButtonView(imageName: "astrophotography_mode_symbol", text1: device.device.name,
                           text2: subTitle) {}
            .padding(.bottom, .sm)
        } else if device.traitType is Google.VideoAnalysisTrait.Type {
          let subTitle = device.cameraDescription ?? ""
          CreateButtonView(
            imageName: "devices_other_symbol",
            text1: device.device.name,
            text2: subTitle
          ) {
            editedCameraDescription = subTitle
            isShowingCameraEditSheet = true
          }
          .padding(.bottom, .sm)
        }
      } else {
        // If there's no selected one, display a button for selection
        CreateButtonView(imageName: "astrophotography_mode_symbol", text1: "Add Starter and Condition",
                         text2: "") {
          navigationPath.append(cameraOnly ? Destination.CameraStarterCandidatesView : Destination.StarterCandidatesView)
        }
        .padding(.bottom, .sm)
      }
    }.listRowSeparator(.hidden)
  }

  private func actionSection() -> some View {
    Section("Action") {
      if let device = candidatesViewModel.selectedActions.first {
        // If there's a selected one, display it
        if device.traitType is Matter.OnOffTrait.Type || device.traitType is Google.SimplifiedOnOffTrait.Type {
          let valueOnOff = device.valueOnOff ? "On": "Off"
          CreateButtonView(imageName: "astrophotography_mode_symbol", text1: device.device.name, text2: valueOnOff) {}
          .padding(.bottom, .sm)
        }
      } else {
        // If there's no selected one, display a button for selection
        CreateButtonView(imageName: "astrophotography_mode_symbol", text1: "Add Action", text2: "") {
          navigationPath.append(Destination.ActionCandidatesView)
        }
        .padding(.bottom, .sm)
      }
    }.listRowSeparator(.hidden)
  }

  @MainActor
  private func saveButtonView() -> some View {
    HStack {
      Spacer()
      Button(action: {
        isShowingProgressView = true
        Task {
          do {
            // Create a DraftAutomation object
            let draftAutomation = try await automationRepository.genericAutomation(
              name: viewModel.name,
              description: viewModel.description,
              starters: candidatesViewModel.selectedStarters,
              actions: candidatesViewModel.selectedActions
            )

            // Create the automation
            try await viewModel.createAutomation(draftAutomation: draftAutomation)

            // Clear selected starter and action
            candidatesViewModel.clearSelected()
            // Redirect back to AutomationsView
            navigationPath.removeLast(navigationPath.count)
            self.isShowingProgressView = false
          } catch {
            self.isShowingErrorAlert = true
            self.isShowingProgressView = false
          }
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
