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
import GoogleHomeSDK
import GoogleHomeTypes
import SwiftUI

@MainActor
struct StarterCandidateDetailView: View {
  @State private var selectedEntryForSheet: CandidatesViewModel.NodeEntry?

  /// Model for the selected device
  @ObservedObject private var viewModel: CandidatesViewModel
  @Binding var navigationPath: NavigationPath

  init(viewModel: CandidatesViewModel, navigationPath: Binding<NavigationPath>) {
    self.viewModel = viewModel
    self._navigationPath = navigationPath
  }
  public var body: some View {
    VStack{
      List {
        if let selectedStarterDevice = viewModel.selectedStarterDevice {
          deviceInfoSection(selectedStarterDevice: selectedStarterDevice)
          deviceNodeSection(selectedStarterDevice: selectedStarterDevice)
        }
        else {
          Text("No device selected. Please back to previous page.")
        }
      }
      .listStyle(.inset)
      .listRowSeparator(.hidden)
      .padding(.top, .lg)
    }
    .sheet(item: $selectedEntryForSheet) { currentEntry in
      StarterConstraintSheetView(entry: currentEntry, viewModel: viewModel, navigationPath: $navigationPath)
    }
  }

  /// Display selected device info
  private func deviceInfoSection(selectedStarterDevice: CandidatesViewModel.DeviceEntry) -> some View {
    Section("Device") {
      CreateButtonView(imageName: selectedStarterDevice.iconName, text1: selectedStarterDevice.device.name, text2: "") {}
            .padding(.bottom, .sm)
    }.listRowSeparator(.hidden)
  }

  /// Display corresponding selectable traits
  private func deviceNodeSection(selectedStarterDevice: CandidatesViewModel.DeviceEntry) -> some View {
    Section(selectedStarterDevice.typeName) {
      let nodes = selectedStarterDevice.nodes.filter {
        $0.isSupported && ($0.node is TraitAttributesCandidate || $0.node is EventCandidate)
      }
      ForEach(nodes) { entry in
        CreateButtonView(
          imageName: entry.iconName,
          text1: entry.description,
          text2: entry.subdescription
        ) {
          selectedEntryForSheet = entry
        }
        .padding(.bottom, .sm)
      }
      .listRowSeparator(.hidden)
    }
  }
}

struct StarterConstraintSheetView: View {
  private static let defaultLevelValue: Float = 125
  private static let minLevelValue: Float = 1
  private static let maxLevelValue: Float = 254
  private static let levelStep: Float = 1
  private static let sheetHeightFraction = 0.65

  let entry: CandidatesViewModel.NodeEntry
  @ObservedObject var viewModel: CandidatesViewModel
  @Binding var navigationPath: NavigationPath

  @State private var toggleValue = false
  @State private var selectedOperation: Operations = .equalsTo
  @State private var levelValue: Float = defaultLevelValue

  // Custom camera trigger variables
  @State private var selectedQueryOption = CandidatesViewModel.queryOptions.first ?? ""
  @State private var cameraDescriptionText: String = ""

  private var minimumLevelValue: Float {
    return Self.minLevelValue
  }

  private var maximumLevelValue: Float {
    // Google.BrightnessTrait uses percentage (0-100), whereas Matter.LevelControlTrait uses 1-254.
    if entry.traitType == Google.BrightnessTrait.self {
      return 100
    }
    return Self.maxLevelValue
  }

  var body: some View {
    let trait = entry.traitType
    let eventType = entry.eventType

    VStack {
      if trait == Matter.OnOffTrait.self || trait == Google.SimplifiedOnOffTrait.self {
        Spacer()
        HStack {
          Text(entry.description).foregroundColor(Color("fontColor"))
          Spacer()
        }.padding(.horizontal, .xxxl)
        Spacer()
        CreateToggleButtonView(isOn: $toggleValue, leftText: "On", rightText: "Off")
        Spacer()
        doneButtonView(cameraDescription: nil)
      } else if trait == Matter.ColorControlTrait.self || trait == Matter.LevelControlTrait.self || trait == Google.BrightnessTrait.self {
        VStack(spacing: .lg) {
          Picker(selection: $selectedOperation, label: Text("Operation")) {
            Text("Equals to").tag(Operations.equalsTo)
            Text("Less than").tag(Operations.lessThan)
            Text("Greater than").tag(Operations.greaterThan)
          }
          .pickerStyle(SegmentedPickerStyle())

          Spacer()

          Text("Value: \(String(format: "%.0f", levelValue))")
          Slider(
            value: $levelValue,
            in: minimumLevelValue...maximumLevelValue,
            step: Self.levelStep
          ) {
            Text("Level")
          } minimumValueLabel: {
            Text(String(format: "%.0f", minimumLevelValue))
          } maximumValueLabel: {
            Text(String(format: "%.0f", maximumLevelValue))
          }

          Spacer()

          doneButtonView(cameraDescription: nil)
        }
        .padding(.horizontal, .xl)
      } else if eventType == Google.VideoAnalysisTrait.QueryMatchedEvent.self {
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
            TextField("Enter description...", text: $cameraDescriptionText)
              .textFieldStyle(.roundedBorder)
              .padding(.vertical, .sm)
              .autocorrectionDisabled(true)
              .textInputAutocapitalization(.never)
          }

          Spacer()

          let finalDescription = (selectedQueryOption == "custom text") ? cameraDescriptionText : selectedQueryOption
          doneButtonView(cameraDescription: finalDescription)
        }
        .padding(.horizontal, .xl)
        .contentShape(Rectangle())
        .onTapGesture {
          UIApplication.shared.endEditing()
        }
      } else {
        Text("No supported trait")
      }
    }
    .presentationDetents([.fraction(Self.sheetHeightFraction)])
    .presentationCornerRadius(.lg)
    .contentShape(Rectangle())
    .onTapGesture {
      UIApplication.shared.endEditing()
    }
    .onAppear {
      if eventType == Google.VideoAnalysisTrait.QueryMatchedEvent.self {
        selectedOperation = .cameraDescriptionMatch
      }
      // If default levelValue (125) exceeds BrightnessTrait percentage upper bound (100), reset to midpoint (50%).
      if entry.traitType == Google.BrightnessTrait.self && levelValue > 100 {
        levelValue = 50
      }
    }
  }

  @ViewBuilder
  private func doneButtonView(cameraDescription: String?) -> some View {
    if let selectedStarterDevice = viewModel.selectedStarterDevice {
      let isCameraEvent = entry.eventType == Google.VideoAnalysisTrait.QueryMatchedEvent.self
      let isInvalidCameraDescription =
        isCameraEvent
        && (cameraDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

      HStack {
        Spacer()
        Button(action: {
          viewModel.addSelectedStarters(
            device: selectedStarterDevice.device,
            deviceType: selectedStarterDevice.deviceType,
            trait: entry.traitType,
            eventType: entry.eventType,
            valueOnOff: toggleValue,
            operation: selectedOperation,
            levelValue: UInt8(levelValue),
            cameraDescription: cameraDescription
          )
          navigationPath.removeLast(2)
        }) {
          Text("Done")
            .frame(width: Dimensions.buttonWidth, height: Dimensions.buttonHeight)
            .background(isInvalidCameraDescription ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(.md)
            .padding(.bottom, .lg)
            .padding(.trailing, .smd)
        }
        .disabled(isInvalidCameraDescription)
      }
    }
  }
}
